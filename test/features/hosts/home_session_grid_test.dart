import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/hosts/presentation/home_board_controller.dart';
import 'package:conduit/features/hosts/presentation/widgets/home_session_grid.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/sessions/domain/remote_session_listing.dart';
import 'package:conduit/features/terminal/presentation/terminal_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

HomeBoardWorkspace workspace(
  String id,
  String label, {
  List<AgentAttentionState> states = const [],
  String status = '',
  int tabs = 0,
}) {
  return HomeBoardWorkspace(
    workspace: HerdrWorkspaceInfo(
      id: id,
      label: label,
      agentStatus: status,
      tabCount: tabs,
    ),
    panes: [
      for (var index = 0; index < states.length; index++)
        HomeBoardPane(
          agent: AgentInfo(
            id: '$id:p$index',
            name: 'agent $index',
            state: states[index],
            workspace: id,
            pane: '$id:p$index',
          ),
        ),
    ],
  );
}

void main() {
  final palette = AppPalette.values.first;

  Widget host(Widget child, {double width = 190, double height = 290}) =>
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: width, height: height, child: child),
          ),
        ),
      );

  TerminalSessionController session(SavedHostBuilder build) {
    final controller = TerminalSessionController(
      host: build(),
      repository: ImmediateTerminalRepository(TrackableTerminalSession()),
    );
    addTearDown(controller.dispose);
    return controller;
  }

  group('HomeGridMetrics', () {
    test('two large 4:5 columns on a Galaxy M53', () {
      // 1080 px at 2.625 px/dp.
      final metrics = HomeGridMetrics.of(1080 / 2.625);
      expect(metrics.columns, 2);
      expect(metrics.tileWidth, closeTo(183.7, 0.5));
      expect(
        metrics.sessionExtent,
        closeTo(metrics.tileWidth * 1.25 + HomeGridMetrics.labelHeight, 0.01),
      );
      expect(HomeGridMetrics.of(1080 / 2.625, large: true).columns, 1);
      expect(HomeGridMetrics.of(700).columns, 3);
    });
  });

  group('HomeSessionInfo', () {
    test('uses the live Herdr workspace name and state', () {
      final herdr = session(
        () => const ConnectTarget.herdr(
          workspaceId: 'w1',
          label: 'Old name',
        ).apply(buildHost('a')),
      );
      final info = HomeSessionInfo.of(
        herdr,
        workspaces: [
          workspace(
            'w1',
            'Infrastructure',
            states: [
              AgentAttentionState.working,
              AgentAttentionState.needsInput,
            ],
          ),
        ],
      );
      expect(info.isHerdr, isTrue);
      expect(info.targetLabel, 'Infrastructure');
      expect(info.agentState, AgentAttentionState.needsInput);

      // Without the board the name baked into the title is used.
      expect(HomeSessionInfo.of(herdr).targetLabel, 'Old name');
      expect(HomeSessionInfo.of(session(() => buildHost('p'))).targetLabel, '');
    });
  });

  group('HomeSessionTile', () {
    testWidgets('shows badge, title, workspace and agent state', (
      tester,
    ) async {
      final herdr = session(
        () => const ConnectTarget.herdr(
          workspaceId: 'w1',
          label: 'DTech',
        ).apply(buildHost('a').copyWith(useMosh: true)),
      );
      herdr.terminal.write('hello from herdr');
      var taps = 0;
      var longPresses = 0;
      await tester.pumpWidget(
        host(
          HomeSessionTile(
            session: herdr,
            info: HomeSessionInfo.of(
              herdr,
              agentState: AgentAttentionState.needsInput,
            ),
            palette: palette,
            brightness: Brightness.dark,
            fontFamily: 'monospace',
            onTap: () => taps += 1,
            onLongPress: () => longPresses += 1,
          ),
        ),
      );

      expect(find.text('Mosh'), findsOneWidget);
      expect(find.text('Host a: DTech'), findsNWidgets(2));
      expect(find.text('DTech'), findsOneWidget);
      expect(find.byIcon(herdrIcon), findsOneWidget);
      expect(find.text('Needs input'), findsOneWidget);
      final dot = tester.widget<Container>(
        find.byKey(const ValueKey('home-tile-dot')),
      );
      expect((dot.decoration! as BoxDecoration).color, const Color(0xFFF59E0B));
      final text = tester.widget<RichText>(
        find.byKey(const ValueKey('live-preview-text')),
      );
      expect(text.text.toPlainText(), contains('hello from herdr'));

      await tester.tap(find.byType(InkWell));
      await tester.longPress(find.byType(InkWell));
      expect((taps, longPresses), (1, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an idle session says so and shows SSH', (tester) async {
      final plain = session(() => buildHost('p'));
      await tester.pumpWidget(
        host(
          HomeSessionTile(
            session: plain,
            info: HomeSessionInfo.of(plain),
            palette: palette,
            brightness: Brightness.dark,
            fontFamily: 'monospace',
            onTap: () {},
            onLongPress: () {},
          ),
        ),
      );
      expect(find.text('SSH'), findsOneWidget);
      expect(find.text('Not connected'), findsOneWidget);
      expect(find.text(plain.host.endpoint), findsOneWidget);
    });
  });

  group('DormantWorkspaceTile', () {
    testWidgets('names the workspace and counts its agents by state', (
      tester,
    ) async {
      var opened = 0;
      await tester.pumpWidget(
        host(
          DormantWorkspaceTile(
            workspace: workspace(
              'w3',
              'TheCalendar',
              tabs: 3,
              states: [
                AgentAttentionState.working,
                AgentAttentionState.working,
                AgentAttentionState.needsInput,
              ],
            ),
            palette: palette,
            brightness: Brightness.dark,
            onTap: () => opened += 1,
          ),
          height: 118,
        ),
      );
      expect(find.text('TheCalendar'), findsOneWidget);
      expect(find.text('3 agents · 3 tabs'), findsOneWidget);
      expect(find.text('Needs input'), findsOneWidget);
      expect(find.text('Working ×2'), findsOneWidget);
      await tester.tap(find.text('TheCalendar'));
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('falls back to Herdr\'s workspace status', (tester) async {
      await tester.pumpWidget(
        host(
          DormantWorkspaceTile(
            workspace: workspace('w4', 'Quiet', status: 'done'),
            palette: palette,
            brightness: Brightness.dark,
            onTap: () {},
          ),
          height: 118,
        ),
      );
      expect(find.text('Not open in the app'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });
  });

  group('HomeBoardNotice', () {
    test('explains every state the board cannot list in', () {
      HomeBoardNotice? of(
        HomeBoardPhase phase, {
        HomeBoardRequestReason? reason,
        String? message,
        List<HomeBoardWorkspace> workspaces = const [],
        bool herdrOpen = false,
      }) => HomeBoardNotice.of(
        HomeBoardState(phase: phase, message: message, workspaces: workspaces),
        requestReason: reason,
        hasOpenHerdrSession: herdrOpen,
      );

      expect(of(HomeBoardPhase.idle), isNull);
      expect(
        of(
          HomeBoardPhase.awaitingRequest,
          reason: HomeBoardRequestReason.hardwareKey,
        )!.title,
        'Hardware-key login',
      );
      final never = of(
        HomeBoardPhase.awaitingRequest,
        reason: HomeBoardRequestReason.neverConnected,
      )!;
      expect(never.title, 'Not connected yet');
      expect(never.action, HomeBoardNoticeAction.request);
      expect(of(HomeBoardPhase.loading)!.busy, isTrue);
      expect(
        of(HomeBoardPhase.notInstalled)!.action,
        HomeBoardNoticeAction.openShell,
      );
      expect(
        of(HomeBoardPhase.notRunning)!.action,
        HomeBoardNoticeAction.startHerdr,
      );
      final failed = of(HomeBoardPhase.failed, message: 'timed out')!;
      expect(failed.title, 'Could not list Herdr workspaces');
      expect(failed.message, 'timed out');
      expect(failed.action, HomeBoardNoticeAction.retry);
      expect(
        of(HomeBoardPhase.failed, workspaces: [workspace('w1', 'A')])!.title,
        'Showing the last list',
      );
      expect(of(HomeBoardPhase.ready)!.title, 'No Herdr workspaces');
      expect(of(HomeBoardPhase.ready, herdrOpen: true), isNull);
      expect(
        of(HomeBoardPhase.ready, workspaces: [workspace('w1', 'A')]),
        isNull,
      );
    });

    testWidgets('the tile shows the reason and runs the action', (
      tester,
    ) async {
      var acted = 0;
      await tester.pumpWidget(
        host(
          HomeBoardNoticeTile(
            notice: HomeBoardNotice.of(
              const HomeBoardState(
                phase: HomeBoardPhase.failed,
                message: 'Connection refused',
              ),
            )!,
            palette: palette,
            brightness: Brightness.dark,
            onAction: () => acted += 1,
          ),
          width: 380,
          height: 100,
        ),
      );
      expect(find.text('Connection refused'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(acted, 1);
    });
  });
}

typedef SavedHostBuilder = SavedHost Function();
