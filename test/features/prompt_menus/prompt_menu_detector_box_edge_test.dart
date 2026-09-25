import 'package:conduit/features/prompt_menus/domain/prompt_menu_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Regression: a row that is only a box edge (a lone │, as drawn by Herdr's
  // pane borders and sidebar) used to throw a RangeError while stripping the
  // box, which blanked the whole terminal page when it was reopened.
  test('rows that are only a box edge do not throw', () {
    final rows = ['│', '  │  ', '┃', '║', '', 'plain text', '│'];
    expect(() => detectPromptMenu(rows, cursorRow: 0), returnsNormally);
    expect(detectPromptMenu(rows, cursorRow: 0), isNull);
  });

  test('a Claude menu next to lone box edges is still found', () {
    final rows = [
      '│',
      '│ Do you want to proceed?',
      '│ ❯ 1. Yes',
      '│   2. No',
      '│',
    ];
    expect(() => detectPromptMenu(rows, cursorRow: 4), returnsNormally);
  });
}
