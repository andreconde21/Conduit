import 'dart:convert';

import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/features/prompt_menus/presentation/prompt_menu_strip.dart';
import 'package:conduit/features/terminal/presentation/terminal_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

const _permissionPrompt =
    ' Bash command\r\n'
    '\r\n'
    '   git status\r\n'
    '   Show working tree status\r\n'
    '\r\n'
    ' Do you want to proceed?\r\n'
    ' ❯ 1. Yes\r\n'
    "   2. Yes, and don't ask again for git status commands in /srv/app\r\n"
    '   3. No, and tell Claude what to do differently (esc)';

const _bashSelect = '1) dev\r\n2) prod\r\n3) quit\r\n#? ';

const _modelPicker =
    ' Select model\r\n'
    ' ❯ Default (recommended)\r\n'
    '   Sonnet\r\n'
    '   Haiku\r\n'
    ' ↑/↓ to navigate · Enter to select · Esc to cancel';

const _aptPrompt = 'Do you want to continue? [Y/n] ';

void main() {
  late TrackableTerminalSession remote;
  late TerminalSessionController session;
  var sentCount = 0;

  Future<void> pumpStrip(WidgetTester tester) async {
    remote = TrackableTerminalSession();
    session = TerminalSessionController(
      host: buildHost('a'),
      repository: ImmediateTerminalRepository(remote),
    );
    addTearDown(session.dispose);
    // connect() must run outside the fake-async test zone.
    await tester.runAsync(session.connect);
    sentCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox.expand()),
              PromptMenuStrip(
                session: session,
                palette: AppPalette.everforest,
                brightness: Brightness.dark,
                onSent: () => sentCount += 1,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Writes remote output and waits past the detection debounce.
  Future<void> show(WidgetTester tester, String output) async {
    session.terminal.write(output);
    await tester.pump(PromptMenuStrip.defaultDebounce);
    await tester.pump();
  }

  List<String> sent() => [for (final bytes in remote.sent) utf8.decode(bytes)];

  group('PromptMenuStrip', () {
    testWidgets('stays hidden while no prompt is on screen', (tester) async {
      await pumpStrip(tester);
      await show(
        tester,
        r'user@host:~$ ls'
        '\r\n'
        'a.txt  b.txt'
        '\r\n',
      );

      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('renders one button per option plus Esc for a Claude Code '
        'permission prompt', (tester) async {
      await pumpStrip(tester);
      await show(tester, _permissionPrompt);

      expect(find.text('1  Yes'), findsOneWidget);
      expect(
        find.text("2  Yes, and don't ask again for git status…"),
        findsOneWidget,
      );
      expect(
        find.text('3  No, and tell Claude what to do differently'),
        findsOneWidget,
      );
      expect(find.text('Esc'), findsOneWidget);
    });

    testWidgets('a tap sends just the digit to a Claude Code menu', (
      tester,
    ) async {
      await pumpStrip(tester);
      await show(tester, _permissionPrompt);

      await tester.tap(find.text('1  Yes'));
      await tester.pump();

      expect(sent(), ['1']);
      expect(sentCount, 1);
    });

    testWidgets('the Esc chip sends Escape', (tester) async {
      await pumpStrip(tester);
      await show(tester, _permissionPrompt);

      // The Esc chip sits past the right edge until the strip is scrolled.
      await tester.ensureVisible(find.text('Esc'));
      await tester.pump();
      await tester.tap(find.text('Esc'));
      await tester.pump();

      expect(sent(), ['\x1b']);
    });

    testWidgets('hides after answering and returns once the screen changes '
        'to a new prompt', (tester) async {
      await pumpStrip(tester);
      await show(tester, _permissionPrompt);

      await tester.tap(find.text('1  Yes'));
      await tester.pump();

      expect(find.text('1  Yes'), findsNothing);

      // A screen update that keeps the same menu still leaves it hidden.
      await show(tester, '');
      expect(find.text('1  Yes'), findsNothing);

      await show(tester, '\x1b[2J\x1b[H$_bashSelect');
      expect(find.text('1  dev'), findsOneWidget);
      expect(find.text('1  Yes'), findsNothing);
    });

    testWidgets('offers the same menu again after the grace period', (
      tester,
    ) async {
      await pumpStrip(tester);
      await show(tester, _permissionPrompt);
      await tester.tap(find.text('1  Yes'));
      await tester.pump();
      expect(find.text('1  Yes'), findsNothing);

      await tester.pump(PromptMenuStrip.answeredGrace);
      await tester.pump();

      expect(find.text('1  Yes'), findsOneWidget);
    });

    testWidgets('a typed menu gets the digit followed by Enter', (
      tester,
    ) async {
      await pumpStrip(tester);
      await show(tester, _bashSelect);

      await tester.tap(find.text('2  prod'));
      await tester.pump();

      expect(sent(), ['2', '\r']);
    });

    testWidgets('an arrow-driven list is navigated relative to the pointer', (
      tester,
    ) async {
      await pumpStrip(tester);
      await show(tester, _modelPicker);

      expect(find.text('Default (recommended)'), findsOneWidget);
      await tester.tap(find.text('Haiku'));
      await tester.pump();

      expect(sent(), ['\x1b[B', '\x1b[B', '\r']);
    });

    testWidgets('a y/n prompt types the answer word and Enter', (tester) async {
      await pumpStrip(tester);
      await show(tester, _aptPrompt);

      expect(find.text('Yes'), findsOneWidget);
      expect(find.text('No'), findsOneWidget);
      await tester.tap(find.text('No'));
      await tester.pump();

      expect(sent(), ['n', '\r']);
    });

    testWidgets('long-pressing a button shows the full option text', (
      tester,
    ) async {
      await pumpStrip(tester);
      await show(tester, _permissionPrompt);

      await tester.longPress(
        find.text("2  Yes, and don't ask again for git status…"),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text(
          "Yes, and don't ask again for git status commands in /srv/app",
        ),
        findsOneWidget,
      );
      expect(sent(), isEmpty);
    });

    testWidgets('disappears when the prompt scrolls away', (tester) async {
      await pumpStrip(tester);
      await show(tester, _permissionPrompt);
      expect(find.text('1  Yes'), findsOneWidget);

      await show(tester, '\x1b[2J\x1b[H\$ ');

      expect(find.text('1  Yes'), findsNothing);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('debounces bursts of output before re-detecting', (
      tester,
    ) async {
      await pumpStrip(tester);
      session.terminal.write(_permissionPrompt);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('1  Yes'), findsNothing);

      // More output within the debounce window pushes detection out again.
      session.terminal.write('');
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('1  Yes'), findsNothing);

      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('1  Yes'), findsOneWidget);
    });
  });
}
