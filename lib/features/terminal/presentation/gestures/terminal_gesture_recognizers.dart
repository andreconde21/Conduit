import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';

/// Where a one-finger swipe started on the terminal surface.
enum TerminalSwipeZone { body, header, rightEdge }

/// One-finger swipes recognised on the terminal surface.
enum TerminalSwipeKind { windowNext, windowPrevious, headerDown, edgeIn }

/// Describes the geometry a [TerminalSwipeRecognizer] uses to classify a
/// pointer-down position. Updated on every build so it follows layout.
class TerminalSwipeZones {
  const TerminalSwipeZones({
    required this.size,
    this.headerHeight = 48,
    this.edgeWidth = 24,
  });

  final Size size;
  final double headerHeight;
  final double edgeWidth;

  TerminalSwipeZone zoneAt(Offset localPosition) {
    if (localPosition.dx >= size.width - edgeWidth) {
      return TerminalSwipeZone.rightEdge;
    }
    if (localPosition.dy <= headerHeight) {
      return TerminalSwipeZone.header;
    }
    return TerminalSwipeZone.body;
  }
}

/// Why the gesture members below are fed from a [Listener] instead of
/// living in a `RawGestureDetector`:
///
/// Pointer events reach `Listener` callbacks (innermost widget first) before
/// the gesture binding routes them to any gesture recogniser. A recogniser
/// in an *outer* widget therefore always sees a move *after* the terminal
/// view's own recognisers, so on a fast flick the terminal's vertical scroll
/// could claim the pointer in the same event that would have made a header
/// or edge swipe unambiguous. Handling the events in a `Listener` lets the
/// layer classify each move before the terminal view's recognisers look at
/// it, while still competing in the ordinary gesture arena so that a
/// rejected swipe hands the pointer back untouched.
abstract class TerminalPointerMember extends GestureArenaMember {
  void handlePointerDown(PointerDownEvent event);
  void handlePointerMove(PointerMoveEvent event);
  void handlePointerUp(PointerUpEvent event);
  void handlePointerCancel(PointerCancelEvent event);
}

/// Recognises the one-finger swipes the terminal responds to and arbitrates
/// them in the gesture arena against the terminal view's own recognisers.
///
/// The terminal view already owns taps (keyboard summon, mouse forwarding,
/// path taps), long presses (text selection) and a vertical drag (scrolling).
/// This member therefore only claims a pointer once movement makes the
/// intent unambiguous:
///
/// * a swipe starting in the header strip or on the right edge is claimed as
///   soon as it moves [zoneSlop] in the expected direction, which is below
///   the platform touch slop the terminal's scroll needs;
/// * a swipe in the body is only claimed once it has travelled the full touch
///   slop horizontally with clearly less vertical movement, so vertical
///   scrolling and diagonal fumbles stay with the terminal view;
/// * anything else is rejected as soon as it is recognisable, handing the
///   pointer back to the terminal view.
///
/// [onSwipe] fires on pointer up, and only when the swipe travelled at least
/// [minimumDistance] in its direction. Only the first finger is considered;
/// a second finger belongs to [TwoFingerGestureRecognizer].
class TerminalSwipeRecognizer extends TerminalPointerMember {
  TerminalSwipeRecognizer({this.onSwipe});

  static const double zoneSlop = 12;
  static const double minimumDistance = 64;

  TerminalSwipeZones zones = const TerminalSwipeZones(size: Size.zero);
  bool windowSwipeEnabled = true;
  bool headerSwipeEnabled = true;
  bool edgeSwipeEnabled = true;
  double touchSlop = kTouchSlop;
  void Function(TerminalSwipeKind kind)? onSwipe;

  int? _pointer;
  Offset? _start;
  Offset? _last;
  TerminalSwipeZone? _zone;
  TerminalSwipeKind? _claimed;
  GestureArenaEntry? _entry;

  bool get _anyEnabled =>
      windowSwipeEnabled || headerSwipeEnabled || edgeSwipeEnabled;

  /// The pointer currently under consideration, for tests.
  int? get trackedPointer => _pointer;

  @override
  void handlePointerDown(PointerDownEvent event) {
    if (_pointer != null ||
        !_anyEnabled ||
        event.kind != PointerDeviceKind.touch) {
      return;
    }
    _pointer = event.pointer;
    _start = event.localPosition;
    _last = event.localPosition;
    _zone = zones.zoneAt(event.localPosition);
    _claimed = null;
    _entry = GestureBinding.instance.gestureArena.add(event.pointer, this);
  }

