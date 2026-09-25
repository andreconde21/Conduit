import 'package:conduit/core/diagnostics/app_error_log.dart';
import 'package:conduit/core/presentation/theme_sheet.dart';
import 'package:conduit/core/theme/terminal_appearance.dart';
import 'package:conduit/core/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_doubles.dart';

void main() {
  testWidgets('appearance sheet toggles local shell visibility', (
    tester,
  ) async {
    final controller = ThemeController(InMemoryThemePreferences());
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    showThemeSheet(context: context, controller: controller);
                  },
                  child: const Text('Appearance'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    // Near the end of a long sheet: big steps stay within the 50-drag cap.
    await tester.scrollUntilVisible(
      find.text('Show local shell'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(find.text('Show local shell'), findsOneWidget);
    expect(controller.showLocalShell, isTrue);

    await tester.tap(find.text('Show local shell'));
    await tester.pumpAndSettle();

    expect(controller.showLocalShell, isFalse);
  });

  testWidgets('appearance sheet toggles terminal mouse input', (tester) async {
    final controller = ThemeController(InMemoryThemePreferences());
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    showThemeSheet(context: context, controller: controller);
                  },
                  child: const Text('Appearance'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Send mouse taps'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(find.text('Send mouse taps'), findsOneWidget);
    expect(controller.terminalMouseInput, isFalse);

    await tester.tap(find.text('Send mouse taps'));
    await tester.pumpAndSettle();

    expect(controller.terminalMouseInput, isTrue);
  });

  testWidgets('appearance sheet toggles restoring sessions on launch', (
    tester,
  ) async {
    final controller = ThemeController(InMemoryThemePreferences());
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    showThemeSheet(context: context, controller: controller);
                  },
                  child: const Text('Appearance'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Restore sessions on launch'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(controller.restoreSessionsOnLaunch, isTrue);
    await tester.tap(find.text('Restore sessions on launch'));
    await tester.pumpAndSettle();
    expect(controller.restoreSessionsOnLaunch, isFalse);
  });

  testWidgets('appearance sheet switches the toolbar style', (tester) async {
    final controller = ThemeController(InMemoryThemePreferences());
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    showThemeSheet(context: context, controller: controller);
                  },
                  child: const Text('Appearance'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Toolbar style'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(controller.terminalToolbarStyle, TerminalToolbarStyle.floatingPill);

    await tester.tap(find.text('Key rows').last);
    await tester.pumpAndSettle();

    expect(controller.terminalToolbarStyle, TerminalToolbarStyle.keyRows);
  });

  testWidgets('appearance sheet toggles menu buttons', (tester) async {
    final controller = ThemeController(InMemoryThemePreferences());
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    showThemeSheet(context: context, controller: controller);
                  },
                  child: const Text('Appearance'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Menu buttons'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(find.text('Menu buttons'), findsOneWidget);
    expect(controller.menuButtonsEnabled, isTrue);

    await tester.tap(find.text('Menu buttons'));
    await tester.pumpAndSettle();

    expect(controller.menuButtonsEnabled, isFalse);
  });

  testWidgets('appearance sheet changes terminal enter sequence', (
    tester,
  ) async {
    final controller = ThemeController(InMemoryThemePreferences());
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    showThemeSheet(context: context, controller: controller);
                  },
                  child: const Text('Appearance'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Enter sends'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(controller.terminalEnterSequence, TerminalEnterSequence.cr);

    await tester.tap(find.text('CRLF'));
    await tester.pumpAndSettle();

    expect(controller.terminalEnterSequence, TerminalEnterSequence.crlf);
  });

  testWidgets('key row editor adds and saves a custom text key', (
    tester,
  ) async {
    final controller = ThemeController(InMemoryThemePreferences());
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    showThemeSheet(context: context, controller: controller);
                  },
                  child: const Text('Appearance'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(TextButton, 'Edit'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    final initialCount = controller.terminalKeyboardRows.first.items.length;
    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Key Rows (1)'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit keys'));
    await tester.pumpAndSettle();
    expect(find.text('Row 1 Keys ($initialCount)'), findsOneWidget);

    await tester.drag(
      find.byType(ReorderableListView).last,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Custom'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'gs');
    await tester.enterText(find.byType(TextField).at(1), 'git status');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.text('gs'), findsOneWidget);
    expect(find.text('Row 1 Keys (${initialCount + 1})'), findsOneWidget);
    expect(
      controller.terminalKeyboardRows.first.items.length,
      initialCount + 1,
    );
    expect(tester.getTopLeft(find.text('gs')).dy, greaterThanOrEqualTo(0));
    expect(
      tester.getBottomRight(find.text('gs')).dy,
      lessThanOrEqualTo(
        tester.view.physicalSize.height / tester.view.devicePixelRatio,
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Done').last);
    await tester.pumpAndSettle();

    final custom = controller.terminalKeyboardRows.first.items.first;
    expect(custom.kind, TerminalKeyboardItemKind.customText);
    expect(custom.label, 'gs');
    expect(custom.text, 'git status');
  });

  testWidgets('appearance sheet credits upstream Conduit in About', (
    tester,
  ) async {
    final controller = ThemeController(InMemoryThemePreferences());
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    showThemeSheet(context: context, controller: controller);
                  },
                  child: const Text('Appearance'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    final credit = find.byKey(const ValueKey('about-upstream-credit'));
    for (var i = 0; i < 40 && credit.evaluate().isEmpty; i += 1) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pumpAndSettle();
    }

    expect(find.text('Conductore'), findsOneWidget);
    expect(
      find.text('Based on Conduit by gwitko (Apache-2.0)'),
      findsOneWidget,
    );
    expect(find.text('Recent errors'), findsOneWidget);

    AppErrorLog.instance.recordError(StateError('boom'), null);
    addTearDown(AppErrorLog.instance.clear);
    await tester.pump();
    await tester.ensureVisible(find.text('Recent errors (1)'));
    await tester.pumpAndSettle();
    // The sheet's list can reach past the screen's bottom edge: keep
    // dragging until the button is on screen, not just in the list.
    final screenBottom =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    for (
      var i = 0;
      i < 10 &&
          tester.getCenter(find.text('Recent errors (1)')).dy >
              screenBottom - 24;
      i += 1
    ) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -200));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Recent errors (1)'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recent-errors')), findsOneWidget);
    expect(find.text('Bad state: boom'), findsOneWidget);
    expect(find.byKey(const ValueKey('recent-errors-copy')), findsOneWidget);
  });

  testWidgets('appearance sheet toggles pasting images as files', (
    tester,
  ) async {
    final controller = ThemeController(InMemoryThemePreferences());
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () =>
                    showThemeSheet(context: context, controller: controller),
                child: const Text('Appearance'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    final tile = find.byKey(const ValueKey('paste-images-as-files'));
    await tester.scrollUntilVisible(
      tile,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(controller.pasteImagesAsFiles, isTrue);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(controller.pasteImagesAsFiles, isFalse);
  });
}
