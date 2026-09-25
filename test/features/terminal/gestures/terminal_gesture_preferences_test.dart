import 'package:conduit/features/terminal/domain/terminal_gesture_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TerminalGesturePreferences', () {
    test('defaults enable every gesture and target tmux', () {
      const defaults = TerminalGesturePreferences.defaults;
      expect(defaults.swipeSwitchesWindow, isTrue);
      expect(defaults.windowSwitchTarget, TerminalWindowSwitchTarget.tmux);
      expect(defaults.pinchZoom, isTrue);
      expect(defaults.twoFingerScroll, isTrue);
      expect(defaults.headerSwipeOpensSessions, isTrue);
      expect(defaults.edgeSwipeOpensAgents, isTrue);
      expect(defaults.herdrPinch, HerdrPinchAction.fontSize);
      expect(defaults.herdrTwoFingerVertical, HerdrVerticalSwipe.workspaces);
      expect(defaults.herdrTwoFingerPanes, isTrue);
    });

    test('round-trips through json', () {
      const preferences = TerminalGesturePreferences(
        swipeSwitchesWindow: false,
        windowSwitchTarget: TerminalWindowSwitchTarget.herdr,
        pinchZoom: false,
        headerSwipeOpensSessions: false,
        herdrPinch: HerdrPinchAction.zoomPane,
        herdrTwoFingerVertical: HerdrVerticalSwipe.scrollback,
        herdrTwoFingerPanes: false,
      );

      final decoded = TerminalGesturePreferences.decode(preferences.encode());

      expect(decoded, preferences);
      expect(decoded.hashCode, preferences.hashCode);
    });

    test('falls back field by field on a partial or corrupt record', () {
      expect(
        TerminalGesturePreferences.decode('not json'),
        TerminalGesturePreferences.defaults,
      );
      expect(
        TerminalGesturePreferences.decode(''),
        TerminalGesturePreferences.defaults,
      );
      expect(
        TerminalGesturePreferences.decode('[1, 2]'),
        TerminalGesturePreferences.defaults,
      );

      final partial = TerminalGesturePreferences.decode(
        '{"pinchZoom": false, "windowSwitchTarget": "bogus", '
        '"twoFingerScroll": "yes"}',
      );
      expect(partial.pinchZoom, isFalse);
      expect(partial.windowSwitchTarget, TerminalWindowSwitchTarget.tmux);
      expect(partial.twoFingerScroll, isTrue);
      expect(partial.swipeSwitchesWindow, isTrue);
    });

    test('a record from before schema 2 migrates pinch to font size', () {
      // Preview 7 and earlier always stored the old zoom-pane default.
      final legacy = TerminalGesturePreferences.decode(
        '{"pinchZoom": true, "windowSwitchTarget": "herdr", '
        '"herdrPinch": "zoomPane", "herdrTwoFingerPanes": false}',
      );
      expect(legacy.herdrPinch, HerdrPinchAction.fontSize);
      expect(legacy.pinchZoom, isTrue);
      expect(legacy.windowSwitchTarget, TerminalWindowSwitchTarget.herdr);
      expect(legacy.herdrTwoFingerPanes, isFalse);

      // Saving again marks the record current, so the choice sticks.
      final reencoded = TerminalGesturePreferences.decode(legacy.encode());
      expect(reencoded, legacy);
    });

    test('an explicit zoom-pane choice survives once saved as schema 2', () {
      final chosen = TerminalGesturePreferences.defaults.copyWith(
        herdrPinch: HerdrPinchAction.zoomPane,
      );
      final decoded = TerminalGesturePreferences.decode(chosen.encode());
      expect(decoded.herdrPinch, HerdrPinchAction.zoomPane);
    });

    test('copyWith changes only the named field', () {
      final next = TerminalGesturePreferences.defaults.copyWith(
        windowSwitchTarget: TerminalWindowSwitchTarget.herdr,
      );
      expect(next.windowSwitchTarget, TerminalWindowSwitchTarget.herdr);
      expect(next.pinchZoom, isTrue);
      expect(next.anyEnabled, isTrue);

      const none = TerminalGesturePreferences(
        swipeSwitchesWindow: false,
        pinchZoom: false,
        twoFingerScroll: false,
        headerSwipeOpensSessions: false,
        edgeSwipeOpensAgents: false,
        herdrTwoFingerPanes: false,
      );
      expect(none.anyEnabled, isFalse);
    });
  });
}
