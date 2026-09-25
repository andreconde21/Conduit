import 'dart:async';
import 'dart:convert';

import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/agent_attention/data/herdr_attention_provider.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_controller.dart';
import 'package:conduit/features/app_lock/presentation/app_lock_controller.dart';
import 'package:conduit/features/backup/data/app_backup_service.dart';
import 'package:conduit/features/companion_setup/presentation/companion_setup_controller.dart';
import 'package:conduit/features/hosts/domain/home_preferences.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/hosts/presentation/home_board_controller.dart';
import 'package:conduit/features/hosts/presentation/hosts_controller.dart';
import 'package:conduit/features/hosts/presentation/hosts_page.dart';
import 'package:conduit/features/local_shell/presentation/local_shell_controller.dart';
import 'package:conduit/features/sessions/domain/connect_preferences.dart';
import 'package:conduit/features/sessions/presentation/session_connect_flow.dart';
import 'package:conduit/features/terminal/domain/predictive_terminal_session.dart';
import 'package:conduit/features/terminal/domain/roaming_terminal_session.dart';
import 'package:conduit/features/terminal/domain/ssh_terminal_repository.dart';
import 'package:conduit/features/terminal/domain/ssh_terminal_session.dart';
import 'package:conduit/features/terminal/presentation/host_key_prompt_coordinator.dart';
import 'package:conduit/features/terminal/presentation/terminal_page.dart';
import 'package:conduit/features/terminal/presentation/terminal_session_controller.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';
import 'package:conduit/features/terminal/presentation/widgets/terminal_header.dart';
import 'package:conduit/main.dart';
import 'package:conduit_vt/conduit_vt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';
import 'home_board_fakes.dart';

