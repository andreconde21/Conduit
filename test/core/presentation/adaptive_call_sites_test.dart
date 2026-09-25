import 'dart:async';

import 'package:conduit/core/presentation/adaptive_modal.dart';
import 'package:conduit/core/presentation/theme_sheet.dart';
import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/hosts/domain/multiplexer_prefix_key.dart';
import 'package:conduit/features/hosts/presentation/widgets/multiplexer_prefix_picker.dart';
import 'package:conduit/features/terminal/presentation/widgets/terminal_link_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

/// Representative call sites: the same result on phone (bottom sheet) and
/// desktop (popover or dialog).
void main() {
  Future<BuildContext> pumpHost(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext hostContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    return hostContext;
  }

  const phone = Size(400, 800);
  const desktop = Size(1280, 800);
  final popover = find.byKey(const ValueKey('adaptive-modal-popover'));
  final dialog = find.byKey(const ValueKey('adaptive-modal-dialog'));

  testWidgets(
    'link actions: popover at the pointer on desktop',
    (tester) async {
      final context = await pumpHost(tester, desktop);
      // A long-press at (300, 200) opened the menu.
      await tester.tapAt(const Offset(300, 200));
      final result = showTerminalLinkSheet(context, url: 'https://x.dev');
      await tester.pumpAndSettle();
      expect(popover, findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      final rect = tester.getRect(popover);
      expect(rect.left, closeTo(300, 1));
      expect(rect.top, greaterThanOrEqualTo(200));
      await tester.tap(find.text('Copy link'));
      await tester.pumpAndSettle();
      expect(await result, TerminalLinkAction.copyLink);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets('link actions: bottom sheet on a phone, same result', (
    tester,
  ) async {
    final context = await pumpHost(tester, phone);
    final result = showTerminalLinkSheet(context, url: 'https://x.dev');
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(popover, findsNothing);
    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();
    expect(await result, TerminalLinkAction.copyLink);
  });

  // The home gear's menu sheet became the full-screen Settings page; the
  // lock screen's theme sheet is the settings modal left.
  testWidgets(
    'lock screen theme sheet: centred dialog on desktop',
    (tester) async {
      final theme = ThemeController(InMemoryThemePreferences());
      await theme.load();
      final context = await pumpHost(tester, desktop);
      unawaited(showThemeSheet(context: context, controller: theme));
      await tester.pumpAndSettle();
      expect(dialog, findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Appearance'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('lock screen theme sheet: bottom sheet on a phone', (
    tester,
  ) async {
    final theme = ThemeController(InMemoryThemePreferences());
    await theme.load();
    final context = await pumpHost(tester, phone);
    unawaited(showThemeSheet(context: context, controller: theme));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets(
    'prefix picker: centred dialog on desktop, Esc cancels',
    (tester) async {
      final context = await pumpHost(tester, desktop);
      final result = showMultiplexerPrefixPicker(
        context: context,
        initial: MultiplexerPrefixKey.controlB,
      );
      await tester.pumpAndSettle();
      expect(dialog, findsOneWidget);
      final rect = tester.getRect(dialog);
      expect(rect.center.dx, closeTo(640, 1));
      expect(rect.height, lessThanOrEqualTo(800 * 0.8));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(await result, isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('prefix picker: bottom sheet on a phone', (tester) async {
    final context = await pumpHost(tester, phone);
    showMultiplexerPrefixPicker(
      context: context,
      initial: MultiplexerPrefixKey.controlB,
    ).ignore();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(dialog, findsNothing);
  });

  setUp(() {
    // main() installs the tracker at startup.
    AdaptiveModalPointer.install();
    AdaptiveModalPointer.reset();
  });
}
