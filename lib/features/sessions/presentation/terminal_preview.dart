import 'dart:math' as math;

import 'package:conduit_vt/conduit_vt.dart';

/// A downscaled text snapshot of a terminal's viewport for the session grid.
class TerminalPreview {
  const TerminalPreview(this.lines);

  static const empty = TerminalPreview([]);

  /// Visible rows, oldest first, each already cut to the preview width.
  final List<String> lines;

  bool get isEmpty => lines.isEmpty;

  /// Captures the last [rows] non-blank rows of the current viewport (the
  /// alternate screen when a full-screen app is active), each truncated to
  /// [columns] characters. Trailing blank rows are dropped so a mostly
  /// empty screen shows its content instead of whitespace.
  static TerminalPreview capture(
    Terminal terminal, {
    int rows = 12,
    int columns = 48,
  }) {
    final buffer = terminal.buffer;
    final height = buffer.height;
    final viewHeight = math.max(1, terminal.viewHeight);
    final start = math.max(0, height - viewHeight);
    final lines = <String>[];
    for (var index = start; index < height; index++) {
      final line = buffer.lines[index];
      lines.add(line.getText(0, math.min(columns, line.length)));
    }
    var end = lines.length;
    while (end > 0 && lines[end - 1].trim().isEmpty) {
      end -= 1;
    }
    final begin = math.max(0, end - rows);
    return TerminalPreview(lines.sublist(begin, end));
  }

  @override
  bool operator ==(Object other) {
    if (other is! TerminalPreview || other.lines.length != lines.length) {
      return false;
    }
    for (var index = 0; index < lines.length; index++) {
      if (other.lines[index] != lines[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(lines);
}