/// A Herdr client behind SSH, as far as the phone can tell: it draws the
/// focused workspace when attached and repaints only when the window size
/// really changes (the kernel sends no SIGWINCH for a same-size
/// window-change). [screen] is what the server shows; the phone only knows
/// what was drawn to it.
class _HerdrClient
    implements
        SshTerminalSession,
        PredictiveTerminalSession,
        RoamingTerminalSession {
  _HerdrClient(this.columns, this.rows);

  int columns;
  int rows;
  String screen = 'HERDR workspace w1';
  bool attached = false;
  final resizes = <(int, int)>[];
  final _done = Completer<void>();
  final _stdout = StreamController<List<int>>();

  void _draw() {
    final out = StringBuffer('\x1b[?1049h\x1b[2J\x1b[H$screen');
    for (var row = 2; row <= rows; row++) {
      out.write('\x1b[$row;1H~');
    }
    _stdout.add(utf8.encode(out.toString()));
  }

  /// The connection dies (the phone slept, the network changed).
  void drop() {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  Future<void> close() async => drop();

  @override
  void resize(int columns, int rows, int pixelWidth, int pixelHeight) {
    resizes.add((columns, rows));
    final changed = columns != this.columns || rows != this.rows;
    this.columns = columns;
    this.rows = rows;
    if (attached && changed) _draw();
  }

  @override
  Stream<int> get echoAcks => const Stream.empty();

  @override
  Duration? get smoothedRtt => const Duration(milliseconds: 80);

  var _inputs = 0;

  @override
  int sendWithInputState(List<int> data) {
    unawaited(send(data));
    return ++_inputs;
  }

  @override
  Future<void> rehome() async {}

  @override
  Future<void> send(List<int> data) async {
    if (utf8.decode(data).contains('herdr')) {
      attached = true;
      _draw();
    }
  }
}

class _HerdrRepository implements SshTerminalRepository {
  final clients = <_HerdrClient>[];

  @override
  Future<SshTerminalSession> connect(
    SavedHost host, {
    required int columns,
    required int rows,
  }) async {
    final client = _HerdrClient(columns, rows);
    clients.add(client);
    return client;
  }
}

void main() {
  late _HerdrRepository repository;
  late TerminalWorkspaceController workspace;
  late SessionConnectFlow flow;

  Future<void> pumpHome(WidgetTester tester, {bool mosh = false}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final themeController = ThemeController(InMemoryThemePreferences());
    await themeController.load();
    final runner = HerdrFakeRunner();
    final host = buildHost('a').copyWith(
      lastConnectedAt: DateTime.utc(2026),
      useMosh: mosh,
      predictiveEchoEnabled: mosh,
    );
    final hostsController = HostsController(
      FakeHostsRepository()..persisted = [host],
    );
    repository = _HerdrRepository();
    workspace = TerminalWorkspaceController(repository);
    addTearDown(workspace.dispose);
    final attention = AgentAttentionController(
      workspace: workspace,
      runnerFactory: (_) => ScriptedAgentCommandRunner([StateError('none')]),
      provider: const HerdrAttentionProvider(),
      pollInterval: const Duration(days: 1),
    );
    addTearDown(attention.dispose);
    final boards = HomeBoards(
      runnerFactory: (_) => runner,
      pollInterval: const Duration(days: 1),
    );
    addTearDown(boards.dispose);
    flow = SessionConnectFlow(
      hostsController: hostsController,
      workspace: workspace,
      runnerFactory: (_) => runner,
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
          agentAttention: attention,
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
          paneRefocusDelay: const Duration(milliseconds: 50),
        ),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
  }

  /// Lets route transitions and the redraw nudge finish.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Tears the page down and runs out the idle timers it left behind.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    // Closes the Herdr command channels and their idle timers.
    unawaited(flow.herdr.dispose());
    await tester.pump(const Duration(seconds: 1));
  }

  String screenText(Terminal terminal) => [
    for (final line in terminal.buffer.lines.toList()) line.getText(),
  ].join('\n');

  /// The terminal on screen: one view, showing [session]'s terminal.
  void expectShowing(WidgetTester tester, TerminalSessionController session) {
    expect(tester.takeException(), isNull);
    expect(find.byType(TerminalPage), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.byType(TerminalHeader), findsOneWidget);
    expect(find.byKey(const ValueKey('toolbar-chat')), findsOneWidget);
    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    expect(identical(view.terminal, session.terminal), isTrue);
    final state = tester.state<TerminalViewState>(find.byType(TerminalView));
    expect(state.renderTerminal.attached, isTrue);
    expect(state.renderTerminal.size.height, greaterThan(100));
  }

  Future<TerminalSessionController> openWorkspaceAndGoHome(
    WidgetTester tester, {
    bool mosh = false,
  }) async {
    await pumpHome(tester, mosh: mosh);
    await tester.tap(find.byKey(const ValueKey('other-herdr-a-w1')));
    await settle(tester);
    final session = workspace.sessions.single;
    expectShowing(tester, session);
    expect(screenText(session.terminal), contains('HERDR workspace w1'));

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await settle(tester);
    expect(find.byType(TerminalPage), findsNothing);
    return session;
  }

  testWidgets('reopening a live Herdr session from its tile shows its '
      'screen, repainted by the server', (tester) async {
    final session = await openWorkspaceAndGoHome(tester);
    final client = repository.clients.single;
    // While the phone looked elsewhere the server's screen moved on, and
    // none of it reached the phone's buffer.
    client.screen = 'HERDR after the break';
    client.resizes.clear();

    await tester.tap(find.byKey(const ValueKey('home-session-a#herdr:w1')));
    await settle(tester);

    expectShowing(tester, session);
    expect(repository.clients, hasLength(1));
    final size = (session.terminal.viewWidth, session.terminal.viewHeight);
    // A real size change, so the kernel signals Herdr, then the true size.
    expect(client.resizes, [(size.$1, size.$2 - 1), size]);
    expect(screenText(session.terminal), contains('HERDR after the break'));
    await unmount(tester);
  });

  testWidgets('a session that dropped while home reconnects when its tile '
      'is tapped and shows the new attach', (tester) async {
    final session = await openWorkspaceAndGoHome(tester);
    repository.clients.single.drop();
    await tester.pump();
    expect(session.status, TerminalConnectionStatus.disconnected);

    await tester.tap(find.byKey(const ValueKey('home-session-a#herdr:w1')));
    await settle(tester);

    expectShowing(tester, session);
    expect(session.status, TerminalConnectionStatus.connected);
    expect(repository.clients, hasLength(2));
    expect(screenText(session.terminal), contains('HERDR workspace w1'));
    await unmount(tester);
  });

  testWidgets('a Mosh session with predictive echo reopens from its tile '
      'with the whole page', (tester) async {
    final session = await openWorkspaceAndGoHome(tester, mosh: true);
    // Typing while the page is open leaves predictions on screen.
    session.sendText('ls');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('home-session-a#herdr:w1')));
    await settle(tester);

    expectShowing(tester, session);
    await unmount(tester);
  });

  testWidgets('in the whole app: open a Mosh Herdr workspace, go home, '
      'tap its tile, and the whole terminal page is there', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      errors.add(details);
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);
    final themeController = ThemeController(InMemoryThemePreferences());
    await themeController.load();
    final runner = HerdrFakeRunner();
    final host = buildHost('a').copyWith(
      lastConnectedAt: DateTime.utc(2026),
      useMosh: true,
      predictiveEchoEnabled: true,
    );
    final hostsController = HostsController(
      FakeHostsRepository()..persisted = [host],
    );
    repository = _HerdrRepository();
    workspace = TerminalWorkspaceController(repository);
    final attention = AgentAttentionController(
      workspace: workspace,
      runnerFactory: (_) => ScriptedAgentCommandRunner([StateError('none')]),
      provider: const HerdrAttentionProvider(),
      pollInterval: const Duration(days: 1),
    );
    flow = SessionConnectFlow(
      hostsController: hostsController,
      workspace: workspace,
      runnerFactory: (_) => runner,
      preferences: InMemoryConnectPreferencesRepository(),
    );
    final companion = CompanionSetupController(
      runnerFactory: (_) => runner,
      sftpRepository: NoNetworkSftpRepository(),
    );
    final verifier = NoopVerifier();
    await tester.pumpWidget(
      CompanionSetupScope(
        controller: companion,
        agentAttention: attention,
        child: ConduitApp(
          lockController: AppLockController(AlwaysAuthenticates()),
          themeController: themeController,
          hostsController: hostsController,
          terminalRepository: NoNetworkTerminalRepository(),
          workspaceController: workspace,
          localShellController: LocalShellController(),
          hostKeyVerifier: verifier,
          promptCoordinator: HostKeyPromptCoordinator(),
          sftpRepository: NoNetworkSftpRepository(),
          sftpBookmarksRepository: InMemorySftpBookmarks(),
          agentAttention: attention,
          backupService: AppBackupService(
            hostsController: hostsController,
            themeController: themeController,
            hostKeyVerifier: verifier,
          ),
          fileExport: RecordingFileExport(),
          connectFlow: flow,
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('other-herdr-a-w1')));
    await settle(tester);
    final session = workspace.sessions.single;
    expectShowing(tester, session);
    session.sendText('ls');
    await tester.pump();

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await settle(tester);
    expect(find.byType(TerminalPage), findsNothing);

    await tester.tap(find.byKey(const ValueKey('home-session-a#herdr:w1')));
    await settle(tester);
    expectShowing(tester, session);
    expect(errors, isEmpty, reason: errors.map((e) => '$e').join('\n'));
    await unmount(tester);
  });
}
