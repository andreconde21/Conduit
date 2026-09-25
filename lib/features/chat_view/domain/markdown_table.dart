/// Column alignment from a GitHub-style delimiter row.
enum MarkdownTableAlign { start, center, end }

/// A parsed GitHub-style table. Every row has exactly [columns] cells
/// (short rows are padded with empty cells, extra cells dropped).
class MarkdownTable {
  const MarkdownTable({
    required this.headers,
    required this.aligns,
    required this.rows,
  });

  final List<String> headers;
  final List<MarkdownTableAlign> aligns;
  final List<List<String>> rows;

  int get columns => headers.length;
}

/// Finds and parses GitHub-flavoured Markdown tables: a header row, a
/// delimiter row (`---`, `:--`, `:-:`, `--:`), then body rows until a
/// blank line or a line without a pipe. Leading and trailing pipes are
/// optional; `\|` is a literal pipe, and pipes inside `code` do not split.
abstract final class MarkdownTables {
  static final _delimiterCell = RegExp(r'^:?-+:?$');

  /// The table starting at [lines]`[start]` and how many lines it spans,
  /// or null when no table starts there.
  static (MarkdownTable, int)? tryParse(List<String> lines, int start) {
    if (start + 1 >= lines.length) return null;
    final headerLine = lines[start];
    final delimiterLine = lines[start + 1];
    if (!headerLine.contains('|') || !delimiterLine.contains('|')) {
      return null;
    }
    final delimiters = splitRow(delimiterLine);
    if (delimiters.isEmpty ||
        !delimiters.every((cell) => _delimiterCell.hasMatch(cell.trim()))) {
      return null;
    }
    final headers = splitRow(headerLine);
    if (headers.isEmpty) return null;
    final columns = headers.length;
    final aligns = [
      for (var c = 0; c < columns; c++)
        c < delimiters.length
            ? _align(delimiters[c].trim())
            : MarkdownTableAlign.start,
    ];
    final rows = <List<String>>[];
    var i = start + 2;
    while (i < lines.length &&
        lines[i].trim().isNotEmpty &&
        lines[i].contains('|')) {
      rows.add(_fit(splitRow(lines[i]), columns));
      i += 1;
    }
    return (
      MarkdownTable(headers: headers, aligns: aligns, rows: rows),
      i - start,
    );
  }

  static MarkdownTableAlign _align(String cell) {
    final left = cell.startsWith(':');
    final right = cell.endsWith(':');
    if (left && right) return MarkdownTableAlign.center;
    if (right) return MarkdownTableAlign.end;
    return MarkdownTableAlign.start;
  }

  static List<String> _fit(List<String> cells, int columns) => [
    for (var c = 0; c < columns; c++) c < cells.length ? cells[c] : '',
  ];

  /// Splits one row into trimmed cells. Public for tests.
  static List<String> splitRow(String line) {
    var text = line.trim();
    if (text.startsWith('|')) text = text.substring(1);
    if (text.endsWith('|') && !text.endsWith(r'\|')) {
      text = text.substring(0, text.length - 1);
    }
    final cells = <String>[];
    final cell = StringBuffer();
    var inCode = false;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == r'\' && i + 1 < text.length && text[i + 1] == '|') {
        cell.write('|');
        i += 1;
      } else if (char == '`') {
        inCode = !inCode;
        cell.write(char);
      } else if (char == '|' && !inCode) {
        cells.add(cell.toString().trim());
        cell.clear();
      } else {
        cell.write(char);
      }
    }
    cells.add(cell.toString().trim());
    return cells;
  }
}
