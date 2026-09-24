import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/agent_attention/data/herdr_attention_provider.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_controller.dart';
import 'package:conduit/features/app_lock/presentation/app_lock_controller.dart';
import 'package:conduit/features/backup/data/app_backup_service.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/hosts/presentation/home_board_controller.dart';
import 'package:conduit/features/hosts/presentation/hosts_controller.dart';
import 'package:conduit/features/hosts/presentation/hosts_page.dart';
import 'package:conduit/features/hosts/presentation/widgets/herdr_board.dart';
import 'package:conduit/features/local_shell/presentation/local_shell_controller.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/sessions/presentation/session_grid_page.dart';
import 'package:conduit/features/terminal/presentation/host_key_prompt_coordinator.dart';
import 'package:conduit/features/terminal/presentation/terminal_page.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';
import 'home_board_fakes.dart';

void main() {
  late ThemeController themeController;
  late HerdrFakeRunner runner;
  late List<String> runnerHosts;

  setUp(() async {
    themeController = ThemeController(InMemoryThemePreferences());
    await themeController.load();
    runner = HerdrFakeRunner();
    runnerHosts = [];
  });

  Future<(TerminalWorkspaceController, HomeBoardController)> pumpHome(
    WidgetTester tester, {
    List<SavedHost> hosts = const [],
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    final repository = FakeHostsRepository()..persisted = List.of(hosts);
    final hostsController = HostsController(repository);
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
    final board = HomeBoardController(
      runnerFactory: (host) {
        runnerHosts.add(host.id);
        return runner;
      },
      pollInterval: const Duration(days: 1),
    );
    addTearDown(board.dispose);
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
          homeBoard: board,
          previewRefreshInterval: const Duration(days: 1),
          paneRefocusDelay: const Duration(milliseconds: 50),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    return (workspace, board);
  }

  SavedHost host(String id, {DateTime? lastConnectedAt}) {
    return buildHost(
      id,
    ).copyWith(lastConnectedAt: lastConnectedAt ?? DateTime.utc(2026));
  }

  testWidgets('no machines shows the add-machine flow and no board', (
    tester,
  ) async {
    await pumpHome(tester);

    expect(find.text('No saved machines yet'), findsOneWidget);
    expect(find.text('Add machine'), findsOneWidget);
    expect(find.byType(HerdrBoard), findsNothing);
    expect(runnerHosts, isEmpty);
    // App lock and appearance (backup lives in its sheet) stay reachable.
    expect(find.byTooltip('Lock'), findsOneWidget);
    expect(find.byTooltip('Appearance'), findsOneWidget);
  });

  testWidgets('one machine: board lists workspaces, panes and states', (
    tester,
  ) async {
    await pumpHome(tester, hosts: [host('a')]);

    expect(find.byKey(const ValueKey('machine-name')), findsOneWidget);
    expect(find.text('Host a'), findsOneWidget);
    expect(runnerHosts, ['a']);

    expect(find.text('Infrastructure'), findsOneWidget);
    expect(find.text('TheCalendar'), findsOneWidget);
    expect(find.text('Deploying images'), findsOneWidget);
    expect(find.text('Proofing PR 398'), findsOneWidget);
    expect(find.text('main › claude'), findsOneWidget);
    expect(find.text('review › claude'), findsOneWidget);
    expect(find.text('Tab 1 › codex'), findsOneWidget);
    expect(find.text('Working'), findsOneWidget);
    expect(find.text('Needs input'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('1 waiting'), findsOneWidget);
    expect(find.text('3 agent panes'), findsOneWidget);
    // Counters and the local shell are tucked into "More".
    expect(find.text('MORE'), findsOneWidget);
    expect(find.text('Live sessions'), findsNothing);
  });

  testWidgets('tapping a pane opens its Herdr workspace and focuses it', (
    tester,
  ) async {
    final (workspace, board) = await pumpHome(tester, hosts: [host('a')]);

    await tester.tap(find.text('Proofing PR 398'));
    await tester.pump();
    await tester.pump();

    expect(
      runner.commands.where((c) => c.contains('agent focus w1:p2')),
      hasLength(1),
    );
    expect(workspace.sessions, hasLength(1));
    final session = workspace.sessions.single;
    expect(session.host.id, 'a#herdr:w1');
    expect(session.host.name, 'Host a: Infrastructure');

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byType(TerminalPage), findsOneWidget);
    // Covered by the terminal: polling stops and the channel is closed.
    expect(board.visible, isFalse);
    expect(runner.closeCount, greaterThanOrEqualTo(1));

    // The pane is focused again once the new client has attached.
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      runner.commands.where((c) => c.contains('agent focus w1:p2')),
      hasLength(2),
    );

    // Back on the home page the board resumes and lists again.
    final polls = runner.commands.where((c) => c.contains('workspace list'));
    final before = polls.length;
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(board.visible, isTrue);
    expect(
      runner.commands.where((c) => c.contains('workspace list')).length,
      greaterThan(before),
    );
  });

  testWidgets('a pane in an open Herdr session activates that session', (
    tester,
  ) async {
    final (workspace, _) = await pumpHome(tester, hosts: [host('a')]);
    final herdr = workspace.open(
      const ConnectTarget.herdr(
        workspaceId: 'w1',
        label: 'Infrastructure',
      ).apply(host('a')),
    );
    workspace.open(host('a'));
    await tester.pump();
    expect(workspace.activeSession, isNot(herdr));

    // Open sessions for the machine show as live tiles.
    expect(find.byType(SessionTile), findsNWidgets(2));
    expect(find.text('Open'), findsWidgets);

    await tester.tap(find.text('Deploying images'));
    await tester.pump();
    expect(workspace.sessions, hasLength(2));
    expect(workspace.activeSession, herdr);
    expect(runner.commands.last, contains('agent focus w1:p1'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TerminalPage), findsOneWidget);
  });

  testWidgets('many machines: defaults to the last connected and switches', (
    tester,
  ) async {
    await pumpHome(
      tester,
      hosts: [
        host('a', lastConnectedAt: DateTime.utc(2026, 9, 2)),
        host('b', lastConnectedAt: DateTime.utc(2026, 9, 20)),
        host('c'),
      ],
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('machine-name'))).data,
      'Host b',
    );
    expect(runnerHosts, ['b']);

    await tester.tap(find.byKey(const ValueKey('machine-name')));
    await tester.pumpAndSettle();
    expect(find.text('Machines'), findsOneWidget);
    expect(find.text('Add machine'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('picker-c')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('machine-name'))).data,
      'Host c',
    );
    expect(runnerHosts, ['b', 'c']);
  });

  testWidgets('hardware-key machines list panes only on request', (
    tester,
  ) async {
    await pumpHome(
      tester,
      hosts: [host('k').copyWith(authMethod: SshAuthMethod.hardwareKey)],
    );
    expect(find.text('Hardware-key login'), findsOneWidget);
    expect(runnerHosts, isEmpty);

    await tester.tap(find.text('Show panes'));
    await tester.pump();
    await tester.pump();
    expect(runnerHosts, ['k']);
    expect(find.text('Infrastructure'), findsOneWidget);
  });

  testWidgets('Herdr not running offers to start it', (tester) async {
    runner
      ..workspaces = HerdrFixtures.notRunning
      ..workspaceExitCode = 1;
    final (workspace, _) = await pumpHome(tester, hosts: [host('a')]);
    expect(find.text('Herdr is not running'), findsOneWidget);

    await tester.tap(find.text('Start Herdr'));
    await tester.pump();
    expect(workspace.sessions.single.host.id, 'a#herdr');
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('machine menu keeps edit, files, connect to and delete', (
    tester,
  ) async {
    await pumpHome(tester, hosts: [host('a')]);

    await tester.tap(find.byTooltip('Machine actions'));
    await tester.pumpAndSettle();
    for (final label in [
      'Connect to…',
      'Files',
      'Edit',
      'Duplicate',
      'Copy address',
      'Delete',
      'Add machine',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('a never-connected machine lists panes only on request', (
    tester,
  ) async {
    await pumpHome(tester, hosts: [buildHost('n')]);
    expect(find.text('Not connected yet'), findsOneWidget);
    expect(runnerHosts, isEmpty);

    await tester.tap(find.text('Show panes'));
    await tester.pump();
    await tester.pump();
    expect(runnerHosts, ['n']);
    expect(find.text('Infrastructure'), findsOneWidget);
  });
}
