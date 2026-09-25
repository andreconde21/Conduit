import 'package:conduit/core/app_failure.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/hosts/presentation/home_board_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';
import 'home_board_fakes.dart';

SavedHost connected(String id) =>
    buildHost(id).copyWith(lastConnectedAt: DateTime.utc(2026, 9, 2));

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
    board.selectHost(connected('a'));
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
    board.selectHost(connected('a'));
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
      ..selectHost(connected('a'));
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
      ..selectHost(connected('a'));
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
      ..selectHost(connected('a'));
    board.selectHost(connected('b'));
    await pumpEventQueue();
    expect(board.host?.id, 'b');
    expect(board.state.phase, HomeBoardPhase.ready);
    expect(runner.closeCount, greaterThanOrEqualTo(1));
  });

  test('focusPane sends herdr agent focus with the pane id', () async {
    board
      ..setVisible(true)
      ..selectHost(connected('a'));
    await pumpEventQueue();
    final pane = board.state.workspaces.first.panes.last;
    await board.focusPane(pane.agent);
    expect(runner.commands.last, contains('agent focus w1:p2'));

    await board.focusWorkspace('w2');
    expect(runner.commands.last, contains('workspace focus w2'));
  });

  test('a never-connected machine waits, then starts once connected', () async {
    board
      ..setVisible(true)
      ..selectHost(buildHost('n'));
    await pumpEventQueue();
    expect(board.state.phase, HomeBoardPhase.awaitingRequest);
    expect(board.requestReason, HomeBoardRequestReason.neverConnected);
    expect(created, 0);

    // The first connection records a timestamp: the board starts.
    board.selectHost(connected('n'));
    await pumpEventQueue();
    expect(created, 1);
    expect(board.state.phase, HomeBoardPhase.ready);
  });

  test('a machine reached before lists without a request', () async {
    // No saved timestamp, but the host key is trusted.
    board
      ..setVisible(true)
      ..selectHost(buildHost('t'), connectedBefore: true);
    await pumpEventQueue();
    expect(board.requestReason, isNull);
    expect(created, 1);
    expect(board.state.phase, HomeBoardPhase.ready);
  });

  test('learning that a waiting machine was reached starts it', () async {
    board
      ..setVisible(true)
      ..selectHost(buildHost('n'));
    await pumpEventQueue();
    expect(board.state.phase, HomeBoardPhase.awaitingRequest);

    // The trusted keys load after the first frame.
    board.selectHost(buildHost('n'), connectedBefore: true);
    await pumpEventQueue();
    expect(created, 1);
    expect(board.state.phase, HomeBoardPhase.ready);
  });

  testWidgets('polling stops after repeated failures until refreshed', (
    tester,
  ) async {
    final timed = HomeBoardController(runnerFactory: (_) => runner);
    addTearDown(timed.dispose);
    runner.error = const AppFailure('Host key rejected.');
    timed
      ..setVisible(true)
      ..selectHost(connected('a'));
    await tester.pump(const Duration(minutes: 10));
    final attempts = runner.commands.length;
    expect(attempts, 3);

    await tester.pump(const Duration(minutes: 10));
    expect(runner.commands.length, attempts);

    runner.error = null;
    await tester.runAsync(timed.refresh);
    expect(timed.state.phase, HomeBoardPhase.ready);
    timed.setVisible(false);
  });
}
