import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/agent_attention/data/herdr_attention_provider.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_controller.dart';
import 'package:conduit/features/app_lock/presentation/app_lock_controller.dart';
import 'package:conduit/features/backup/data/app_backup_service.dart';
import 'package:conduit/features/desktop_shell/data/desktop_shell_store.dart';
import 'package:conduit/features/desktop_shell/presentation/desktop_shell_controller.dart';
import 'package:conduit/features/hosts/domain/home_preferences.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/hosts/presentation/home_board_controller.dart';
import 'package:conduit/features/hosts/presentation/hosts_controller.dart';
import 'package:conduit/features/hosts/presentation/hosts_page.dart';
import 'package:conduit/features/local_shell/presentation/local_shell_controller.dart';
import 'package:conduit/features/sessions/domain/connect_preferences.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/sessions/presentation/session_connect_flow.dart';
import 'package:conduit/features/terminal/presentation/host_key_prompt_coordinator.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';
import '../hosts/home_board_fakes.dart';

/// Demo machines for the shell tests.
final workstation = buildHost(
  'workstation',
).copyWith(name: 'workstation', lastConnectedAt: DateTime.utc(2026, 9, 2));
final buildBox = buildHost(
  'build-box',
).copyWith(name: 'build-box', lastConnectedAt: DateTime.utc(2026, 9, 2));

/// A home page running as the desktop shell over fake machines:
/// workstation (Herdr: Infrastructure needs you, TheCalendar done; tmux
/// main and build) and build-box (tmux only).
class ShellHarness {
  late ThemeController theme;
  late HostsController hosts;
  late TerminalWorkspaceController workspace;
  late AgentAttentionController attention;
  late HomeBoards boards;
  late SessionConnectFlow flow;
  late DesktopShellController shell;
  late InMemoryDesktopShellStore store;
  late FreshTerminalRepository terminals;
  final runners = <String, HerdrFakeRunner>{
    'workstation': HerdrFakeRunner(tmuxSessions: TmuxFixtures.sessions),
    'build-box': HerdrFakeRunner.tmuxOnly(
      tmuxSessions: 'ci\t1\t2\t1790229600\n',
    ),
  };

  HerdrFakeRunner runnerFor(SavedHost host) =>
      runners[baseHostId(host.id)] ?? HerdrFakeRunner.tmuxOnly();

  Widget page({bool? shellMode}) => MaterialApp(
    home: HostsPage(
      hostsController: hosts,
      lockController: AppLockController(AlwaysAuthenticates()),
      terminalRepository: NoNetworkTerminalRepository(),
      workspaceController: workspace,
      localShellController: LocalShellController(),
      themeController: theme,
      hostKeyVerifier: NoopVerifier(),
      promptCoordinator: HostKeyPromptCoordinator(),
      sftpRepository: NoNetworkSftpRepository(),
      sftpBookmarksRepository: InMemorySftpBookmarks(),
      agentAttention: attention,
      backupService: AppBackupService(
        hostsController: hosts,
        themeController: theme,
        hostKeyVerifier: NoopVerifier(),
      ),
      fileExport: RecordingFileExport(),
      homeBoards: boards,
      homePreferences: InMemoryHomePreferencesRepository(),
      connectFlow: flow,
      previewRefreshInterval: const Duration(days: 1),
      desktopShell: shell,
      shellMode: shellMode,
    ),
  );
}

Future<ShellHarness> pumpShell(
  WidgetTester tester, {
  InMemoryDesktopShellStore? store,
  Size size = const Size(1280, 800),
  double pixelRatio = 1,
  bool? shellMode,
  void Function(ShellHarness harness)? before,
}) async {
  tester.view.physicalSize = size * pixelRatio;
  tester.view.devicePixelRatio = pixelRatio;
  addTearDown(tester.view.reset);
  final harness = ShellHarness();
  harness.theme = ThemeController(InMemoryThemePreferences());
  await harness.theme.load();
  final repository = FakeHostsRepository()..persisted = [workstation, buildBox];
  harness.hosts = HostsController(repository);
  await harness.hosts.load();
  harness.terminals = FreshTerminalRepository();
  harness.workspace = TerminalWorkspaceController(harness.terminals);
  addTearDown(harness.workspace.dispose);
  harness.attention = AgentAttentionController(
    workspace: harness.workspace,
    runnerFactory: (_) =>
        ScriptedAgentCommandRunner([StateError('no polling here')]),
    provider: const HerdrAttentionProvider(),
  );
  addTearDown(harness.attention.dispose);
  harness.boards = HomeBoards(
    runnerFactory: harness.runnerFor,
    pollInterval: const Duration(days: 1),
  );
  addTearDown(harness.boards.dispose);
  harness.flow = SessionConnectFlow(
    hostsController: harness.hosts,
    workspace: harness.workspace,
    runnerFactory: harness.runnerFor,
    preferences: InMemoryConnectPreferencesRepository(),
  );
  harness.store = store ?? InMemoryDesktopShellStore();
  harness.shell = DesktopShellController(
    store: harness.store,
    saveDelay: const Duration(milliseconds: 10),
  );
  addTearDown(harness.shell.dispose);
  before?.call(harness);
  await tester.pumpWidget(harness.page(shellMode: shellMode));
  await settleShell(tester);
  return harness;
}

/// Lets boards list, the layout load and a few frames run.
Future<void> settleShell(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Unmounts the page and lets timers (Herdr timeouts, debounces) finish.
Future<void> tearDownShell(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 3));
}
