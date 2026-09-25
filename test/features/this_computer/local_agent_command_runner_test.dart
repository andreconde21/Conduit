@TestOn('linux || mac-os')
library;

import 'dart:io';

import 'package:conduit/core/app_failure.dart';
import 'package:conduit/features/sessions/data/remote_session_lister.dart';
import 'package:conduit/features/sessions/domain/remote_session_listing.dart';
import 'package:conduit/features/this_computer/data/local_agent_command_runner.dart';
import 'package:conduit/features/this_computer/domain/local_shell_launch.dart';
import 'package:flutter_test/flutter_test.dart';

// Captured from Herdr 0.9.1 (same fixtures as remote_session_listing_test).
const _workspaceList =
    '{"id":"cli:workspace:list","result":{"type":"workspace_list",'
    '"workspaces":[{"active_tab_id":"w4:t4","agent_status":"idle",'
    '"focused":false,"label":"Infrastructure","number":1,"pane_count":1,'
    '"tab_count":2,"workspace_id":"w4"},{"active_tab_id":"wX:t1",'
    '"agent_status":"working","focused":true,"label":"Conductore-Mobile",'
    '"number":11,"pane_count":1,"tab_count":1,"workspace_id":"wX"}]}}';
const _tabList =
    '{"id":"cli:tab:list","result":{"tabs":[{"agent_status":"idle",'
    '"focused":false,"label":"Infrastructure","number":4,"pane_count":1,'
    '"tab_id":"w4:t4","workspace_id":"w4"},{"agent_status":"blocked",'
    '"focused":false,"label":"Deploy","number":1,"pane_count":1,'
    '"tab_id":"w4:t1","workspace_id":"w4"}],"type":"tab_list"}}';

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('conductore-local-');
  });

  tearDown(() async {
    await home.delete(recursive: true);
  });

  Future<void> tool(String relativeDir, String name, String script) async {
    final dir = Directory('${home.path}/$relativeDir');
    await dir.create(recursive: true);
    final file = File('${dir.path}/$name');
    await file.writeAsString('#!/bin/sh\n$script\n');
    await Process.run('chmod', ['+x', file.path]);
  }

  LocalAgentCommandRunner runner() => LocalAgentCommandRunner(
    environment: {'HOME': home.path, 'PATH': '/usr/bin:/bin'},
  );

  test('runs a command under sh -c in the home directory', () async {
    final result = await runner().run(
      r'printf "%s|%s" "$PWD" "$(echo hi)"; echo oops >&2; exit 3',
      timeout: const Duration(seconds: 10),
    );
    expect(result.stdout, '${home.resolveSymbolicLinksSync()}|hi');
    expect(result.stderr.trim(), 'oops');
    expect(result.exitCode, 3);
  });

  test('finds tools in the user-local install directories', () async {
    await tool('.local/bin', 'mytool', 'echo local-bin');
    await tool('.local/share/mise/shims', 'shimmed', 'echo mise');
    await tool('.cargo/bin', 'rusty', 'echo cargo');
    final result = await runner().run(
      'mytool; shimmed; rusty',
      timeout: const Duration(seconds: 10),
    );
    expect(
      result.stdout.split('\n'),
      containsAll(['local-bin', 'mise', 'cargo']),
    );
    expect(result.exitCode, 0);
  });

  test('a missing tool reads as not installed (exit 127)', () async {
    final result = await runner().run(
      'definitely-not-installed-tool',
      timeout: const Duration(seconds: 10),
    );
    expect(result.exitCode, 127);
  });

  test('stdin is closed, so a reader sees end of file', () async {
    final result = await runner().run(
      'cat; echo done',
      timeout: const Duration(seconds: 10),
    );
    expect(result.stdout.trim(), 'done');
  });

  test('times out and kills a hung command', () async {
    await expectLater(
      runner().run('sleep 30', timeout: const Duration(milliseconds: 200)),
      throwsA(isA<AppFailure>()),
    );
  });

  test('a closed runner refuses commands', () async {
    final closed = runner();
    await closed.close();
    await expectLater(
      closed.run('true', timeout: const Duration(seconds: 1)),
      throwsA(isA<AppFailure>()),
    );
  });

  test('on Windows, commands need the WSL shell', () async {
    final windows = LocalAgentCommandRunner(
      os: LocalOs.windows,
      environment: const {},
      windowsShell: () => WindowsShellKind.powershell,
    );
    await expectLater(
      windows.run('tmux ls', timeout: const Duration(seconds: 1)),
      throwsA(
        isA<AppFailure>().having((f) => f.message, 'message', contains('WSL')),
      ),
    );
    final (executable, arguments) = windows.invocation('tmux ls');
    expect(executable, 'wsl.exe');
    expect(arguments, ['-e', 'sh', '-c', 'tmux ls']);
  });

  group('listing through the local runner', () {
    test('lists tmux sessions from a mise-installed tmux', () async {
      await tool(
        '.local/share/mise/shims',
        'tmux',
        r'''printf 'main\t1\t3\t1790229500\nscratch\t0\t1\t1790229600\n' ''',
      );
      final listing = await RemoteSessionLister(runner()).listTmux();
      expect(listing, isA<RemoteListingAvailable<TmuxSessionInfo>>());
      final items = (listing as RemoteListingAvailable<TmuxSessionInfo>).items;
      expect(items.map((s) => s.name), ['main', 'scratch']);
      expect(items.first.isAttached, isTrue);
      expect(items.first.windows, 3);
    });

    test('no tmux server yet reads as an empty list', () async {
      await tool(
        '.local/bin',
        'tmux',
        r'echo "no server running on /tmp/tmux-1000/default" >&2; exit 1',
      );
      final listing = await RemoteSessionLister(runner()).listTmux();
      expect(listing, isA<RemoteListingAvailable<TmuxSessionInfo>>());
      expect(
        (listing as RemoteListingAvailable<TmuxSessionInfo>).items,
        isEmpty,
      );
    });

    test('lists Herdr workspaces and tabs from ~/.local/bin/herdr', () async {
      await tool('.local/bin', 'herdr', '''
case "\$*" in
  "session list --json") exit 2 ;;
  "workspace list") echo '$_workspaceList' ;;
  "tab list") echo '$_tabList' ;;
  *) echo "unexpected: \$*" >&2; exit 1 ;;
esac''');
      final listing = await RemoteSessionLister(runner()).listHerdr();
      expect(listing, isA<RemoteListingAvailable<HerdrWorkspaceInfo>>());
      final items =
          (listing as RemoteListingAvailable<HerdrWorkspaceInfo>).items;
      expect(items.map((w) => w.label), [
        'Infrastructure',
        'Conductore-Mobile',
      ]);
      expect(items.first.tabs.map((t) => t.label), contains('Deploy'));
    });
  });
}
