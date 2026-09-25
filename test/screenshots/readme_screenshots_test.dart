@Tags(['screenshots'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:conduit/core/presentation/theme_sheet.dart';
import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/core/theme/theme_preferences_repository.dart';
import 'package:conduit/features/agent_attention/data/conductore_host_attention_provider.dart';
import 'package:conduit/features/agent_attention/data/herdr_attention_provider.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_controller.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_sheet.dart';
import 'package:conduit/features/app_lock/presentation/app_lock_controller.dart';
import 'package:conduit/features/backup/data/app_backup_service.dart';
import 'package:conduit/features/chat_view/presentation/chat_view_controller.dart';
import 'package:conduit/features/chat_view/presentation/chat_view_page.dart';
import 'package:conduit/features/companion_setup/data/companion_bundle.dart';
import 'package:conduit/features/companion_setup/presentation/companion_setup_controller.dart';
import 'package:conduit/features/companion_setup/presentation/companion_setup_page.dart';
import 'package:conduit/features/hosts/domain/home_preferences.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/hosts/presentation/home_board_controller.dart';
import 'package:conduit/features/hosts/presentation/hosts_controller.dart';
import 'package:conduit/features/hosts/presentation/hosts_page.dart';
import 'package:conduit/features/local_shell/presentation/local_shell_controller.dart';
import 'package:conduit/features/prompt_menus/presentation/prompt_menu_strip.dart';
import 'package:conduit/features/sessions/domain/connect_preferences.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/sessions/presentation/session_connect_flow.dart';
import 'package:conduit/features/terminal/domain/herdr_keymap.dart';
import 'package:conduit/features/terminal/domain/herdr_navigator.dart';
import 'package:conduit/features/terminal/presentation/host_key_prompt_coordinator.dart';
import 'package:conduit/features/terminal/presentation/terminal_page.dart';
import 'package:conduit/features/terminal/presentation/terminal_session_controller.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../features/chat_view/chat_fixtures.dart';
import '../features/companion_setup/companion_fakes.dart' show MatchingRunner;
import '../features/hosts/home_board_fakes.dart';
import '../features/terminal/herdr/fake_herdr_runner.dart';
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
    '"agent_status":"blocked","focused":true,"tab_count":2,'
    '"active_tab_id":"w1:t1"},'
    '{"workspace_id":"w2","label":"web","number":2,'
    '"agent_status":"working","tab_count":1,"active_tab_id":"w2:t1"},'
    '{"workspace_id":"w3","label":"infra","number":3,'
    '"agent_status":"done","tab_count":3,"active_tab_id":"w3:t1"},'
    '{"workspace_id":"w4","label":"docs","number":4,'
    '"agent_status":"idle","tab_count":1,"active_tab_id":"w4:t1"}]}}';

const workstationTabs =
    '{"id":"2","result":{"tabs":['
    '{"tab_id":"w1:t1","workspace_id":"w1","label":"claude","number":1},'
    '{"tab_id":"w1:t2","workspace_id":"w1","label":"server","number":2},'
    '{"tab_id":"w2:t1","workspace_id":"w2","label":"claude","number":1},'
    '{"tab_id":"w3:t1","workspace_id":"w3","label":"plan","number":1},'
    '{"tab_id":"w3:t2","workspace_id":"w3","label":"apply","number":2},'
    '{"tab_id":"w3:t3","workspace_id":"w3","label":"logs","number":3},'
    '{"tab_id":"w4:t1","workspace_id":"w4","label":"","number":1}]}}';

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
    '"cwd":"/home/demo/demo/todo-api","focused":true},'
    '{"pane_id":"w1:p2","workspace_id":"w1","tab_id":"w1:t2",'
    '"cwd":"/home/demo/demo/todo-api"}],"type":"pane_list"}}';

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
    '{"sessionId":"$id","name":"$name","cwd":"/home/demo/demo/$name",'
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
  Future<ThemeController> pumpHome(WidgetTester tester) async {
    usePhoneView(tester);
    final theme = await everforest();
    final repository = FakeHostsRepository()
      ..persisted = [workstation, buildBox];
    final hostsController = HostsController(repository);
    final workspace = TerminalWorkspaceController(DemoTerminalRepository());
    addTearDown(workspace.dispose);
    final agentAttention = AgentAttentionController(
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
    };
    final boards = HomeBoards(
      runnerFactory: (host) => runners[host.id]!,
      pollInterval: const Duration(days: 1),
    );
    addTearDown(boards.dispose);

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
          previewRefreshInterval: const Duration(days: 1),
        ),
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
  }) async {
    usePhoneView(tester);
    HerdrPaneListingCache.instance.clear();
    HerdrKeymapCache.instance.clear();
    final theme = await everforest();
    SavedHost companion(SavedHost host) => host.copyWith(
      agentAttentionEnabled: true,
      agentMonitor: AgentMonitorKind.companion,
    );
    final host = const ConnectTarget.herdr(
      workspaceId: 'w1',
      label: 'api',
      tabId: 'w1:t1',
    ).apply(companion(workstation));
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
    if (inbox) {
      await openDemoSession(
        tester,
        workspace,
        const ConnectTarget.tmux('ci').apply(companion(buildBox)),
        shellTestsScreen(),
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
        ),
      ),
    );
    await pumpFrames(tester);
    session.terminal.write(claudeTerminalScreen(withPrompt: withPrompt));
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
      userLine('u1', 'Add a due date to todos and cover it with tests'),
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
          'file_path': '/home/demo/demo/todo-api/src/routes/todos.ts',
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
          page(
            thread,
            state: 'needs_permission',
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
    await tester.tap(find.text('/home/demo/demo/todo-api/src/routes/todos.ts'));
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

  testWidgets('07 appearance', (tester) async {
    final theme = await pumpHome(tester);
    final context = tester.element(find.byType(HostsPage));
    unawaited(showThemeSheet(context: context, controller: theme));
    await pumpFrames(tester, 8);
    await saveShot(tester, '07-appearance');
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
}
