import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/terminal/domain/herdr_navigator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_herdr_runner.dart';

void main() {
  group('HerdrNavigator.load', () {
    test('lists agent panes and agent-less tabs as workspace › tab › pane, '
        'marking the focused tab', () async {
      final runner = FakeHerdrRunner.withPanes();

      final listing = await HerdrNavigator.load(runner);

      expect(listing, isA<HerdrPanesAvailable>());
      final entries = (listing as HerdrPanesAvailable).entries;
      expect(entries.map((entry) => entry.path), [
        'Infrastructure › main › reviewer',
        'Infrastructure › logs',
        'TheCalendar › api › fix-auth',
      ]);
      expect(entries[0].paneId, 'w1:p1');
      expect(entries[0].agentKind, 'claude');
      expect(entries[0].status, AgentAttentionState.working);
      expect(entries[0].focused, isTrue);
      expect(entries[1].isAgent, isFalse);
      expect(entries[1].focused, isFalse);
      expect(entries[2].status, AgentAttentionState.needsInput);
      expect(entries[2].focused, isFalse);
      expect(runner.commands, hasLength(3));
    });

    test('reports Herdr as not found when the command is missing', () async {
      final runner = FakeHerdrRunner.notInstalled();

      final listing = await HerdrNavigator.load(runner);

      expect(listing, isA<HerdrNotFound>());
      expect(runner.commands, hasLength(1));
    });

    test('reports a stopped Herdr server', () async {
      final runner = FakeHerdrRunner(
        (_) => const AgentCommandResult(
          stdout: '',
          stderr: '{"error":{"code":"server_not_running"}}',
          exitCode: 1,
        ),
      );

      expect(await HerdrNavigator.load(runner), isA<HerdrNotRunning>());
    });

    test('still lists tabs when agent list is unsupported', () async {
      final runner = FakeHerdrRunner((command) {
        if (command.contains('agent list')) {
          return const AgentCommandResult(
            stdout: '',
            stderr: 'unknown command',
            exitCode: 2,
          );
        }
        return FakeHerdrRunner.panesResponse(command);
      });

      final listing = await HerdrNavigator.load(runner) as HerdrPanesAvailable;

      expect(listing.entries.every((entry) => !entry.isAgent), isTrue);
      expect(listing.entries.map((entry) => entry.tabLabel), [
        'main',
        'logs',
        'api',
      ]);
    });
  });

  group('HerdrNavigator.focus', () {
    test('focuses an agent pane by id and a plain tab by tab id', () async {
      final runner = FakeHerdrRunner.withPanes();
      final entries =
          (await HerdrNavigator.load(runner) as HerdrPanesAvailable).entries;
      runner.commands.clear();

      expect(await HerdrNavigator.focus(runner, entries[0]), isTrue);
      expect(await HerdrNavigator.focus(runner, entries[1]), isTrue);

      expect(runner.commands[0], contains('herdr agent focus w1:p1'));
      expect(runner.commands[1], contains('herdr tab focus w1:t2'));
    });

    test(
      'returns false when the CLI refuses so callers can fall back',
      () async {
        final runner = FakeHerdrRunner(
          (_) =>
              const AgentCommandResult(stdout: '', stderr: 'no', exitCode: 2),
        );
        const entry = HerdrPaneEntry(
          workspaceId: 'w1',
          workspaceLabel: 'W',
          tabId: 't',
          tabLabel: 'T',
          title: 'x',
          paneId: 'w1:p9',
        );

        expect(await HerdrNavigator.focus(runner, entry), isFalse);
      },
    );
  });
}
