import 'package:conduit/core/presentation/multiplexer_icon.dart';
import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/core/theme/app_theme.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/hosts/presentation/widgets/home_session_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<BuildContext> _pumpThemed(
  WidgetTester tester,
  AppPalette palette,
) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(brightness: Brightness.light, palette: palette),
      darkTheme: AppTheme.build(brightness: Brightness.dark, palette: palette),
      themeMode: palette.themeMode,
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox();
        },
      ),
    ),
  );
  // MaterialApp animates a theme change; read the settled theme.
  await tester.pumpAndSettle();
  return captured;
}

void main() {
  testWidgets('the active palette is reachable from the theme', (tester) async {
    final context = await _pumpThemed(tester, AppPalette.tokyoNight);
    expect(AppPalette.of(context), AppPalette.tokyoNight);
  });

  testWidgets('outside an app theme the default palette answers', (
    tester,
  ) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(AppPalette.of(captured), AppPalette.defaultPalette);
  });

  testWidgets('tmux logomark stays visible on dark themes', (tester) async {
    var context = await _pumpThemed(tester, AppPalette.everforest);
    expect(
      MultiplexerIcon.tmuxScreenColor(context),
      AppPalette.everforest.foreground,
    );
    context = await _pumpThemed(tester, AppPalette.rosePine);
    expect(MultiplexerIcon.tmuxScreenColor(context), const Color(0xFF3C3C3C));
  });

  testWidgets('home status colours come from the theme', (tester) async {
    final context = await _pumpThemed(tester, AppPalette.gruvbox);
    const palette = AppPalette.gruvbox;
    expect(
      agentStateColor(context, AgentAttentionState.needsInput),
      palette.colors.orange,
    );
    expect(
      agentStateColor(context, AgentAttentionState.finished),
      palette.colors.green,
    );
  });
}
