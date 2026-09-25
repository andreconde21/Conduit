@Tags(['screenshots'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conduit/core/presentation/adaptive_modal.dart';
import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/core/theme/theme_preferences_repository.dart';
import 'package:conduit/features/agent_attention/data/conductore_host_attention_provider.dart';
import 'package:conduit/features/agent_attention/data/herdr_attention_provider.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_controller.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_sheet.dart';
import 'package:conduit/features/app_lock/presentation/app_lock_controller.dart';
import 'package:conduit/features/backup/data/app_backup_service.dart';
import 'package:conduit/features/chat_view/presentation/chat_view_controller.dart';
import 'package:conduit/features/chat_view/presentation/chat_view_page.dart';
import 'package:conduit/features/chat_view/presentation/chat_view_presenter.dart';
import 'package:conduit/features/companion_setup/data/companion_bundle.dart';
import 'package:conduit/features/companion_setup/presentation/companion_setup_controller.dart';
import 'package:conduit/features/companion_setup/presentation/companion_setup_page.dart';
import 'package:conduit/features/desktop_shell/data/desktop_shell_store.dart';
import 'package:conduit/features/desktop_shell/domain/shell_layout.dart';
import 'package:conduit/features/desktop_shell/domain/sidebar_prefs.dart';
import 'package:conduit/features/desktop_shell/presentation/desktop_home.dart';
import 'package:conduit/features/desktop_shell/presentation/desktop_shell_controller.dart';
import 'package:conduit/features/hosts/domain/home_preferences.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/hosts/presentation/home_board_controller.dart';
import 'package:conduit/features/hosts/presentation/hosts_controller.dart';
import 'package:conduit/features/hosts/presentation/hosts_page.dart';
import 'package:conduit/features/live_preview/presentation/preview_ready_controller.dart';
import 'package:conduit/features/local_shell/presentation/local_shell_controller.dart';
import 'package:conduit/features/prompt_menus/presentation/prompt_menu_strip.dart';
import 'package:conduit/features/sessions/domain/connect_preferences.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/sessions/presentation/session_connect_flow.dart';
import 'package:conduit/features/sync/data/sync_crypto.dart';
import 'package:conduit/features/sync/data/sync_setup.dart';
import 'package:conduit/features/sync/data/sync_state_store.dart';
import 'package:conduit/features/sync/presentation/sync_controller.dart';
import 'package:conduit/features/sync/presentation/sync_page.dart';
import 'package:conduit/features/sync/presentation/widgets/qr_code_view.dart';
import 'package:conduit/features/terminal/domain/herdr_keymap.dart';
import 'package:conduit/features/terminal/domain/herdr_navigator.dart';
import 'package:conduit/features/terminal/domain/host_key_verifier.dart';
import 'package:conduit/features/terminal/presentation/host_key_prompt_coordinator.dart';
import 'package:conduit/features/terminal/presentation/terminal_page.dart';
import 'package:conduit/features/terminal/presentation/terminal_session_controller.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';
import 'package:conduit/features/this_computer/domain/this_computer_settings.dart';
import 'package:conduit/features/voice/presentation/dictation_controller.dart';
import 'package:conduit/features/voice/presentation/voice_settings_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../features/chat_view/chat_fixtures.dart';
import '../features/companion_setup/companion_fakes.dart' show MatchingRunner;
import '../features/hosts/home_board_fakes.dart';
import '../features/sync/fake_sync_hub.dart';
import '../features/sync/sync_test_support.dart';
import '../features/terminal/herdr/fake_herdr_runner.dart';
import '../features/voice/fake_speech_recognizer.dart';
import '../features/voice/fake_tts.dart';
import '../support/test_doubles.dart';
import 'demo_screens.dart';
import 'screenshot_harness.dart';

// Demo machines. Nothing here points at a real host.
final workstation = SavedHost(
  id: 'workstation',
  name: 'workstation',
  host: 'workstation.local',
  port: 22,
  username: 'demo',
  authMethod: SshAuthMethod.password,
  password: 'demo',
  agentAttentionEnabled: true,
  lastConnectedAt: DateTime.utc(2026, 9, 25, 9),
);
final buildBox = SavedHost(
  id: 'build-box',
  name: 'build-box',
  host: 'build-box.local',
  port: 22,
  username: 'demo',
  authMethod: SshAuthMethod.password,
  password: 'demo',
  lastConnectedAt: DateTime.utc(2026, 9, 25, 8),
);

/// Herdr on the workstation: api (blocked), web (working), infra (done).
const workstationWorkspaces =
    '{"id":"1","result":{"workspaces":['
    '{"workspace_id":"w1","label":"api","number":1,'
    '"agent_status":"blocked","focused":true,"tab_count":4,'
    '"active_tab_id":"w1:t1"},'
    '{"workspace_id":"w2","label":"web","number":2,'
    '"agent_status":"working","tab_count":1,"active_tab_id":"w2:t1"},'
    '{"workspace_id":"w3","label":"infra","number":3,'
    '"agent_status":"done","tab_count":3,"active_tab_id":"w3:t1"},'
    '{"workspace_id":"w4","label":"docs","number":4,'
    '"agent_status":"idle","tab_count":1,"active_tab_id":"w4:t1"}]}}';

/// `herdr tab list` (Herdr 0.9.1 shape): api has four tabs, claude focused.
const workstationTabs =
    '{"id":"2","result":{"tabs":['
    '{"tab_id":"w1:t1","workspace_id":"w1","label":"claude","number":1,'
    '"agent_status":"working","focused":true,"pane_count":1},'
    '{"tab_id":"w1:t2","workspace_id":"w1","label":"server","number":2,'
    '"agent_status":"idle","focused":false,"pane_count":1},'
    '{"tab_id":"w1:t3","workspace_id":"w1","label":"tests","number":3,'
    '"agent_status":"blocked","focused":false,"pane_count":2},'
    '{"tab_id":"w1:t4","workspace_id":"w1","label":"logs","number":4,'
    '"agent_status":"idle","focused":false,"pane_count":1},'
    '{"tab_id":"w2:t1","workspace_id":"w2","label":"claude","number":1,'
    '"agent_status":"working","focused":true,"pane_count":1},'
    '{"tab_id":"w3:t1","workspace_id":"w3","label":"plan","number":1,'
    '"agent_status":"done","focused":true,"pane_count":1},'
    '{"tab_id":"w3:t2","workspace_id":"w3","label":"apply","number":2,'
    '"agent_status":"working","focused":false,"pane_count":1},'
    '{"tab_id":"w3:t3","workspace_id":"w3","label":"logs","number":3,'
    '"agent_status":"idle","focused":false,"pane_count":1},'
    '{"tab_id":"w4:t1","workspace_id":"w4","label":"","number":1,'
    '"agent_status":"idle","focused":true,"pane_count":1}]}}';

/// Herdr on This computer: one workspace, "notes".
const thisComputerWorkspaces =
    '{"id":"1","result":{"workspaces":['
    '{"workspace_id":"w1","label":"notes","number":1,'
    '"agent_status":"idle","focused":true,"tab_count":1,'
    '"active_tab_id":"w1:t1"}]}}';

const workstationAgents =
    '{"id":"3","result":{"agents":['
    '{"agent":"claude","pane_id":"w1:p1","tab_id":"w1:t1",'
    '"workspace_id":"w1","agent_status":"blocked",'
    '"terminal_title_stripped":"Due dates for todos"},'
    '{"agent":"claude","pane_id":"w2:p1","tab_id":"w2:t1",'
    '"workspace_id":"w2","agent_status":"working",'
    '"terminal_title_stripped":"Keyboard shortcuts"},'
    '{"agent":"claude","pane_id":"w3:p1","tab_id":"w3:t1",'
    '"workspace_id":"w3","agent_status":"done",'
    '"terminal_title_stripped":"Terraform plan"},'
    '{"agent":"codex","pane_id":"w3:p2","tab_id":"w3:t2",'
    '"workspace_id":"w3","agent_status":"working",'
    '"terminal_title_stripped":"Apply staging"}]}}';

/// `tmux list-sessions` lines, active [minutesAgo] minutes ago.
String tmuxLine(
  String name, {
  int attached = 0,
  int windows = 1,
  int minutesAgo = 3,
}) {
  final activity =
      DateTime.now()
          .subtract(Duration(minutes: minutesAgo))
          .millisecondsSinceEpoch ~/
      1000;
  return '$name\t$attached\t$windows\t$activity\n';
}

String buildBoxTmux() =>
    tmuxLine('ci', attached: 1, windows: 2, minutesAgo: 1) +
    tmuxLine('deploy', minutesAgo: 42);

/// One terminal session per connect whose screen is written by the test.
class DemoTerminalRepository extends FreshTerminalRepository {}

Future<TerminalSessionController> openDemoSession(
  WidgetTester tester,
  TerminalWorkspaceController workspace,
  SavedHost host,
  String screen, {
  int columns = 46,
  int rows = 40,
}) async {
  final session = workspace.open(host);
  await tester.runAsync(session.connect);
  session.terminal.resize(columns, rows);
  session.terminal.write(screen);
  return session;
}

class _NoopWakelock extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}

  @override
  Future<bool> get enabled async => false;
}

