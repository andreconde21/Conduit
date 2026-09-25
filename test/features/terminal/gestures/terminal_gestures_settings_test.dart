import 'package:conduit/core/presentation/theme_sheet.dart';
import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/terminal/domain/terminal_gesture_preferences.dart';
import 'package:conduit/features/terminal/presentation/gestures/terminal_gestures_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/test_doubles.dart';

void main() {
  testWidgets('each gesture switch updates and persists its preference', (
    tester,
  ) async {
    final repository = InMemoryThemePreferences();
    final controller = ThemeController(repository);
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) =>
                  TerminalGesturesSettings(controller: controller),
            ),
          ),
        ),
      ),
    );

    Future<void> toggle(String title) async {
      await tester.ensureVisible(find.text(title).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(title).first);
      await tester.pumpAndSettle();
    }

    await toggle('Swipe switches window');
    expect(controller.terminalGestures.swipeSwitchesWindow, isFalse);

    await toggle('Pinch to zoom');
    expect(controller.terminalGestures.pinchZoom, isFalse);

    await toggle('Two-finger scrollback');
    expect(controller.terminalGestures.twoFingerScroll, isFalse);

    await toggle('Swipe down opens sessions');
    expect(controller.terminalGestures.headerSwipeOpensSessions, isFalse);

    await toggle('Edge swipe opens agents');
    expect(controller.terminalGestures.edgeSwipeOpensAgents, isFalse);

    await toggle('Herdr');
    expect(
      controller.terminalGestures.windowSwitchTarget,
      TerminalWindowSwitchTarget.herdr,
    );

    await toggle('Two-finger swipe switches pane');
    expect(controller.terminalGestures.herdrTwoFingerPanes, isFalse);

    await toggle('Scrollback');
    expect(
      controller.terminalGestures.herdrTwoFingerVertical,
      HerdrVerticalSwipe.scrollback,
    );

    expect(controller.terminalGestures.herdrPinch, HerdrPinchAction.fontSize);
    await toggle('Zoom pane');
    expect(controller.terminalGestures.herdrPinch, HerdrPinchAction.zoomPane);

    // Everything went through the repository.
    final saved = await repository.load();
    expect(saved.terminalGestures, controller.terminalGestures);
    expect(saved.terminalGestures.anyEnabled, isFalse);

    await toggle('Pinch to zoom');
    expect(controller.terminalGestures.pinchZoom, isTrue);
  });

  testWidgets('the appearance sheet shows a Gestures section', (tester) async {
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
      find.text('GESTURES'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.scrollUntilVisible(
      find.text('Pinch to zoom'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(controller.terminalGestures.pinchZoom, isTrue);

    await tester.tap(find.text('Pinch to zoom'));
    await tester.pumpAndSettle();

    expect(controller.terminalGestures.pinchZoom, isFalse);
  });
}
