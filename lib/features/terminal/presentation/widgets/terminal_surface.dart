import 'dart:async';

import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/features/terminal/domain/terminal_link_detector.dart';
import 'package:conduit/features/terminal/domain/terminal_path_detector.dart';
import 'package:conduit/features/terminal/presentation/terminal_session_controller.dart';
import 'package:conduit_vt/conduit_vt.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class TerminalSurface extends StatefulWidget {
  const TerminalSurface({
    required this.session,
    required this.palette,
    required this.brightness,
    required this.fontFamily,
    required this.fontSize,
    required this.predictiveEchoEnabled,
    required this.terminalMouseInput,
    required this.focusNode,
    required this.tmuxScrollMode,
    required this.onExitTmuxScrollMode,
    this.onPathTap,
    this.onLinkTap,
    this.onLinkLongPress,
    this.autoConnect = true,
    super.key,
  });

  final TerminalSessionController session;
  final AppPalette palette;
  final Brightness brightness;
  final String fontFamily;
  final double fontSize;
  final bool predictiveEchoEnabled;
  final bool terminalMouseInput;
  final FocusNode? focusNode;
  final bool tmuxScrollMode;
  final VoidCallback onExitTmuxScrollMode;

  /// Called when the user taps something in the output that looks like a
  /// file path.
  final ValueChanged<String>? onPathTap;

  /// Called when the user taps an http(s) link in the output.
  final ValueChanged<String>? onLinkTap;

  /// Called when the user long-presses an http(s) link, with the link and
  /// the logical line it sits on. The word selection the long press makes
  /// stays unless the callback resolves to true (an action was taken).
  final Future<bool> Function(String url, String line)? onLinkLongPress;

  /// Whether a disconnected session connects as soon as this view is
  /// built. False for a background tab that waits to be shown (a session
  /// restored from the last app run); it connects when this turns true.
  final bool autoConnect;

  @override
  State<TerminalSurface> createState() => _TerminalSurfaceState();
}

class _TerminalSurfaceState extends State<TerminalSurface> {
  double _tmuxScrollDelta = 0;
  late final TerminalController _terminalController;
  final _viewKey = GlobalKey<TerminalViewState>();
  Timer? _longPressTimer;
  int? _longPressPointer;
  Offset? _longPressOrigin;

  static PointerInputs _pointerInputsFor(bool terminalMouseInput) {
    return terminalMouseInput
        ? const PointerInputs({PointerInput.tap})
        : const PointerInputs.none();
  }

  @override
  void initState() {
    super.initState();
    _terminalController = TerminalController(
      pointerInputs: _pointerInputsFor(widget.terminalMouseInput),
    );
    widget.session.predictiveEchoEnabled = widget.predictiveEchoEnabled;
    WidgetsBinding.instance.addPostFrameCallback((_) => _connectIfNeeded());
  }

