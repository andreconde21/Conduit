import 'package:conduit/core/presentation/multiplexer_icon.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/desktop_shell/domain/sidebar_prefs.dart';
import 'package:conduit/features/desktop_shell/domain/sidebar_tree.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/hosts/presentation/home_board_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';
import '../hosts/home_board_fakes.dart';

SavedHost connected(String id) =>
    buildHost(id).copyWith(lastConnectedAt: DateTime.utc(2026, 9, 2));

/// The board a [HerdrFakeRunner] machine lists, through the real
/// [HomeBoardController].
Future<HomeBoardState> fakeBoard(SavedHost host, HerdrFakeRunner runner) async {
  final board = HomeBoardController(
    runnerFactory: (_) => runner,
    pollInterval: const Duration(days: 1),
  );
  addTearDown(board.dispose);
  board
    ..selectHost(host)
    ..setVisible(true);
  await board.pollNow();
  await pumpEventQueue();
  return board.state;
}

void main() {
  group('SidebarTreeBuilder', () {
    test('machines, Herdr workspaces, tabs and agents from a board', () async {
      final host = connected('a');
      final board = await fakeBoard(
        host,
        HerdrFakeRunner(tmuxSessions: TmuxFixtures.sessions),
      );
      final tree = SidebarTreeBuilder.build([
        SidebarMachineInput(
          host: SavedHost.thisComputer(),
          openSessions: const [
            SidebarOpenSession(
              sessionHostId: thisComputerHostId,
              title: 'This computer',
            ),
          ],
        ),
        SidebarMachineInput(host: host, board: board),
      ], const SidebarPrefs());

      expect(tree.map((node) => node.label), ['This computer', 'Host a']);
      final local = tree.first;
      expect(local.openInApp, isTrue);
      expect(local.children.single.kind, SidebarNodeKind.openSession);
      expect(local.children.single.detail, 'Shell');

      final machine = tree.last;
      expect(machine.kind, SidebarNodeKind.machine);
      // Needs you rolls up to the machine.
      expect(machine.dot, SidebarDot.needsYou);
      expect(machine.children.map((node) => node.label), [
        'Infrastructure',
        'TheCalendar',
        'main',
        'build',
      ]);
      final infra = machine.children.first;
      expect(infra.multiplexer, MultiplexerKind.herdr);
      expect(infra.dot, SidebarDot.needsYou);
      // Tabs by their labels (never ids), agents inside them.
      expect(infra.children.map((node) => node.label), ['main', 'review']);
      expect(infra.children.first.kind, SidebarNodeKind.herdrTab);
      expect(infra.children.first.agentKind, 'claude');
      expect(infra.children.last.dot, SidebarDot.needsYou);
      final calendar = machine.children[1];
      expect(calendar.dot, SidebarDot.done);
      expect(calendar.children.single.label, 'Tab 1');

      final tmux = machine.children[2];
      expect(tmux.kind, SidebarNodeKind.tmuxSession);
      expect(tmux.multiplexer, MultiplexerKind.tmux);
      expect(tmux.detail, '3 windows');
      expect(tmux.lazyChildren, isTrue);
      // Keys nest, so a prefix covers a subtree.
      expect(SidebarKeys.isUnder(infra.children.last.key, infra.key), isTrue);
      expect(SidebarKeys.machineIdOf(infra.key), 'a');
    });

    test(
      'open sessions mark their workspace; tmux windows get agents',
      () async {
        final host = connected('a');
        final board = await fakeBoard(
          host,
          HerdrFakeRunner(tmuxSessions: TmuxFixtures.sessions),
        );
        final tree = SidebarTreeBuilder.build([
          SidebarMachineInput(
            host: host,
            board: board,
            openSessions: const [
              SidebarOpenSession(
                sessionHostId: 'a#herdr:w2',
                title: 'a: TheCalendar',
                herdrWorkspaceId: 'w2',
              ),
              SidebarOpenSession(
                sessionHostId: 'a#tmux:main',
                title: 'a: main',
                tmuxSession: 'main',
              ),
            ],
            agents: const [
              AgentInfo(
                id: 's1',
                name: 'todo-api',
                state: AgentAttentionState.working,
                kind: 'claude',
                tab: 'main:1',
              ),
            ],
            tmuxWindows: {'main': TmuxFixture.windows},
          ),
        ], const SidebarPrefs());
        final machine = tree.single;
        expect(
          machine.children
              .where((node) => node.openInApp)
              .map((node) => node.label),
          ['TheCalendar', 'main'],
        );
        // No separate rows for sessions a workspace already stands for.
        expect(
          machine.children.where(
            (node) => node.kind == SidebarNodeKind.openSession,
          ),
          isEmpty,
        );
        final main = machine.children.firstWhere(
          (node) => node.label == 'main',
        );
        expect(main.lazyChildren, isFalse);
        expect(main.children.map((node) => node.label), [
          '0: zsh',
          '1: claude',
          '2: logs',
        ]);
        expect(main.children[1].dot, SidebarDot.working);
        expect(main.children[1].agentKind, 'claude');
        expect(main.dot, SidebarDot.working);
      },
    );

    test('the companion names Herdr panes', () async {
      final host = connected('a');
      final board = await fakeBoard(host, HerdrFakeRunner());
      final tree = SidebarTreeBuilder.build([
        SidebarMachineInput(
          host: host,
          board: board,
          agents: const [
            AgentInfo(
              id: 's-infra',
              name: 'infra-deploy',
              state: AgentAttentionState.needsInput,
              workspace: 'w1',
              tab: 'w1:t1',
              pane: 'w1:p1',
            ),
          ],
        ),
      ], const SidebarPrefs());
      final infra = tree.single.children.first;
      final main = infra.children.first;
      expect(main.dot, SidebarDot.needsYou);
      final panes = SidebarTreeBuilder.needsYou(tree);
      expect(panes.map((node) => node.label), contains('main'));
      expect(panes.map((node) => node.label), contains('review'));
      final pane = (main.target as HerdrTabTarget).workspace.panes.firstWhere(
        (pane) => pane.agent.pane == 'w1:p1',
      );
      expect(pane.title, 'infra-deploy');
      // Herdr's kind is kept when the companion does not report one.
      expect(pane.agent.kind, 'claude');
    });

    test('saved order and filter', () async {
      final a = connected('a');
      final b = connected('b');
      final board = await fakeBoard(a, HerdrFakeRunner());
      final inputs = [
        SidebarMachineInput(host: a, board: board),
        SidebarMachineInput(host: b),
      ];
      final prefs = const SidebarPrefs(machineOrder: ['b', 'a']).moveChild(
        'a',
        SidebarKeys.herdrWorkspace('a', 'w2'),
        visibleOrder: [
          SidebarKeys.herdrWorkspace('a', 'w1'),
          SidebarKeys.herdrWorkspace('a', 'w2'),
        ],
        beforeKey: SidebarKeys.herdrWorkspace('a', 'w1'),
      );
      final tree = SidebarTreeBuilder.build(inputs, prefs);
      expect(tree.map((node) => node.label), ['Host b', 'Host a']);
      expect(tree.last.children.map((node) => node.label), [
        'TheCalendar',
        'Infrastructure',
      ]);

      final filtered = SidebarTreeBuilder.filter(tree, 'proofing');
      expect(filtered.map((node) => node.label), ['Host a']);
      expect(filtered.single.children.single.label, 'Infrastructure');
      expect(filtered.single.children.single.children.single.label, 'review');
      expect(
        filtered.single.children.single.children.single.detail,
        'Proofing PR 398',
      );
      // A matching machine keeps everything under it.
      expect(
        SidebarTreeBuilder.filter(tree, 'HOST A').single.children.length,
        2,
      );
      expect(SidebarTreeBuilder.filter(tree, 'nothing'), isEmpty);
      expect(
        SidebarTreeBuilder.find(
          tree,
          SidebarKeys.herdrWorkspace('a', 'w2'),
        )?.label,
        'TheCalendar',
      );
    });
  });
}

/// Parsed [TmuxFixtures.windows].
abstract final class TmuxFixture {
  static final windows = HomeTmuxCommands.parseWindows(TmuxFixtures.windows);
}
