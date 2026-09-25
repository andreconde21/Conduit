import 'dart:io';

import 'package:conduit/features/sync/domain/sync_hub.dart';
import 'package:conduit/features/sync/domain/sync_hub_commands.dart';
import 'package:flutter_test/flutter_test.dart';

const _vault = '0123456789abcdef0123456789abcdef';
const _device = 'fedcba9876543210fedcba9876543210';
const _key =
    'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGq2vR3cWn0yQ8m5d0c1W6yJ0H2s6d4k2fQe7y9rZx1a';
const _otherKey =
    'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  group('authorized_keys commands', () {
    test('the line carries the device comment and a clean name', () {
      expect(
        SyncHubCommands.authorizedKeyLine(_key, "André's Pixel 9!"),
        '$_key conductore-device Andrs Pixel 9',
      );
      expect(
        SyncHubCommands.authorizedKeyLine('$_key old-comment', '  '),
        '$_key conductore-device device',
      );
    });

    test('add is an exact, idempotent append', () {
      expect(
        SyncHubCommands.addAuthorizedKey(_key, 'Pixel'),
        'umask 077\n'
        'mkdir -p "\$HOME/.ssh"\n'
        'touch "\$HOME/.ssh/authorized_keys"\n'
        "if grep -qF 'AAAAC3NzaC1lZDI1NTE5AAAAIGq2vR3cWn0yQ8m5d0c1W6yJ0H2s6d4k2fQe7y9rZx1a' "
        '"\$HOME/.ssh/authorized_keys"; then exit 0; fi\n'
        'if [ -s "\$HOME/.ssh/authorized_keys" ] && '
        '[ -n "\$(tail -c 1 "\$HOME/.ssh/authorized_keys")" ]; '
        "then printf '\\n' >> \"\$HOME/.ssh/authorized_keys\"; fi\n"
        "printf '%s\\n' '$_key conductore-device Pixel' "
        '>> "\$HOME/.ssh/authorized_keys"',
      );
    });

    test('remove is an exact in-place rewrite', () {
      expect(
        SyncHubCommands.removeAuthorizedKey(_key),
        '[ -f "\$HOME/.ssh/authorized_keys" ] || exit 0\n'
        "grep -qF 'AAAAC3NzaC1lZDI1NTE5AAAAIGq2vR3cWn0yQ8m5d0c1W6yJ0H2s6d4k2fQe7y9rZx1a' "
        '"\$HOME/.ssh/authorized_keys" || exit 0\n'
        "{ grep -vF 'AAAAC3NzaC1lZDI1NTE5AAAAIGq2vR3cWn0yQ8m5d0c1W6yJ0H2s6d4k2fQe7y9rZx1a' "
        '"\$HOME/.ssh/authorized_keys" || true; } > '
        '"\$HOME/.ssh/authorized_keys.conductore.tmp"\n'
        'cat "\$HOME/.ssh/authorized_keys.conductore.tmp" > '
        '"\$HOME/.ssh/authorized_keys"\n'
        'rm -f "\$HOME/.ssh/authorized_keys.conductore.tmp"',
      );
    });

    test('malformed keys and ids never reach a command', () {
      expect(
        () => SyncHubCommands.addAuthorizedKey(
          "ssh-ed25519 x'; touch pwned",
          'x',
        ),
        throwsArgumentError,
      );
      expect(
        () => SyncHubCommands.removeAuthorizedKey('ssh-ed25519 AAAA'),
        throwsArgumentError,
      );
      expect(() => SyncHubCommands.readMeta('../x'), throwsArgumentError);
      expect(
        () => SyncHubCommands.commit(_vault, 'nope', 0),
        throwsArgumentError,
      );
    });

    test('parses the device lines', () {
      final keys = SyncHubCommands.parseAuthorizedKeys(
        '$_key conductore-device Pixel 9\n'
        'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7 laptop\n'
        '$_otherKey conductore-device iPad\n',
      );
      expect(keys.map((k) => k.name), ['Pixel 9', 'iPad']);
      expect(keys.first.publicKey, _key);
    });
  });

  group('against a real shell', () {
    late Directory home;

    setUp(() async {
      home = await Directory.systemTemp.createTemp('conductore-hub-');
    });
    tearDown(() => home.delete(recursive: true));

    Future<ProcessResult> sh(String command) => Process.run(
      'sh',
      ['-c', command],
      environment: {'HOME': home.path, 'PATH': Platform.environment['PATH']!},
    );

    File authorizedKeys() => File('${home.path}/.ssh/authorized_keys');

    test(
      'add twice gives one line and keeps an unterminated last key',
      () async {
        await Directory('${home.path}/.ssh').create();
        await authorizedKeys().writeAsString('ssh-rsa AAAAexisting laptop');

        for (var i = 0; i < 2; i++) {
          final result = await sh(
            SyncHubCommands.addAuthorizedKey(_key, 'Pixel'),
          );
          expect(result.exitCode, 0, reason: '${result.stderr}');
        }

        expect(
          await authorizedKeys().readAsString(),
          'ssh-rsa AAAAexisting laptop\n$_key conductore-device Pixel\n',
        );
        final listed = await sh(SyncHubCommands.listAuthorizedKeys());
        expect(
          SyncHubCommands.parseAuthorizedKeys(
            listed.stdout as String,
          ).single.name,
          'Pixel',
        );
      },
    );

    test('add creates ~/.ssh private to the user', () async {
      await sh(SyncHubCommands.addAuthorizedKey(_key, 'Pixel'));
      final mode = await sh(
        'stat -c %a "\$HOME/.ssh" "\$HOME/.ssh/authorized_keys"',
      );
      expect((mode.stdout as String).split('\n').take(2), ['700', '600']);
    }, skip: !Platform.isLinux);

    test('remove drops only that key and is idempotent', () async {
      await sh(SyncHubCommands.addAuthorizedKey(_key, 'Pixel'));
      await sh(SyncHubCommands.addAuthorizedKey(_otherKey, 'iPad'));
      for (var i = 0; i < 2; i++) {
        final result = await sh(SyncHubCommands.removeAuthorizedKey(_key));
        expect(result.exitCode, 0, reason: '${result.stderr}');
      }
      expect(
        await authorizedKeys().readAsString(),
        '$_otherKey conductore-device iPad\n',
      );
      expect(
        File('${home.path}/.ssh/authorized_keys.conductore.tmp').existsSync(),
        isFalse,
      );
      await authorizedKeys().delete();
      final missing = await sh(SyncHubCommands.removeAuthorizedKey(_key));
      expect(missing.exitCode, 0);
    });

    Future<void> stage(String bundle, int metaVersion) async {
      await sh(SyncHubCommands.prepare());
      await File(
        '${home.path}/${SyncHubCommands.uploadPath(_vault, _device, 'bundle')}',
      ).writeAsString(bundle);
      await File(
        '${home.path}/${SyncHubCommands.uploadPath(_vault, _device, 'meta')}',
      ).writeAsString(
        '${SyncHubMeta(version: metaVersion, updatedBy: _device).encode()}\n',
      );
    }

    Future<ProcessResult> upload(int version) async {
      await stage('bundle $version', version);
      return sh(SyncHubCommands.commit(_vault, _device, version - 1));
    }

    test('commit is a compare-and-swap on the meta version', () async {
      expect((await upload(1)).exitCode, 0);
      expect((await upload(2)).exitCode, 0);
      final bundle = File('${home.path}/${SyncHubCommands.bundlePath(_vault)}');
      expect(await bundle.readAsString(), 'bundle 2');

      // A device that last saw version 0 loses the race.
      await stage('stale', 1);
      final stale = await sh(SyncHubCommands.commit(_vault, _device, 0));
      expect(stale.exitCode, 3);
      expect(await bundle.readAsString(), 'bundle 2');
      final leftovers = Directory(
        '${home.path}/${SyncHubCommands.directory}',
      ).listSync().map((e) => e.path.split('/').last);
      expect(leftovers, unorderedEquals(['$_vault.bundle', '$_vault.meta']));

      final meta = await sh(SyncHubCommands.readMeta(_vault));
      expect(SyncHubMeta.decode(meta.stdout as String)!.version, 2);
      final vaults = await sh(SyncHubCommands.listVaults());
      expect((vaults.stdout as String).trim(), _vault);
    });

    test('a stale lock from a dead push is broken', () async {
      await sh(SyncHubCommands.prepare());
      final lock = '${home.path}/${SyncHubCommands.directory}/$_vault.lock';
      await Directory(lock).create();
      await sh('touch -d "10 minutes ago" "$lock"');
      expect((await upload(1)).exitCode, 0);
      expect(Directory(lock).existsSync(), isFalse);
    }, skip: !Platform.isLinux);

    test('delete removes the vault and nothing else', () async {
      await upload(1);
      await File(
        '${home.path}/${SyncHubCommands.directory}/keep.txt',
      ).writeAsString('x');
      expect((await sh(SyncHubCommands.deleteVault(_vault))).exitCode, 0);
      final left = Directory(
        '${home.path}/${SyncHubCommands.directory}',
      ).listSync().map((e) => e.path.split('/').last);
      expect(left, ['keep.txt']);
      expect((await sh(SyncHubCommands.readMeta(_vault))).stdout, '');
    });
  }, skip: Platform.isWindows);

  test('meta JSON starts with the version the commit script reads', () {
    final meta = SyncHubMeta(
      version: 12,
      updatedBy: _device,
      devices: [
        SyncDeviceInfo(
          id: _device,
          name: 'Pixel',
          lastSeen: DateTime.utc(2026),
        ),
      ],
      revoked: const ['a'],
    );
    expect(meta.encode(), startsWith('{"version":12,'));
    final back = SyncHubMeta.decode(meta.encode())!;
    expect(back.devices.single.name, 'Pixel');
    expect(back.revoked, ['a']);
    expect(SyncHubMeta.decode('garbage'), isNull);
  });
}