AgentCommandResult ok(String stdout) =>
    AgentCommandResult(stdout: stdout, stderr: '', exitCode: 0);

/// `herdr pane list`: the focused Claude pane of workspace api.
const workstationPanes =
    '{"id":"cli:pane:list","result":{"panes":['
    '{"pane_id":"w1:p1","workspace_id":"w1","tab_id":"w1:t1",'
    '"cwd":"/home/demo/todo-api","focused":true},'
    '{"pane_id":"w1:p2","workspace_id":"w1","tab_id":"w1:t2",'
    '"cwd":"/home/demo/todo-api"}],"type":"pane_list"}}';

/// Answers the Herdr CLI on the workstation from the demo fixtures.
AgentCommandResult workstationHerdr(String command) {
  if (command.contains('herdr/config.toml')) {
    return const AgentCommandResult(stdout: '', stderr: '', exitCode: 1);
  }
  if (command.contains('pane list')) return ok(workstationPanes);
  if (command.contains('workspace list')) return ok(workstationWorkspaces);
  if (command.contains('tab list')) return ok(workstationTabs);
  if (command.contains('agent list')) return ok(workstationAgents);
  return ok('');
}

/// The bundled companion's version, so the hooks screen reads up to date.
Future<CompanionBundle> loadCompanionBundle() async {
  final manifest =
      jsonDecode(File('assets/companion/manifest.json').readAsStringSync())
          as Map<String, Object?>;
  return CompanionBundle(
    version: manifest['version']! as String,
    archive: Uint8List(0),
  );
}

int minutesAgo(int minutes) =>
    DateTime.now().subtract(Duration(minutes: minutes)).millisecondsSinceEpoch;

/// One agent in `conductore-hostd status`.
String agentJson(
  String id,
  String name, {
  required String state,
  required int minutes,
  String? message,
  String pending = '',
  String extra = '',
}) =>
    '{"sessionId":"$id","name":"$name","cwd":"/home/demo/$name",'
    '"state":"$state","updatedAt":${minutesAgo(minutes)},'
    '"startedAt":${minutesAgo(minutes + 30)}'
    '${message == null ? '' : ',"lastMessage":"$message"'}'
    ',"pending":[$pending]$extra}';

