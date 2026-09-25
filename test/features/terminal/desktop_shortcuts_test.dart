import 'dart:convert';

import 'package:conduit/core/theme/terminal_appearance.dart';
import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/hosts/presentation/hosts_controller.dart';
import 'package:conduit/features/sessions/domain/connect_preferences.dart';
import 'package:conduit/features/sessions/presentation/connect_picker_sheet.dart';
import 'package:conduit/features/sessions/presentation/session_connect_flow.dart';
import 'package:conduit/features/terminal/presentation/desktop_shortcuts.dart';
import 'package:conduit/features/terminal/presentation/terminal_page.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';
import 'package:conduit/features/terminal/presentation/widgets/terminal_header.dart';
import 'package:conduit_vt/conduit_vt.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../../support/test_doubles.dart';

class _NoopWakelock extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}

  @override
  Future<bool> get enabled async => false;
}

const _desktops = TargetPlatformVariant({
  TargetPlatform.linux,
  TargetPlatform.windows,
});

class _Harness {
  _Harness(this.workspace, this.theme, this.session);

  final TerminalWorkspaceController workspace;
  final ThemeController theme;
  final TrackableTerminalSession session;

  String get sent => session.sent.map(latin1.decode).join();
  int get activeIndex => workspace.sessions.indexOf(workspace.activeSession!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WakelockPlusPlatformInterface.instance = _NoopWakelock();

  Future<_Harness> pumpTerminal(
    WidgetTester tester, {
    int sessions = 1,
    bool withFlow = false,
  }) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final theme = ThemeController(InMemoryThemePreferences());
    await theme.load();
    final session = TrackableTerminalSession();
    final workspace = TerminalWorkspaceController(
      ImmediateTerminalRepository(session),
    );
    addTearDown(workspace.dispose);
    final hosts = [for (var i = 0; i < sessions; i++) buildHost('h$i')];
    SessionConnectFlow? flow;
    if (withFlow) {
      final hostsController = HostsController(
        FakeHostsRepository()..persisted = hosts,
      );
      await hostsController.load();
      flow = SessionConnectFlow(
        hostsController: hostsController,
        workspace: workspace,
        runnerFactory: (_) => ScriptedAgentCommandRunner([
          const AgentCommandResult(stdout: '', stderr: '', exitCode: 0),
        ]),
        preferences: InMemoryConnectPreferencesRepository(),
      );
    }
    for (final host in hosts) {
      workspace.open(host);
    }
    workspace.activate(workspace.sessions.first);
    await tester.pumpWidget(
      MaterialApp(
        home: TerminalPage(
          workspace: workspace,
          themeController: theme,
          sftpRepository: NoNetworkSftpRepository(),
          connectFlow: flow,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    session.sent.clear();
    return _Harness(workspace, theme, session);
  }

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool ctrl = false,
    bool shift = false,
    bool alt = false,
    bool meta = false,
  }) async {
    final modifiers = [
      if (ctrl) LogicalKeyboardKey.controlLeft,
      if (shift) LogicalKeyboardKey.shiftLeft,
      if (alt) LogicalKeyboardKey.altLeft,
      if (meta) LogicalKeyboardKey.metaLeft,
    ];
    for (final modifier in modifiers) {
      await tester.sendKeyDownEvent(modifier);
    }
    await tester.sendKeyEvent(key);
    for (final modifier in modifiers.reversed) {
      await tester.sendKeyUpEvent(modifier);
    }
    await tester.pump();
  }

  Future<void> wheel(
    WidgetTester tester,
    double dy, {
    bool ctrl = false,
  }) async {
    final center = tester.getCenter(find.byType(TerminalView));
    final pointer = TestPointer(7, PointerDeviceKind.mouse);
    if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(pointer.hover(center));
    await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
    if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('Ctrl + wheel zooms; a plain wheel does not', (tester) async {
    final h = await pumpTerminal(tester);
    final start = h.theme.terminalFontSize;

    await wheel(tester, -100, ctrl: true);
    expect(h.theme.terminalFontSize, start + desktopZoomStep);
    await wheel(tester, 100, ctrl: true);
    await wheel(tester, 100, ctrl: true);
    expect(h.theme.terminalFontSize, start - desktopZoomStep);

    await wheel(tester, -100);
    expect(h.theme.terminalFontSize, start - desktopZoomStep);
    expect(h.sent, isEmpty);
    // Let the resize the font change triggered settle.
    await tester.pump(const Duration(seconds: 1));
  }, variant: _desktops);

  testWidgets('zoom keys change the font size and never reach the shell', (
    tester,
  ) async {
    final h = await pumpTerminal(tester);
    final start = h.theme.terminalFontSize;

    await press(tester, LogicalKeyboardKey.equal, ctrl: true);
    await press(tester, LogicalKeyboardKey.equal, ctrl: true, shift: true);
    expect(h.theme.terminalFontSize, start + 2 * desktopZoomStep);
    await press(tester, LogicalKeyboardKey.minus, ctrl: true);
    expect(h.theme.terminalFontSize, start + desktopZoomStep);
    await press(tester, LogicalKeyboardKey.digit0, ctrl: true);
    expect(h.theme.terminalFontSize, terminalFontSizeDefault);

    expect(h.sent, isEmpty);
    // Undo (Ctrl+_) still belongs to the shell.
    await press(tester, LogicalKeyboardKey.minus, ctrl: true, shift: true);
    expect(h.theme.terminalFontSize, terminalFontSizeDefault);
    await tester.pump(const Duration(seconds: 1));
  }, variant: _desktops);

  testWidgets('next, previous and numbered session shortcuts', (tester) async {
    final h = await pumpTerminal(tester, sessions: 3);
    expect(h.activeIndex, 0);

    await press(tester, LogicalKeyboardKey.tab, ctrl: true);
    expect(h.activeIndex, 1);
    await press(tester, LogicalKeyboardKey.tab, ctrl: true);
    expect(h.activeIndex, 2);
    await press(tester, LogicalKeyboardKey.tab, ctrl: true);
    expect(h.activeIndex, 0, reason: 'wraps around');
    await press(tester, LogicalKeyboardKey.tab, ctrl: true, shift: true);
    expect(h.activeIndex, 2);
    await press(tester, LogicalKeyboardKey.tab, ctrl: true, shift: true);
    expect(h.activeIndex, 1);
    await press(tester, LogicalKeyboardKey.digit1, alt: true);
    expect(h.activeIndex, 0);
    await press(tester, LogicalKeyboardKey.digit3, alt: true);
    expect(h.activeIndex, 2);

    expect(h.sent, isEmpty);
    await tester.pump(const Duration(milliseconds: 300));
  }, variant: _desktops);

  testWidgets('F11 toggles the fullscreen terminal', (tester) async {
    await pumpTerminal(tester);
    expect(find.byType(TerminalHeader), findsOneWidget);
    await press(tester, LogicalKeyboardKey.f11);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(TerminalHeader), findsNothing);
    await press(tester, LogicalKeyboardKey.f11);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(TerminalHeader), findsOneWidget);
  }, variant: _desktops);

