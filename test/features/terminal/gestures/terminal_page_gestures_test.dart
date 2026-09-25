import 'dart:convert';

import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/terminal/domain/terminal_gesture_preferences.dart';
import 'package:conduit/features/terminal/presentation/terminal_page.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';
import 'package:conduit_vt/conduit_vt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/test_doubles.dart';

/// End-to-end through the real terminal view: the gesture layer must win
/// the arena against the view's own scroll, tap and selection handling and
/// the resulting keys must reach the SSH session as bytes.
void main() {
  Future<(TrackableTerminalSession, ThemeController)> pumpTerminal(
    WidgetTester tester, {
    TerminalGesturePreferences gestures = TerminalGesturePreferences.defaults,
    SavedHost? host,
  }) async {
    final repository = InMemoryThemePreferences();
    final themeController = ThemeController(repository);
    await themeController.load();
    await themeController.setTerminalGestures(gestures);
    final session = TrackableTerminalSession();
    final workspace = TerminalWorkspaceController(
      ImmediateTerminalRepository(session),
    );
    addTearDown(workspace.dispose);
    workspace.open(host ?? buildHost('gestures'));

    await tester.pumpWidget(
      MaterialApp(
        home: TerminalPage(
          workspace: workspace,
          themeController: themeController,
          sftpRepository: NoNetworkSftpRepository(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    session.sent.clear();
    return (session, themeController);
  }

  String sentText(TrackableTerminalSession session) {
    return session.sent.map(latin1.decode).join();
  }

  Future<void> swipe(WidgetTester tester, Offset from, Offset by) async {
    final gesture = await tester.startGesture(from);
    await tester.pump();
    for (var i = 0; i < 6; i += 1) {
      await gesture.moveBy(by / 6);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
  }

  testWidgets('a horizontal swipe on the terminal sends prefix and n', (
    tester,
  ) async {
    final (session, _) = await pumpTerminal(tester);
    final center = tester.getCenter(find.byType(TerminalView));

    await swipe(tester, center, const Offset(-140, 0));

    expect(sentText(session), '\x02n');
  });

  testWidgets('a vertical drag on the terminal sends nothing', (tester) async {
    final (session, _) = await pumpTerminal(tester);
    final center = tester.getCenter(find.byType(TerminalView));

    await swipe(tester, center, const Offset(0, -140));

    expect(session.sent, isEmpty);
  });

  testWidgets('a two-finger swipe down enters copy mode and scrolls', (
    tester,
  ) async {
    final (session, _) = await pumpTerminal(tester);
    final center = tester.getCenter(find.byType(TerminalView));
    final first = await tester.createGesture(pointer: 21);
    final second = await tester.createGesture(pointer: 22);
    await first.down(center.translate(-30, -60));
    await second.down(center.translate(30, -60));
    await tester.pump();
    for (var i = 0; i < 8; i += 1) {
      await first.moveBy(const Offset(0, 14));
      await second.moveBy(const Offset(0, 14));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await first.up();
    await second.up();
    await tester.pump();

    final text = sentText(session);
    expect(text, startsWith('\x02['));
    expect(text.substring(2), contains('\x1b[A'));
    expect(text.substring(2).replaceAll('\x1b[A', ''), isEmpty);
  });

  testWidgets('the window swipe honours the gesture switch', (tester) async {
    final (session, _) = await pumpTerminal(
      tester,
      gestures: const TerminalGesturePreferences(swipeSwitchesWindow: false),
    );
    final center = tester.getCenter(find.byType(TerminalView));

    await swipe(tester, center, const Offset(-140, 0));

    expect(session.sent, isEmpty);
  });

  testWidgets('pinch on the terminal page still changes the font size', (
    tester,
  ) async {
    final (session, themeController) = await pumpTerminal(tester);
    final initial = themeController.terminalFontSize;
    final center = tester.getCenter(find.byType(TerminalView));
    final first = await tester.createGesture(pointer: 31);
    final second = await tester.createGesture(pointer: 32);
    await first.down(center.translate(-40, 0));
    await second.down(center.translate(40, 0));
    await tester.pump();
    for (var i = 0; i < 4; i += 1) {
      await first.moveBy(const Offset(-8, 0));
      await second.moveBy(const Offset(8, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await first.up();
    await second.up();
    await tester.pump(const Duration(milliseconds: 300));

    expect(themeController.terminalFontSize, greaterThan(initial));
    expect(session.sent, isEmpty);
  });

  Future<void> pinchOut(WidgetTester tester) async {
    final center = tester.getCenter(find.byType(TerminalView));
    final first = await tester.createGesture(pointer: 41);
    final second = await tester.createGesture(pointer: 42);
    await first.down(center.translate(-40, 0));
    await second.down(center.translate(40, 0));
    await tester.pump();
    for (var i = 0; i < 4; i += 1) {
      await first.moveBy(const Offset(-8, 0));
      await second.moveBy(const Offset(8, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await first.up();
    await second.up();
    await tester.pump(const Duration(milliseconds: 300));
  }

  double viewFontSize(WidgetTester tester) {
    return tester
        .widget<TerminalView>(find.byType(TerminalView))
        .textStyle
        .fontSize;
  }

  testWidgets('pinch in a Herdr session changes the font size by default', (
    tester,
  ) async {
    final (session, themeController) = await pumpTerminal(
      tester,
      host: const ConnectTarget.herdr(
        workspaceId: 'w1',
      ).apply(buildHost('gestures')),
    );
    final initial = viewFontSize(tester);

    await pinchOut(tester);

    expect(themeController.terminalFontSize, greaterThan(initial));
    // The rendered terminal picked it up, not just the preference.
    expect(viewFontSize(tester), themeController.terminalFontSize);
    // No Herdr zoom keys (prefix z) went to the session.
    expect(session.sent, isEmpty);
  });

  testWidgets('a legacy saved record still pinches the font in Herdr', (
    tester,
  ) async {
    // What preview 7 wrote: the old zoom-pane default, no schema version.
    final legacy = TerminalGesturePreferences.decode(
      '{"pinchZoom": true, "herdrPinch": "zoomPane"}',
    );
    final (session, themeController) = await pumpTerminal(
      tester,
      gestures: legacy,
      host: const ConnectTarget.herdr(
        workspaceId: 'w1',
      ).apply(buildHost('gestures')),
    );
    final initial = viewFontSize(tester);

    await pinchOut(tester);

    expect(viewFontSize(tester), greaterThan(initial));
    expect(session.sent, isEmpty);
  });

  testWidgets('Herdr zoom pane stays available as an opt-in', (tester) async {
    final (session, themeController) = await pumpTerminal(
      tester,
      gestures: const TerminalGesturePreferences(
        herdrPinch: HerdrPinchAction.zoomPane,
      ),
      host: const ConnectTarget.herdr(
        workspaceId: 'w1',
      ).apply(buildHost('gestures')),
    );
    final initial = themeController.terminalFontSize;

    await pinchOut(tester);

    expect(themeController.terminalFontSize, initial);
    expect(sentText(session), '\x02z');
  });
}
