import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/core/theme/app_theme.dart';
import 'package:conduit/features/hosts/domain/multiplexer_prefix_key.dart';
import 'package:conduit/features/terminal/presentation/widgets/herdr_navigator_sheet.dart';
import 'package:conduit/features/terminal/presentation/widgets/tmux_navigator_sheet.dart';
import 'package:conduit/features/terminal/presentation/widgets/toolbar_snippet_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app theme gives every bottom sheet its drag handle; a sheet that
/// draws its own on top shows two.
void main() {
  const palette = AppPalette.catppuccin;
  const brightness = Brightness.dark;

  Future<void> open(
    WidgetTester tester,
    Future<void> Function(BuildContext context) show,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(brightness: brightness, palette: palette),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Small bars 36 dp wide: the theme's handle (36 x 3) plus any the
  /// sheet draws itself.
  int handles(WidgetTester tester) => tester
      .widgetList<Container>(find.byType(Container))
      .where(
        (container) =>
            container.constraints?.maxWidth == 36 &&
            (container.constraints?.maxHeight ?? 0) <= 4,
      )
      .length;

  testWidgets('the Herdr navigator has only the theme\'s handle', (
    tester,
  ) async {
    await open(
      tester,
      (context) => showHerdrNavigatorSheet(
        context: context,
        palette: palette,
        brightness: brightness,
        hostPrefix: MultiplexerPrefixKey.controlB,
      ),
    );
    expect(find.byKey(const ValueKey('herdr-navigator')), findsOneWidget);
    expect(handles(tester), 1);
  });

  testWidgets('the tmux navigator has only the theme\'s handle', (
    tester,
  ) async {
    await open(
      tester,
      (context) => showTmuxNavigatorSheet(
        context: context,
        palette: palette,
        brightness: brightness,
        hostPrefix: MultiplexerPrefixKey.controlB,
        sessionName: 'main',
      ),
    );
    expect(find.byKey(const ValueKey('tmux-navigator')), findsOneWidget);
    expect(handles(tester), 1);
  });

  testWidgets('the snippet palette has only the theme\'s handle', (
    tester,
  ) async {
    await open(
      tester,
      (context) => showToolbarSnippetPalette(
        context: context,
        palette: palette,
        brightness: brightness,
        hostSnippets: const [],
        globalSnippets: const [],
        onQuickPrompt: (_) {},
        onSnippet: (_) {},
      ),
    );
    expect(find.text('Quick prompts'), findsOneWidget);
    expect(handles(tester), 1);
  });
}