  @override
  void handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _last = event.localPosition;
    if (_claimed == null) {
      _classify(event.localPosition - _start!);
    }
  }

  @override
  void handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _finish();
    _reset(GestureDisposition.rejected);
  }

  @override
  void handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer == _pointer) {
      _reset(GestureDisposition.rejected);
    }
  }

  @override
  void acceptGesture(int pointer) {
    // Accepted by default because every other member dropped out. Keep
    // classifying; the swipe still has to qualify on its own terms.
  }

  @override
  void rejectGesture(int pointer) {
    if (pointer == _pointer) {
      _reset(null);
    }
  }

  void _classify(Offset delta) {
    final dx = delta.dx;
    final dy = delta.dy;
    final horizontal = dx.abs() > dy.abs();
    switch (_zone!) {
      case TerminalSwipeZone.header:
        if (headerSwipeEnabled && dy >= zoneSlop && !horizontal) {
          _claim(TerminalSwipeKind.headerDown);
          return;
        }
        if (dy.abs() >= zoneSlop && !horizontal) {
          // Upward swipe from the header strip: plain terminal scroll.
          _giveUp();
          return;
        }
        _classifyHorizontal(dx, dy);
      case TerminalSwipeZone.rightEdge:
        if (edgeSwipeEnabled && -dx >= zoneSlop && horizontal) {
          _claim(TerminalSwipeKind.edgeIn);
          return;
        }
        if (dx.abs() >= zoneSlop && horizontal) {
          // Swiping outwards from the edge means nothing; give it back.
          _giveUp();
          return;
        }
        if (dy.abs() >= touchSlop) {
          _giveUp();
        }
      case TerminalSwipeZone.body:
        _classifyHorizontal(dx, dy);
    }
  }

  void _classifyHorizontal(double dx, double dy) {
    if (!windowSwipeEnabled) {
      if (dx.abs() >= touchSlop || dy.abs() >= touchSlop) {
        _giveUp();
      }
      return;
    }
    if (dx.abs() >= touchSlop && dx.abs() >= dy.abs() * 2) {
      _claim(
        dx < 0
            ? TerminalSwipeKind.windowNext
            : TerminalSwipeKind.windowPrevious,
      );
      return;
    }
    if (dy.abs() >= touchSlop && dy.abs() > dx.abs()) {
      _giveUp();
    }
  }

  void _claim(TerminalSwipeKind kind) {
    _claimed = kind;
    _entry?.resolve(GestureDisposition.accepted);
  }

  void _giveUp() {
    _reset(GestureDisposition.rejected);
  }

  void _finish() {
    final kind = _claimed;
    final start = _start;
    final last = _last;
    if (kind == null || start == null || last == null) {
      return;
    }
    final delta = last - start;
    final travelled = switch (kind) {
      TerminalSwipeKind.headerDown => delta.dy,
      TerminalSwipeKind.edgeIn => -delta.dx,
      TerminalSwipeKind.windowNext => -delta.dx,
      TerminalSwipeKind.windowPrevious => delta.dx,
    };
    if (travelled >= minimumDistance) {
      onSwipe?.call(kind);
    }
  }

  void _reset(GestureDisposition? disposition) {
    final entry = _entry;
    _entry = null;
    _pointer = null;
    _start = null;
    _last = null;
    _zone = null;
    _claimed = null;
    if (disposition != null) {
      // A no-op once the arena has already been decided.
      entry?.resolve(disposition);
    }
  }
}

/// A snapshot of a two-finger gesture relative to where the second finger
/// landed.
class TwoFingerUpdate {
  const TwoFingerUpdate({
    required this.focalDelta,
    required this.focalStep,
    required this.scale,
    required this.spanDelta,
    this.firstDelta = Offset.zero,
    this.secondDelta = Offset.zero,
  });

  /// Movement of the midpoint between the two fingers since the gesture
  /// started.
  final Offset focalDelta;

  /// Movement of the midpoint since the previous update.
  final Offset focalStep;

  /// Current finger distance divided by the starting distance.
  final double scale;

  /// Change in finger distance since the gesture started, in pixels.
  final double spanDelta;

