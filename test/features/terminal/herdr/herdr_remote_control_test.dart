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
}
