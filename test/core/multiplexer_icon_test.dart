import 'package:conduit/core/presentation/multiplexer_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseSvgPathData', () {
    test('absolute lines and close', () {
      final bounds = parseSvgPathData(
        'M0,0 L160,0 L160,30 L0,30 Z',
      ).getBounds();
      expect(bounds, const Rect.fromLTRB(0, 0, 160, 30));
    });

    test('relative commands with implicit repeats', () {
      // m then implicit l pairs, h/v, and a relative cubic.
      final bounds = parseSvgPathData(
        'm10 10 20 0 0 20 h-20 v-20 c0 -5 5 -5 10 -5 z',
      ).getBounds();
      expect(bounds.left, 10);
      expect(bounds.right, 30);
      expect(bounds.bottom, 30);
      expect(bounds.top, lessThan(10));
    });

    test('rejects data without a leading command', () {
      expect(() => parseSvgPathData('10 10'), throwsFormatException);
    });
  });

  testWidgets('draws each logo at the requested size with a label', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MultiplexerIcon(MultiplexerKind.tmux, size: 14),
            MultiplexerIcon(MultiplexerKind.herdr, size: 22),
          ],
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('multiplexer-icon-tmux'))),
      const Size.square(14),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('multiplexer-icon-herdr'))),
      const Size.square(22),
    );
    expect(find.bySemanticsLabel('tmux'), findsOneWidget);
    expect(find.bySemanticsLabel('Herdr'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
