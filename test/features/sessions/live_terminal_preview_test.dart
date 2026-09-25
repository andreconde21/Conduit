import 'package:conduit/features/sessions/presentation/live_terminal_preview.dart';
import 'package:conduit/features/sessions/presentation/terminal_preview.dart';
import 'package:conduit_vt/conduit_vt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StyledTerminalPreview', () {
    test('captures the screen with colour runs at full width', () {
      final terminal = Terminal(maxLines: 100)..resize(60, 5);
      terminal.write('plain \x1b[31mred\x1b[0m \x1b[1;44mbold\x1b[0m\r\n');
      terminal.write('second line\r\n');

      final preview = StyledTerminalPreview.capture(terminal);

      expect(preview.columns, 60);
      expect(preview.rows, hasLength(2));
      expect(preview.lines.first.trimRight(), 'plain red bold');
      final runs = preview.rows.first;
      final red = runs.firstWhere((run) => run.text == 'red');
      expect(red.foreground & CellColor.typeMask, isNot(CellColor.normal));
      final bold = runs.firstWhere((run) => run.text == 'bold');
      expect(bold.flags & CellFlags.bold, isNot(0));
      expect(bold.background & CellColor.typeMask, isNot(CellColor.normal));
      expect(StyledTerminalPreview.capture(terminal), preview);
    });

    test('keeps only the last rows when asked', () {
      final terminal = Terminal(maxLines: 100)..resize(20, 6);
      for (var index = 0; index < 5; index++) {
        terminal.write('row $index\r\n');
      }
      final preview = StyledTerminalPreview.capture(terminal, maxRows: 2);
      expect(preview.lines.map((line) => line.trimRight()), ['row 3', 'row 4']);
    });

    test('is empty for a blank screen', () {
      final terminal = Terminal(maxLines: 100)..resize(20, 4);
      expect(StyledTerminalPreview.capture(terminal).isEmpty, isTrue);
    });
  });

  group('LiveTerminalPreview', () {
    test('fits the screen width into the tile', () {
      final size = LiveTerminalPreview.fitFontSize(
        width: 180,
        columns: 60,
        fontFamily: 'monospace',
      );
      // Whatever the font's advance, 60 cells fill the 180 px.
      expect(size, greaterThan(2));
      expect(
        LiveTerminalPreview.fitRows(height: 100, fontSize: 5, lineHeight: 1),
        20,
      );
    });

    testWidgets('renders bottom rows in the theme colours', (tester) async {
      final terminal = Terminal(maxLines: 100)..resize(40, 30);
      for (var index = 0; index < 29; index++) {
        terminal.write('line $index\r\n');
      }
      terminal.write('\x1b[32mlast\x1b[0m');
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 160,
              height: 40,
              child: LiveTerminalPreview(
                preview: StyledTerminalPreview.capture(terminal),
                theme: TerminalThemes.defaultTheme,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      );
      final text = tester.widget<RichText>(
        find.byKey(const ValueKey('live-preview-text')),
      );
      final plain = text.text.toPlainText();
      expect(plain, contains('last'));
      expect(plain, isNot(contains('line 0')));
      final green = <Color>[];
      text.text.visitChildren((span) {
        if (span is TextSpan && span.text == 'last') {
          green.add(span.style!.color!);
        }
        return true;
      });
      expect(green, [TerminalThemes.defaultTheme.green]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows a placeholder while empty', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: LiveTerminalPreview(
            preview: StyledTerminalPreview.empty,
            theme: TerminalThemes.defaultTheme,
            fontFamily: 'monospace',
            placeholder: 'Connecting…',
          ),
        ),
      );
      expect(find.text('Connecting…'), findsOneWidget);
    });
  });
}
