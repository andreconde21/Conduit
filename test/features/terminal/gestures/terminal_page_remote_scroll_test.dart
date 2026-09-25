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

/// Through the whole terminal page: a one-finger drag on a full-screen
/// program must beat the gesture layer's swipes and the view's own scroll.
void main() {
  Future<TrackableTerminalSession> pumpTerminal(
    WidgetTester tester, {
    required SavedHost host,
    required String screen,
    TerminalGesturePreferences gestures = TerminalGesturePreferences.defaults,
  }) async {
    final themeController = ThemeController(InMemoryThemePreferences());
    await themeController.load();
    await themeController.setTerminalGestures(gestures);
    final remote = TrackableTerminalSession();
    final workspace = TerminalWorkspaceController(
      ImmediateTerminalRepository(remote),
    );
    addTearDown(workspace.dispose);
    workspace.open(host);
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
    workspace.activeSession!.terminal.write(
      '$screen${List.generate(80, (i) => 'line $i').join('\r\n')}',
    );
    await tester.pump();
    remote.sent.clear();
    return remote;
  }

  String sentText(TrackableTerminalSession session) =>
      session.sent.map(latin1.decode).join();

  Future<void> drag(WidgetTester tester, Offset by) async {
    final start = tester.getCenter(find.byType(TerminalView));
    final gesture = await tester.startGesture(start);
    await tester.pump();
    for (var i = 0; i < 8; i += 1) {
      await gesture.moveBy(by / 8);
      await tester.pump(const Duration(milliseconds: 120));
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
  }

  final herdr = const ConnectTarget.herdr(
    workspaceId: 'w1',
  ).apply(buildHost('scroll'));
  final tmux = const ConnectTarget.tmux('main').apply(buildHost('scroll'));

  testWidgets('Herdr: a one-finger drag down sends SGR wheel-up only', (
    tester,
  ) async {
    // What Herdr 0.9.1 enables on its client terminal.
    final session = await pumpTerminal(
      tester,
      host: herdr,
      screen: '\x1b[?1049h\x1b[?1000h\x1b[?1002h\x1b[?1003h\x1b[?1006h',
    );

    await drag(tester, const Offset(0, 140));

    final text = sentText(session);
    final notches = RegExp(r'\x1b\[<64;\d+;\d+M').allMatches(text).length;
    // 140 px less the touch slop, one notch per 14 px.
    expect(notches, inInclusiveRange(7, 10));
    expect(text.replaceAll(RegExp(r'\x1b\[<64;\d+;\d+M'), ''), isEmpty);
  });

  testWidgets('tmux without mouse: the first drag enters copy mode, a tap '
      'leaves it', (tester) async {
    final session = await pumpTerminal(
      tester,
      host: tmux,
      screen: '\x1b[?1049h',
    );

    await drag(tester, const Offset(0, 140));
    final text = sentText(session);
    expect(text, startsWith('\x02['));
    expect(text.substring(2), matches(RegExp(r'^(\x1b\[A)+$')));

    session.sent.clear();
    await tester.tapAt(tester.getCenter(find.byType(TerminalView)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(sentText(session), 'q');

    // Back to normal: the next drag enters copy mode again.
    session.sent.clear();
    await drag(tester, const Offset(0, 140));
    expect(sentText(session), startsWith('\x02['));
  });

  testWidgets('the setting off keeps the old behaviour (no copy mode)', (
    tester,
  ) async {
    final session = await pumpTerminal(
      tester,
      host: tmux,
      screen: '\x1b[?1049h',
      gestures: const TerminalGesturePreferences(dragScrollsRemote: false),
    );

    await drag(tester, const Offset(0, 140));
    expect(sentText(session), isNot(contains('\x02[')));
  });

  testWidgets('a horizontal swipe on a mouse-tracking screen still switches '
      'the window', (tester) async {
    final session = await pumpTerminal(
      tester,
      host: tmux,
      screen: '\x1b[?1049h\x1b[?1000h\x1b[?1006h',
    );
    final start = tester.getCenter(find.byType(TerminalView));
    final gesture = await tester.startGesture(start);
    await tester.pump();
    for (var i = 0; i < 6; i += 1) {
      await gesture.moveBy(const Offset(-140 / 6, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
    expect(sentText(session), '\x02n');
  });
}