  @override
  void didUpdateWidget(covariant TerminalSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.predictiveEchoEnabled != widget.predictiveEchoEnabled ||
        oldWidget.session != widget.session) {
      widget.session.predictiveEchoEnabled = widget.predictiveEchoEnabled;
    }
    if (oldWidget.terminalMouseInput != widget.terminalMouseInput) {
      _terminalController.setPointerInputs(
        _pointerInputsFor(widget.terminalMouseInput),
      );
    }
    if (oldWidget.session != widget.session ||
        (!oldWidget.autoConnect && widget.autoConnect)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _connectIfNeeded());
    }
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _terminalController.dispose();
    super.dispose();
  }

  /// Connects a new or dropped session. A session that is already live
  /// had no view while this page was closed (or the app was away), so the
  /// remote is asked for a full repaint instead of trusting the buffer.
  Future<void> _connectIfNeeded() async {
    if (!mounted) return;
    final session = widget.session;
    if (session.shouldConnect) {
      if (!widget.autoConnect) return;
      await session.connect();
    } else if (session.isConnected) {
      session.forceResize();
    }
  }

  void _handleTmuxScrollDrag(DragUpdateDetails details) {
    _tmuxScrollDelta += details.primaryDelta ?? 0;
    const step = 12.0;
    while (_tmuxScrollDelta.abs() >= step) {
      if (_tmuxScrollDelta > 0) {
        widget.session.sendKey(TerminalKey.arrowUp);
        _tmuxScrollDelta -= step;
      } else {
        widget.session.sendKey(TerminalKey.arrowDown);
        _tmuxScrollDelta += step;
      }
    }
  }

  void _handleTmuxScrollEnd(DragEndDetails details) {
    _tmuxScrollDelta = 0;
  }

  static const _maxWrappedRows = 8;

  void _handleTapUp(TapUpDetails details, CellOffset offset) {
    if (widget.tmuxScrollMode) {
      return;
    }
    // The cursor row is the prompt or the command being typed. Tapping there
    // is how the keyboard gets summoned on a phone, and prompts routinely
    // show the working directory, so it must not raise an "Open" snackbar on
    // every tap. Output above the cursor is unaffected.
    if (offset.y == widget.session.terminal.buffer.absoluteCursorY) {
      return;
    }
    final line = _logicalLineAt(offset);
    if (line == null) {
      return;
    }
    final onLinkTap = widget.onLinkTap;
    if (onLinkTap != null) {
      final url = terminalUrlAt(line.text, line.column);
      if (url != null) {
        onLinkTap(url);
        return;
      }
    }
    final onPathTap = widget.onPathTap;
    if (onPathTap == null) {
      return;
    }
    final path = terminalPathAt(line.text, line.column);
    if (path != null) {
      onPathTap(path);
    }
  }

  /// The logical line under [offset] with soft-wrapped rows joined, so a
  /// path or link broken across rows is still recognized, and the tapped
  /// column translated into it. Earlier rows are padded back to full width
  /// because getText() trims trailing blanks.
  ({String text, int column})? _logicalLineAt(CellOffset offset) {
    final terminal = widget.session.terminal;
    final lines = terminal.buffer.lines;
    if (offset.y < 0 || offset.y >= lines.length) {
      return null;
    }
    var first = offset.y;
    while (first > 0 &&
        offset.y - first < _maxWrappedRows &&
        lines[first].isWrapped) {
      first--;
    }
    final buffer = StringBuffer();
    var column = offset.x;
    for (var row = first; row < lines.length; row++) {
      if (row != first && !lines[row].isWrapped) {
        break;
      }
      if (row - first >= _maxWrappedRows) {
        break;
      }
      var text = lines[row].getText();
      if (row < offset.y) {
        text = text.padRight(terminal.viewWidth);
        column += terminal.viewWidth;
      }
      buffer.write(text);
    }
    return (text: buffer.toString(), column: column);
  }

  // Long press on a link. The terminal's own long press (word selection)
  // lives inside TerminalView's gesture arena; a raw Listener watches the
  // same pointer without competing, so selection keeps working and the
  // link menu opens on top of it.
  void _handlePointerDown(PointerDownEvent event) {
    // A second finger (pinch, two-finger scroll) is never a long press.
    final multiTouch = _longPressPointer != null;
    _cancelLongPress();
    if (multiTouch || widget.onLinkLongPress == null || widget.tmuxScrollMode) {
      return;
    }
    _longPressPointer = event.pointer;
    _longPressOrigin = event.position;
    _longPressTimer = Timer(kLongPressTimeout, () {
      final origin = _longPressOrigin;
      _longPressPointer = null;
      if (origin != null) {
        unawaited(_handleLinkLongPress(origin));
      }
    });
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final origin = _longPressOrigin;
    if (event.pointer == _longPressPointer &&
        origin != null &&
        (event.position - origin).distance > kTouchSlop) {
      _cancelLongPress();
    }
  }

  void _handlePointerEnd(PointerEvent event) {
    if (event.pointer == _longPressPointer) {
      _cancelLongPress();
    }
  }

  void _cancelLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _longPressPointer = null;
    _longPressOrigin = null;
  }

  Future<void> _handleLinkLongPress(Offset globalPosition) async {
    final onLinkLongPress = widget.onLinkLongPress;
    final render = _viewKey.currentState?.renderTerminal;
    if (onLinkLongPress == null || render == null || !render.attached) {
      return;
    }
    final offset = render.getCellOffset(render.globalToLocal(globalPosition));
    final line = _logicalLineAt(offset);
    if (line == null) {
      return;
    }
    final url = terminalUrlAt(line.text, line.column);
    if (url == null) {
      return;
    }
    final acted = await onLinkLongPress(url, line.text.trimRight());
    if (acted && mounted) {
      _terminalController.clearSelection();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        children: [
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _handlePointerDown,
            onPointerMove: _handlePointerMove,
            onPointerUp: _handlePointerEnd,
            onPointerCancel: _handlePointerEnd,
            child: ListenableBuilder(
              listenable: widget.session.terminalPaintListenable,
              builder: (context, _) {
                final overlays = widget.session.overlays;
                return TerminalView(
                  widget.session.terminal,
                  key: _viewKey,
                  controller: _terminalController,
                  onTapUp: _handleTapUp,
                  focusNode: widget.focusNode,
                  autofocus: widget.focusNode != null,
                  deleteDetection: true,
                  keyboardType: TextInputType.visiblePassword,
                  theme: widget.palette.terminalThemeFor(widget.brightness),
                  overlays: overlays,
                  textStyle: TerminalStyle(
                    fontFamily: widget.fontFamily,
                    fontSize: widget.fontSize,
                  ),
                  padding: const EdgeInsets.fromLTRB(0, 6, 0, 4),
                  cursorType: overlays.isEmpty
                      ? TerminalCursorType.block
                      : TerminalCursorType.verticalBar,
                  alwaysShowCursor: true,
                  simulateScroll: !widget.tmuxScrollMode,
                );
              },
            ),
          ),
          if (widget.tmuxScrollMode)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragUpdate: _handleTmuxScrollDrag,
                onVerticalDragEnd: _handleTmuxScrollEnd,
                child: const SizedBox.expand(),
              ),
            ),
        ],
      ),
    );
  }
}
