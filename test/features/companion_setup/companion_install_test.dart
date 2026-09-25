import 'dart:convert';
import 'dart:io';

import 'package:conduit/features/companion_setup/data/companion_bundle.dart';
import 'package:conduit/features/companion_setup/domain/companion_status.dart';
import 'package:conduit/features/companion_setup/presentation/companion_setup_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';
import 'companion_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSftpSession sftp;
  late MatchingRunner runner;
  late CompanionSetupController controller;
  final host = buildHost('box');

  setUp(() {
    sftp = FakeSftpSession(home: '/home/andre', tree: {});
    runner = MatchingRunner({
      'mkdir -p': ok(''),
      'install.sh': ok(
        '{"ok":true,"settings":"/home/andre/.claude/settings.json"}\n',
      ),
      'exec node --version': ok('v22.1.0'),
      'conductore-hostd version': notFound,
    });
    controller = CompanionSetupController(
      runnerFactory: (_) => runner,
      sftpRepository: FakeSftpRepository(sftp),
      loadBundle: () async => fakeBundle(),
    );
  });

  tearDown(() => controller.dispose());

  test('install uploads the bundle, runs install.sh, then re-checks', () async {
    expect((await controller.refresh(host)).state, CompanionState.notInstalled);
    // After install.sh the companion answers like a healthy install.
    runner.responses.addAll(healthyResponses(daemon: false));
    runner.commands.clear();

    final log = <String>[];
    final outcome = await controller.install(host, onLog: log.add);

    const dir = '/home/andre/.local/share/conductore-src/0.3.0';
    expect(outcome.ok, isTrue);
    expect(outcome.directory, dir);
    expect(sftp.writtenFiles.keys, {
      '$dir/install.sh',
      '$dir/bin/conductore-hostd',
      '$dir/bin/conductore-hook',
      '$dir/lib/cli.js',
    });
    expect(utf8.decode(sftp.writtenFiles['$dir/lib/cli.js']!), 'cli');
    expect(sftp.closeCalls, 1);

    // mkdir before upload, install.sh after, then the status check.
    final mkdir = runner.commands.indexWhere((c) => c.contains('mkdir -p'));
    final install = runner.commands.indexWhere((c) => c.contains('install.sh'));
    final recheck = runner.commands.lastIndexWhere(
      (c) => c.contains('conductore-hostd doctor'),
    );
    expect(mkdir, 0);
    expect(runner.commands[mkdir], contains('$dir/bin'));
    expect(runner.commands[mkdir], contains('$dir/lib'));
    expect(install, greaterThan(mkdir));
    expect(runner.commands[install], contains('exec sh'));
    expect(runner.commands[install], contains('$dir/install.sh'));
    expect(runner.commands[install], isNot(contains('--uninstall')));
    expect(recheck, greaterThan(install));

    expect(
      controller.statusFor(host)?.state,
      CompanionState.waitingForFirstEvent,
    );
    expect(log.first, contains('Uploading companion 0.3.0 (4 files)'));
    expect(log, contains('Installed.'));
  });

  test('a failing install.sh reports failure with its output', () async {
    runner.responses['install.sh'] = failed(
      1,
      stderr: 'node not found on PATH; Claude Code needs Node.js too',
    );
    final outcome = await controller.install(host);
    expect(outcome.ok, isFalse);
    expect(outcome.exitCode, 1);
    expect(outcome.log.join('\n'), contains('node not found on PATH'));
    expect(outcome.log.last, contains('install.sh failed (exit 1)'));
    // Still re-checked so the screen reflects reality.
    expect(controller.statusFor(host)?.state, CompanionState.notInstalled);
  });

  test('uninstall uploads and runs install.sh --uninstall', () async {
    final outcome = await controller.uninstall(host);
    expect(outcome.ok, isTrue);
    expect(sftp.writtenFiles, isNotEmpty);
    final command = runner.commands.firstWhere((c) => c.contains('install.sh'));
    expect(command, endsWith("install.sh'\\'' --uninstall'"));
  });

  test('stop daemon runs conductore-hostd stop', () async {
    runner.responses.addAll(healthyResponses());
    runner.responses['conductore-hostd stop'] = ok(
      '{"ok":true,"running":true,"stopped":true}',
    );
    expect(await controller.stopDaemon(host), isTrue);
    expect(runner.ran('conductore-hostd stop'), isTrue);
  });

  test('send test event pipes JSON into conductore-hook and finds the '
      'agent', () async {
    runner.responses.addAll({
      'conductore-hook Notification': ok(''),
      ...healthyResponses(),
    });
    runner.responses['conductore-hostd status'] = ok(
      statusJson(
        source: 'daemon',
        seq: 2,
        agents: [
          agent('conductore-test', state: 'ended', updatedAt: DateTime.now()),
        ],
      ),
    );
    final result = await controller.sendTestEvent(host);
    expect(result.ok, isTrue);
    expect(result.message, contains('pruned after an hour'));
    final sent = runner.commands.firstWhere(
      (c) => c.contains('conductore-hook Notification'),
    );
    expect(sent, contains(r'\"session_id\":\"conductore-test\"'));
    expect(sent, contains(r'\"message\":\"Test from Conductore\"'));
    expect(sent, contains('conductore-hook SessionEnd'));
  });

  test('send test event reports a missing agent', () async {
    runner.responses.addAll({
      'conductore-hook Notification': ok(''),
      ...healthyResponses(),
    });
    final result = await controller.sendTestEvent(host);
    expect(result.ok, isFalse);
    expect(result.message, contains('hostd.log'));
  });

  test('status is cached per connection and reset when it changes', () async {
    final runners = <MatchingRunner>[];
    final cached = CompanionSetupController(
      runnerFactory: (_) {
        final r = MatchingRunner(healthyResponses());
        runners.add(r);
        return r;
      },
      sftpRepository: FakeSftpRepository(sftp),
      loadBundle: () async => fakeBundle(),
    );
    addTearDown(cached.dispose);

    cached.ensureChecked(host);
    cached.ensureChecked(host);
    await pumpEventQueue();
    expect(cached.statusFor(host)?.state, CompanionState.active);
    cached.ensureChecked(host);
    await pumpEventQueue();
    expect(runners, hasLength(1));
    expect(
      runners.single.commands.where((c) => c.contains('hostd version')),
      hasLength(1),
    );

    final moved = host.copyWith(host: '10.0.0.9');
    expect(cached.statusFor(moved), isNull);
    await cached.refresh(moved);
    expect(runners, hasLength(2));
    expect(runners.first.closeCount, 1);
  });

  group('bundled assets', () {
    test('the manifest lists every bundled file and matches host/', () async {
      final bundle = await CompanionBundle.load(rootBundle);
      final package =
          jsonDecode(File('host/package.json').readAsStringSync())
              as Map<String, Object?>;
      expect(bundle.version, package['version']);
      expect(
        bundle.files.keys,
        containsAll([
          'install.sh',
          'package.json',
          'README.md',
          'bin/conductore-hostd',
          'bin/conductore-hook',
          'lib/cli.js',
          'lib/hook.js',
        ]),
      );
      expect(bundle.files.keys.where((p) => p.startsWith('test/')), isEmpty);

      // Fails when host/ changed without re-running
      // tools/bundle-companion.sh.
      final hostFiles = [
        for (final dir in ['bin', 'lib'])
          for (final entity in Directory('host/$dir').listSync())
            if (entity is File) '$dir/${entity.uri.pathSegments.last}',
        'install.sh',
        'package.json',
        'README.md',
      ];
      expect(bundle.files.keys.toSet(), hostFiles.toSet());
      for (final path in hostFiles) {
        expect(
          bundle.files[path],
          File('host/$path').readAsBytesSync(),
          reason: '$path is stale: run tools/bundle-companion.sh',
        );
      }
    });
  });
}
