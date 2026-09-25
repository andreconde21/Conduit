import 'dart:convert';

/// Which multiplexer a horizontal swipe on the terminal drives.
///
/// tmux and Herdr both switch windows with `prefix + n` / `prefix + p` using
/// the host's configured multiplexer prefix; the bindings after the prefix
/// are what differ. The app cannot tell which one is running inside the
/// session, so the choice is a preference; tmux is the default because that
/// is what the connect flow starts.
enum TerminalWindowSwitchTarget { tmux, herdr }

extension TerminalWindowSwitchTargetDetails on TerminalWindowSwitchTarget {
  String get label => switch (this) {
    TerminalWindowSwitchTarget.tmux => 'tmux',
    TerminalWindowSwitchTarget.herdr => 'Herdr',
  };
}

/// What a pinch does in a Herdr session.
enum HerdrPinchAction {
  /// Spread to zoom the focused pane full-screen, pinch in to restore
  /// (`herdr pane zoom --on` / `--off`).
  zoomPane,

  /// Change the terminal font size, as in tmux and plain shells.
  fontSize,
}

/// What a two-finger vertical swipe does in a Herdr session.
enum HerdrVerticalSwipe {
  /// Swipe up for the next workspace, down for the previous one. Scrollback
  /// is reached by resting two fingers first, then dragging.
  workspaces,

  /// Scroll back through history, as in tmux.
  scrollback,
}

extension HerdrPinchActionDetails on HerdrPinchAction {
  String get label => switch (this) {
    HerdrPinchAction.zoomPane => 'Zoom pane',
    HerdrPinchAction.fontSize => 'Font size',
  };
}

extension HerdrVerticalSwipeDetails on HerdrVerticalSwipe {
  String get label => switch (this) {
    HerdrVerticalSwipe.workspaces => 'Workspaces',
    HerdrVerticalSwipe.scrollback => 'Scrollback',
  };
}

/// Per-gesture switches for the terminal touch gestures. Every gesture is
/// individually toggleable so a gesture that fights a remote app (a TUI that
/// wants its own two-finger scroll, say) can be turned off on its own.
class TerminalGesturePreferences {
  const TerminalGesturePreferences({
    this.swipeSwitchesWindow = true,
    this.windowSwitchTarget = TerminalWindowSwitchTarget.tmux,
    this.pinchZoom = true,
    this.twoFingerScroll = true,
    this.headerSwipeOpensSessions = true,
    this.edgeSwipeOpensAgents = true,
    this.herdrPinch = HerdrPinchAction.zoomPane,
    this.herdrTwoFingerVertical = HerdrVerticalSwipe.workspaces,
    this.herdrTwoFingerPanes = true,
  });

  static const defaults = TerminalGesturePreferences();

  /// One-finger horizontal swipe sends next/previous window to the
  /// multiplexer chosen by [windowSwitchTarget].
  final bool swipeSwitchesWindow;
  final TerminalWindowSwitchTarget windowSwitchTarget;

  /// Two-finger pinch changes the terminal font size.
  final bool pinchZoom;

  /// Two-finger vertical swipe enters scrollback mode and scrolls by lines.
  final bool twoFingerScroll;

  /// Swipe down that starts in the top strip of the terminal opens the
  /// session grid.
  final bool headerSwipeOpensSessions;

  /// Swipe in from the right edge opens the agent panel.
  final bool edgeSwipeOpensAgents;

  /// In Herdr: what [pinchZoom] does.
  final HerdrPinchAction herdrPinch;

  /// In Herdr: what a two-finger vertical swipe does. With
  /// [HerdrVerticalSwipe.workspaces], scrollback needs [twoFingerScroll].
  final HerdrVerticalSwipe herdrTwoFingerVertical;

  /// In Herdr: two-finger left/right focuses the neighbouring pane.
  final bool herdrTwoFingerPanes;

  bool get anyEnabled =>
      swipeSwitchesWindow ||
      pinchZoom ||
      twoFingerScroll ||
      headerSwipeOpensSessions ||
      edgeSwipeOpensAgents ||
      herdrTwoFingerPanes;

