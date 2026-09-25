import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/agent_attention/data/herdr_attention_provider.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_controller.dart';
import 'package:conduit/features/app_lock/presentation/app_lock_controller.dart';
import 'package:conduit/features/backup/data/app_backup_service.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/hosts/presentation/home_board_controller.dart';
import 'package:conduit/features/hosts/presentation/hosts_controller.dart';
import 'package:conduit/features/hosts/presentation/hosts_page.dart';
import 'package:conduit/features/hosts/presentation/widgets/home_session_grid.dart';
import 'package:conduit/features/local_shell/presentation/local_shell_controller.dart';
import 'package:conduit/features/sessions/domain/connect_preferences.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/sessions/presentation/session_connect_flow.dart';
import 'package:conduit/features/terminal/domain/host_key_verifier.dart';
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

  SessionConnectFlow? flow;

  Future<(TerminalWorkspaceController, HomeBoardController)> pumpHome(
    WidgetTester tester, {
    List<SavedHost> hosts = const [],
    bool withConnectFlow = false,
    HostKeyVerifier? hostKeyVerifier,
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
    final verifier = hostKeyVerifier ?? NoopVerifier();
    flow = withConnectFlow
        ? SessionConnectFlow(
            hostsController: hostsController,
            workspace: workspace,
            runnerFactory: (_) => runner,
            preferences: InMemoryConnectPreferencesRepository(),
          )
        : null;

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
          connectFlow: flow,
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

  Finder dormant(String id) => find.byKey(ValueKey('dormant-$id'));

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('home-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pump();
  }

  testWidgets('no machines shows the add-machine flow and no board', (
    tester,
  ) async {
    await pumpHome(tester);

    expect(find.text('No saved machines yet'), findsOneWidget);
    expect(find.text('Add machine'), findsOneWidget);
    expect(find.byType(DormantWorkspaceTile), findsNothing);
    expect(find.byType(HomeBoardNoticeTile), findsNothing);
    expect(runnerHosts, isEmpty);
    // Lock sits in the bar; appearance (with backup) and trusted keys sit
    // behind the gear.
    expect(find.byTooltip('Lock'), findsOneWidget);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Trusted keys'), findsOneWidget);
    expect(find.text('Lock now'), findsOneWidget);
  });

  testWidgets('one machine: Herdr workspaces show as dormant tiles', (
    tester,
  ) async {
    await pumpHome(tester, hosts: [host('a')]);

    expect(find.byKey(const ValueKey('machine-name')), findsOneWidget);
    expect(find.text('Host a'), findsOneWidget);
    expect(runnerHosts, ['a']);
    expect(find.text('SESSIONS'), findsOneWidget);
    expect(find.text('none open'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-add-tile')), findsOneWidget);
    expect(find.byType(HomeBoardNoticeTile), findsNothing);

    expect(dormant('w1'), findsOneWidget);
    expect(dormant('w2'), findsOneWidget);
    expect(
      find.descendant(of: dormant('w1'), matching: find.text('Infrastructure')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dormant('w1'),
        matching: find.text('2 agents · 2 tabs'),
      ),
      findsOneWidget,
    );
    for (final chip in ['Needs input', 'Working']) {
      expect(
        find.descendant(of: dormant('w1'), matching: find.text(chip)),
        findsOneWidget,
        reason: chip,
      );
    }
    expect(
      find.descendant(of: dormant('w2'), matching: find.text('Done')),
      findsOneWidget,
    );
    expect(find.text('2 workspaces not open'), findsOneWidget);
    // Counters and the local shell are tucked into "More".
    await scrollTo(tester, find.text('MORE'));
    expect(find.text('MORE'), findsOneWidget);
    expect(find.text('Live sessions'), findsNothing);
  });

  testWidgets('tapping a dormant workspace opens it', (tester) async {
    final (workspace, board) = await pumpHome(tester, hosts: [host('a')]);

    await tester.tap(dormant('w1'));
    await tester.pump();
    await tester.pump();

    final session = workspace.sessions.single;
    expect(session.host.id, 'a#herdr:w1');
    expect(session.host.name, 'Host a: Infrastructure');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byType(TerminalPage), findsOneWidget);
    // Covered by the terminal: polling stops and the channel is closed.
    expect(board.visible, isFalse);
    expect(runner.closeCount, greaterThanOrEqualTo(1));

    // Back home: the board resumes, and the workspace is now a live tile.
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
    expect(find.byType(HomeSessionTile), findsOneWidget);
    expect(dormant('w1'), findsNothing);
    expect(dormant('w2'), findsOneWidget);
  });

  testWidgets('long-pressing a dormant workspace opens one of its panes', (
    tester,
  ) async {
    final (workspace, _) = await pumpHome(tester, hosts: [host('a')]);

    await tester.longPress(dormant('w1'));
    await tester.pumpAndSettle();
    expect(find.text('main › claude'), findsOneWidget);
    expect(find.text('review › claude'), findsOneWidget);
    await tester.tap(find.text('Proofing PR 398'));
    await tester.pump();
    await tester.pump();

    expect(
      runner.commands.where((c) => c.contains('agent focus w1:p2')),
      hasLength(1),
    );
    expect(workspace.sessions.single.host.id, 'a#herdr:w1');
    await tester.pump(const Duration(seconds: 1));
    // The pane is focused again once the new client has attached.
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      runner.commands.where((c) => c.contains('agent focus w1:p2')),
      hasLength(2),
    );
  });

  testWidgets('with the connect flow a pane opens at its exact place', (
    tester,
  ) async {
    final (workspace, _) = await pumpHome(
      tester,
      hosts: [host('a')],
      withConnectFlow: true,
    );

    await tester.longPress(dormant('w1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Proofing PR 398'));
    await tester.pump();
    await tester.pump();

    final session = workspace.sessions.single;
    expect(session.host.id, 'a#herdr:w1');
    // The attach command focuses the agent's pane before attaching, so the
    // new client lands on it (Herdr's focus is per server).
    expect(session.startupCommand, contains('herdr agent focus w1:p2'));
    expect(session.startupCommand, endsWith('; herdr'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(TerminalPage), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump(const Duration(seconds: 1));
    await flow!.herdr.dispose();
  });

  testWidgets('open sessions show as live tiles with transport and '
      'workspace', (tester) async {
    final (workspace, _) = await pumpHome(
      tester,
      hosts: [host('a'), host('m').copyWith(useMosh: true)],
    );
    workspace.open(host('m').copyWith(useMosh: true));
    // Opened last, so the page shows its machine.
    final herdr = workspace.open(
      const ConnectTarget.herdr(
        workspaceId: 'w1',
        label: 'Infrastructure',
      ).apply(host('a')),
    );
    herdr.terminal.write('\x1b[32mclaude\x1b[0m is working on it');
    await tester.pump();

    expect(find.byType(HomeSessionTile), findsNWidgets(2));
    expect(find.text('2 open'), findsOneWidget);
    final herdrTile = find.byKey(const ValueKey('home-session-a#herdr:w1'));
    expect(
      find.descendant(of: herdrTile, matching: find.text('SSH')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: herdrTile, matching: find.text('Infrastructure')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: herdrTile, matching: find.byIcon(herdrIcon)),
      findsOneWidget,
    );
    // The live preview renders the screen, colours included.
    final preview = tester.widget<RichText>(
      find.descendant(
        of: herdrTile,
        matching: find.byKey(const ValueKey('live-preview-text')),
      ),
    );
    expect(preview.text.toPlainText(), contains('claude is working on it'));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-session-m')),
        matching: find.text('Mosh'),
      ),
      findsOneWidget,
    );
    // The attached workspace is no longer dormant.
    expect(dormant('w1'), findsNothing);
    expect(dormant('w2'), findsOneWidget);

    final mosh = workspace.sessions.first;
    await tester.tap(find.byKey(const ValueKey('home-session-m')));
    await tester.pump();
    expect(workspace.activeSession, mosh);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TerminalPage), findsOneWidget);
  });

  testWidgets('long-press on a tile renames, reconnects or closes', (
    tester,
  ) async {
    final (workspace, _) = await pumpHome(tester, hosts: [host('a')]);
    final session = workspace.open(host('a'));
    await tester.pump();
    final tile = find.byKey(const ValueKey('home-session-a'));

    await tester.longPress(tile);
    await tester.pumpAndSettle();
    expect(find.text('Reconnect'), findsOneWidget);
    expect(find.text('Close session'), findsOneWidget);
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Deploys');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();
    expect(session.title, 'Deploys');
    expect(
      find.descendant(of: tile, matching: find.text('Deploys')),
      findsWidgets,
    );

    await tester.longPress(tile);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close session'));
    await tester.pumpAndSettle();
    expect(workspace.sessions, isEmpty);
    expect(find.byType(HomeSessionTile), findsNothing);
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

  testWidgets('hardware-key machines list workspaces only on request', (
    tester,
  ) async {
    await pumpHome(
      tester,
      hosts: [host('k').copyWith(authMethod: SshAuthMethod.hardwareKey)],
    );
    expect(find.text('Hardware-key login'), findsOneWidget);
    expect(runnerHosts, isEmpty);

    await tester.tap(find.text('List workspaces'));
    await tester.pump();
    await tester.pump();
    expect(runnerHosts, ['k']);
    expect(dormant('w1'), findsOneWidget);
    expect(find.byType(HomeBoardNoticeTile), findsNothing);
  });

  testWidgets('Herdr not running shows a notice that starts it', (
    tester,
  ) async {
    runner
      ..workspaces = HerdrFixtures.notRunning
      ..workspaceExitCode = 1;
    final (workspace, _) = await pumpHome(tester, hosts: [host('a')]);
    expect(find.byType(HomeBoardNoticeTile), findsOneWidget);
    expect(find.text('Herdr is not running'), findsOneWidget);

    await tester.tap(find.text('Start Herdr'));
    await tester.pump();
    expect(workspace.sessions.single.host.id, 'a#herdr');
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('a listing failure shows its reason and retries', (
    tester,
  ) async {
    runner.error = StateError('connection refused');
    await pumpHome(tester, hosts: [host('a')]);
    expect(find.text('Could not list Herdr workspaces'), findsOneWidget);
    expect(find.textContaining('connection refused'), findsOneWidget);

    runner.error = null;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(HomeBoardNoticeTile), findsNothing);
    expect(dormant('w1'), findsOneWidget);
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
      'Agent hooks',
      'Duplicate',
      'Copy address',
      'Delete',
      'Add machine',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('a never-connected machine lists workspaces only on request', (
    tester,
  ) async {
    await pumpHome(tester, hosts: [buildHost('n')]);
    expect(find.text('Not connected yet'), findsOneWidget);
    expect(runnerHosts, isEmpty);

    await tester.tap(find.text('List workspaces'));
    await tester.pump();
    await tester.pump();
    expect(runnerHosts, ['n']);
    expect(dormant('w1'), findsOneWidget);
  });

  testWidgets('a machine with a trusted host key lists on its own', (
    tester,
  ) async {
    await pumpHome(
      tester,
      hosts: [buildHost('n')],
      hostKeyVerifier: _TrustedVerifier('192.168.1.1', 22),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Not connected yet'), findsNothing);
    expect(runnerHosts, ['n']);
    expect(dormant('w1'), findsOneWidget);
  });

  testWidgets('the bottom of the page clears the 3-button navigation bar', (
    tester,
  ) async {
    // Galaxy M53 with 3-button navigation: a 48 dp bar at 2.6 px/dp.
    tester.view.padding = const FakeViewPadding(bottom: 125);
    tester.view.viewPadding = const FakeViewPadding(bottom: 125);
    await pumpHome(tester, hosts: [host('a')]);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    await scrollTo(tester, find.text('MORE'));
    await tester.tap(find.text('MORE'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('home-scroll')),
      const Offset(0, -3000),
    );
    await tester.pumpAndSettle();
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final navBar = 125 / tester.view.devicePixelRatio;
    // Nothing scrolls under the buttons: the list ends above the bar.
    final list = tester.getRect(find.byKey(const ValueKey('home-scroll')));
    expect(list.bottom, lessThanOrEqualTo(screen.height - navBar + 0.01));
    // The expanded "More" area (counters) is fully above it.
    final counters = tester.getRect(find.text('Live sessions'));
    expect(counters.bottom, lessThan(screen.height - navBar));
  });
}

class _TrustedVerifier extends NoopVerifier {
  _TrustedVerifier(this.host, this.port);

  final String host;
  final int port;

  @override
  Future<List<HostKeyRecord>> loadTrustedKeys() async => [
    HostKeyRecord(
      host: host,
      port: port,
      type: 'ssh-ed25519',
      fingerprint: 'SHA256:test',
      trustedAt: DateTime.utc(2026),
    ),
  ];
}
