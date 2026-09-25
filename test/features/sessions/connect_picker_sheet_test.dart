import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/sessions/domain/connect_preferences.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/sessions/presentation/connect_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

void main() {
  const tmuxOutput = AgentCommandResult(
    stdout: 'root\t1\t2\t1790229500\nbuild\t0\t1\t1790229600\n',
    stderr: '',
    exitCode: 0,
  );
  const herdrOutput = AgentCommandResult(
    stdout:
        '{"id":"cli:workspace:list","result":{"type":"workspace_list",'
        '"workspaces":[{"active_tab_id":"w4:t4","agent_status":"idle",'
        '"focused":false,"label":"Infrastructure","number":1,"pane_count":1,'
        '"tab_count":1,"workspace_id":"w4"},{"active_tab_id":"wX:t1",'
        '"agent_status":"blocked","focused":true,"label":"Conductore-Mobile",'
        '"number":11,"pane_count":1,"tab_count":1,"workspace_id":"wX"}]}}',
    stderr: '',
    exitCode: 0,
  );
  const notInstalled = AgentCommandResult(
    stdout: '',
    stderr: 'sh: 1: herdr: not found',
    exitCode: 127,
  );

  Future<(ScriptedAgentCommandRunner, List<ConnectPickerResult>)> pumpPicker(
    WidgetTester tester,
    List<Object> script, {
    SavedHost? host,
    ConnectPreferences preferences = const ConnectPreferences(),
    Set<String> activeTargetKeys = const {},
    ConnectPickerTab initialTab = ConnectPickerTab.tmux,
  }) async {
    final runner = ScriptedAgentCommandRunner(script);
    final picked = <ConnectPickerResult>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConnectPickerSheet(
            host: host ?? buildHost('h'),
            runner: runner,
            preferences: preferences,
            activeTargetKeys: activeTargetKeys,
            initialTab: initialTab,
            onPicked: picked.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (runner, picked);
  }

  testWidgets('lists tmux sessions with attached and active badges', (
    tester,
  ) async {
    final (runner, picked) = await pumpPicker(
      tester,
      [tmuxOutput, herdrOutput],
      activeTargetKeys: {'tmux:build'},
    );

    expect(runner.commands.first, startsWith('tmux list-sessions'));
    expect(find.text('root'), findsOneWidget);
    expect(find.text('build'), findsOneWidget);
    expect(find.text('Attached'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('New session'), findsOneWidget);

    await tester.tap(find.text('root'));
    expect(picked.single.target, const ConnectTarget.tmux('root'));
    expect(picked.single.remember, isFalse);
  });

  testWidgets('lists Herdr workspaces and picks one with its label', (
    tester,
  ) async {
    final (runner, picked) = await pumpPicker(
      tester,
      [tmuxOutput, herdrOutput],
      initialTab: ConnectPickerTab.herdr,
      activeTargetKeys: {'herdr:w4'},
    );

    expect(runner.commands, hasLength(3));
    expect(runner.commands[1], contains('herdr session list --json'));
    expect(runner.commands[2], contains('herdr workspace list'));
    expect(find.text('Infrastructure'), findsOneWidget);
    expect(find.text('Conductore-Mobile'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Needs input'), findsOneWidget);
    // One Herdr session: workspaces are listed directly, and the one Herdr
    // has focused carries the dot.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('herdr-workspace-:wX')),
        matching: find.byKey(const ValueKey('herdr-focused-dot')),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('herdr-focused-dot')), findsOneWidget);
    expect(find.textContaining('default'), findsNothing);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.text('Conductore-Mobile'));
    expect(
      picked.single.target,
      const ConnectTarget.herdr(workspaceId: 'wX', label: 'Conductore-Mobile'),
    );
    expect(picked.single.remember, isTrue);
  });

  testWidgets('lists several Herdr sessions as session ‧ workspace', (
    tester,
  ) async {
    const sessions = AgentCommandResult(
      stdout:
          '{"sessions":[{"default":true,"name":"default","running":true},'
          '{"default":false,"name":"work","running":true},'
          '{"default":false,"name":"old","running":false}]}',
      stderr: '',
      exitCode: 0,
    );
    const workOutput = AgentCommandResult(
      stdout:
          '{"result":{"workspaces":[{"workspace_id":"w1","label":"api",'
          '"focused":true,"tab_count":1,"active_tab_id":"w1:t1"}]}}',
      stderr: '',
      exitCode: 0,
    );
    final (runner, picked) = await pumpPicker(
      tester,
      [tmuxOutput, sessions, herdrOutput, workOutput],
      initialTab: ConnectPickerTab.herdr,
      activeTargetKeys: {'herdr@work:w1'},
    );

    expect(runner.commands, hasLength(4));
    expect(runner.commands[2], contains('exec herdr workspace list'));
    expect(
      runner.commands[3],
      contains('exec herdr --session work workspace list'),
    );
    expect(find.text('default ‧ Infrastructure'), findsOneWidget);
    expect(find.text('default ‧ Conductore-Mobile'), findsOneWidget);
    expect(find.text('work ‧ api'), findsOneWidget);
    // Each session has its own focused workspace.
    expect(find.byKey(const ValueKey('herdr-focused-dot')), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('herdr-workspace-work:w1')),
        matching: find.text('Active'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('work ‧ api'));
    expect(
      picked.single.target,
      const ConnectTarget.herdr(
        workspaceId: 'w1',
        label: 'work ‧ api',
        session: 'work',
      ),
    );
    expect(
      picked.single.target.startupCommand,
      'herdr --session work workspace focus w1 >/dev/null 2>&1; '
      'herdr --session work',
    );
  });

  testWidgets('explains when Herdr is not installed', (tester) async {
    await pumpPicker(tester, [
      tmuxOutput,
      notInstalled,
    ], initialTab: ConnectPickerTab.herdr);
    expect(
      find.text('Herdr is not installed on this machine.'),
      findsOneWidget,
    );
  });

  testWidgets('skip returns a plain shell', (tester) async {
    final (_, picked) = await pumpPicker(tester, [tmuxOutput, herdrOutput]);
    await tester.tap(find.text('Skip'));
    expect(picked.single.target, const ConnectTarget.shell());
  });

  testWidgets('recent tab shows earlier choices', (tester) async {
    final (_, picked) = await pumpPicker(
      tester,
      [tmuxOutput, herdrOutput],
      initialTab: ConnectPickerTab.recent,
      preferences: const ConnectPreferences(
        recents: [
          ConnectTarget.herdr(workspaceId: 'w7', label: 'TheCalendar'),
          ConnectTarget.tmux('ops'),
        ],
      ),
    );
    expect(find.text('TheCalendar'), findsOneWidget);
    expect(find.text('ops'), findsOneWidget);

    await tester.tap(find.text('ops'));
    expect(picked.single.target, const ConnectTarget.tmux('ops'));
  });

  testWidgets('new tmux session asks for a name', (tester) async {
    final (_, picked) = await pumpPicker(tester, [tmuxOutput, herdrOutput]);
    await tester.tap(find.text('New session'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'agents');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(picked.single.target, const ConnectTarget.tmux('agents'));
  });

  testWidgets('does not list automatically for hardware-key logins', (
    tester,
  ) async {
    final (runner, _) = await pumpPicker(
      tester,
      [tmuxOutput, herdrOutput],
      host: buildHost(
        'h',
      ).copyWith(authMethod: SshAuthMethod.hardwareKey, privateKey: 'stub'),
    );
    expect(runner.commands, isEmpty);
    expect(find.text('Load sessions'), findsOneWidget);

    await tester.tap(find.text('Load sessions'));
    await tester.pumpAndSettle();
    expect(runner.commands, hasLength(3));
    expect(find.text('root'), findsOneWidget);
  });
}
