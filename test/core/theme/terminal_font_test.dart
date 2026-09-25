import 'dart:io';
import 'dart:ui' as ui;

import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/core/theme/terminal_appearance.dart';
import 'package:conduit/core/theme/theme_licenses.dart';
import 'package:conduit/core/theme/theme_preferences_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final file in files) {
    final bytes = File(file).readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

void main() {
  test('JetBrains Mono Nerd Font (Omarchy\'s font) is the default', () async {
    expect(defaultTerminalFont, TerminalFontOption.jetBrainsMonoNerdFont);
    expect(TerminalFontOption.values.first, defaultTerminalFont);
    final preferences = await ThemePreferencesRepository(
      InMemorySecureStorage(),
    ).load();
    expect(preferences.terminalFont, TerminalFontOption.jetBrainsMonoNerdFont);
    expect(preferences.palette, AppPalette.everforest);
  });

  test(
    'the old default font migrates, an explicit system choice stays',
    () async {
      final oldDefault = InMemorySecureStorage();
      await oldDefault.write(
        key: 'conduit.terminal_font.v1',
        value: 'atkynsonNerdFont',
      );
      await oldDefault.write(key: 'conduit.palette.v1', value: 'synthwave');
      final migrated = await ThemePreferencesRepository(oldDefault).load();
      expect(migrated.terminalFont, TerminalFontOption.jetBrainsMonoNerdFont);
      expect(migrated.palette, AppPalette.everforest);

      final system = InMemorySecureStorage();
      await system.write(
        key: 'conduit.terminal_font.v1',
        value: 'systemMonospace',
      );
      expect(
        (await ThemePreferencesRepository(system).load()).terminalFont,
        TerminalFontOption.systemMonospace,
      );
    },
  );

  test('a picked font and theme persist under the new keys', () async {
    final storage = InMemorySecureStorage();
    final repository = ThemePreferencesRepository(storage);
    await repository.save(
      const ThemePreferences(
        themeMode: ThemeMode.dark,
        palette: AppPalette.rosePine,
        terminalFont: TerminalFontOption.atkynsonNerdFont,
      ),
    );
    final loaded = await repository.load();
    expect(loaded.terminalFont, TerminalFontOption.atkynsonNerdFont);
    expect(loaded.palette, AppPalette.rosePine);
    expect(await storage.read(key: 'conductore.palette.v2'), 'rose-pine');
  });

  test('machine font names map to the bundled fonts', () {
    for (final name in [
      'JetBrainsMono Nerd Font',
      'JetBrainsMono NF',
      'JetBrainsMono Nerd Font Mono',
      'JetBrains Mono',
    ]) {
      expect(
        terminalFontForFamily(name),
        TerminalFontOption.jetBrainsMonoNerdFont,
        reason: name,
      );
    }
    expect(
      terminalFontForFamily('AtkynsonMono Nerd Font'),
      TerminalFontOption.atkynsonNerdFont,
    );
    expect(terminalFontForFamily('CaskaydiaMono Nerd Font'), isNull);
  });

  test('pubspec bundles the font weights and every licence text', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final asset in [
      'assets/fonts/JetBrainsMonoNerdFontMono-Regular.ttf',
      'assets/fonts/JetBrainsMonoNerdFontMono-Bold.ttf',
      'assets/fonts/LICENSE-JetBrainsMonoNerdFont.txt',
      'assets/fonts/README-JetBrainsMonoNerdFont.md',
      'assets/fonts/LICENSE-AtkynsonMono.txt',
    ]) {
      expect(pubspec, contains(asset));
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
    expect(
      File('assets/fonts/LICENSE-JetBrainsMonoNerdFont.txt').readAsStringSync(),
      contains('SIL OPEN FONT LICENSE Version 1.1'),
    );
    expect(omarchyLicenseText, contains('David Heinemeier Hansson'));
  });

  testWidgets('renders the Nerd Font glyphs Herdr and prompts use', (
    tester,
  ) async {
    await _loadFont('JetBrainsMonoNerdFontMono', [
      'assets/fonts/JetBrainsMonoNerdFontMono-Regular.ttf',
      'assets/fonts/JetBrainsMonoNerdFontMono-Bold.ttf',
    ]);
    const size = 24.0;
    TextPainter painterFor(String text, FontWeight weight) => TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: TerminalFontOption.jetBrainsMonoNerdFont.fontFamily,
          fontSize: size,
          fontWeight: weight,
          color: const Color(0xFFFFFFFF),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Rasterises one glyph; a glyph the font lacks draws its .notdef box.
    Future<List<int>> pixels(String text, FontWeight weight) async {
      final painter = painterFor(text, weight);
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), Offset.zero);
      painter.dispose();
      final image = await recorder.endRecording().toImage(40, 40);
      final bytes = await image.toByteData();
      image.dispose();
      return bytes!.buffer.asUint8List().toList();
    }

    final cell = painterFor('M', FontWeight.w400).width;
    const glyphs = {
      'box drawing ─': 0x2500,
      'box drawing ╭': 0x256D,
      'block █': 0x2588,
      'braille spinner ⣿': 0x28FF,
      'powerline branch': 0xE0A0,
      'powerline arrow': 0xE0B0,
      'powerline round': 0xE0B6,
      'nf-dev-git': 0xE725,
      'nf-fa-check': 0xF00C,
      'nf-fa-folder': 0xF07B,
      'nf-oct-git_branch': 0xF418,
      'nf-cod-sparkle': 0xEB99,
      'nf-md-robot (supplementary plane)': 0xF06A9,
      'heavy chevron ❯': 0x276F,
    };
    await tester.runAsync(() async {
      for (final weight in [FontWeight.w400, FontWeight.w700]) {
        // U+23FA is not in the font: this is what "missing" looks like.
        final missing = await pixels(String.fromCharCode(0x23FA), weight);
        expect(missing.any((byte) => byte != 0), isTrue);
        for (final entry in glyphs.entries) {
          final glyph = String.fromCharCode(entry.value);
          final drawn = await pixels(glyph, weight);
          final reason = '${entry.key} ($weight)';
          expect(drawn.any((byte) => byte != 0), isTrue, reason: reason);
          expect(drawn, isNot(missing), reason: reason);
          // "Mono" variant: every icon keeps exactly one terminal cell.
          expect(
            painterFor(glyph, weight).width,
            closeTo(cell, 0.01),
            reason: reason,
          );
        }
      }
    });
  });
}
