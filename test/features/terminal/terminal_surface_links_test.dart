import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/features/terminal/presentation/terminal_session_controller.dart';
import 'package:conduit/features/terminal/presentation/widgets/terminal_surface.dart';
import 'package:conduit_vt/conduit_vt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

void main() {
  late TerminalSessionController session;
  late List<String> links;
  late List<String> paths;
  late List<(String, String)> longPresses;
  late bool longPressResult;

  Future<void> pumpSurface(WidgetTester tester) async {
    session = TerminalSessionController(
      host: buildHost('links'),
      repository: ImmediateTerminalRepository(TrackableTerminalSession()),
    );
    addTearDown(session.dispose);
    links = [];
    paths = [];
    longPresses = [];
    longPressResult = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 700,
            height: 400,
            child: TerminalSurface(
              session: session,
              palette: AppPalette.catppuccin,
              brightness: Brightness.dark,
              fontFamily: 'monospace',
              fontSize: 14,
              predictiveEchoEnabled: false,
              terminalMouseInput: false,
              focusNode: null,
              tmuxScrollMode: false,
              onExitTmuxScrollMode: () {},
              onPathTap: paths.add,
              onLinkTap: links.add,
              onLinkLongPress: (url, line) async {
                longPresses.add((url, line));
                return longPressResult;
              },
            ),
          ),
        ),
      ),
    );
    session.terminal.write(
      'docs at https://example.com/guide now\r\n'
      'error in /etc/nginx/nginx.conf\r\n'
      r'$ ',
    );
    await tester.pump();
  }

  Offset cellCenter(WidgetTester tester, int column, int row) {
    final state = tester.state<TerminalViewState>(find.byType(TerminalView));
    final render = state.renderTerminal;
    final cell = render.cellSize;
    final origin = render.getOffset(CellOffset(column, row));
    return render.localToGlobal(
      origin + Offset(cell.width / 2, cell.height / 2),
    );
  }

  TerminalController controllerOf(WidgetTester tester) =>
      tester.widget<TerminalView>(find.byType(TerminalView)).controller!;

  testWidgets('a tap on a link reports the link, a tap on a path the path', (
    tester,
  ) async {
    await pumpSurface(tester);

    await tester.tapAt(cellCenter(tester, 12, 0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(links, ['https://example.com/guide']);
    expect(paths, isEmpty);

    await tester.tapAt(cellCenter(tester, 12, 1));
    await tester.pump(const Duration(milliseconds: 400));
    expect(paths, ['/etc/nginx/nginx.conf']);
    expect(links, hasLength(1));

    // Plain words do nothing.
    await tester.tapAt(cellCenter(tester, 1, 0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(links, hasLength(1));
    expect(paths, hasLength(1));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('a long press on a link opens the menu callback and keeps the '
      'word selection unless an action was taken', (tester) async {
    await pumpSurface(tester);

    await tester.longPressAt(cellCenter(tester, 18, 0));
    await tester.pump();
    expect(longPresses, [
      ('https://example.com/guide', 'docs at https://example.com/guide now'),
    ]);
    expect(controllerOf(tester).selection, isNotNull);
    expect(links, isEmpty);

    // A tap clears the selection (and its toolbar) first.
    await tester.tapAt(cellCenter(tester, 1, 1));
    await tester.pump(const Duration(milliseconds: 400));
    expect(controllerOf(tester).selection, isNull);

    longPressResult = true;
    await tester.longPressAt(cellCenter(tester, 18, 0));
    await tester.pump();
    expect(longPresses, hasLength(2));
    expect(controllerOf(tester).selection, isNull);
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('a long press elsewhere only selects', (tester) async {
    await pumpSurface(tester);

    await tester.longPressAt(cellCenter(tester, 1, 0));
    await tester.pump();
    expect(longPresses, isEmpty);
    expect(controllerOf(tester).selection, isNotNull);
    await tester.pump(const Duration(milliseconds: 300));
  });
}
