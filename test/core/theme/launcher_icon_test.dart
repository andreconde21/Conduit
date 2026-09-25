import 'dart:io';

import 'package:conduit/core/presentation/conduit_brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The in-app mark and the Android launcher vector draw the same shapes.
void main() {
  const res = 'android/app/src/main/res';

  List<double> numbers(String pathData) => RegExp(
    r'-?\d+(?:\.\d+)?',
  ).allMatches(pathData).map((m) => double.parse(m.group(0)!)).toList();

  // The launcher glyph box is 60dp at 24dp on the 108dp adaptive canvas.
  double dp(double unit) => 24 + unit * 60;

  test('launcher vector matches ConductoreMarkPainter', () {
    final xml = File(
      '$res/drawable/ic_launcher_foreground.xml',
    ).readAsStringSync();
    final paths = RegExp(
      r'android:pathData="([^"]+)"',
    ).allMatches(xml).map((m) => numbers(m.group(1)!)).toList();
    const chevron = ConductoreMarkPainter.chevron;
    expect(
      paths[0],
      [
        for (final point in chevron) ...[dp(point.dx), dp(point.dy)],
      ].map((v) => closeTo(v, 0.05)).toList(),
    );
    const handle = ConductoreMarkPainter.batonHandle;
    const tip = ConductoreMarkPainter.batonTip;
    expect(
      paths[1],
      [
        dp(handle.dx),
        dp(handle.dy),
        dp(tip.dx),
        dp(tip.dy),
      ].map((v) => closeTo(v, 0.05)).toList(),
    );
    expect(xml, contains('#A7C080'));
    expect(
      File('$res/values/colors.xml').readAsStringSync(),
      contains('#2D353B'),
    );
    final adaptive = File(
      '$res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    expect(adaptive, contains('@drawable/ic_launcher_monochrome'));
    // No density PNG may shadow the vector drawables.
    for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      expect(
        File('$res/drawable-$density/ic_launcher_foreground.png').existsSync(),
        isFalse,
      );
    }
  });

  testWidgets('the brand glyph paints the mark in the theme accent', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: ConduitGlyph(size: 48))),
    );
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(ConduitGlyph),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(paint.painter, isA<ConductoreMarkPainter>());
    expect(tester.getSize(find.byType(ConduitGlyph)), const Size(48, 48));
  });
}
