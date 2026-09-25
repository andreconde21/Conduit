import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/terminal/domain/herdr_remote_control.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_herdr_runner.dart';

void main() {
  group('HerdrCommands', () {
    test('wraps herdr for a non-interactive shell', () {
      const commands = HerdrCommands();
      expect(
        commands.workspaceFocus('w2'),
        contains('exec herdr workspace focus w2'),
      );
      expect(
        commands.tabFocus('w2:t1'),
        contains('exec herdr tab focus w2:t1'),
      );
      expect(
        commands.agentFocus('w1:p3'),
        contains('exec herdr agent focus w1:p3'),
      );
      expect(
        commands.paneFocus(HerdrDirection.right),
        contains('exec herdr pane focus --direction right'),
      );
      expect(
        commands.paneZoom(on: true),
        contains('exec herdr pane zoom --on'),
      );
      expect(
        commands.paneZoom(on: false),
        contains('exec herdr pane zoom --off'),
      );
    });

    test('targets a named session with --session', () {
      const commands = HerdrCommands('work');
      expect(
        commands.workspaceList,
        contains('exec herdr --session work workspace list'),
      );
    });
  });

  group('HerdrRemoteControl', () {
    late FakeHerdrRunner runner;
    late int opened;
    late HerdrRemoteControl control;

    setUp(() {
      runner = FakeHerdrRunner.withPanes();
      opened = 0;
      control = HerdrRemoteControl(
        runnerFactory: () {
          opened += 1;
          return runner;
        },
      );
    });

    tearDown(() => control.close());

    test('reuses one channel for several commands, in order', () async {
      final results = await Future.wait([
        control.focusPane(HerdrDirection.left),
        control.setZoom(on: true),
        control.focusWorkspace('w2'),
      ]);
      expect(results, [true, true, true]);
      expect(opened, 1);
      expect(runner.commands, [
        contains('pane focus --direction left'),
        contains('pane zoom --on'),
        contains('workspace focus w2'),
      ]);
    });

    test('next workspace wraps around after the last one', () async {
      // w1 is focused; the next is w2, and the one after wraps to w1.
      expect(await control.focusAdjacentWorkspace(1), 'w2');
      expect(runner.commands.last, contains('workspace focus w2'));
      expect(await control.focusAdjacentWorkspace(-1), 'w2');
    });

    test('focusLocation prefers the pane, then the tab', () async {
      final failing = FakeHerdrRunner(
        (command) => command.contains('agent focus')
            ? const AgentCommandResult(
                stdout: '{"error":{"code":"agent_not_found"}}',
                stderr: '',
                exitCode: 1,
              )
            : FakeHerdrRunner.panesResponse(command),
      );
      final fallback = HerdrRemoteControl(runnerFactory: () => failing);
      expect(
        await fallback.focusLocation(
          workspaceId: 'w2',
          tabId: 'w2:t1',
          paneId: 'w2:p1',
        ),
        isTrue,
      );
      expect(failing.commands, [
        contains('agent focus w2:p1'),
        contains('tab focus w2:t1'),
      ]);
      await fallback.close();
    });

    test('closeFocusedPane closes the focused pane from pane list', () async {
      final panes = FakeHerdrRunner(
        (command) => command.contains('pane list')
            ? const AgentCommandResult(
                stdout:
                    '{"id":"cli:pane:list","result":{"panes":['
                    '{"pane_id":"w1:p1","focused":false,'
                    '"scroll":{"offset_from_bottom":0}},'
                    '{"pane_id":"w1:p2","focused":true,'
                    '"agent_session":{"agent":"claude"}}]}}',
                stderr: '',
                exitCode: 0,
              )
            : const AgentCommandResult(stdout: '', stderr: '', exitCode: 0),
      );
      final closer = HerdrRemoteControl(runnerFactory: () => panes);
      expect(await closer.closeFocusedPane(), isTrue);
      expect(panes.commands.last, contains('pane close w1:p2'));
      await closer.close();
    });

    test('readFocusedPane reads the focused pane with its workspace and '
        'tab', () async {
      final panes = FakeHerdrRunner(
        (command) => const AgentCommandResult(
          stdout:
              '{"id":"cli:pane:list","result":{"panes":['
              '{"pane_id":"w5:p3","tab_id":"w5:t3","workspace_id":"w5",'
              '"focused":false},'
              '{"pane_id":"w5:p5","tab_id":"w5:t3","workspace_id":"w5",'
              '"focused":true,"cwd":"/home/user/x"}]}}',
          stderr: '',
          exitCode: 0,
        ),
      );
      final control = HerdrRemoteControl(runnerFactory: () => panes);
      final pane = await control.readFocusedPane();
      expect(pane?.paneId, 'w5:p5');
      expect(pane?.tabId, 'w5:t3');
      expect(pane?.workspaceId, 'w5');
      expect(panes.commands.single, contains('pane list'));
      await control.close();
    });

    test('reports failure and stays usable when the channel throws', () async {
      var calls = 0;
      final flaky = HerdrRemoteControl(
        runnerFactory: () => FakeHerdrRunner((command) {
          calls += 1;
          if (calls == 1) {
            throw StateError('connection dropped');
          }
          return const AgentCommandResult(stdout: '', stderr: '', exitCode: 0);
        }),
      );
      expect(await flaky.focusWorkspace('w1'), isFalse);
      expect(await flaky.focusWorkspace('w1'), isTrue);
      await flaky.close();
    });

    test('closes the channel when closed', () async {
      await control.focusWorkspace('w1');
      await control.close();
      expect(runner.closed, isTrue);
      expect(await control.focusWorkspace('w1'), isFalse);
    });
  });

  group('New pane (Herdr 0.9.1 CLI)', () {
    const paneList =
        '{"id":"cli:pane:list","result":{"panes":['
        '{"pane_id":"w1:p1","workspace_id":"w1","tab_id":"w1:t1",'
        '"cwd":"/srv/app","focused":false},'
        '{"pane_id":"w1:p2","workspace_id":"w1","tab_id":"w1:t1",'
        '"cwd":"/srv/my app","foreground_cwd":"/srv/my app","focused":true}'
        '],"type":"pane_list"}}';

    FakeHerdrRunner scripted({bool createFails = false}) => FakeHerdrRunner((
      command,
    ) {
      if (command.contains('pane list')) {
        return const AgentCommandResult(
          stdout: paneList,
          stderr: '',
          exitCode: 0,
        );
      }
      if (createFails) {
        return const AgentCommandResult(
          stdout:
              '{"error":{"code":"pane_not_found","message":"pane not '
              'found"},"id":"cli:pane:split"}',
          stderr: '',
          exitCode: 1,
        );
      }
      return const AgentCommandResult(stdout: '{}', stderr: '', exitCode: 0);
    });

    test('reads the focused pane with its workspace and directory', () {
      expect(
        HerdrRemoteControl.focusedPane(paneList),
        const HerdrFocusedPane(
          paneId: 'w1:p2',
          workspaceId: 'w1',
          tabId: 'w1:t1',
          cwd: '/srv/my app',
        ),
      );
      expect(
        HerdrRemoteControl.focusedPane(
          '{"panes":[{"pane_id":"w2:p1","foreground_cwd":"/tmp",'
          '"focused":true}]}',
        )?.cwd,
        '/tmp',
      );
      expect(HerdrRemoteControl.focusedPane('not json'), isNull);
    });

    const expected = {
      HerdrNewPane.splitRight:
          "exec herdr pane split w1:p2 --direction right --cwd '\\''/srv/my "
          "app'\\'' --focus",
      HerdrNewPane.splitDown:
          "exec herdr pane split w1:p2 --direction down --cwd '\\''/srv/my "
          "app'\\'' --focus",
      HerdrNewPane.newTab:
          "exec herdr tab create --workspace w1 --cwd '\\''/srv/my app'\\'' "
          '--focus',
      HerdrNewPane.newWorkspace:
          "exec herdr workspace create --cwd '\\''/srv/my app'\\'' --focus",
    };
    for (final MapEntry(key: kind, value: command) in expected.entries) {
      test('${kind.name} runs `$command` after `pane list`', () async {
        final runner = scripted();

        expect(await HerdrRemoteControl.createPaneOn(runner, kind), isTrue);

        expect(runner.commands, hasLength(2));
        expect(runner.commands[0], contains('exec herdr pane list'));
        expect(runner.commands[1], contains(command));
      });
    }

    test('a named session passes --session to both commands', () async {
      final runner = scripted();

      await HerdrRemoteControl.createPaneOn(
        runner,
        HerdrNewPane.splitRight,
        const HerdrCommands('work'),
      );

      expect(runner.commands, [
        contains('exec herdr --session work pane list'),
        contains('exec herdr --session work pane split w1:p2'),
      ]);
    });

    test('a split needs a focused pane; a tab or workspace does not', () async {
      final runner = FakeHerdrRunner(
        (command) => const AgentCommandResult(
          stdout: '{"result":{"panes":[]}}',
          stderr: '',
          exitCode: 0,
        ),
      );

      expect(
        await HerdrRemoteControl.createPaneOn(runner, HerdrNewPane.splitDown),
        isFalse,
      );
      expect(runner.commands, hasLength(1));
      expect(
        await HerdrRemoteControl.createPaneOn(runner, HerdrNewPane.newTab),
        isTrue,
      );
      expect(runner.commands.last, contains('exec herdr tab create --focus'));
      expect(
        await HerdrRemoteControl.createPaneOn(
          runner,
          HerdrNewPane.newWorkspace,
        ),
        isTrue,
      );
      expect(
        runner.commands.last,
        contains('exec herdr workspace create --focus'),
      );
    });

    test('reports failure when Herdr rejects the command', () async {
      final runner = scripted(createFails: true);

      expect(
        await HerdrRemoteControl.createPaneOn(runner, HerdrNewPane.splitRight),
        isFalse,
      );
    });

    test('the shared control runs the same two commands', () async {
      final runner = scripted();
      final control = HerdrRemoteControl(runnerFactory: () => runner);
      addTearDown(control.close);

      expect(await control.createPane(HerdrNewPane.newTab), isTrue);
      expect(runner.commands, [
        contains('pane list'),
        contains('exec herdr tab create --workspace w1'),
      ]);
    });
  });
}
