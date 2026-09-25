import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/agent_attention/data/herdr_attention_provider.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_controller.dart';
import 'package:conduit/features/app_lock/presentation/app_lock_controller.dart';
import 'package:conduit/features/backup/data/app_backup_service.dart';
import 'package:conduit/features/hosts/domain/home_preferences.dart';
import 'package:conduit/features/hosts/presentation/home_board_controller.dart';
import 'package:conduit/features/hosts/presentation/hosts_controller.dart';
import 'package:conduit/features/hosts/presentation/hosts_page.dart';
import 'package:conduit/features/local_shell/presentation/local_shell_controller.dart';
import 'package:conduit/features/session_navigation/domain/session_view_preferences.dart';
import 'package:conduit/features/session_navigation/presentation/session_view_controller.dart';
import 'package:conduit/features/sessions/domain/connect_preferences.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/sessions/presentation/session_connect_flow.dart';
import 'package:conduit/features/terminal/presentation/host_key_prompt_coordinator.dart';
import 'package:conduit/features/terminal/presentation/terminal_page.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';
import '../hosts/home_board_fakes.dart';

/// The quick switcher from the home page: its top-bar button and Ctrl+K,
/// with the machines' other workspaces; and a tile's "Open in…".
void main() {
  late ThemeController themeController;

  setUp(() async {
    themeController = ThemeController(InMemoryThemePreferences());
    await themeController.load();
  });

  final switcher = find.byKey(const ValueKey('quick-switcher'));
  final machine = buildHost('a').copyWith(lastConnectedAt: DateTime.utc(2026));

  late SessionConnectFlow flow;

  Future<(TerminalWorkspaceController, SessionViewController)> pumpHome(
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final hostsController = HostsController(
      FakeHostsRepository()..persisted = [machine],
    );
    final workspace = TerminalWorkspaceController(
      ImmediateTerminalRepository(TrackableTerminalSession()),
    );
    addTearDown(workspace.dispose);
    final agentAttention = AgentAttentionController(
      workspace: workspace,
      runnerFactory: (_) => ScriptedAgentCommandRunner([
        StateError('no agent polling in this test'),
      ]),
      provider: const HerdrAttentionProvider(),
    );
    addTearDown(agentAttention.dispose);
    final runner = HerdrFakeRunner();
    final boards = HomeBoards(
      runnerFactory: (_) => runner,
      pollInterval: const Duration(days: 1),
    );
    addTearDown(boards.dispose);
    final preferences = InMemoryConnectPreferencesRepository();
    await preferences.save(
      'a',
      const ConnectPreferences().withChoice(
        const ConnectTarget.tmux('old'),
        remember: false,
      ),
    );
    flow = SessionConnectFlow(
      hostsController: hostsController,
      workspace: workspace,
      runnerFactory: (_) => runner,
      preferences: preferences,
    );
    final views = SessionViewController(
      InMemorySessionViewPreferencesRepository(),
    );
    addTearDown(views.dispose);
    final verifier = NoopVerifier();
    await tester.pumpWidget(
      SessionViewScope(
        controller: views,
        child: MaterialApp(
          home: HostsPage(
            hostsController: hostsController,
            lockController: AppLockController(AlwaysAuthenticates()),
            terminalRepository: NoNetworkTerminalRepository(),
            workspaceController: workspace,
            localShellController: LocalShellController(),
            themeController: themeController,
            hostKeyVerifier: verifier,
            promptCoordinator: HostKeyPromptCoordinator(),
            sftpRepository: NoNetworkSftpRepository(),
            sftpBookmarksRepository: InMemorySftpBookmarks(),
            agentAttention: agentAttention,
            backupService: AppBackupService(
              hostsController: hostsController,
              themeController: themeController,
              hostKeyVerifier: verifier,
            ),
            fileExport: RecordingFileExport(),
            homeBoards: boards,
            homePreferences: InMemoryHomePreferencesRepository(),
            connectFlow: flow,
            previewRefreshInterval: const Duration(days: 1),
          ),
        ),
      ),
    );
    for (var i = 0; i < 4; i += 1) {
      await tester.pump();
    }
    return (workspace, views);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i += 1) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('the top bar opens the switcher with the machine\'s other '
      'workspaces and recents; one opens in the terminal', (tester) async {
    final (workspace, _) = await pumpHome(tester);

    await tester.tap(find.byTooltip('Switch sessions'));
    await settle(tester);

    expect(switcher, findsOneWidget);
    Finder inSwitcher(Finder finder) =>
        find.descendant(of: switcher, matching: finder);
    expect(inSwitcher(find.text('OTHER WORKSPACES')), findsOneWidget);
    expect(inSwitcher(find.text('RECENT')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('switcher-recent-a-tmux:old')),
      findsOneWidget,
    );
    final infra = find.byKey(const ValueKey('switcher-workspace-a-herdr-w1'));
    expect(infra, findsOneWidget);

    await tester.tap(infra);
    await settle(tester);

    expect(switcher, findsNothing);
    expect(workspace.activeSession?.host.id, startsWith('a#herdr:w1'));
    expect(find.byType(TerminalPage), findsOneWidget);
    // Herdr's re-focus after attaching.
    await flow.herdr.dispose();
  });

  testWidgets('Ctrl+K opens it on the home page', (tester) async {
    await pumpHome(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);

    expect(switcher, findsOneWidget);
  });

  testWidgets('a session tile\'s long-press sets where it opens', (
    tester,
  ) async {
    final (workspace, views) = await pumpHome(tester);
    workspace.open(const ConnectTarget.tmux('work').apply(machine));
    await settle(tester);

    await tester.longPress(
      find.byKey(const ValueKey('home-session-a#tmux:work')),
    );
    await settle(tester);
    expect(find.text('Default (Terminal)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('session-action-open-in')));
    await settle(tester);
    await tester.tap(find.text('Always open in Chat View'));
    await settle(tester);

    expect(views.overrideFor('a#tmux:work'), SessionView.chat);
  });
}
