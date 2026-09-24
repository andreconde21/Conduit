import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/features/terminal/domain/terminal_path_detector.dart';
import 'package:conduit/features/terminal/presentation/terminal_session_controller.dart';
import 'package:conduit_vt/conduit_vt.dart';
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

  @override
  State<TerminalSurface> createState() => _TerminalSurfaceState();
}

class _TerminalSurfaceState extends State<TerminalSurface> {
  double _tmuxScrollDelta = 0;
  late final TerminalController _terminalController;

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
    if (oldWidget.session != widget.session) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _connectIfNeeded());
    }
  }

  @override
  void dispose() {
    _terminalController.dispose();
    super.dispose();
  }

  Future<void> _connectIfNeeded() async {
    if (!mounted || !widget.session.shouldConnect) return;
    await widget.session.connect();
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
    final onPathTap = widget.onPathTap;
    if (onPathTap == null || widget.tmuxScrollMode) {
      return;
    }
    final terminal = widget.session.terminal;
    final lines = terminal.buffer.lines;
    if (offset.y < 0 || offset.y >= lines.length) {
      return;
    }
    // The cursor row is the prompt or the command being typed. Tapping there
    // is how the keyboard gets summoned on a phone, and prompts routinely
    // show the working directory, so it must not raise an "Open" snackbar on
    // every tap. Output above the cursor is unaffected.
    if (offset.y == terminal.buffer.absoluteCursorY) {
      return;
    }
    // Join soft-wrapped rows into one logical line so a path broken across
    // rows is still recognized; earlier rows are padded back to full width
    // because getText() trims trailing blanks.
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
    final path = terminalPathAt(buffer.toString(), column);
    if (path != null) {
      onPathTap(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        children: [
          ListenableBuilder(
            listenable: widget.session.terminalPaintListenable,
            builder: (context, _) {
              final overlays = widget.session.overlays;
              return TerminalView(
                widget.session.terminal,
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
