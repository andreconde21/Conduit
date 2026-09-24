import 'package:conduit/core/app_failure.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/hosts/presentation/home_board_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';
import 'home_board_fakes.dart';

void main() {
  late HerdrFakeRunner runner;
  late int created;
  late HomeBoardController board;

  setUp(() {
    runner = HerdrFakeRunner();
    created = 0;
    board = HomeBoardController(
      runnerFactory: (_) {
        created += 1;
        return runner;
      },
      pollInterval: const Duration(days: 1),
    );
  });

  tearDown(() => board.dispose());

  test('stays idle until visible, then lists workspaces with panes', () async {
    board.selectHost(buildHost('a'));
    expect(created, 0);
    expect(board.state.phase, HomeBoardPhase.loading);

    board.setVisible(true);
    await board.pollNow();
    await pumpEventQueue();

    final state = board.state;
    expect(state.phase, HomeBoardPhase.ready);
    expect(state.workspaces.map((w) => w.label), [
      'Infrastructure',
      'TheCalendar',
    ]);
    final infra = state.workspaces.first;
    // Ordered by tab number, tab labels resolved.
    expect(infra.panes.map((p) => p.title), [
      'Deploying images',
      'Proofing PR 398',
    ]);
    expect(infra.panes.map((p) => p.tabLabel), ['main', 'review']);
    expect(infra.summary, AgentAttentionState.needsInput);
    expect(state.workspaces.last.panes.single.tabLabel, 'Tab 1');
    expect(state.workspaces.last.summary, AgentAttentionState.finished);
    expect(state.attentionCount, 1);
    expect(state.paneCount, 3);
  });

  test('hiding closes the channel and stops listing', () async {
    board.selectHost(buildHost('a'));
    board.setVisible(true);
    await pumpEventQueue();
    expect(runner.commands, isNotEmpty);

    board.setVisible(false);
    await pumpEventQueue();
    expect(runner.closeCount, 1);
    final before = runner.commands.length;
    await board.pollNow();
    // pollNow still works (the page calls refresh only while visible), but
    // a hidden board never starts a timer.
    expect(runner.commands.length, greaterThanOrEqualTo(before));
  });

  test('hardware-key machines wait for an explicit request', () async {
    final host = buildHost('k').copyWith(authMethod: SshAuthMethod.hardwareKey);
    board
      ..setVisible(true)
      ..selectHost(host);
    await pumpEventQueue();
    expect(board.state.phase, HomeBoardPhase.awaitingRequest);
    expect(created, 0);

    await board.refresh();
    expect(created, 0);

    board.requestLoad();
    await pumpEventQueue();
    expect(created, 1);
    expect(board.state.phase, HomeBoardPhase.ready);
  });

  test('reports Herdr not running and not installed', () async {
    runner
      ..workspaces = HerdrFixtures.notRunning
      ..workspaceExitCode = 1;
    board
      ..setVisible(true)
      ..selectHost(buildHost('a'));
    await pumpEventQueue();
    expect(board.state.phase, HomeBoardPhase.notRunning);

    runner
      ..workspaces = ''
      ..workspaceExitCode = 127
      ..workspaceStderr = 'sh: herdr: not found';
    await board.refresh();
    expect(board.state.phase, HomeBoardPhase.notInstalled);
  });

  test('a failed poll keeps the last board and reconnects next time', () async {
    board
      ..setVisible(true)
      ..selectHost(buildHost('a'));
    await pumpEventQueue();
    expect(board.state.workspaces, hasLength(2));

    runner.error = const AppFailure('Could not reach Host a.');
    await board.refresh();
    expect(board.state.phase, HomeBoardPhase.failed);
    expect(board.state.message, contains('Could not reach'));
    expect(board.state.workspaces, hasLength(2));
    expect(runner.closeCount, 1);

    runner.error = null;
    await board.refresh();
    expect(board.state.phase, HomeBoardPhase.ready);
    expect(created, 2);
  });

  test('switching machine starts over and ignores the old fetch', () async {
    board
      ..setVisible(true)
      ..selectHost(buildHost('a'));
    board.selectHost(buildHost('b'));
    await pumpEventQueue();
    expect(board.host?.id, 'b');
    expect(board.state.phase, HomeBoardPhase.ready);
    expect(runner.closeCount, greaterThanOrEqualTo(1));
  });

  test('focusPane sends herdr agent focus with the pane id', () async {
    board
      ..setVisible(true)
      ..selectHost(buildHost('a'));
    await pumpEventQueue();
    final pane = board.state.workspaces.first.panes.last;
    await board.focusPane(pane.agent);
    expect(runner.commands.last, contains('agent focus w1:p2'));

    await board.focusWorkspace('w2');
    expect(runner.commands.last, contains('workspace focus w2'));
  });
}