String statusOf(List<String> agents) =>
    '{"version":1,"seq":2,"source":"daemon","agents":[${agents.join(',')}]}';

const apiPending =
    '{"id":"req-1","toolName":"Bash","summary":"npm test -- due-date",'
    '"toolInput":{"command":"npm test -- due-date",'
    '"description":"Run the due date tests"}}';

/// Companion status on the workstation: the Claude session in workspace
/// api, plus (for the inbox) two more.
String workstationStatus({bool needsApproval = false, bool all = false}) =>
    statusOf([
      agentJson(
        's-api',
        'todo-api',
        state: needsApproval ? 'needs_permission' : 'working',
        minutes: 0,
        message: needsApproval ? null : 'Writing the due date tests.',
        pending: needsApproval ? apiPending : '',
        extra: ',"herdr":{"tabId":"w1:t1","paneId":"w1:p1"}',
      ),
      if (all) ...[
        agentJson(
          's-web',
          'todo-web',
          state: 'working',
          minutes: 1,
          message: 'Refactoring TodoList for keyboard navigation.',
        ),
        agentJson(
          's-infra',
          'infra',
          state: 'ended',
          minutes: 18,
          message: 'Plan: 3 to add, 0 to change, 0 to destroy.',
        ),
      ],
    ]);

String buildBoxStatus() => statusOf([
  agentJson(
    's-docs',
    'todo-docs',
    state: 'ended',
    minutes: 9,
    message: 'README updated with the new due date API.',
  ),
]);

/// [line] stamped [ago] before now, so elapsed times read naturally.
Map<String, Object?> stamped(Map<String, Object?> line, Duration ago) =>
    line
      ..['timestamp'] = DateTime.now().toUtc().subtract(ago).toIso8601String();

/// A transcript page whose agent started [started] ago.
String livePage(
  List<Map<String, Object?>> entries, {
  required String state,
  Duration started = const Duration(minutes: 26),
  List<Map<String, Object?>> pending = const [],
}) {
  final json =
      jsonDecode(page(entries, state: state, pending: pending))
          as Map<String, Object?>;
  final agent = json['agent']! as Map<String, Object?>;
  final now = DateTime.now();
  agent['startedAt'] = now.subtract(started).millisecondsSinceEpoch;
  agent['updatedAt'] = now.millisecondsSinceEpoch;
  return jsonEncode(json);
}

const _dateTable =
    'Here is how they compare for a due date field:\n\n'
    '| Library | Time zones | Tree-shakes | Size |\n'
    '|:--------|:----------:|:-----------:|:----:|\n'
    '| date-fns | add-on | yes | 18 KB |\n'
    '| Day.js | plugin | partly | 3 KB |\n'
    '| Luxon | built in | no | 23 KB |\n\n'
    "I'll go with **date-fns**: we only need parsing and comparing, and it "
    'tree-shakes to about 2 KB for that.';

/// Demo sync keys: fast parameters, nothing real.
const _syncCrypto = SyncCrypto(
  params: KdfParams.insecureFast,
  useIsolate: false,
);

