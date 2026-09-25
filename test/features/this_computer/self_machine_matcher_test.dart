import 'dart:convert';
import 'dart:typed_data';

import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/terminal/data/ssh_client_factory.dart';
import 'package:conduit/features/terminal/domain/host_key_verifier.dart';
import 'package:conduit/features/this_computer/data/self_machine_matcher.dart';
import 'package:conduit/features/this_computer/domain/self_machine.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

/// The PC's `/etc/ssh/ssh_host_ed25519_key.pub`, and its fingerprint as
/// `ssh-keygen -l -E md5` prints it.
const _hostKey =
    'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIACR5Qr1xMX44j3jiFQRYSMgmbSos6s187'
    'FvZyIauZw9 root@omarchy';
const _hostKeyMd5 = 'MD5:7e:9a:e3:cf:70:b4:7c:c7:98:67:93:57:2a:af:8b:de';

SavedHost _ssh(String id, String host, {int port = 22}) =>
    buildHost(id).copyWith(name: id, host: host, port: port);

HostKeyRecord _trusted(String host, String fingerprint, {int port = 22}) =>
    HostKeyRecord(
      host: host,
      port: port,
      type: 'ssh-ed25519',
      fingerprint: fingerprint,
      trustedAt: DateTime.utc(2026),
    );

/// André's PC: host name omarchy, LAN 192.168.1.40, Tailscale
/// 100.97.235.112 and its fd7a:115c:a1e0:: address, MagicDNS
/// omarchy.tail574592.ts.net.
SelfMachineProbes _omarchy({List<String> keys = const [_hostKey]}) =>
    SelfMachineProbes(
      interfaceAddresses: () async => [
        '127.0.0.1',
        '192.168.1.40',
        '100.97.235.112',
        'fd7a:115c:a1e0::b901:eb70',
      ],
      localHostname: () => 'omarchy',
      tailscale: () async => const TailscaleSelf(
        dnsName: 'omarchy.tail574592.ts.net',
        addresses: ['100.97.235.112', 'fd7a:115c:a1e0::b901:eb70'],
      ),
      hostKeys: () async => keys,
    );

