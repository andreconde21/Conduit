import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/features/terminal/presentation/widgets/toolbar_snippet_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, {VoidCallback? onDictate}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ToolbarSnippetPalette(
            palette: AppPalette.catppuccin,
            brightness: Brightness.dark,
            hostSnippets: const [],
            globalSnippets: const [],
            onQuickPrompt: (_) {},
            onSnippet: (_) {},
            onDictate: onDictate,
          ),
        ),
      ),
    );
  }

  testWidgets('the swipe-up palette offers Dictate first', (tester) async {
    var dictated = 0;
    await pump(tester, onDictate: () => dictated += 1);

    final chip = find.byKey(const ValueKey('palette-dictate'));
    expect(chip, findsOneWidget);
    expect(
      tester.getTopLeft(chip).dx,
      lessThan(tester.getTopLeft(find.text('/clear')).dx),
    );
    await tester.tap(chip);
    expect(dictated, 1);
  });

  testWidgets('no Dictate without voice input', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('palette-dictate')), findsNothing);
  });
}
