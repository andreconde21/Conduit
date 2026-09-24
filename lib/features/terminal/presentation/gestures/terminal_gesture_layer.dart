import 'package:conduit/core/theme/terminal_appearance.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/terminal/domain/terminal_gesture_preferences.dart';
import 'package:conduit/features/terminal/presentation/gestures/terminal_gesture_recognizers.dart';
import 'package:conduit/features/terminal/presentation/terminal_session_controller.dart';
import 'package:conduit_vt/conduit_vt.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// The key sequences the gestures send, kept apart from the widget so they
/// can be unit tested and reused by whoever wires more gestures later.
class TerminalGestureCommands {
  const TerminalGestureCommands(this.session, this.target);

  final TerminalSessionController session;
  final TerminalWindowSwitchTarget target;

  /// The prefix key for [target]: the host's configured tmux prefix, or
  /// Herdr's fixed ctrl+b.
  TerminalKey get prefixKey => switch (target) {
    TerminalWindowSwitchTarget.herdr => TerminalKey.keyB,
    TerminalWindowSwitchTarget.tmux => switch (session.host.tmuxPrefixKey) {
      TmuxPrefixKey.controlB => TerminalKey.keyB,
      TmuxPrefixKey.controlA => TerminalKey.keyA,
    },
  };

  void _prefixed(String binding) {
    session.sendControl(prefixKey);
    session.sendText(binding);
  }

  /// `prefix n`: next window in tmux, next tab in Herdr.
  void nextWindow() => _prefixed('n');

  /// `prefix p`: previous window in tmux, previous tab in Herdr.
  void previousWindow() => _prefixed('p');

  /// `prefix [`: copy (scrollback) mode in both tmux and Herdr.
  void enterScrollback() => _prefixed('[');

  /// `q` leaves copy mode in both tmux and Herdr.
  void exitScrollback() => session.sendText('q');

  void scrollBack(int lines) {
    for (var i = 0; i < lines; i += 1) {
      session.sendKey(TerminalKey.arrowUp);
    }
  }

  void scrollForward(int lines) {
    for (var i = 0; i < lines; i += 1) {
      session.sendKey(TerminalKey.arrowDown);
    }
  }
}

enum _TwoFingerKind { pinch, scroll }

/// Adds the Moshi-style touch gestures on top of a terminal surface:
///
/// * one-finger horizontal swipe switches the multiplexer window;
/// * pinch changes the terminal font size;
/// * two-finger vertical swipe scrolls back through history (entering the
///   app's scroll mode on the way in, leaving it again when swiped past the
///   bottom);
/// * swipe down from the header strip opens the session grid;
/// * swipe in from the right edge opens the agent panel.
///
/// Each gesture is switched by [preferences]. The layer never touches the
/// terminal view's own tap, long-press and single-finger scroll handling: its
/// recognisers only enter the gesture arena and win by the rules described
/// on [TerminalSwipeRecognizer] and [TwoFingerGestureRecognizer].
class TerminalGestureLayer extends StatefulWidget {
  const TerminalGestureLayer({
    required this.preferences,
    required this.session,
    required this.fontSize,
    required this.onFontSizeChanged,
    required this.scrollMode,
    required this.onEnterScrollMode,
    required this.onExitScrollMode,
    required this.child,
    this.enabled = true,
    this.onOpenSessionGrid,
    this.onOpenAgentPanel,
    this.headerZoneHeight = 48,
    this.edgeZoneWidth = 24,
    super.key,
  });

  final TerminalGesturePreferences preferences;
  final TerminalSessionController session;
  final double fontSize;
  final ValueChanged<double> onFontSizeChanged;

  /// Whether the app's scroll (tmux copy) mode is active for this session.
  /// The layer sends the keys that enter and leave copy mode itself and only
  /// asks the owner to flip its state through [onEnterScrollMode] and
  /// [onExitScrollMode].
  final bool scrollMode;
  final VoidCallback onEnterScrollMode;
  final VoidCallback onExitScrollMode;

  /// Opens the session grid; null disables the header swipe.
  final VoidCallback? onOpenSessionGrid;

  /// Opens the agent panel; null disables the right-edge swipe.
  final VoidCallback? onOpenAgentPanel;

  /// Turns every gesture off (for example while a file tab covers the
  /// terminal) without rebuilding the child.
  final bool enabled;

  /// Height of the strip at the top of the terminal that counts as the
  /// header for the swipe-down gesture.
  final double headerZoneHeight;