Future<SyncController> demoSyncDevice(
  FakeHubServer server, {
  List<SavedHost> hosts = const [],
}) async {
  final local = await LocalDevice.create(
    hosts: hosts,
    trustedKeys: [
      HostKeyRecord(
        host: workstation.host,
        port: 22,
        type: 'ssh-ed25519',
        fingerprint: 'SHA256:demo-workstation',
        trustedAt: DateTime.utc(2026, 9),
      ),
    ],
  );
  final sync = SyncController(
    state: InMemorySyncStateStore(),
    local: local.store,
    hubFactory: server.factory,
    hosts: local.hosts,
    hostKeys: local.verifier,
    crypto: _syncCrypto,
    setupCodec: const SyncSetupCodec(
      crypto: _syncCrypto,
      params: KdfParams.insecureFast,
    ),
    timers: FakeSyncTimers(),
    observeLifecycle: false,
  );
  await sync.start();
  return sync;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WakelockPlusPlatformInterface.instance = _NoopWakelock();
  setUpAll(loadShotFonts);

  Future<ThemeController> everforest() async {
    final controller = ThemeController(
      InMemoryThemePreferences(
        const ThemePreferences(
          themeMode: ThemeMode.dark,
          palette: AppPalette.everforest,
        ),
      ),
    );
    await controller.load();
    return controller;
  }

  /// The home page: two Herdr sessions open, other workspaces listed.
  SessionConnectFlow? homeFlow;

  Future<ThemeController> pumpHome(
    WidgetTester tester, {
    bool desktop = false,
    bool thisComputer = false,
    bool withFlow = false,
    DesktopShellController? shell,
    AgentAttentionController? attention,
    void Function(TerminalWorkspaceController workspace)? onWorkspace,
  }) async {
    if (desktop) {
      useDesktopView(tester);
    } else {
      usePhoneView(tester);
    }
    final theme = await everforest();
    final repository = FakeHostsRepository()
      ..persisted = [workstation, buildBox];
    final hostsController = HostsController(
      repository,
      thisComputerStore: thisComputer
          ? InMemoryThisComputerStore(
              ThisComputerSettings(
                // No agent polling timers in the screenshots.
                host: SavedHost.thisComputer(
                  hostname: 'devbox',
                  username: 'demo',
                ).copyWith(agentAttentionEnabled: false),
              ),
            )
          : null,
    );
    final workspace = TerminalWorkspaceController(DemoTerminalRepository());
    addTearDown(workspace.dispose);
    final agentAttention =
        attention ??
        AgentAttentionController(
          workspace: workspace,
          runnerFactory: (_) =>
              ScriptedAgentCommandRunner([StateError('no polling')]),
          provider: const HerdrAttentionProvider(),
        );
    addTearDown(agentAttention.dispose);
    final runners = {
      'workstation': HerdrFakeRunner(
        workspaces: workstationWorkspaces,
        tabs: workstationTabs,
        agents: workstationAgents,
        tmuxSessions: tmuxLine('scratch', minutesAgo: 12),
      ),
      'build-box': HerdrFakeRunner.tmuxOnly(tmuxSessions: buildBoxTmux()),
      thisComputerHostId: HerdrFakeRunner(
        workspaces: thisComputerWorkspaces,
        tabs: '{"result":{"tabs":[]}}',
        agents: '{"result":{"agents":[]}}',
        tmuxSessions: tmuxLine('dotfiles', minutesAgo: 30),
      ),
    };
    final boards = HomeBoards(
      runnerFactory: (host) => runners[host.id]!,
      pollInterval: const Duration(days: 1),
    );
    addTearDown(boards.dispose);
    homeFlow = withFlow
        ? SessionConnectFlow(
            hostsController: hostsController,
            workspace: workspace,
            runnerFactory: (host) => runners[baseHostId(host.id)]!,
            preferences: InMemoryConnectPreferencesRepository(),
          )
        : null;

    await openDemoSession(
      tester,
      workspace,
      const ConnectTarget.herdr(
        workspaceId: 'w1',
        label: 'api',
      ).apply(workstation),
      claudePermissionScreen(),
    );
    await openDemoSession(
      tester,
      workspace,
      const ConnectTarget.herdr(
        workspaceId: 'w2',
        label: 'web',
      ).apply(workstation),
      claudeWorkingScreen(),
    );
    onWorkspace?.call(workspace);

    final verifier = NoopVerifier();
    await tester.pumpWidget(
      shotApp(
        home: HostsPage(
          hostsController: hostsController,
          lockController: AppLockController(AlwaysAuthenticates()),
          terminalRepository: NoNetworkTerminalRepository(),
          workspaceController: workspace,
          localShellController: LocalShellController(),
          themeController: theme,
          hostKeyVerifier: verifier,
          promptCoordinator: HostKeyPromptCoordinator(),
          sftpRepository: NoNetworkSftpRepository(),
          sftpBookmarksRepository: InMemorySftpBookmarks(),
          agentAttention: agentAttention,
          backupService: AppBackupService(
            hostsController: hostsController,
            themeController: theme,
            hostKeyVerifier: verifier,
          ),
          fileExport: RecordingFileExport(),
          homeBoards: boards,
          homePreferences: InMemoryHomePreferencesRepository(),
          connectFlow: homeFlow,
          previewRefreshInterval: const Duration(days: 1),
          desktopShell: shell,
        ),
        systemBars: !desktop,
      ),
    );
    await tester.runAsync(pumpEventQueue);
    await pumpFrames(tester);
    await tester.runAsync(pumpEventQueue);
    await pumpFrames(tester);
    return theme;
  }

  testWidgets('01 home', (tester) async {
    await pumpHome(tester);
    await saveShot(tester, '01-home');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  Future<void> tearDownPage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    // Herdr remote-control timeouts.
    await tester.pump(const Duration(minutes: 3));
  }

  /// The terminal page on the Herdr workspace "api" running Claude Code.
  Future<TerminalSessionController> pumpTerminal(
    WidgetTester tester, {
    required bool withPrompt,
    bool inbox = false,
    bool desktop = false,
    bool moreSessions = false,
    ConnectTarget? target,
    String? screen,
    PreviewReadyController Function(TerminalSessionController)?
    previewWatcherFactory,
  }) async {
    if (desktop) {
      useDesktopView(tester);
    } else {
      usePhoneView(tester);
    }
    HerdrPaneListingCache.instance.clear();
    HerdrKeymapCache.instance.clear();
    final theme = await everforest();
    SavedHost companion(SavedHost host) => host.copyWith(
      agentAttentionEnabled: true,
      agentMonitor: AgentMonitorKind.companion,
    );
    final host =
        (target ??
                const ConnectTarget.herdr(
                  workspaceId: 'w1',
                  label: 'api',
                  tabId: 'w1:t1',
                ))
            .apply(companion(workstation));
    final hostsController = HostsController(
      FakeHostsRepository()..persisted = [workstation, buildBox],
    );
    final workspace = TerminalWorkspaceController(DemoTerminalRepository());
    addTearDown(workspace.dispose);
    final agentAttention = AgentAttentionController(
      workspace: workspace,
      runnerFactory: (host) => ScriptedAgentCommandRunner([
        ok(
          host.id.startsWith('build-box')
              ? buildBoxStatus()
              : workstationStatus(needsApproval: withPrompt, all: inbox),
        ),
      ]),
      provider: const ConductoreHostAttentionProvider(),
      pollInterval: const Duration(days: 1),
    );
    agentAttention.setAppForeground(false);
    addTearDown(agentAttention.dispose);
    final flow = SessionConnectFlow(
      hostsController: hostsController,
      workspace: workspace,
      runnerFactory: (_) => FakeHerdrRunner(workstationHerdr),
      preferences: InMemoryConnectPreferencesRepository(),
    );
    if (inbox || moreSessions) {
      await openDemoSession(
        tester,
        workspace,
        const ConnectTarget.tmux('ci').apply(companion(buildBox)),
        shellTestsScreen(),
      );
    }
    if (moreSessions) {
      await openDemoSession(
        tester,
        workspace,
        const ConnectTarget.herdr(
          workspaceId: 'w2',
          label: 'web',
        ).apply(companion(workstation)),
        claudeWorkingScreen(),
      );
    }
    final session = workspace.open(host);
    await tester.runAsync(session.connect);
    await tester.runAsync(pumpEventQueue);
    workspace.activate(session);

    await tester.pumpWidget(
      shotApp(
        home: TerminalPage(
          workspace: workspace,
          themeController: theme,
          sftpRepository: NoNetworkSftpRepository(),
          agentAttention: agentAttention,
          connectFlow: flow,
          previewWatcherFactory: previewWatcherFactory,
        ),
        systemBars: !desktop,
      ),
    );
    await pumpFrames(tester);
    session.terminal.write(
      screen ??
          claudeTerminalScreen(
            withPrompt: withPrompt,
            width: desktop ? 96 : 46,
          ),
    );
    await tester.pump(PromptMenuStrip.defaultDebounce);
    await pumpFrames(tester);

    if (inbox) {
      final context = tester.element(find.byType(TerminalPage));
      unawaited(
        showAgentAttentionSheet(
          context: context,
          controller: agentAttention,
          onOpenAgent: (_, _) {},
          onOpenChat: (_, _) {},
        ),
      );
      await pumpFrames(tester, 8);
      // Pull the sheet up to its full height.
      await tester.dragFrom(
        tester.getTopLeft(find.byType(AgentAttentionSheet)) +
            const Offset(200, 12),
        const Offset(0, -600),
      );
      await pumpFrames(tester, 8);
    }
    return session;
  }

  testWidgets('02 terminal', (tester) async {
    await pumpTerminal(tester, withPrompt: false);
    await saveShot(tester, '02-terminal');
    await tearDownPage(tester);
  });

  testWidgets('03 chat view', (tester) async {
    usePhoneView(tester);
    final thread = [
      stamped(
        userLine('u1', 'Add a due date to todos and cover it with tests'),
        const Duration(minutes: 12),
      ),
      assistantLine('a1', [
        text(
          "I'll add an optional **`dueDate`** to the todo schema, then:\n"
          '- validate it as an ISO date\n'
          '- sort overdue todos first',
        ),
        toolUse('t1', 'Bash', {
          'command': 'npm test -- todos',
          'description': 'Run the todo tests',
        }),
      ]),
      userLine('r1', [toolResult('t1', 'Tests  18 passed (18)')]),
      assistantLine('a2', [
        toolUse('t2', 'Edit', {
          'file_path': '/home/demo/todo-api/src/routes/todos.ts',
          'old_string': '  done: z.boolean(),',
          'new_string':
              '  dueDate: z.string().datetime().optional(),\n'
              '  done: z.boolean().default(false),',
        }),
        toolUse('t3', 'TodoWrite', {
          'todos': [
            {'content': 'Add a validated dueDate', 'status': 'completed'},
            {'content': 'Test overdue sorting', 'status': 'in_progress'},
          ],
        }),
        toolUse('t4', 'Bash', {
          'command': 'npm test -- due-date',
          'description': 'Run the due date tests',
        }),
      ]),
    ];
    final controller = ChatViewController(
      runner: ScriptedAgentCommandRunner([
        ok(
          livePage(
            thread,
            state: 'needs_permission',
            started: const Duration(minutes: 12),
            pending: [
              {
                'id': 'req-1',
                'toolName': 'Bash',
                'summary': 'npm test -- due-date',
                'toolInput': {
                  'command': 'npm test -- due-date',
                  'description': 'Run the due date tests',
                },
              },
            ],
          ),
        ),
      ]),
      sessionId: 's-1',
      decide: (_, _) async {},
      pollInterval: const Duration(days: 1),
    );
    await tester.pumpWidget(shotApp(home: const Scaffold()));
    await pushPage(
      tester,
      ChatViewPage(
        controller: controller,
        hostName: 'workstation',
        onOpenTerminal: () {},
      ),
    );
    await pumpFrames(tester);
    await tester.tap(find.text('/home/demo/todo-api/src/routes/todos.ts'));
    await pumpFrames(tester);
    await saveShot(tester, '03-chat-view');
    await tearDownPage(tester);
  });

  testWidgets('04 agents inbox', (tester) async {
    await pumpTerminal(tester, withPrompt: true, inbox: true);
    await saveShot(tester, '04-agents-inbox');
    await tearDownPage(tester);
  });

  testWidgets('05 herdr navigator', (tester) async {
    await pumpTerminal(tester, withPrompt: false);
    await tester.tap(find.byKey(const ValueKey('toolbar-herdr')));
    await pumpFrames(tester, 8);
    await saveShot(tester, '05-herdr-navigator');
    await tearDownPage(tester);
  });

  testWidgets('06 menu buttons', (tester) async {
    await pumpTerminal(tester, withPrompt: true);
    await saveShot(tester, '06-menu-buttons');
    await tearDownPage(tester);
  });

  testWidgets('07 settings', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byTooltip('Settings'));
    await pumpFrames(tester, 8);
    await saveShot(tester, '07-settings');
    await tearDownPage(tester);
  });

  testWidgets('08 agent hooks', (tester) async {
    usePhoneView(tester);
    final installed = (await loadCompanionBundle()).version;
    final runner = MatchingRunner({
      'conductore-hostd version': ok(
        '{"version":"$installed","protocol":1,"node":"22.11.0"}',
      ),
      'conductore-hostd doctor': ok(
        '{"ok":true,"user":"demo","checks":['
        '{"name":"node","ok":true,"detail":"node 22.11.0 (need >= 18)"},'
        '{"name":"hook client","ok":true,'
        '"detail":"~/.local/share/conductore/bin/conductore-hook"},'
        '{"name":"settings.json","ok":true,"detail":"~/.claude/settings.json"},'
        '{"name":"hooks registered","ok":true,"detail":"9 events"},'
        '{"name":"daemon","ok":true,"detail":"pid 4242, seq 318"},'
        '{"name":"herdr","ok":true,"detail":"herdr 0.9.1"}]}',
      ),
      'conductore-hostd status': ok(workstationStatus(all: true)),
      'exec node --version': ok('v22.11.0\n'),
      'exec claude --version': ok('2.1.0 (Claude Code)\n'),
    });
    final controller = CompanionSetupController(
      runnerFactory: (_) => runner,
      sftpRepository: NoNetworkSftpRepository(),
      loadBundle: loadCompanionBundle,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      CompanionSetupScope(
        controller: controller,
        child: shotApp(home: const Scaffold()),
      ),
    );
    await pushPage(
      tester,
      CompanionSetupPage(host: workstation, controller: controller),
    );
    await tester.runAsync(pumpEventQueue);
    await pumpFrames(tester, 8);
    await saveShot(tester, '08-agent-hooks');
    await tearDownPage(tester);
  });

  testWidgets('09 quick switcher', (tester) async {
    await pumpTerminal(tester, withPrompt: true, moreSessions: true);
    await tester.tap(find.byTooltip('Sessions'));
    await pumpFrames(tester, 8);
    await saveShot(tester, '09-quick-switcher');
    await tearDownPage(tester);
  });

  testWidgets('10 chat view working', (tester) async {
    usePhoneView(tester);
    final thread = [
      stamped(
        userLine('u0', 'Add a dueDate field to the todo schema'),
        const Duration(minutes: 9),
      ),
      assistantLine('a0', [
        text(
          'Added an optional `dueDate` (ISO 8601) to the schema and the '
          'create route. Asking the reviewer agent to check it.',
        ),
      ]),
      stamped(
        userLine(
          'm1',
          '<teammate-message teammate_id="reviewer" color="green" '
              'summary="Due date PR reviewed">\n'
              'Looks good. Sort overdue todos before the ones without a '
              'date.\n</teammate-message>',
        ),
        const Duration(minutes: 6),
      ),
      stamped(
        userLine('u1', 'Which date library should the due date use?'),
        const Duration(minutes: 2, seconds: 14),
      ),
      assistantLine('a1', [
        toolUse('task1', 'Task', {
          'description': 'Compare date libraries',
          'subagent_type': 'Explore',
          'prompt': 'Compare date-fns, Day.js and Luxon for this repo',
        }),
      ]),
      assistantLine('s1', [
        toolUse('g1', 'Grep', {'pattern': 'new Date\\('}),
      ], sidechain: true),
      userLine('s2', [toolResult('g1', 'Found 7 files')], sidechain: true),
      assistantLine('s3', [
        toolUse('r1', 'Read', {
          'file_path': '/home/demo/todo-api/package.json',
        }),
      ], sidechain: true),
      userLine('s4', [toolResult('r1', '{ ... }')], sidechain: true),
      userLine('u2', [toolResult('task1', 'date-fns fits best.')]),
      assistantLine('a2', [text(_dateTable)]),
      assistantLine('a3', [
        toolUse('t2', 'Bash', {
          'command': 'npm install date-fns && npm test -- due-date',
          'description': 'Install date-fns and run the due date tests',
        }),
      ]),
    ];
    final controller = ChatViewController(
      runner: ScriptedAgentCommandRunner([
        ok(livePage(thread, state: 'working')),
      ]),
      sessionId: 's-1',
      decide: (_, _) async {},
      pollInterval: const Duration(days: 1),
    );
    await tester.pumpWidget(shotApp(home: const Scaffold()));
    await pushPage(
      tester,
      ChatViewPage(
        controller: controller,
        hostName: 'workstation',
        onOpenTerminal: () {},
      ),
    );
    await pumpFrames(tester, 8);
    await saveShot(tester, '10-chat-working');
    await tearDownPage(tester);
  });

  testWidgets('11 talk mode', (tester) async {
    usePhoneView(tester);
    final theme = await everforest();
    await theme.setVoice(theme.voice.copyWith(talkSendSilenceSeconds: 2));
    final mic = FakeSpeechRecognizer();
    final dictation = DictationController(mic, language: () => 'en-US');
    addTearDown(dictation.dispose);
    final history = [
      stamped(
        userLine('u-1', 'Add a due date to todos and cover it with tests'),
        const Duration(minutes: 14),
      ),
      assistantLine('a-1', [
        text(
          'Done. Todos now have an optional **`dueDate`**:\n'
          '- validated as an ISO 8601 date in the create and update routes\n'
          '- returned by `GET /todos` and filterable with `?due=today`\n'
          '- covered by 12 new tests in `test/due-date.test.ts`',
        ),
      ]),
      stamped(
        userLine('u0', 'Sort overdue todos first'),
        const Duration(minutes: 8),
      ),
      assistantLine('a0', [
        toolUse('t0', 'Edit', {
          'file_path': '/home/demo/todo-api/src/lib/sort.ts',
          'old_string': '  return a.createdAt - b.createdAt;',
          'new_string':
              '  if (isOverdue(a) !== isOverdue(b)) {\n'
              '    return isOverdue(a) ? -1 : 1;\n'
              '  }\n'
              '  return a.createdAt - b.createdAt;',
        }),
      ]),
      userLine('r0', [toolResult('t0', 'ok')]),
      assistantLine('a00', [
        text('Overdue todos now come first; the rest keep their order.'),
      ]),
      stamped(
        userLine('u1', 'Run the due date tests'),
        const Duration(minutes: 3),
      ),
      assistantLine('a1', [
        toolUse('t1', 'Bash', {
          'command': 'npm test -- due-date',
          'description': 'Run the due date tests',
        }),
      ]),
      userLine('r1', [toolResult('t1', 'Tests  24 passed (24)')]),
      assistantLine('a2', [
        text(
          'All **24** due date tests pass, including the overdue sorting. '
          'Want me to add a reminder before a todo is due?',
        ),
      ]),
    ];
    final idle = ok(livePage(history, state: 'waiting_input'));
    final controller = ChatViewController(
      runner: ScriptedAgentCommandRunner([
        idle,
        ok('{"ok":true}'),
        for (var i = 0; i < 8; i++) idle,
      ]),
      sessionId: 's-1',
      decide: (_, _) async {},
      pollInterval: const Duration(days: 1),
    );
    await tester.pumpWidget(
      VoiceSettingsScope(
        settings: theme,
        child: shotApp(home: const Scaffold()),
      ),
    );
    await pushPage(
      tester,
      ChatViewPage(
        controller: controller,
        hostName: 'workstation',
        onOpenTerminal: () {},
        textToSpeech: FakeTts(),
        dictation: dictation,
      ),
    );
    await pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey('chat-talk')));
    await tester.pump();
    mic.say('Yes, remind me the evening before');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2400));
    await pumpFrames(tester, 2);
    await saveShot(tester, '11-talk-mode');
    await tearDownPage(tester);
  });

  /// A phone syncing through the workstation, with a laptop and a Mac
  /// joined through setup codes. The hub is a fake in memory.
  Future<SyncController> pumpSync(WidgetTester tester) async {
    usePhoneView(tester);
    final server = FakeHubServer();
    final phone = await demoSyncDevice(server, hosts: [workstation, buildBox]);
    await phone.setUp(
      hub: workstation,
      passphrase: 'demo-passphrase-only',
      deviceName: 'Pixel 8',
    );
    for (final name in ['ThinkPad', 'MacBook']) {
      final offer = await phone.addDevice(name);
      final other = await demoSyncDevice(server);
      await other.join(
        setupCode: offer.setupCode,
        words: offer.words.join(' '),
        deviceName: name,
      );
    }
    await phone.syncNow();
    await phone.refreshDevices();
    await tester.pumpWidget(shotApp(home: const Scaffold()));
    await pushPage(tester, SyncPage(controller: phone));
    await tester.runAsync(pumpEventQueue);
    await pumpFrames(tester, 8);
    return phone;
  }

  /// Lets real async work (the fake hub, crypto) finish while frames pump.
  Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await pumpFrames(tester, 8);
  }

  testWidgets('12 sync', (tester) async {
    await pumpSync(tester);
    // Down to the device list, keeping the last switches in view.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -470));
    await pumpFrames(tester, 8);
    await saveShot(tester, '12-sync');
    await tearDownPage(tester);
  });

  testWidgets('13 sync add device', (tester) async {
    await pumpSync(tester);
    final add = find.byKey(const ValueKey('sync-add-device'));
    await tester.scrollUntilVisible(
      add,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await pumpFrames(tester);
    await tester.tap(add);
    await pumpFrames(tester, 8);
    await tester.enterText(
      find.byKey(const ValueKey('sync-new-device-name')),
      'iPad',
    );
    await tester.tap(find.byKey(const ValueKey('sync-create-pairing')));
    await pumpFrames(tester, 8);
    await tester.tap(find.byKey(const ValueKey('sync-add-device-confirm')));
    await pumpUntil(
      tester,
      () => find.byType(QrCodeView).evaluate().isNotEmpty,
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await pumpFrames(tester, 8);
    await saveShot(tester, '13-sync-add-device');
    await tearDownPage(tester);
  });

  testWidgets('14 live preview ready', (tester) async {
    final runner = ScriptedAgentCommandRunner([
      for (var i = 0; i < 4; i++) ok('{"seq":3,"ports":[]}'),
    ]);
    await pumpTerminal(
      tester,
      withPrompt: false,
      target: const ConnectTarget.tmux('web-dev'),
      screen: viteDevServerScreen(),
      previewWatcherFactory: (_) =>
          PreviewReadyController(runnerFactory: () => runner),
    );
    await tester.pump(PreviewReadyController.defaultStartDelay);
    await tester.pump(PreviewReadyController.defaultScreenDebounce);
    await pumpFrames(tester);
    await saveShot(tester, '14-live-preview-ready');
    await tearDownPage(tester);
  });

  testWidgets('15 desktop terminal', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await pumpTerminal(tester, withPrompt: false, desktop: true);
      await saveShot(tester, '15-desktop-terminal', pixelRatio: 1);
      await tearDownPage(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('16 desktop home', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await pumpHome(tester, desktop: true);
      await saveShot(tester, '16-desktop-home', pixelRatio: 1);
      await tearDownPage(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  /// Runs [body] as a Linux desktop.
  Future<void> asDesktop(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('17 desktop settings', (tester) async {
    await asDesktop(() async {
      await pumpHome(tester, desktop: true);
      await tester.tap(find.byTooltip('Settings'));
      await pumpFrames(tester, 8);
      await saveShot(tester, '17-desktop-settings', pixelRatio: 1);
      await tearDownPage(tester);
    });
  });

  testWidgets('18 herdr tabs', (tester) async {
    await pumpTerminal(tester, withPrompt: false);
    await tester.runAsync(pumpEventQueue);
    await pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey('mux-inline-label')));
    await tester.runAsync(pumpEventQueue);
    await pumpFrames(tester, 8);
    await saveShot(tester, '18-herdr-tabs');
    await tearDownPage(tester);
  });

  testWidgets('19 desktop tab popover', (tester) async {
    await asDesktop(() async {
      AdaptiveModalPointer.install();
      await pumpTerminal(tester, withPrompt: false, desktop: true);
      await tester.runAsync(pumpEventQueue);
      await pumpFrames(tester);
      await tester.longPress(find.byKey(const ValueKey('mux-tab-w1:t3')));
      await pumpFrames(tester, 8);
      await saveShot(tester, '19-desktop-tab-popover', pixelRatio: 1);
      await tearDownPage(tester);
    });
  });

  testWidgets('20 desktop this computer', (tester) async {
    await asDesktop(() async {
      await pumpHome(tester, desktop: true, thisComputer: true);
      await tester.tap(find.byKey(const ValueKey('machine-name')));
      await pumpFrames(tester, 8);
      await saveShot(tester, '20-desktop-this-computer', pixelRatio: 1);
      await tearDownPage(tester);
    });
  });

  testWidgets('21 desktop connect dialog', (tester) async {
    await asDesktop(() async {
      await pumpHome(tester, desktop: true, withFlow: true);
      final context = tester.element(find.byType(HostsPage));
      unawaited(homeFlow!.connect(context, workstation, forcePicker: true));
      await tester.runAsync(pumpEventQueue);
      await pumpFrames(tester, 8);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('adaptive-modal-dialog')),
          matching: find.text('Herdr'),
        ),
      );
      await tester.runAsync(pumpEventQueue);
      await pumpFrames(tester, 8);
      await saveShot(tester, '21-desktop-connect-dialog', pixelRatio: 1);
      await tearDownPage(tester);
    });
  });

  /// The desktop shell on Linux: sidebar, tabs, splits and dashboard.
  Future<DesktopShellController> pumpShellHome(
    WidgetTester tester, {
    AgentAttentionController? attention,
    void Function(TerminalWorkspaceController workspace)? onWorkspace,
  }) async {
    final shell = DesktopShellController(store: InMemoryDesktopShellStore());
    addTearDown(shell.dispose);
    await pumpHome(
      tester,
      desktop: true,
      thisComputer: true,
      withFlow: true,
      shell: shell,
      attention: attention,
      onWorkspace: onWorkspace,
    );
    await tester.runAsync(pumpEventQueue);
    await pumpFrames(tester, 6);
    return shell;
  }

  testWidgets('22 desktop shell dashboard', (tester) async {
    await asDesktop(() async {
      final shell = await pumpShellHome(tester);
      shell.updatePrefs(
        (prefs) => prefs.setExpanded('m/workstation/h/w1', true),
      );
      shell.showHome = true;
      await pumpFrames(tester, 6);
      await saveShot(tester, '22-desktop-shell-dashboard', pixelRatio: 1);
      await tearDownPage(tester);
    });
  });

  testWidgets('23 desktop shell split', (tester) async {
    await asDesktop(() async {
      final shell = await pumpShellHome(tester);
      final views = {
        'session:workstation#herdr:w1',
        'session:workstation#herdr:w2',
      };
      shell.editLayout(
        views,
        (layout) => layout.split(
          layout.focusedPane.id,
          ShellEdge.right,
          'session:workstation#herdr:w1',
          fallbackView: 'session:workstation#herdr:w2',
        ),
      );
      await pumpFrames(tester, 6);
      await saveShot(tester, '23-desktop-shell-split', pixelRatio: 1);
      await tearDownPage(tester);
    });
  });

  testWidgets('24 desktop shell chat split', (tester) async {
    await asDesktop(() async {
      final shell = await pumpShellHome(tester);
      // A group, a pin and a couple of unread rows in the sidebar.
      shell.updatePrefs(
        (prefs) => prefs
            .addGroup(
              const SidebarGroup(
                id: 'clients',
                name: 'Clients',
                machineIds: ['build-box'],
              ),
            )
            .togglePin('m/workstation/h/w3'),
      );
      shell
        ..markUnread('m/workstation/h/w2')
        ..markUnread('m/build-box/t/ci');
      final thread = [
        stamped(
          userLine('u1', 'Add a due date to todos and cover it with tests'),
          const Duration(minutes: 12),
        ),
        assistantLine('a1', [
          text(
            "I'll add an optional **`dueDate`** to the todo schema, then "
            'validate it as an ISO date and sort overdue todos first.',
          ),
          toolUse('t1', 'Bash', {
            'command': 'npm test -- due-date',
            'description': 'Run the due date tests',
          }),
        ]),
      ];
      final controller = ChatViewController(
        runner: ScriptedAgentCommandRunner([
          ok(
            livePage(
              thread,
              state: 'needs_permission',
              started: const Duration(minutes: 12),
              pending: [
                {
                  'id': 'req-1',
                  'toolName': 'Bash',
                  'summary': 'npm test -- due-date',
                  'toolInput': {
                    'command': 'npm test -- due-date',
                    'description': 'Run the due date tests',
                  },
                },
              ],
            ),
          ),
        ]),
        sessionId: 's-api',
        fallbackName: 'todo-api',
        decide: (_, _) async {},
        pollInterval: const Duration(days: 1),
      );
      final home = tester.state<DesktopHomeState>(find.byType(DesktopHome));
      final api = const ConnectTarget.herdr(
        workspaceId: 'w1',
        label: 'api',
      ).apply(workstation);
      home.embedding.host!.presentChat(
        ChatViewRequest(
          host: api,
          agent: const AgentInfo(
            id: 's-api',
            name: 'todo-api',
            state: AgentAttentionState.needsInput,
            kind: 'claude',
          ),
          controller: controller,
          onOpenTerminal: () {},
          onDispose: () {},
        ),
      );
      await pumpFrames(tester, 4);
      final views = home.embedding.host!.viewIds.toSet();
      shell.editLayout(
        views,
        (layout) => layout
            .showIn(layout.focusedPane.id, 'session:${api.id}')
            .split(
              layout.focusedPane.id,
              ShellEdge.right,
              'chat:${api.id}:s-api',
            ),
      );
      await pumpFrames(tester, 8);
      await saveShot(tester, '24-desktop-shell-chat-split', pixelRatio: 1);
      await tearDownPage(tester);
    });
  });
}
