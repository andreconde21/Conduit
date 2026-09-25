import 'dart:convert';

import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/terminal/presentation/desktop_keyboard.dart';
import 'package:conduit/features/terminal/presentation/terminal_keyboard_bar.dart';
import 'package:conduit/features/terminal/presentation/terminal_page.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';
import 'package:conduit/features/terminal/presentation/widgets/floating_toolbar.dart';
import 'package:conduit_vt/conduit_vt.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

void main() {
  group('DesktopKeyInputHandler', () {
    String? send(
      TerminalTargetPlatform platform,
      TerminalKey key, {
      bool ctrl = false,
      bool alt = false,
      bool shift = false,
    }) {
      String? output;
      final terminal = Terminal(
        platform: platform,
        inputHandler: const CascadeInputHandler([
          DesktopKeyInputHandler(),
          defaultInputHandler,
        ]),
        onOutput: (data) => output = data,
      );
      final handled = terminal.keyInput(
        key,
        ctrl: ctrl,
        alt: alt,
        shift: shift,
      );
      return handled ? output : null;
    }

    const linux = TerminalTargetPlatform.linux;
    const macos = TerminalTargetPlatform.macos;

    test('Alt is meta: ESC plus the letter in its real case', () {
      expect(send(linux, TerminalKey.keyB, alt: true), '\x1bb');
      expect(send(linux, TerminalKey.keyB, alt: true, shift: true), '\x1bB');
      expect(send(linux, TerminalKey.digit1, alt: true), '\x1b1');
      expect(send(linux, TerminalKey.period, alt: true), '\x1b.');
    });

    test('Ctrl reaches the shell for letters and symbols', () {
      expect(send(linux, TerminalKey.keyC, ctrl: true), '\x03');
      expect(send(linux, TerminalKey.keyA, ctrl: true), '\x01');
      expect(send(linux, TerminalKey.bracketRight, ctrl: true), '\x1d');
      expect(send(linux, TerminalKey.backslash, ctrl: true), '\x1c');
      expect(send(linux, TerminalKey.slash, ctrl: true), '\x1f');
      expect(send(linux, TerminalKey.space, ctrl: true), '\x00');
    });

    test('cursor and function keys keep their xterm sequences', () {
      expect(send(linux, TerminalKey.arrowUp), '\x1b[A');
      expect(send(linux, TerminalKey.arrowLeft, ctrl: true), '\x1b[1;5D');
      expect(send(linux, TerminalKey.arrowLeft, alt: true), '\x1b[1;3D');
      expect(
        send(linux, TerminalKey.arrowRight, alt: true, shift: true),
        '\x1b[1;4C',
      );
      expect(send(linux, TerminalKey.home), '\x1b[H');
      expect(send(linux, TerminalKey.f1), '\x1bOP');
      expect(send(linux, TerminalKey.f5), '\x1b[15~');
      expect(send(linux, TerminalKey.f12), '\x1b[24~');
      expect(send(linux, TerminalKey.tab, shift: true), '\x1b[Z');
    });

    test('macOS leaves Option to compose characters', () {
      expect(send(macos, TerminalKey.keyB, alt: true), isNull);
      expect(send(macos, TerminalKey.digit2, alt: true), isNull);
      expect(send(macos, TerminalKey.keyC, ctrl: true), '\x03');
    });

    testWidgets(
      'desktop sessions get the handler, the platform flag and shortcuts',
      (tester) async {
        expect(terminalInputHandlerForPlatform(), isA<CascadeInputHandler>());
        expect(terminalTargetPlatform(), TerminalTargetPlatform.linux);
        final shortcuts = desktopTerminalShortcuts()!;
        expect(
          shortcuts.keys.whereType<SingleActivator>().where(
            (a) => a.control && !a.shift,
          ),
          isEmpty,
          reason: 'plain Ctrl combinations belong to the shell',
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    test('phones keep conduit_vt defaults', () {
      expect(terminalInputHandlerForPlatform(), same(defaultInputHandler));
      expect(terminalTargetPlatform(), TerminalTargetPlatform.unknown);
      expect(desktopTerminalShortcuts(), isNull);
    });
  });

  group('terminal page on desktop', () {
    Future<TrackableTerminalSession> pumpTerminal(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final themeController = ThemeController(InMemoryThemePreferences());
      await themeController.load();
      final session = TrackableTerminalSession();
      final workspace = TerminalWorkspaceController(
        ImmediateTerminalRepository(session),
      );
      addTearDown(workspace.dispose);
      workspace.open(buildHost('desktop'));
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
      return session;
    }

    String sent(TrackableTerminalSession session) =>
        session.sent.map(latin1.decode).join();

    const toggle = ValueKey('desktop-keys-toggle');
    // The pill (default style) or the classic key rows.
    final touchToolbar = find.byWidgetPredicate(
      (widget) =>
          widget is FloatingTerminalToolbar || widget is TerminalKeyboardBar,
    );

    testWidgets(
      'hides the pill and key rows by default, one click brings them back',
      (tester) async {
        await pumpTerminal(tester);
        expect(touchToolbar, findsNothing);
        expect(find.text('On-screen keys'), findsOneWidget);

        await tester.tap(find.byKey(toggle));
        await tester.pump();
        expect(touchToolbar, findsOneWidget);
        expect(find.text('Hide on-screen keys'), findsOneWidget);

        await tester.tap(find.byKey(toggle));
        await tester.pump();
        expect(touchToolbar, findsNothing);
        // Let the resize the layout change triggered settle.
        await tester.pump(const Duration(milliseconds: 300));
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.linux,
        TargetPlatform.windows,
        TargetPlatform.macOS,
      }),
    );

    testWidgets(
      'hardware keys go straight to the remote shell',
      (tester) async {
        final session = await pumpTerminal(tester);

        Future<void> chord(
          LogicalKeyboardKey modifier,
          LogicalKeyboardKey key,
        ) async {
          await tester.sendKeyDownEvent(modifier, platform: 'linux');
          await tester.sendKeyEvent(key, platform: 'linux');
          await tester.sendKeyUpEvent(modifier, platform: 'linux');
        }

        await chord(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyC);
        await chord(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyA);
        await chord(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyV);
        await chord(LogicalKeyboardKey.altLeft, LogicalKeyboardKey.keyB);
        await tester.sendKeyEvent(
          LogicalKeyboardKey.arrowUp,
          platform: 'linux',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.f5, platform: 'linux');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape, platform: 'linux');
        await tester.pump();

        expect(sent(session), '\x03\x01\x16\x1bb\x1b[A\x1b[15~\x1b');
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    testWidgets('phones keep the key rows and no toggle', (tester) async {
      await pumpTerminal(tester);
      expect(touchToolbar, findsOneWidget);
      expect(find.byKey(toggle), findsNothing);
    });
  });
}