  /// Width of the strip along the right side that starts the edge swipe.
  final double edgeZoneWidth;

  final Widget child;

  /// Pixels of two-finger travel per scrolled line.
  static const double scrollLineStep = 14;

  /// Extra upward two-finger travel, once at the bottom of the scrollback,
  /// that leaves scroll mode.
  static const double scrollExitDistance = 56;

  /// Two-finger movement needed before the gesture is classified as a pinch
  /// or a scroll.
  static const double classifyThreshold = 10;

  @override
  State<TerminalGestureLayer> createState() => _TerminalGestureLayerState();
}

class _TerminalGestureLayerState extends State<TerminalGestureLayer> {
  late final TerminalSwipeRecognizer _swipe;
  late final TwoFingerGestureRecognizer _twoFinger;
  _TwoFingerKind? _twoFingerKind;
  double _pinchStartFontSize = terminalFontSizeDefault;
  double _scrollRemainder = 0;
  double _exitTravel = 0;
  // Lines this layer has scrolled above the live screen. Only an estimate:
  // the Touch key's single-finger drag scrolls through the same session
  // without telling us, so "the bottom" can be reached early.
  int _linesAbove = 0;
  bool _scrollMode = false;

  TerminalGestureCommands get _commands => TerminalGestureCommands(
    widget.session,
    widget.preferences.windowSwitchTarget,
  );

  @override
  void initState() {
    super.initState();
    _scrollMode = widget.scrollMode;
    _swipe = TerminalSwipeRecognizer(onSwipe: _handleSwipe);
    _twoFinger = TwoFingerGestureRecognizer(
      onStart: _handleTwoFingerStart,
      onUpdate: _handleTwoFingerUpdate,
      onEnd: _handleTwoFingerEnd,
    );
  }

