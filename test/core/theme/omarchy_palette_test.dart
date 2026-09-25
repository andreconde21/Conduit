import 'dart:io';
import 'dart:math' as math;

import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/core/theme/omarchy_colors.dart';
import 'package:conduit/core/theme/omarchy_themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  const lightThemes = {
    'catppuccin-latte',
    'flexoki-light',
    'lupine',
    'rose-pine',
    'white',
  };

  test('bundles every theme Omarchy ships, Everforest as the default', () {
    final fixtures = Directory('test/fixtures/omarchy/themes')
        .listSync()
        .whereType<Directory>()
        .map((dir) => dir.uri.pathSegments.where((s) => s.isNotEmpty).last)
        .toSet();
    expect(fixtures, hasLength(22));
    expect(AppPalette.values.map((p) => p.id).toSet(), fixtures);
    expect(omarchyBundledThemes.keys.toSet(), fixtures);
    expect(AppPalette.defaultPalette, AppPalette.everforest);
    expect(AppPalette.everforest.canvas, const Color(0xFF2D353B));
    expect(AppPalette.everforest.accent, const Color(0xFF7FBBB3));
  });

  for (final palette in AppPalette.values) {
    group(palette.label, () {
      test('the Dart resolver matches Omarchy\'s resolver', () {
        final source = File(
          'test/fixtures/omarchy/themes/${palette.id}/colors.toml',
        ).readAsStringSync();
        expect(OmarchyColorResolver.resolveToml(source), palette.colors);
      });

      test('keeps Omarchy\'s mode', () {
        expect(palette.isDark, !lightThemes.contains(palette.id));
        expect(
          palette.brightness,
          lightThemes.contains(palette.id) ? Brightness.light : Brightness.dark,
        );
      });

      test('maps 16 ANSI colours plus fg, bg, cursor and selection', () {
        final t = palette.terminalTheme;
        final ansi = [
          t.black,
          t.red,
          t.green,
          t.yellow,
          t.blue,
          t.magenta,
          t.cyan,
          t.white,
          t.brightBlack,
          t.brightRed,
          t.brightGreen,
          t.brightYellow,
          t.brightBlue,
          t.brightMagenta,
          t.brightCyan,
          t.brightWhite,
        ];
        expect(ansi, hasLength(16));
        for (final color in ansi) {
          expect(color.a, 1.0);
        }
        expect(t.background, palette.colors.background);
        expect(t.foreground, palette.colors.foreground);
        expect(t.black, palette.colors.background);
        expect(t.brightBlack, palette.colors.muted);
        expect(t.cursor, palette.colors.brightForeground);
        // Painted over text, so it must stay translucent.
        expect(t.selection.a, lessThan(0.5));
        expect(identical(palette.terminalTheme, t), isTrue);
      });

      test('text contrast on the background is at least 4.5:1', () {
        expect(
          contrast(palette.foreground, palette.canvas),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(palette.foreground, palette.panelElevated),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(palette.mutedForeground, palette.canvas),
          greaterThanOrEqualTo(3),
        );
      });

      test('chrome is flat and derived from the theme background', () {
        expect(palette.canvas, palette.colors.background);
        expect(palette.hairline, palette.colors.muted);
        expect(contrast(palette.panel, palette.canvas), lessThan(1.25));
        expect(palette.border, isNot(palette.canvas));
      });
    });
  }

  group('saved palette ids', () {
    test('the old Conduit default and retired palettes become Everforest', () {
      for (final old in [
        'synthwave',
        'dracula',
        'solarized',
        'oneDark',
        'monokai',
        'ayuDark',
        'nightOwl',
        'palenight',
        'githubDark',
        'rosePine',
        null,
        '',
        'garbage',
      ]) {
        expect(
          AppPalette.fromStoredId(old),
          AppPalette.everforest,
          reason: old,
        );
      }
    });

    test('old palettes Omarchy also ships keep that theme', () {
      expect(AppPalette.fromStoredId('tokyoNight'), AppPalette.tokyoNight);
      expect(AppPalette.fromStoredId('catppuccin'), AppPalette.catppuccin);
      expect(AppPalette.fromStoredId('nord'), AppPalette.nord);
      expect(AppPalette.fromStoredId('gruvbox'), AppPalette.gruvbox);
      expect(AppPalette.fromStoredId('kanagawa'), AppPalette.kanagawa);
      expect(AppPalette.fromStoredId('everforest'), AppPalette.everforest);
    });

    test('Omarchy ids round-trip', () {
      for (final palette in AppPalette.values) {
        expect(AppPalette.fromStoredId(palette.name), palette);
      }
    });

    test('Omarchy display names map to the bundled theme', () {
      expect(
        AppPalette.forOmarchyThemeName('Tokyo Night'),
        AppPalette.tokyoNight,
      );
      expect(AppPalette.forOmarchyThemeName('retro-82\n'), AppPalette.retro82);
      expect(AppPalette.forOmarchyThemeName('my-theme'), isNull);
    });
  });
}
