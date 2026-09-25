import 'package:conduit/core/presentation/adaptive_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<Future<String?> Function()> pumpOpener(
    WidgetTester tester,
    AdaptiveModalKind kind, {
    Size size = const Size(1280, 800),
    Widget? content,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext buttonContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Builder(
              builder: (context) {
                buttonContext = context;
                return const SizedBox(
                  key: ValueKey('anchor'),
                  width: 40,
                  height: 40,
                );
              },
            ),
          ),
        ),
      ),
    );
    return () => showAdaptiveModal<String>(
      context: buttonContext,
      kind: kind,
      anchorContext: buttonContext,
      builder: (context) =>
          content ??
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const TextField(key: ValueKey('first-field')),
              ListTile(
                title: const Text('Pick me'),
                onTap: () => Navigator.of(context).pop('picked'),
              ),
            ],
          ),
    );
  }

  const desktops = TargetPlatformVariant({
    TargetPlatform.linux,
    TargetPlatform.windows,
    TargetPlatform.macOS,
  });

  for (final (kind, presentation) in [
    (AdaptiveModalKind.menu, AdaptiveModalPresentation.popover),
    (AdaptiveModalKind.dialog, AdaptiveModalPresentation.dialog),
    (AdaptiveModalKind.sidePanel, AdaptiveModalPresentation.sidePanel),
    (AdaptiveModalKind.palette, AdaptiveModalPresentation.palette),
  ]) {
    testWidgets('desktop shows a ${kind.name} as ${presentation.name}, same '
        'result', (tester) async {
      final open = await pumpOpener(tester, kind);
      final result = open();
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('adaptive-modal-${presentation.name}')),
        findsOneWidget,
      );
      expect(find.byType(BottomSheet), findsNothing);
      await tester.tap(find.text('Pick me'));
      await tester.pumpAndSettle();
      expect(await result, 'picked');
    }, variant: desktops);
  }

  testWidgets('phones keep the bottom sheet for every kind', (tester) async {
    for (final kind in AdaptiveModalKind.values) {
      final open = await pumpOpener(tester, kind, size: const Size(400, 800));
      final result = open();
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget, reason: kind.name);
      await tester.tap(find.text('Pick me'));
      await tester.pumpAndSettle();
      expect(await result, 'picked');
    }
  });

  testWidgets('a wide phone-class window gets the desktop presentation', (
    tester,
  ) async {
    final open = await pumpOpener(tester, AdaptiveModalKind.dialog);
    open().ignore();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('adaptive-modal-dialog')), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('Esc closes with null and the first field gets the focus', (
    tester,
  ) async {
    final open = await pumpOpener(tester, AdaptiveModalKind.dialog);
    final result = open();
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('first-field')),
    );
    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('first-field')),
        matching: find.byType(EditableText),
      ),
    );
    expect(field, isNotNull);
    expect(editable.focusNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('adaptive-modal-dialog')), findsNothing);
    expect(await result, isNull);
  }, variant: desktops);

  testWidgets(
    'a menu popover opens next to its anchor',
    (tester) async {
      final open = await pumpOpener(tester, AdaptiveModalKind.menu);
      open().ignore();
      await tester.pumpAndSettle();
      final anchor = tester.getRect(find.byKey(const ValueKey('anchor')));
      final popover = tester.getRect(
        find.byKey(const ValueKey('adaptive-modal-popover')),
      );
      expect(popover.top, greaterThanOrEqualTo(anchor.bottom));
      expect(popover.left, lessThan(anchor.right + 20));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  test('presentation choice per kind', () {
    expect(AdaptiveModalKind.values, hasLength(4));
  });
}