  TerminalGesturePreferences copyWith({
    bool? swipeSwitchesWindow,
    TerminalWindowSwitchTarget? windowSwitchTarget,
    bool? pinchZoom,
    bool? twoFingerScroll,
    bool? headerSwipeOpensSessions,
    bool? edgeSwipeOpensAgents,
    HerdrPinchAction? herdrPinch,
    HerdrVerticalSwipe? herdrTwoFingerVertical,
    bool? herdrTwoFingerPanes,
  }) {
    return TerminalGesturePreferences(
      swipeSwitchesWindow: swipeSwitchesWindow ?? this.swipeSwitchesWindow,
      windowSwitchTarget: windowSwitchTarget ?? this.windowSwitchTarget,
      pinchZoom: pinchZoom ?? this.pinchZoom,
      twoFingerScroll: twoFingerScroll ?? this.twoFingerScroll,
      headerSwipeOpensSessions:
          headerSwipeOpensSessions ?? this.headerSwipeOpensSessions,
      edgeSwipeOpensAgents: edgeSwipeOpensAgents ?? this.edgeSwipeOpensAgents,
      herdrPinch: herdrPinch ?? this.herdrPinch,
      herdrTwoFingerVertical:
          herdrTwoFingerVertical ?? this.herdrTwoFingerVertical,
      herdrTwoFingerPanes: herdrTwoFingerPanes ?? this.herdrTwoFingerPanes,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'swipeSwitchesWindow': swipeSwitchesWindow,
      'windowSwitchTarget': windowSwitchTarget.name,
      'pinchZoom': pinchZoom,
      'twoFingerScroll': twoFingerScroll,
      'headerSwipeOpensSessions': headerSwipeOpensSessions,
      'edgeSwipeOpensAgents': edgeSwipeOpensAgents,
      'herdrPinch': herdrPinch.name,
      'herdrTwoFingerVertical': herdrTwoFingerVertical.name,
      'herdrTwoFingerPanes': herdrTwoFingerPanes,
    };
  }

  /// Builds preferences from a JSON map. Unknown or malformed fields fall
  /// back to [defaults] one by one so a partial record still loads.
  static TerminalGesturePreferences fromJson(Object? json) {
    if (json is! Map) {
      return defaults;
    }
    bool flag(String key, bool fallback) {
      final value = json[key];
      return value is bool ? value : fallback;
    }

    return TerminalGesturePreferences(
      swipeSwitchesWindow: flag(
        'swipeSwitchesWindow',
        defaults.swipeSwitchesWindow,
      ),
      windowSwitchTarget: TerminalWindowSwitchTarget.values.firstWhere(
        (target) => target.name == json['windowSwitchTarget'],
        orElse: () => defaults.windowSwitchTarget,
      ),
      pinchZoom: flag('pinchZoom', defaults.pinchZoom),
      twoFingerScroll: flag('twoFingerScroll', defaults.twoFingerScroll),
      headerSwipeOpensSessions: flag(
        'headerSwipeOpensSessions',
        defaults.headerSwipeOpensSessions,
      ),
      edgeSwipeOpensAgents: flag(
        'edgeSwipeOpensAgents',
        defaults.edgeSwipeOpensAgents,
      ),
      herdrPinch: HerdrPinchAction.values.firstWhere(
        (value) => value.name == json['herdrPinch'],
        orElse: () => defaults.herdrPinch,
      ),
      herdrTwoFingerVertical: HerdrVerticalSwipe.values.firstWhere(
        (value) => value.name == json['herdrTwoFingerVertical'],
        orElse: () => defaults.herdrTwoFingerVertical,
      ),
      herdrTwoFingerPanes: flag(
        'herdrTwoFingerPanes',
        defaults.herdrTwoFingerPanes,
      ),
    );
  }

  String encode() => jsonEncode(toJson());

  /// Decodes a stored record; anything unreadable yields [defaults].
  static TerminalGesturePreferences decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return defaults;
    }
    try {
      return fromJson(jsonDecode(raw));
    } catch (_) {
      return defaults;
    }
  }

  @override
  bool operator ==(Object other) {
    return other is TerminalGesturePreferences &&
        other.swipeSwitchesWindow == swipeSwitchesWindow &&
        other.windowSwitchTarget == windowSwitchTarget &&
        other.pinchZoom == pinchZoom &&
        other.twoFingerScroll == twoFingerScroll &&
        other.headerSwipeOpensSessions == headerSwipeOpensSessions &&
        other.edgeSwipeOpensAgents == edgeSwipeOpensAgents &&
        other.herdrPinch == herdrPinch &&
        other.herdrTwoFingerVertical == herdrTwoFingerVertical &&
        other.herdrTwoFingerPanes == herdrTwoFingerPanes;
  }

  @override
  int get hashCode => Object.hash(
    swipeSwitchesWindow,
    windowSwitchTarget,
    pinchZoom,
    twoFingerScroll,
    headerSwipeOpensSessions,
    edgeSwipeOpensAgents,
    herdrPinch,
    herdrTwoFingerVertical,
    herdrTwoFingerPanes,
  );
}
