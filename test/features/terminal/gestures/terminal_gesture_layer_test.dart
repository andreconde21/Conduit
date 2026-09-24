import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/terminal/domain/terminal_gesture_preferences.dart';
import 'package:conduit/features/terminal/presentation/gestures/terminal_gesture_layer.dart';
import 'package:conduit/features/terminal/presentation/terminal_session_controller.dart';
import 'package:conduit_vt/conduit_vt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/test_doubles.dart';

/// Stands in for the terminal view: it owns the same single-finger gestures
/// (tap, long press, vertical drag) that the real view competes with.
class _Competitor {
  int taps = 0;
  int longPresses = 0;
  double verticalDrag = 0;
}

class _RecordingSession extends TerminalSessionController {
  _RecordingSession({SavedHost? host})
    : super(
        host: host ?? buildHost('gestures'),
        repository: NoNetworkTerminalRepository(),
      );

  final List<String> log = <String>[];

  @override
  void sendKey(TerminalKey key) => log.add('key:${key.name}');

  @override
  void sendControl(TerminalKey key) => log.add('ctrl:${key.name}');

  @override
  void sendText(String text) => log.add('text:$text');
}

class _Harness {
  _Harness({
    this.preferences = TerminalGesturePreferences.defaults,
    SavedHost? host,
    this.withSessionGrid = true,
    this.withAgentPanel = true,
  }) : session = _RecordingSession(host: host);

  final TerminalGesturePreferences preferences;
  final _RecordingSession session;
  final competitor = _Competitor();
  final bool withSessionGrid;
  final bool withAgentPanel;
  final fontSizes = <double>[];
  int sessionGridOpens = 0;
  int agentPanelOpens = 0;
  int enterScrollMode = 0;
  int exitScrollMode = 0;
  bool scrollMode = false;