void main() {
  group('hostKeyFingerprint', () {
    test('matches ssh-keygen and the SSH client\'s stored format', () {
      expect(hostKeyFingerprint(_hostKey), _hostKeyMd5);
      final blob = base64.decode(_hostKey.split(' ')[1]);
      final stored = SshClientFactory(NoopVerifier())
          .formatFingerprintForTesting(
            Uint8List.fromList(md5.convert(blob).bytes),
          );
      expect(hostKeyFingerprint(_hostKey), stored);
    });

    test('ignores what is not a public key', () {
      expect(hostKeyFingerprint(''), isNull);
      expect(hostKeyFingerprint('ssh-ed25519'), isNull);
      expect(hostKeyFingerprint('ssh-ed25519 not*base64!'), isNull);
    });
  });

  group('SelfMachineMatcher', () {
    Future<SelfMachineMatch?> match(
      List<SavedHost> hosts, {
      List<HostKeyRecord> trustedKeys = const [],
      SelfMachineProbes? probes,
    }) => SelfMachineMatcher(
      probes: probes ?? _omarchy(),
      enabled: true,
    ).match(hosts, trustedKeys: trustedKeys);

    test('a trusted host key that is this device\'s own matches', () async {
      final result = await match(
        [_ssh('pc', 'some-alias.example')],
        trustedKeys: [_trusted('some-alias.example', _hostKeyMd5)],
      );
      expect(result?.host.id, 'pc');
      expect(result?.signal, SelfMachineSignal.hostKey);
    });

    test('a different trusted key wins over a matching address', () async {
      // Something else answers on this device's address (a forwarded VM).
      final result = await match(
        [_ssh('vm', '100.97.235.112')],
        trustedKeys: [_trusted('100.97.235.112', 'MD5:00:11')],
      );
      expect(result, isNull);
    });

    test('the Tailscale IPv4 and IPv6 addresses match', () async {
      for (final address in [
        '100.97.235.112',
        'fd7a:115c:a1e0::b901:eb70',
        'FD7A:115C:A1E0:0:0:0:B901:EB70',
        '[fd7a:115c:a1e0::b901:eb70]',
      ]) {
        final result = await match([_ssh('pc', address)]);
        expect(result?.host.id, 'pc', reason: address);
        expect(result?.signal, SelfMachineSignal.address);
      }
    });

    test('LAN IPs, loopback and names match, in any case', () async {
      for (final address in [
        '192.168.1.40',
        'localhost',
        '127.0.0.1',
        '::1',
        'omarchy',
        'OMARCHY',
        'omarchy.local',
        'omarchy.tail574592.ts.net',
        'omarchy.tail574592.ts.net.',
      ]) {
        expect(
          (await match([_ssh('pc', address)]))?.host.id,
          'pc',
          reason: address,
        );
      }
    });

    test('another tailnet machine is not this device', () async {
      final result = await match([
        _ssh('server', '100.97.235.113'),
        _ssh('other', '100.64.0.1'),
        _ssh('laptop', 'laptop.tail574592.ts.net'),
        _ssh('lookalike', 'omarchy2'),
        _ssh('v6', 'fd7a:115c:a1e0::1'),
      ]);
      expect(result, isNull);
    });

    test('an address on another port is not this device', () async {
      // Usually a container or VM behind a forwarded port.
      expect(await match([_ssh('container', 'localhost', port: 2222)]), isNull);
    });

    test('local shells never match', () async {
      expect(
        await match([SavedHost.localShell(id: 'proot', name: 'This phone')]),
        isNull,
      );
    });

    test('the MagicDNS name comes from tailscale status', () async {
      final probes = SelfMachineProbes(
        interfaceAddresses: () async => const [],
        localHostname: () => 'omarchy',
        tailscale: () async => TailscaleSelf.parse(
          jsonEncode({
            'Self': {
              'DNSName': 'omarchy.tail574592.ts.net.',
              'TailscaleIPs': ['100.97.235.112'],
            },
          }),
        ),
        hostKeys: () async => const [],
      );
      expect(
        (await match([
          _ssh('pc', 'omarchy.tail574592.ts.net'),
        ], probes: probes))?.host.id,
        'pc',
      );
      expect(
        (await match([_ssh('pc', '100.97.235.112')], probes: probes))?.host.id,
        'pc',
      );
    });

    test('failing probes leave their signal out and never throw', () async {
      final broken = SelfMachineProbes(
        interfaceAddresses: () async => throw StateError('no interfaces'),
        localHostname: () => throw StateError('no hostname'),
        tailscale: () async => throw StateError('no tailscale'),
        hostKeys: () async => throw StateError('no keys'),
      );
      // Loopback still counts.
      expect(
        (await match([_ssh('pc', 'localhost')], probes: broken))?.host.id,
        'pc',
      );
      expect(
        await match([_ssh('pc', '100.97.235.112')], probes: broken),
        isNull,
      );

      final partly = SelfMachineProbes(
        interfaceAddresses: () async => throw StateError('no interfaces'),
        localHostname: () => 'omarchy',
        tailscale: () async => null,
        hostKeys: () async => const ['garbage', ''],
      );
      expect(
        (await match([_ssh('pc', 'omarchy.local')], probes: partly))?.host.id,
        'pc',
      );
    });

    test('probes once per session until invalidated', () async {
      final matcher = SelfMachineMatcher(probes: _omarchy(), enabled: true);
      await matcher.match([_ssh('pc', 'omarchy')]);
      await matcher.match([_ssh('pc', 'omarchy')]);
      expect(matcher.probes, 1);
      matcher.invalidate();
      await matcher.match([_ssh('pc', 'omarchy')]);
      expect(matcher.probes, 2);
    });

    test('phones never probe', () async {
      var calls = 0;
      final matcher = SelfMachineMatcher(
        enabled: false,
        probes: SelfMachineProbes(
          interfaceAddresses: () async {
            calls += 1;
            return const ['100.97.235.112'];
          },
          localHostname: () {
            calls += 1;
            return 'omarchy';
          },
          tailscale: () async {
            calls += 1;
            return null;
          },
          hostKeys: () async {
            calls += 1;
            return const [];
          },
        ),
      );
      expect(await matcher.match([_ssh('pc', '100.97.235.112')]), isNull);
      expect(calls, 0);
      expect(matcher.probes, 0);
    });
  });

  test('TailscaleSelf.parse reads Self and nothing else', () {
    final self = TailscaleSelf.parse(
      '{"Self":{"DNSName":"omarchy.tail574592.ts.net.",'
      '"TailscaleIPs":["100.97.235.112","fd7a:115c:a1e0::b901:eb70"]}}',
    );
    expect(self?.dnsName, 'omarchy.tail574592.ts.net');
    expect(self?.addresses, hasLength(2));
    expect(TailscaleSelf.parse('not json'), isNull);
    expect(TailscaleSelf.parse('[]'), isNull);
    expect(TailscaleSelf.parse('{}'), isNull);
  });
}
