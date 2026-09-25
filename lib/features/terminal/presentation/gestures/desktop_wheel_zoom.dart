import 'package:conduit/core/platform_features.dart';
import 'package:conduit/core/theme/terminal_appearance.dart';
import 'package:conduit/features/terminal/presentation/desktop_shortcuts.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Desktop zoom with the pointer: Ctrl + wheel (Cmd + wheel on macOS)
/// changes the terminal font size by [desktopZoomStep] per wheel notch, and
/// a trackpad pinch scales it like the phone's pinch. Same clamp and
/// persistence as the pinch ([onFontSizeChanged] is the pinch's callback).
///
/// A plain wheel keeps scrolling: the zoom modifier is added to the
/// ScrollConfiguration's axis modifiers, so the terminal's scrollables read
/// the (empty) horizontal delta of a Ctrl + wheel event and do not claim it,
/// which leaves the event to this widget.
///
/// Phones get [child] unchanged.
class DesktopWheelZoom extends StatefulWidget {
  const DesktopWheelZoom({
    required this.fontSize,
    required this.onFontSizeChanged,
    required this.child,
    super.key,
  });

  final double fontSize;
  final ValueChanged<double> onFontSizeChanged;
  final Widget child;

  /// Smooth (trackpad) scrolling travel that makes one zoom step.
  static const trackpadTravelPerStep = 40.0;

  @override
  State<DesktopWheelZoom> createState() => _DesktopWheelZoomState();
}

class _DesktopWheelZoomState extends State<DesktopWheelZoom> {
  double _travel = 0;
  double _pinchStart = terminalFontSizeDefault;
  late double _pending = widget.fontSize;

  @override
  void didUpdateWidget(covariant DesktopWheelZoom oldWidget) {
    super.didUpdateWidget(oldWidget);
    _pending = widget.fontSize;
  }

  void _zoomBy(int steps) {
    if (steps == 0) return;
    final next = clampTerminalFontSize(_pending + steps * desktopZoomStep);
    if (next == _pending) return;
    _pending = next;
    widget.onFontSizeChanged(next);
  }

  void _handleSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !isWheelZoomModifierPressed) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final scroll = event as PointerScrollEvent;
      final dy = scroll.scrollDelta.dy;
      if (dy == 0) return;
      if (scroll.kind == PointerDeviceKind.mouse) {
        // One step per notch, whatever the OS's lines-per-notch.
        _zoomBy(dy < 0 ? 1 : -1);
        return;
      }
      _travel += dy;
      final steps = _travel ~/ DesktopWheelZoom.trackpadTravelPerStep;
      _travel -= steps * DesktopWheelZoom.trackpadTravelPerStep;
      _zoomBy(-steps);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformFeatures.isDesktop) return widget.child;
    final behavior = ScrollConfiguration.of(context);
    return ScrollConfiguration(
      behavior: behavior.copyWith(
        pointerAxisModifiers: {
          ...behavior.pointerAxisModifiers,
          ...wheelZoomModifierKeys,
        },
      ),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerSignal: _handleSignal,
        onPointerPanZoomStart: (_) {
          _pinchStart = widget.fontSize;
          _travel = 0;
        },
        onPointerPanZoomUpdate: (event) {
          if ((event.scale - 1).abs() < 0.02) return;
          final next = clampTerminalFontSize(_pinchStart * event.scale);
          if (next == _pending) return;
          _pending = next;
          widget.onFontSizeChanged(next);
        },
        child: widget.child,
      ),
    );
  }
}
