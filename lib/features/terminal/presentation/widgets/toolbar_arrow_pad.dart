import 'dart:async';
import 'dart:math' as math;

import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/core/theme/app_theme.dart';
import 'package:conduit_vt/conduit_vt.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// One arrow key emitted every [toolbarArrowPadStep] logical pixels of drag.
const toolbarArrowPadStep = 18.0;

/// Past this distance from the touch origin the pad keeps repeating the
/// current direction while the finger rests, like holding an arrow key.
const toolbarArrowPadHoldRadius = 56.0;
const toolbarArrowPadRepeatDelay = Duration(milliseconds: 300);
const toolbarArrowPadRepeatInterval = Duration(milliseconds: 80);

/// A single toolbar button that behaves like a tiny trackpad for the arrow
/// keys.
///
/// Drag across it to emit arrows proportional to the drag distance along the
/// dominant axis (moving back re-emits the opposite direction so the cursor
/// mirrors the finger); rest the finger beyond [toolbarArrowPadHoldRadius] to
/// auto-repeat. A tap near an edge sends that single arrow; a tap dead in the
/// centre does nothing.
///
/// The pad claims every pointer that lands on it, so a swipe that starts here
/// never bubbles up as a toolbar gesture.
class ToolbarArrowPad extends StatefulWidget {
  const ToolbarArrowPad({
    required this.onArrow,
    required this.palette,
    required this.brightness,
    this.size = const Size(44, 40),
    super.key,
  });

  final ValueChanged<TerminalKey> onArrow;
  final AppPalette palette;
  final Brightness brightness;
  final Size size;

  @override
  State<ToolbarArrowPad> createState() => _ToolbarArrowPadState();
}

class _ToolbarArrowPadState extends State<ToolbarArrowPad> {
  Offset? _origin;
  bool _moved = false;
  int _emittedX = 0;
  int _emittedY = 0;
  TerminalKey? _activeKey;
  TerminalKey? _repeatKey;
  Timer? _repeatDelay;
  Timer? _repeatTimer;

  @override
  void dispose() {
    _stopRepeat();
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent event) {
    _origin = event.localPosition;
    _moved = false;
    _emittedX = 0;
    _emittedY = 0;
    setState(() => _activeKey = null);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final origin = _origin;
    if (origin == null) {
      return;
    }
    final delta = event.localPosition - origin;
    if (!_moved) {
      if (delta.distance <= kTouchSlop) {
        return;
      }
      _moved = true;
    }
    _emitProportional(delta);
    _updateHoldRepeat(delta);
  }

  void _emitProportional(Offset delta) {
    if (delta.dx.abs() >= delta.dy.abs()) {
      final target = (delta.dx / toolbarArrowPadStep).truncate();
      while (_emittedX != target) {
        final forward = target > _emittedX;
        _emittedX += forward ? 1 : -1;
        _emit(forward ? TerminalKey.arrowRight : TerminalKey.arrowLeft);
      }
    } else {
      final target = (delta.dy / toolbarArrowPadStep).truncate();
      while (_emittedY != target) {
        final forward = target > _emittedY;
        _emittedY += forward ? 1 : -1;
        _emit(forward ? TerminalKey.arrowDown : TerminalKey.arrowUp);
      }
    }
  }

  void _updateHoldRepeat(Offset delta) {
    if (delta.distance < toolbarArrowPadHoldRadius) {
      _stopRepeat();
      return;
    }
    final key = _directionFor(delta);
    if (key == _repeatKey && (_repeatDelay != null || _repeatTimer != null)) {
      return;
    }
    _stopRepeat();
    _repeatKey = key;
    _repeatDelay = Timer(toolbarArrowPadRepeatDelay, () {
      _repeatDelay = null;
      _repeatTimer = Timer.periodic(toolbarArrowPadRepeatInterval, (_) {
        final repeatKey = _repeatKey;
        if (repeatKey != null) {
          _emit(repeatKey);
        }
      });
    });
  }

  void _handlePointerUp(PointerUpEvent event) {
    final origin = _origin;
    _stopRepeat();
    _origin = null;
    if (origin != null && !_moved) {
      final key = _tapDirection(event.localPosition);
      if (key != null) {
        _emit(key);
      }
    }
    if (mounted) {
      setState(() => _activeKey = null);
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _stopRepeat();
    _origin = null;
    if (mounted) {
      setState(() => _activeKey = null);
    }
  }

  /// Which arrow a tap sends, from the tap's direction relative to the pad's
  /// centre; null inside the small dead zone in the middle.
  TerminalKey? _tapDirection(Offset position) {
    final center = Offset(widget.size.width / 2, widget.size.height / 2);
    final delta = position - center;
    final deadZone = math.min(widget.size.width, widget.size.height) * 0.16;
    if (delta.distance < deadZone) {
      return null;
    }
    return _directionFor(delta);
  }

  static TerminalKey _directionFor(Offset delta) {
    if (delta.dx.abs() >= delta.dy.abs()) {
      return delta.dx > 0 ? TerminalKey.arrowRight : TerminalKey.arrowLeft;
    }
    return delta.dy > 0 ? TerminalKey.arrowDown : TerminalKey.arrowUp;
  }

  void _emit(TerminalKey key) {
    if (_activeKey != key && mounted) {
      setState(() => _activeKey = key);
    }
    widget.onArrow(key);
  }

  void _stopRepeat() {
    _repeatDelay?.cancel();
    _repeatDelay = null;
    _repeatTimer?.cancel();
    _repeatTimer = null;
    _repeatKey = null;
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final brightness = widget.brightness;
    final active = _origin != null;
    final foreground = active
        ? palette.accent
        : palette.foregroundFor(brightness);
    final background = active
        ? Color.alphaBlend(
            palette.accent.withValues(alpha: 0.22),
            palette.panelElevatedFor(brightness),
          )
        : palette.panelElevatedFor(brightness);
    final icon = switch (_activeKey) {
      TerminalKey.arrowUp => Icons.keyboard_arrow_up_rounded,
      TerminalKey.arrowDown => Icons.keyboard_arrow_down_rounded,
      TerminalKey.arrowLeft => Icons.keyboard_arrow_left_rounded,
      TerminalKey.arrowRight => Icons.keyboard_arrow_right_rounded,
      _ => Icons.open_with_rounded,
    };
    return Semantics(
      label:
          'Arrow pad. Drag to move the cursor, tap an edge for a single arrow.',
      button: true,
      child: RawGestureDetector(
        // Win the gesture arena on touch-down so neither the toolbar's
        // swipe-up nor a horizontal scroll can steal a drag that starts here.
        gestures: <Type, GestureRecognizerFactory>{
          EagerGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                EagerGestureRecognizer.new,
                (_) {},
              ),
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerUp,
          onPointerCancel: _handlePointerCancel,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: widget.size.width,
            height: widget.size.height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
            child: Icon(icon, color: foreground, size: 22),
          ),
        ),
      ),
    );
  }
}