  @override
  void didUpdateWidget(covariant TerminalGestureLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollMode != widget.scrollMode) {
      _scrollMode = widget.scrollMode;
      if (!_scrollMode) {
        _linesAbove = 0;
        _exitTravel = 0;
      }
    }
  }

  bool get _windowSwipeEnabled =>
      widget.enabled &&
      widget.preferences.swipeSwitchesWindow &&
      !widget.scrollMode;

  bool get _headerSwipeEnabled =>
      widget.enabled &&
      widget.preferences.headerSwipeOpensSessions &&
      widget.onOpenSessionGrid != null;

  bool get _edgeSwipeEnabled =>
      widget.enabled &&
      widget.preferences.edgeSwipeOpensAgents &&
      widget.onOpenAgentPanel != null;

  bool get _pinchEnabled => widget.enabled && widget.preferences.pinchZoom;

  bool get _twoFingerScrollEnabled =>
      widget.enabled && widget.preferences.twoFingerScroll;

  void _handleSwipe(TerminalSwipeKind kind) {
    switch (kind) {
      case TerminalSwipeKind.windowNext:
        _commands.nextWindow();
      case TerminalSwipeKind.windowPrevious:
        _commands.previousWindow();
      case TerminalSwipeKind.headerDown:
        widget.onOpenSessionGrid?.call();
      case TerminalSwipeKind.edgeIn:
        widget.onOpenAgentPanel?.call();
    }
  }

  void _handleTwoFingerStart() {
    _twoFingerKind = null;
    _scrollRemainder = 0;
    _pinchStartFontSize = widget.fontSize;
  }

  void _handleTwoFingerUpdate(TwoFingerUpdate update) {
    var kind = _twoFingerKind;
    if (kind == null) {
      final span = update.spanDelta.abs();
      final travel = update.focalDelta.dy.abs();
      if (span < TerminalGestureLayer.classifyThreshold &&
          travel < TerminalGestureLayer.classifyThreshold) {
        return;
      }
      if (!_pinchEnabled && !_twoFingerScrollEnabled) {
        return;
      }
      kind = _pinchEnabled && (!_twoFingerScrollEnabled || span >= travel)
          ? _TwoFingerKind.pinch
          : _TwoFingerKind.scroll;
      _twoFingerKind = kind;
      if (kind == _TwoFingerKind.scroll) {
        // The travel that classified the gesture counts as scrolling too.
        _scrollRemainder = update.focalDelta.dy;
        _applyScroll();
        return;
      }
    }
    switch (kind) {
      case _TwoFingerKind.pinch:
        widget.onFontSizeChanged(
          clampTerminalFontSize(_pinchStartFontSize * update.scale),
        );
      case _TwoFingerKind.scroll:
        _scrollRemainder += update.focalStep.dy;
        _applyScroll();
    }
  }

  void _applyScroll() {
    const step = TerminalGestureLayer.scrollLineStep;
    final commands = _commands;
    // Fingers moving down reveal older output: scroll back.
    var back = 0;
    while (_scrollRemainder >= step) {
      _scrollRemainder -= step;
      back += 1;
    }
    if (back > 0) {
      _exitTravel = 0;
      if (!_scrollMode) {
        _scrollMode = true;
        _linesAbove = 0;
        commands.enterScrollback();
        widget.onEnterScrollMode();
      }
      commands.scrollBack(back);
      _linesAbove += back;
    }
    // Fingers moving up head back towards the live screen.
    var forward = 0;
    while (_scrollRemainder <= -step) {
      _scrollRemainder += step;
      forward += 1;
    }
    if (forward == 0) {
      return;
    }
    if (!_scrollMode) {
      // Nothing newer than the live screen; swallow the travel.
      return;
    }
    final scrollable = forward.clamp(0, _linesAbove);
    if (scrollable > 0) {
      commands.scrollForward(scrollable);
      _linesAbove -= scrollable;
    }
    final overshoot = forward - scrollable;
    if (overshoot > 0) {
      _exitTravel += overshoot * step;
      if (_exitTravel >= TerminalGestureLayer.scrollExitDistance) {
        _exitTravel = 0;
        _scrollMode = false;
        _linesAbove = 0;
        commands.exitScrollback();
        widget.onExitScrollMode();
      }
    }
  }

  void _handleTwoFingerEnd() {
    _twoFingerKind = null;
    _scrollRemainder = 0;
  }

  @override
  Widget build(BuildContext context) {
    final touchSlop =
        MediaQuery.maybeGestureSettingsOf(context)?.touchSlop ?? kTouchSlop;
    return LayoutBuilder(
      builder: (context, constraints) {
        _swipe
          ..zones = TerminalSwipeZones(
            size: constraints.biggest,
            headerHeight: widget.headerZoneHeight,
            edgeWidth: widget.edgeZoneWidth,
          )
          ..touchSlop = touchSlop
          ..windowSwipeEnabled = _windowSwipeEnabled
          ..headerSwipeEnabled = _headerSwipeEnabled
          ..edgeSwipeEnabled = _edgeSwipeEnabled;
        final twoFinger = _pinchEnabled || _twoFingerScrollEnabled;
        // See TerminalPointerMember for why a Listener feeds the members
        // instead of a RawGestureDetector.
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            _swipe.handlePointerDown(event);
            if (twoFinger) {
              _twoFinger.handlePointerDown(event);
            }
          },
          onPointerMove: (event) {
            _swipe.handlePointerMove(event);
            _twoFinger.handlePointerMove(event);
          },
          onPointerUp: (event) {
            _swipe.handlePointerUp(event);
            _twoFinger.handlePointerUp(event);
          },
          onPointerCancel: (event) {
            _swipe.handlePointerCancel(event);
            _twoFinger.handlePointerCancel(event);
          },
          child: widget.child,
        );
      },
    );
  }
}

/// Wraps a header widget so a downward swipe on it opens the session grid.
///
/// The header has no vertical gestures of its own, so a plain vertical drag
/// is enough here; taps on the header's buttons are unaffected.
class TerminalHeaderSwipeArea extends StatefulWidget {
  const TerminalHeaderSwipeArea({
    required this.onSwipeDown,
    required this.child,
    this.enabled = true,
    super.key,
  });

  final VoidCallback? onSwipeDown;
  final bool enabled;
  final Widget child;

  @override
  State<TerminalHeaderSwipeArea> createState() =>
      _TerminalHeaderSwipeAreaState();
}

class _TerminalHeaderSwipeAreaState extends State<TerminalHeaderSwipeArea> {
  double _travel = 0;

  @override
  Widget build(BuildContext context) {
    final onSwipeDown = widget.onSwipeDown;
    if (!widget.enabled || onSwipeDown == null) {
      return widget.child;
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: (_) => _travel = 0,
      onVerticalDragUpdate: (details) => _travel += details.delta.dy,
      onVerticalDragEnd: (_) {
        if (_travel >= TerminalSwipeRecognizer.minimumDistance) {
          onSwipeDown();
        }
        _travel = 0;
      },
      child: widget.child,
    );
  }
}