  testWidgets(
    'Ctrl+Shift+W asks before ending a plain shell',
    (tester) async {
      final h = await pumpTerminal(tester, sessions: 2);
      final dialog = find.byKey(const ValueKey('close-session-confirm'));

      await press(tester, LogicalKeyboardKey.keyW, ctrl: true, shift: true);
      await tester.pumpAndSettle();
      expect(dialog, findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(h.workspace.sessions, hasLength(2));

      await press(tester, LogicalKeyboardKey.keyW, ctrl: true, shift: true);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Close'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(h.workspace.sessions, hasLength(1));
      expect(h.sent, isEmpty);
      // Semantics off: closing a session trips a semantics geometry assertion
      // on main already (also through the header menu), unrelated to the
      // shortcut.
    },
    variant: _desktops,
    semanticsEnabled: false,
  );

  testWidgets('Ctrl+Shift+T opens the connect picker for this machine', (
    tester,
  ) async {
    await pumpTerminal(tester, withFlow: true);
    await press(tester, LogicalKeyboardKey.keyT, ctrl: true, shift: true);
    await tester.pumpAndSettle();
    expect(find.byType(ConnectPickerSheet), findsOneWidget);
    expect(find.textContaining('h0'), findsWidgets);
  }, variant: _desktops);

  testWidgets('Ctrl+Shift+/ opens the shortcuts sheet', (tester) async {
    await pumpTerminal(tester);
    await press(tester, LogicalKeyboardKey.slash, ctrl: true, shift: true);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('desktop-shortcuts-sheet')),
      findsOneWidget,
    );
    expect(find.text('Ctrl+Shift+T'), findsOneWidget);
    expect(find.text('Alt+1…9'), findsOneWidget);
  }, variant: _desktops);

  testWidgets(
    'macOS uses Cmd for zoom and numbered sessions',
    (tester) async {
      final h = await pumpTerminal(tester, sessions: 2);
      final start = h.theme.terminalFontSize;
      await press(tester, LogicalKeyboardKey.equal, meta: true);
      expect(h.theme.terminalFontSize, start + desktopZoomStep);
      await press(tester, LogicalKeyboardKey.digit2, meta: true);
      expect(h.activeIndex, 1);
      // Ctrl+= is not a zoom key on macOS.
      await press(tester, LogicalKeyboardKey.equal, ctrl: true);
      expect(h.theme.terminalFontSize, start + desktopZoomStep);
      await tester.pump(const Duration(seconds: 1));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('phones: no wheel zoom, keys go to the shell', (tester) async {
    final h = await pumpTerminal(tester, sessions: 2);
    final start = h.theme.terminalFontSize;

    await wheel(tester, -100, ctrl: true);
    await press(tester, LogicalKeyboardKey.equal, ctrl: true);
    await press(tester, LogicalKeyboardKey.digit2, alt: true);
    await press(tester, LogicalKeyboardKey.keyW, ctrl: true, shift: true);
    await tester.pumpAndSettle();

    expect(h.theme.terminalFontSize, start);
    expect(h.activeIndex, 0);
    expect(find.byKey(const ValueKey('close-session-confirm')), findsNothing);
    expect(h.workspace.sessions, hasLength(2));
  });

  test('phones never match a desktop shortcut', () {
    expect(
      matchDesktopShortcut(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.f11,
          logicalKey: LogicalKeyboardKey.f11,
          timeStamp: Duration.zero,
        ),
      ),
      isNull,
    );
  });
}
