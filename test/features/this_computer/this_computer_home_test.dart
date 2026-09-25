import 'package:conduit/core/platform_features.dart';
import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/agent_attention/data/herdr_attention_provider.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_controller.dart';
import 'package:conduit/features/app_lock/presentation/app_lock_controller.dart';
import 'package:conduit/features/desktop_shell/domain/sidebar_tree.dart';
import 'package:conduit/features/backup/data/app_backup_service.dart';
import 'package:conduit/features/hosts/domain/home_preferences.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/hosts/presentation/home_board_controller.dart';
import 'package:conduit/features/hosts/presentation/hosts_controller.dart';
import 'package:conduit/features/hosts/presentation/hosts_page.dart';
import 'package:conduit/features/hosts/presentation/widgets/machine_switcher.dart';
import 'package:conduit/features/local_shell/presentation/local_shell_controller.dart';
import 'package:conduit/features/sessions/domain/connect_preferences.dart';
import 'package:conduit/features/sessions/presentation/session_connect_flow.dart';
import 'package:conduit/features/terminal/presentation/host_key_prompt_coordinator.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';
import 'package:conduit/features/this_computer/domain/this_computer_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';
import '../hosts/home_board_fakes.dart';

void main() {
  test('only desktops have This computer', () {
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      expect(PlatformFeatures.thisComputer, switch (platform) {
        TargetPlatform.linux ||
        TargetPlatform.macOS ||
        TargetPlatform.windows => true,
        _ => false,
      }, reason: platform.name);
    }
    debugDefaultTargetPlatformOverride = null;
    // The proot local shell stays an Android feature.
    expect(PlatformFeatures.prootLocalShell, isTrue);
  });

  test('This computer menus offer no edit, copy or delete', () {
    final choices = MachineMenuChoice.forHost(SavedHost.thisComputer());
    expect(choices, [
      MachineMenuChoice.connectTo,
      MachineMenuChoice.files,
      MachineMenuChoice.agentHooks,
    ]);
    expect(
      MachineMenuChoice.forHost(buildHost('a')),
      isNot(contains(MachineMenuChoice.shell)),
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(
      MachineMenuChoice.forHost(SavedHost.thisComputer()),
      contains(MachineMenuChoice.shell),
    );
    debugDefaultTargetPlatformOverride = null;
  });

  group('home page', () {
    late ThemeController themeController;
    late List<String> runnerHosts;
    late HerdrFakeRunner local;

    setUp(() async {
      themeController = ThemeController(InMemoryThemePreferences());
      await themeController.load();
      runnerHosts = [];
      local = HerdrFakeRunner(tmuxSessions: TmuxFixtures.sessions);
    });

    Future<(TerminalWorkspaceController, HostsController)> pumpHome(
      WidgetTester tester, {
      required bool desktop,
    }) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final hostsController = HostsController(
        FakeHostsRepository(),
        thisComputerStore: desktop
            ? InMemoryThisComputerStore(
                ThisComputerSettings(
                  // No agent polling timers in these tests.
                  host: SavedHost.thisComputer(
                    hostname: 'omarchy',
                  ).copyWith(agentAttentionEnabled: false),
                ),
              )
            : null,
      );
      final workspace = TerminalWorkspaceController(
        ImmediateTerminalRepository(TrackableTerminalSession()),
      );
      addTearDown(workspace.dispose);
      final agentAttention = AgentAttentionController(
        workspace: workspace,
        runnerFactory: (_) =>
            ScriptedAgentCommandRunner([StateError('no polling here')]),
        provider: const HerdrAttentionProvider(),
      );
      addTearDown(agentAttention.dispose);
      HerdrFakeRunner runnerFor(SavedHost host) {
        runnerHosts.add(host.id);
        return local;
      }

      final boards = HomeBoards(
        runnerFactory: runnerFor,
        pollInterval: const Duration(days: 1),
      );
      addTearDown(boards.dispose);
      final flow = SessionConnectFlow(
        hostsController: hostsController,
        workspace: workspace,
        runnerFactory: runnerFor,
        preferences: InMemoryConnectPreferencesRepository(),
      );
      final verifier = NoopVerifier();
      await tester.pumpWidget(
        MaterialApp(
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
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
      return (workspace, hostsController);
    }

    testWidgets('a desktop lists local Herdr and tmux with no saved machine', (
      tester,
    ) async {
      final (workspace, _) = await pumpHome(tester, desktop: true);

      expect(find.text('No saved machines yet'), findsNothing);
      expect(runnerHosts, contains(thisComputerHostId));
      expect(
        find.byKey(const ValueKey('other-herdr-$thisComputerHostId-w1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('other-tmux-$thisComputerHostId-main')),
        findsOneWidget,
      );

      // A local tmux session opens as a This computer session.
      await tester.tap(
        find.byKey(const ValueKey('other-tmux-$thisComputerHostId-main')),
      );
      await tester.pump();
      await tester.pump();
      final session = workspace.sessions.single;
      expect(session.host.id, '$thisComputerHostId#tmux:main');
      expect(session.host.isThisComputer, isTrue);
      expect(session.host.startTmuxOnConnect, isTrue);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the machine sheet shows This computer first', (tester) async {
      await pumpHome(tester, desktop: true);
      await tester.tap(find.byKey(const ValueKey('machine-name')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('machine-row-$thisComputerHostId')),
        findsOneWidget,
      );
      expect(find.text('This computer'), findsWidgets);
      await tester.tap(
        find.byKey(const ValueKey('machine-menu-$thisComputerHostId')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Connect to…'), findsOneWidget);
      expect(find.text('Files'), findsOneWidget);
      expect(find.text('Agent hooks'), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Delete'), findsNothing);
    });

    testWidgets('a desktop shows This computer and no proot "This device"', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await pumpHome(tester, desktop: true);
        // The desktop shell's sidebar lists This computer first.
        expect(
          find.byKey(
            ValueKey(
              'sidebar-row-machines-${SidebarKeys.machine(thisComputerHostId)}',
            ),
          ),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('machine-name')), findsNothing);
        expect(find.text('This device'), findsNothing);
        expect(find.text('Local shell sessions'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Android keeps the proot local shell section', (tester) async {
      await pumpHome(tester, desktop: false);
      await tester.tap(find.byKey(const ValueKey('machine-name')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('machine-filter-local')),
        findsOneWidget,
      );
      expect(find.text('This device'), findsOneWidget);
    });

    testWidgets('a phone has no This computer', (tester) async {
      await pumpHome(tester, desktop: false);
      expect(find.text('No saved machines yet'), findsOneWidget);
      expect(runnerHosts, isEmpty);
    });
  });

  test('a saved "This device" filter only survives on Android', () {
    const filter = MachineFilter({localMachineFilterKey, 'gone'});
    expect(filter.validFor(const []).keys, {localMachineFilterKey});
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(filter.validFor(const []).isAll, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });
}