  /// Movement of each finger since the gesture started. Fingers report
  /// their moves in separate events, so a two-finger swipe briefly looks
  /// like a pinch in [spanDelta]; comparing the fingers tells them apart.
  final Offset firstDelta;
  final Offset secondDelta;
}

/// Claims both pointers of a two-finger touch as soon as the second finger
/// lands, so the terminal view's single-finger scroll and selection never
/// see half of a pinch or a two-finger swipe.
///
/// The member reports raw geometry; whether the gesture is a pinch or a
/// swipe is decided by the caller from [TwoFingerUpdate.spanDelta] versus
/// [TwoFingerUpdate.focalDelta]. Extra fingers are claimed and ignored. Once
/// active the gesture ends when either of the first two fingers lifts; a
/// finger that lingers stays claimed so it cannot start a scroll on its own.
class TwoFingerGestureRecognizer extends TerminalPointerMember {
  TwoFingerGestureRecognizer({this.onStart, this.onUpdate, this.onEnd});

  VoidCallback? onStart;
  void Function(TwoFingerUpdate update)? onUpdate;
  VoidCallback? onEnd;

  final _positions = <int, Offset>{};
  final _order = <int>[];
  final _entries = <int, GestureArenaEntry>{};
  Offset? _startFocal;
  Offset? _lastFocal;
  double? _startSpan;
  Offset? _startFirst;
  Offset? _startSecond;
  bool _active = false;

  bool get isActive => _active;

  @override
  void handlePointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) {
      return;
    }
    _positions[event.pointer] = event.localPosition;
    _order.add(event.pointer);
    final entry = GestureBinding.instance.gestureArena.add(event.pointer, this);
    _entries[event.pointer] = entry;
    if (_active) {
      // A third finger during a pinch: keep it away from the terminal.
      entry.resolve(GestureDisposition.accepted);
      return;
    }
    if (_order.length == 2) {
      _startFocal = _focal;
      _lastFocal = _startFocal;
      _startSpan = _span;
      _startFirst = _positions[_order[0]];
      _startSecond = _positions[_order[1]];
      _active = true;
      for (final entry in List.of(_entries.values)) {
        entry.resolve(GestureDisposition.accepted);
      }
      onStart?.call();
    }
  }

  @override
  void handlePointerMove(PointerMoveEvent event) {
    if (!_positions.containsKey(event.pointer)) {
      return;
    }
    _positions[event.pointer] = event.localPosition;
    if (_active && _order.indexOf(event.pointer) < 2) {
      _report();
    }
  }

  @override
  void handlePointerUp(PointerUpEvent event) {
    _release(event.pointer);
  }

  @override
  void handlePointerCancel(PointerCancelEvent event) {
    _release(event.pointer);
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {
    _forget(pointer);
  }

  void _release(int pointer) {
    if (!_positions.containsKey(pointer)) {
      return;
    }
    final wasPrimary = _order.indexOf(pointer) < 2;
    final entry = _entries[pointer];
    _forget(pointer);
    if (_active && wasPrimary) {
      _active = false;
      _startFocal = null;
      _lastFocal = null;
      _startSpan = null;
      onEnd?.call();
      return;
    }
    if (!_active) {
      // A lone finger: let the terminal view have it.
      entry?.resolve(GestureDisposition.rejected);
    }
  }

  void _report() {
    final startFocal = _startFocal;
    final startSpan = _startSpan;
    final lastFocal = _lastFocal;
    if (startFocal == null ||
        startSpan == null ||
        lastFocal == null ||
        _order.length < 2) {
      return;
    }
    final focal = _focal;
    final span = _span;
    _lastFocal = focal;
    onUpdate?.call(
      TwoFingerUpdate(
        focalDelta: focal - startFocal,
        focalStep: focal - lastFocal,
        scale: startSpan == 0 ? 1 : span / startSpan,
        spanDelta: span - startSpan,
        firstDelta: _positions[_order[0]]! - (_startFirst ?? Offset.zero),
        secondDelta: _positions[_order[1]]! - (_startSecond ?? Offset.zero),
      ),
    );
  }

  Offset get _focal {
    final a = _positions[_order[0]]!;
    final b = _positions[_order[1]]!;
    return (a + b) / 2;
  }

  double get _span {
    final a = _positions[_order[0]]!;
    final b = _positions[_order[1]]!;
    return (a - b).distance;
  }

  void _forget(int pointer) {
    _positions.remove(pointer);
    _order.remove(pointer);
    _entries.remove(pointer);
  }
}