  Widget build() {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            height: 600,
            child: StatefulBuilder(
              builder: (context, setState) {
                return TerminalGestureLayer(
                  preferences: preferences,
                  session: session,
                  fontSize: 14,
                  onFontSizeChanged: fontSizes.add,
                  scrollMode: scrollMode,
                  onEnterScrollMode: () {
                    enterScrollMode += 1;
                    setState(() => scrollMode = true);
                  },
                  onExitScrollMode: () {
                    exitScrollMode += 1;
                    setState(() => scrollMode = false);
                  },
                  onOpenSessionGrid: withSessionGrid
                      ? () => sessionGridOpens += 1
                      : null,
                  onOpenAgentPanel: withAgentPanel
                      ? () => agentPanelOpens += 1
                      : null,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => competitor.taps += 1,
                    onLongPress: () => competitor.longPresses += 1,
                    onVerticalDragUpdate: (details) =>
                        competitor.verticalDrag += details.delta.dy,
                    child: const SizedBox.expand(),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// The layer is centred in an 800x600 test window: x from 200 to 600,
// y from 0 to 600.
const _layerLeft = 200.0;
const _layerTop = 0.0;
const _center = Offset(400, 300);

Future<void> _swipe(
  WidgetTester tester,
  Offset from,
  Offset by, {
  int steps = 6,
}) async {
  final gesture = await tester.startGesture(from);
  await tester.pump();
  for (var i = 0; i < steps; i += 1) {
    await gesture.moveBy(by / steps.toDouble());
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pump();
}

Future<void> _twoFingerMove(
  WidgetTester tester, {
  required Offset firstFrom,
  required Offset firstTo,
  required Offset secondFrom,
  required Offset secondTo,
  int steps = 6,
  bool lift = true,
}) async {
  final first = await tester.createGesture(pointer: 11);
  final second = await tester.createGesture(pointer: 12);
  await first.down(firstFrom);
  await second.down(secondFrom);
  await tester.pump();
  final firstStep = (firstTo - firstFrom) / steps.toDouble();
  final secondStep = (secondTo - secondFrom) / steps.toDouble();
  for (var i = 0; i < steps; i += 1) {
    await first.moveBy(firstStep);
    await second.moveBy(secondStep);
    await tester.pump(const Duration(milliseconds: 16));
  }
  if (lift) {
    await first.up();
    await second.up();
    await tester.pump();
  }
}

void main() {
  group('horizontal swipe', () {
    testWidgets('swipe left sends the tmux prefix and n', (tester) async {
      final harness = _Harness();
      addTearDown(harness.session.dispose);
      await tester.pumpWidget(harness.build());

      await _swipe(tester, _center, const Offset(-120, 4));

      expect(harness.session.log, ['ctrl:keyB', 'text:n']);
      expect(harness.competitor.taps, 0);
      expect(harness.competitor.verticalDrag, 0);
    });

    testWidgets('swipe right sends the tmux prefix and p', (tester) async {
      final harness = _Harness();
      addTearDown(harness.session.dispose);
      await tester.pumpWidget(harness.build());

      await _swipe(tester, _center, const Offset(120, -6));

      expect(harness.session.log, ['ctrl:keyB', 'text:p']);
    });

    testWidgets('tmux target follows the host prefix key', (tester) async {
      final harness = _Harness(
        host: buildHost('a').copyWith(tmuxPrefixKey: TmuxPrefixKey.controlA),
      );
      addTearDown(harness.session.dispose);
      await tester.pumpWidget(harness.build());

      await _swipe(tester, _center, const Offset(-120, 0));

      expect(harness.session.log, ['ctrl:keyA', 'text:n']);
    });

    testWidgets('Herdr target always uses ctrl+b', (tester) async {
      final harness = _Harness(
        host: buildHost('a').copyWith(tmuxPrefixKey: TmuxPrefixKey.controlA),
        preferences: const TerminalGesturePreferences(
          windowSwitchTarget: TerminalWindowSwitchTarget.herdr,
        ),
      );
      addTearDown(harness.session.dispose);
      await tester.pumpWidget(harness.build());

      await _swipe(tester, _center, const Offset(-120, 0));

      expect(harness.session.log, ['ctrl:keyB', 'text:n']);
    });

    testWidgets('a short swipe does nothing', (tester) async {
      final harness = _Harness();
      addTearDown(harness.session.dispose);
      await tester.pumpWidget(harness.build());

      await _swipe(tester, _center, const Offset(-40, 0));

      expect(harness.session.log, isEmpty);
    });

    testWidgets('a diagonal drag stays with the terminal', (tester) async {
      final harness = _Harness();
      addTearDown(harness.session.dispose);
      await tester.pumpWidget(harness.build());

      await _swipe(tester, _center, const Offset(-90, 100));

      expect(harness.session.log, isEmpty);
      expect(harness.competitor.verticalDrag, isNot(0));
    });

    testWidgets('is off while in scroll mode', (tester) async {
      final harness = _Harness()..scrollMode = true;
      addTearDown(harness.session.dispose);
      await tester.pumpWidget(harness.build());

      await _swipe(tester, _center, const Offset(-120, 0));

      expect(harness.session.log, isEmpty);
    });

    testWidgets('can be switched off', (tester) async {
      final harness = _Harness(
        preferences: const TerminalGesturePreferences(
          swipeSwitchesWindow: false,
        ),
      );
      addTearDown(harness.session.dispose);
      await tester.pumpWidget(harness.build());

      await _swipe(tester, _center, const Offset(-120, 0));

      expect(harness.session.log, isEmpty);
    });
  });

  group('arbitration with the terminal view', () {
    testWidgets('taps, long presses and vertical drags reach the terminal', (
      tester,
    ) async {
      final harness = _Harness();
      addTearDown(harness.session.dispose);
      await tester.pumpWidget(harness.build());

      await tester.tap(find.byType(GestureDetector));
      await tester.pump(const Duration(milliseconds: 400));
      expect(harness.competitor.taps, 1);

      await tester.longPress(find.byType(GestureDetector));
      await tester.pump(const Duration(milliseconds: 400));
      expect(harness.competitor.longPresses, 1);

      await _swipe(tester, _center, const Offset(0, -150));
      expect(harness.competitor.verticalDrag, lessThan(-80));

      expect(harness.session.log, isEmpty);
      expect(harness.sessionGridOpens, 0);
      expect(harness.agentPanelOpens, 0);
      expect(harness.fontSizes, isEmpty);
    });
  });

  group('pinch', () {
    testWidgets('spreading two fingers grows the font size', (tester) async {
      final harness = _Harness();
      addTearDown(harness.session.dispose);
      await tester.pumpWidget(harness.build());

      await _twoFingerMove(
        tester,
        firstFrom: _center.translate(-40, 0),
        firstTo: _center.translate(-60, 0),
        secondFrom: _center.translate(40, 0),
        secondTo: _center.translate(60, 0),
      );

      expect(harness.fontSizes, isNotEmpty);
      expect(harness.fontSizes.last, greaterThan(14));
      expect(harness.fontSizes.last, closeTo(14 * 120 / 80, 0.5));
      expect(harness.session.log, isEmpty);
      expect(harness.competitor.verticalDrag, 0);
    });

    testWidgets('pinching in shrinks and clamps the font size', (tester) async {
      final harness = _Harness();
      addTearDown(harness.session.dispose);
      await tester.pumpWidget(harness.build());

      await _twoFingerMove(
        tester,
        firstFrom: _center.translate(-150, 0),
        firstTo: _center.translate(-4, 0),
        secondFrom: _center.translate(150, 0),
        secondTo: _center.translate(4, 0),
      );

      expect(harness.fontSizes.last, lessThan(14));
      expect(harness.fontSizes.last, greaterThanOrEqualTo(4));
    });

    testWidgets('can be switched off', (tester) async {
      final harness = _Harness(
        preferences: const TerminalGesturePreferences(pinchZoom: false),
      );
      addTearDown(harness.session.dispose);
      await tester.pumpWidget(harness.build());

      await _twoFingerMove(
        tester,
        firstFrom: _center.translate(-40, 0),
        firstTo: _center.translate(-100, 0),
        secondFrom: _center.translate(40, 0),
        secondTo: _center.translate(100, 0),
      );

      expect(harness.fontSizes, isEmpty);
    });
  });

  group('two-finger scroll', () {
    testWidgets('swiping down enters scrollback and scrolls by lines', (
      tester,
    ) async {
      final harness = _Harness();
      addTearDown(harness.session.dispose);
      await tester.pumpWidget(harness.build());

      await _twoFingerMove(
        tester,
        firstFrom: _center.translate(-30, -100),
        firstTo: _center.translate(-30, 40),
        secondFrom: _center.translate(30, -100),
        secondTo: _center.translate(30, 40),
      );

      expect(harness.enterScrollMode, 1);
      expect(harness.scrollMode, isTrue);
      expect(harness.session.log.take(2), ['ctrl:keyB', 'text:[']);
      final ups = harness.session.log
          .skip(2)
          .where((entry) => entry == 'key:arrowUp')
          .length;
      // 140px of travel at 14px a line.
      expect(ups, inInclusiveRange(9, 10));
      expect(
        harness.session.log.skip(2).every((e) => e == 'key:arrowUp'),
        isTrue,
      );
      expect(harness.fontSizes, isEmpty);
      expect(harness.competitor.verticalDrag, 0);
    });

    testWidgets('swiping up scrolls forward, then leaves past the bottom', (
      tester,
    ) async {
      final harness = _Harness();
      addTearDown(harness.session.dispose);
      await tester.pumpWidget(harness.build());

      // Scroll back four lines (56px).
      await _twoFingerMove(
        tester,
        firstFrom: _center.translate(-30, -100),
        firstTo: _center.translate(-30, -44),
        secondFrom: _center.translate(30, -100),
        secondTo: _center.translate(30, -44),
      );
      expect(harness.scrollMode, isTrue);
      harness.session.log.clear();

      // Come back four lines, then keep going past the bottom far enough to
      // leave scrollback: 56px forward + 56px exit distance.
      await _twoFingerMove(
        tester,
        firstFrom: _center.translate(-30, 100),
        firstTo: _center.translate(-30, -20),
        secondFrom: _center.translate(30, 100),
        secondTo: _center.translate(30, -20),
        steps: 12,
      );

      final downs = harness.session.log
          .where((entry) => entry == 'key:arrowDown')
          .length;
      expect(downs, 4);
      expect(harness.session.log.last, 'text:q');
      expect(harness.exitScrollMode, 1);
      expect(harness.scrollMode, isFalse);
    });

    testWidgets('swiping up outside scrollback does nothing', (tester) async {
      final harness = _Harness();
      addTearDown(harness.session.dispose);
      await tester.pumpWidget(harness.build());

      await _twoFingerMove(
        tester,
        firstFrom: _center.translate(-30, 100),
        firstTo: _center.translate(-30, -60),
        secondFrom: _center.translate(30, 100),
        secondTo: _center.translate(30, -60),
      );

      expect(harness.session.log, isEmpty);
      expect(harness.enterScrollMode, 0);
      expect(harness.exitScrollMode, 0);
    });

    testWidgets('can be switched off', (tester) async {
      final harness = _Harness(
        preferences: const TerminalGesturePreferences(twoFingerScroll: false),
      );
      addTearDown(harness.session.dispose);
      await tester.pumpWidget(harness.build());

      await _twoFingerMove(
        tester,
        firstFrom: _center.translate(-30, -100),
        firstTo: _center.translate(-30, 40),
        secondFrom: _center.translate(30, -100),
        secondTo: _center.translate(30, 40),
      );

      expect(harness.session.log, isEmpty);
      expect(harness.enterScrollMode, 0);
    });
  });

  group('header swipe', () {
    const headerStart = Offset(_layerLeft + 200, _layerTop + 20);

    testWidgets('swipe down from the top strip opens the session grid', (
      tester,
    ) async {
      final harness = _Harness();
      addTearDown(harness.session.dispose);
      await tester.pumpWidget(harness.build());

      await _swipe(tester, headerStart, const Offset(0, 120));

      expect(harness.sessionGridOpens, 1);
      expect(harness.competitor.verticalDrag, 0);
      expect(harness.session.log, isEmpty);
    });

    testWidgets('swipe down from the body scrolls the terminal instead', (
      tester,
    ) async {
      final harness = _Harness();
      addTearDown(harness.session.dispose);
      await tester.pumpWidget(harness.build());

      await _swipe(tester, _center, const Offset(0, 120));

      expect(harness.sessionGridOpens, 0);
      expect(harness.competitor.verticalDrag, greaterThan(80));
    });

    testWidgets('swipe up from the top strip scrolls the terminal', (
      tester,
    ) async {
      final harness = _Harness();
      addTearDown(harness.session.dispose);
      await tester.pumpWidget(harness.build());

      await _swipe(tester, headerStart, const Offset(0, 120));
      harness.sessionGridOpens = 0;
      harness.competitor.verticalDrag = 0;

      await _swipe(tester, headerStart.translate(0, 20), const Offset(0, -120));

      expect(harness.sessionGridOpens, 0);
      expect(harness.competitor.verticalDrag, lessThan(-80));
    });

    testWidgets('can be switched off', (tester) async {
      final harness = _Harness(
        preferences: const TerminalGesturePreferences(
          headerSwipeOpensSessions: false,
        ),
      );
      addTearDown(harness.session.dispose);
      await tester.pumpWidget(harness.build());

      await _swipe(tester, headerStart, const Offset(0, 120));

      expect(harness.sessionGridOpens, 0);
      expect(harness.competitor.verticalDrag, greaterThan(80));
    });

    testWidgets('is off without a session grid callback', (tester) async {
      final harness = _Harness(withSessionGrid: false);
      addTearDown(harness.session.dispose);
      await tester.pumpWidget(harness.build());

      await _swipe(tester, headerStart, const Offset(0, 120));

      expect(harness.competitor.verticalDrag, greaterThan(80));
    });
  });

  group('edge swipe', () {
    const edgeStart = Offset(_layerLeft + 400 - 8, 300);

    testWidgets('swipe in from the right edge opens the agent panel', (
      tester,
    ) async {
      final harness = _Harness();
      addTearDown(harness.session.dispose);
      await tester.pumpWidget(harness.build());

      await _swipe(tester, edgeStart, const Offset(-120, 0));

      expect(harness.agentPanelOpens, 1);
      // The edge swipe must not double as a window switch.
      expect(harness.session.log, isEmpty);
    });

    testWidgets('a swipe from the edge never switches windows', (tester) async {
      final harness = _Harness(
        preferences: const TerminalGesturePreferences(
          edgeSwipeOpensAgents: false,
        ),
      );
      addTearDown(harness.session.dispose);
      await tester.pumpWidget(harness.build());

      await _swipe(tester, edgeStart, const Offset(-120, 0));

      expect(harness.agentPanelOpens, 0);
      expect(harness.session.log, isEmpty);
    });

    testWidgets('is off without an agent panel callback', (tester) async {
      final harness = _Harness(withAgentPanel: false);
      addTearDown(harness.session.dispose);
      await tester.pumpWidget(harness.build());

      await _swipe(tester, edgeStart, const Offset(-120, 0));

      expect(harness.agentPanelOpens, 0);
      expect(harness.session.log, isEmpty);
    });
  });

  group('TerminalHeaderSwipeArea', () {
    testWidgets('a downward swipe on the header fires the callback', (
      tester,
    ) async {
      var opens = 0;
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalHeaderSwipeArea(
              onSwipeDown: () => opens += 1,
              child: SizedBox(
                height: 56,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => taps += 1,
                    ),
                    const Expanded(child: Text('host')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pump();
      expect(taps, 1);
      expect(opens, 0);

      await _swipe(
        tester,
        tester.getCenter(find.text('host')),
        const Offset(0, 100),
      );
      expect(opens, 1);

      await _swipe(
        tester,
        tester.getCenter(find.text('host')),
        const Offset(0, 30),
      );
      expect(opens, 1);
    });
  });
}
