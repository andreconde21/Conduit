import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conduit/core/platform_features.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/terminal/domain/host_key_verifier.dart';
import 'package:conduit/features/this_computer/domain/self_machine.dart';

/// What `tailscale status --json` says about this device.
class TailscaleSelf {
  const TailscaleSelf({this.dnsName = '', this.addresses = const []});

  /// `omarchy.tail1234.ts.net` (without the trailing dot), or empty.
  final String dnsName;

  /// Its Tailscale IPs (100.x and fd7a:115c:a1e0::).
  final List<String> addresses;

  /// Reads the `Self` part of `tailscale status --json`; null when [json]
  /// is not that.
  static TailscaleSelf? parse(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) return null;
      final self = decoded['Self'];
      if (self is! Map) return null;
      final dnsName = self['DNSName'];
      final ips = self['TailscaleIPs'];
      return TailscaleSelf(
        dnsName: dnsName is String
            ? dnsName.trim().replaceFirst(RegExp(r'\.+$'), '')
            : '',
        addresses: [
          if (ips is List)
            for (final ip in ips)
              if (ip is String) ip,
        ],
      );
    } on FormatException {
      return null;
    }
  }
}

/// How [SelfMachineMatcher] looks at the device. Each probe may fail or
/// return nothing; the matcher then goes on with the others.
class SelfMachineProbes {
  const SelfMachineProbes({
    required this.interfaceAddresses,
    required this.localHostname,
    required this.tailscale,
    required this.hostKeys,
  });

  /// The real device: its network interfaces, host name, `tailscale
  /// status` and SSH host public keys.
  factory SelfMachineProbes.system({
    Duration tailscaleTimeout = const Duration(seconds: 3),
  }) => SelfMachineProbes(
    interfaceAddresses: _interfaceAddresses,
    localHostname: () => Platform.localHostname,
    tailscale: () => _tailscaleStatus(tailscaleTimeout),
    hostKeys: _hostPublicKeys,
  );

  /// Every IP of the device's interfaces.
  final Future<List<String>> Function() interfaceAddresses;

  /// The device's host name (`omarchy`).
  final String Function() localHostname;

  /// This device in `tailscale status`, or null without Tailscale.
  final Future<TailscaleSelf?> Function() tailscale;

  /// The device's SSH host public keys (`.pub` file contents).
  final Future<List<String>> Function() hostKeys;

  static Future<List<String>> _interfaceAddresses() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: true,
      includeLinkLocal: true,
    );
    return [
      for (final interface in interfaces)
        for (final address in interface.addresses) address.address,
    ];
  }

  static Future<TailscaleSelf?> _tailscaleStatus(Duration timeout) async {
    final process = await Process.start('tailscale', const [
      'status',
      '--json',
    ]);
    unawaited(process.stdin.close());
    unawaited(process.stderr.drain<void>());
    try {
      final output = await process.stdout
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      final code = await process.exitCode.timeout(timeout);
      return code == 0 ? TailscaleSelf.parse(output) : null;
    } finally {
      process.kill();
    }
  }

  /// Where sshd keeps its host keys: `/etc/ssh` on Linux and macOS,
  /// `%ProgramData%\ssh` on Windows (OpenSSH for Windows).
  static List<Directory> get hostKeyDirectories => [
    if (Platform.isWindows)
      Directory(
        '${Platform.environment['ProgramData'] ?? r'C:\ProgramData'}\\ssh',
      )
    else ...[
      Directory('/etc/ssh'),
      // Some macOS releases kept them here.
      if (Platform.isMacOS) Directory('/private/etc/ssh'),
    ],
  ];

  static Future<List<String>> _hostPublicKeys() async {
    final keys = <String>[];
    for (final directory in hostKeyDirectories) {
      try {
        await for (final entry in directory.list()) {
          final name = entry.uri.pathSegments.last;
          if (entry is! File ||
              !name.startsWith('ssh_host_') ||
              !name.endsWith('_key.pub')) {
            continue;
          }
          try {
            keys.add(await entry.readAsString());
          } on FileSystemException {
            // Unreadable: the other keys and the addresses still count.
          }
        }
      } on FileSystemException {
        // No sshd here.
      }
    }
    return keys;
  }
}

/// Finds the saved machine that is the device the app runs on (see
/// [findSelfMachine]), on desktops only: phones are not SSH targets here,
/// so there it matches nothing and never probes.
///
/// The device's identity is read on first use and cached; [invalidate]
/// (network change, app resume) makes the next match read it again. No
/// call throws: a failing probe only leaves its signal out.
class SelfMachineMatcher {
  SelfMachineMatcher({SelfMachineProbes? probes, bool? enabled})
    : _probes = probes ?? SelfMachineProbes.system(),
      enabled = enabled ?? PlatformFeatures.thisComputer;

  final SelfMachineProbes _probes;

  /// False on phones: [match] returns null without probing.
  final bool enabled;

  Future<DeviceIdentity>? _identity;

  /// Times the device was probed (tests).
  int probes = 0;

  /// Forgets the cached identity.
  void invalidate() => _identity = null;

  /// This device's identity, probed once until [invalidate].
  Future<DeviceIdentity> identity() {
    if (!enabled) return Future.value(DeviceIdentity.empty);
    return _identity ??= _probe();
  }

  /// The saved machine among [hosts] that is this device, or null.
  Future<SelfMachineMatch?> match(
    List<SavedHost> hosts, {
    List<HostKeyRecord> trustedKeys = const [],
  }) async {
    if (!enabled || hosts.isEmpty) return null;
    try {
      return findSelfMachine(hosts, await identity(), trustedKeys: trustedKeys);
    } catch (_) {
      return null;
    }
  }

  Future<DeviceIdentity> _probe() async {
    probes += 1;
    final results = await Future.wait([
      _attempt(_probes.interfaceAddresses, const <String>[]),
      _attempt(() async => _probes.localHostname(), ''),
      _attempt(_probes.tailscale, null),
      _attempt(_probes.hostKeys, const <String>[]),
    ]);
    final interfaces = results[0] as List<String>;
    final hostname = (results[1] as String).trim();
    final tailscale = results[2] as TailscaleSelf?;
    final keys = results[3] as List<String>;

    final dnsName = tailscale?.dnsName ?? '';
    final dot = dnsName.indexOf('.');
    final tailnetSuffix = dot > 0 ? dnsName.substring(dot) : '';
    final tailnetHost = dot > 0 ? dnsName.substring(0, dot) : dnsName;
    final shortName = hostname.split('.').first;
    return DeviceIdentity(
      addresses: [
        'localhost',
        '127.0.0.1',
        '::1',
        ...interfaces,
        ...?tailscale?.addresses,
        if (hostname.isNotEmpty) ...[
          hostname,
          shortName,
          '$shortName.local',
          if (tailnetSuffix.isNotEmpty) '$shortName$tailnetSuffix',
        ],
        if (dnsName.isNotEmpty) ...[dnsName, tailnetHost],
      ],
      hostKeyFingerprints: [
        for (final key in keys)
          for (final line in const LineSplitter().convert(key))
            ?hostKeyFingerprint(line),
      ],
    );
  }

  static Future<T> _attempt<T>(Future<T> Function() probe, T fallback) async {
    try {
      return await probe();
    } catch (_) {
      return fallback;
    }
  }
}
