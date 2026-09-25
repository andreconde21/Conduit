import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/agent_attention/data/herdr_attention_provider.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_controller.dart';
import 'package:conduit/features/app_lock/presentation/app_lock_controller.dart';
import 'package:conduit/features/backup/data/app_backup_service.dart';
import 'package:conduit/features/desktop_shell/domain/sidebar_tree.dart';
import 'package:conduit/features/hosts/domain/home_preferences.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/hosts/presentation/home_board_controller.dart';
import 'package:conduit/features/hosts/presentation/hosts_controller.dart';
import 'package:conduit/features/hosts/presentation/hosts_page.dart';
import 'package:conduit/features/local_shell/presentation/local_shell_controller.dart';
import 'package:conduit/features/sessions/domain/connect_preferences.dart';
import 'package:conduit/features/sessions/presentation/session_connect_flow.dart';
import 'package:conduit/features/settings/presentation/settings_catalog.dart';
import 'package:conduit/features/settings/presentation/settings_page.dart';
import 'package:conduit/features/settings/presentation/settings_services.dart';
import 'package:conduit/features/terminal/presentation/host_key_prompt_coordinator.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';
import 'package:conduit/features/this_computer/domain/this_computer_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';
import '../hosts/home_board_fakes.dart';

/// The phone's SSH entry for this PC, synced here, and another machine.
final omarchy = buildHost(
  'omarchy-ssh',
).copyWith(name: 'omarchy', host: '100.97.235.112');
final box = buildHost('box').copyWith(name: 'box', host: 'box.lan');

void main() {
  late ThemeController themeController;
  late List<String> runnerHosts;

  setUp(() async {
    themeController = ThemeController(InMemoryThemePreferences());
    await themeController.load();
    runnerHosts = [];
  });

  Future<HostsController> matchedHosts() async {
    final hosts = HostsController(
      FakeHostsRepository()..persisted = [omarchy, box],
      thisComputerStore: InMemoryThisComputerStore(
        ThisComputerSettings(
          // No agent polling timers in these tests.
          host: SavedHost.thisComputer(
            hostname: 'omarchy',
          ).copyWith(agentAttentionEnabled: false),
        ),
      ),
    );
    await hosts.load();
    hosts.setSelfMachineId(omarchy.id);
    return hosts;
  }

  Future<HostsController> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final hostsController = await matchedHosts();
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
    final local = HerdrFakeRunner(tmuxSessions: TmuxFixtures.sessions);
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
    return hostsController;
  }

  testWidgets('the home and machine switcher fold it into This computer', (
    tester,
  ) async {
    await pumpHome(tester);

    // Its boards are listed through the local runner, never over SSH.
    expect(runnerHosts, contains(thisComputerHostId));
    expect(runnerHosts, isNot(contains(omarchy.id)));

    await tester.tap(find.byKey(const ValueKey('machine-name')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('machine-row-$thisComputerHostId')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('machine-row-box')), findsOneWidget);
    expect(find.byKey(ValueKey('machine-row-${omarchy.id}')), findsNothing);
    expect(find.text('This computer · omarchy'), findsWidgets);
  });

  testWidgets('the desktop sidebar lists This computer, not it', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await pumpHome(tester);
      Finder row(String id) => find.byKey(
        ValueKey('sidebar-row-machines-${SidebarKeys.machine(id)}'),
      );
      expect(row(thisComputerHostId), findsOneWidget);
      expect(row('box'), findsOneWidget);
      expect(row(omarchy.id), findsNothing);
      expect(find.textContaining('This computer · omarchy'), findsWidgets);
      expect(runnerHosts, isNot(contains(omarchy.id)));
      await tester.pumpWidget(const SizedBox());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Settings › Sync offers to show it separately', (tester) async {
    final hosts = await matchedHosts();
    final services = SettingsServices(
      theme: themeController,
      hostsController: hosts,
    );
    expect(
      settingsCatalog
          .where(
            (entry) => entry.title == 'This computer on your other devices',
          )
          .single
          .isAvailable(services),
      isTrue,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsSectionPage(
          section: SettingsSection.syncBackup,
          services: services,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('This computer on your other devices'), findsOneWidget);
    expect(
      find.textContaining('Also shown as omarchy on your other devices'),
      findsOneWidget,
    );
    final toggle = find.byKey(const ValueKey('settings-self-machine-switch'));
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(hosts.showSelfSeparately, isTrue);
    expect(hosts.sortedHosts, contains(omarchy));
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(hosts.sortedHosts, isNot(contains(omarchy)));
  });

  testWidgets('without a match Settings shows nothing about it', (
    tester,
  ) async {
    final hosts = HostsController(
      FakeHostsRepository()..persisted = [omarchy, box],
      thisComputerStore: InMemoryThisComputerStore(
        ThisComputerSettings(host: SavedHost.thisComputer()),
      ),
    );
    await hosts.load();
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsSectionPage(
          section: SettingsSection.syncBackup,
          services: SettingsServices(
            theme: themeController,
            hostsController: hosts,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('This computer on your other devices'), findsNothing);
  });
}
