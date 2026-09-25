/// Parsed `git diff --no-color` output.
///
/// The parser is deliberately forgiving: anything it does not understand is
/// kept as a metadata line inside the current file so nothing is dropped.
class UnifiedDiff {
  const UnifiedDiff(this.files);

  final List<DiffFile> files;

  bool get isEmpty => files.isEmpty;

  int get additions => files.fold(0, (total, file) => total + file.additions);
  int get deletions => files.fold(0, (total, file) => total + file.deletions);

  /// Parses [text], the raw output of `git diff --no-color`.
  static UnifiedDiff parse(String text) {
    final files = <DiffFile>[];
    _DiffFileBuilder? file;
    _DiffHunkBuilder? hunk;

    void finishHunk() {
      final pending = hunk;
      if (pending != null && file != null) {
        file!.hunks.add(pending.build());
      }
      hunk = null;
    }

    void finishFile() {
      finishHunk();
      if (file != null) {
        files.add(file!.build());
      }
      file = null;
    }

    for (final rawLine in _splitLines(text)) {
      if (rawLine.startsWith('diff --git ')) {
        finishFile();
        file = _DiffFileBuilder(_pathsFromHeader(rawLine));
        continue;
      }
      if (file == null && rawLine.trim().isEmpty) {
        continue;
      }
      // Output before the first `diff --git` header has nothing to attach
      // to; an anonymous file keeps the text visible.
      file ??= _DiffFileBuilder(const (null, null));
      final current = file!;
      if (rawLine.startsWith('@@')) {
        finishHunk();
        hunk = _DiffHunkBuilder.fromHeader(rawLine);
        continue;
      }
      if (hunk != null) {
        final active = hunk!;
        if (rawLine.startsWith('+')) {
          active.add(
            DiffLine(
              kind: DiffLineKind.addition,
              text: rawLine.substring(1),
              newLineNumber: active.newCursor++,
            ),
          );
          continue;
        }
        if (rawLine.startsWith('-')) {
          active.add(
            DiffLine(
              kind: DiffLineKind.deletion,
              text: rawLine.substring(1),
              oldLineNumber: active.oldCursor++,
            ),
          );
          continue;
        }
        if (rawLine.startsWith(' ') || rawLine.isEmpty) {
          active.add(
            DiffLine(
              kind: DiffLineKind.context,
              text: rawLine.isEmpty ? '' : rawLine.substring(1),
              oldLineNumber: active.oldCursor++,
              newLineNumber: active.newCursor++,
            ),
          );
          continue;
        }
        if (rawLine.startsWith(r'\')) {
          active.add(DiffLine(kind: DiffLineKind.meta, text: rawLine));
          continue;
        }
        // Anything else ends the hunk (e.g. an unexpected header).
        finishHunk();
      }
      _applyFileMeta(current, rawLine);
    }
    finishFile();
    return UnifiedDiff(files);
  }

  static void _applyFileMeta(_DiffFileBuilder file, String line) {
    if (line.startsWith('--- ')) {
      file.oldPath ??= _stripPrefix(line.substring(4));
      return;
    }
    if (line.startsWith('+++ ')) {
      file.newPath ??= _stripPrefix(line.substring(4));
      return;
    }
    if (line.startsWith('new file mode')) {
      file.status = DiffFileStatus.added;
    } else if (line.startsWith('deleted file mode')) {
      file.status = DiffFileStatus.deleted;
    } else if (line.startsWith('rename from ')) {
      file.status = DiffFileStatus.renamed;
      file.oldPath = line.substring('rename from '.length);
    } else if (line.startsWith('rename to ')) {
      file.status = DiffFileStatus.renamed;
      file.newPath = line.substring('rename to '.length);
    } else if (line.startsWith('copy from ')) {
      file.status = DiffFileStatus.copied;
      file.oldPath = line.substring('copy from '.length);
    } else if (line.startsWith('copy to ')) {
      file.status = DiffFileStatus.copied;
      file.newPath = line.substring('copy to '.length);
    } else if (line.startsWith('Binary files ') ||
        line.startsWith('GIT binary patch')) {
      file.binary = true;
    }
    file.meta.add(line);
  }

  /// `diff --git a/x b/y` → (x, y). Quoted paths (spaces, unicode) keep
  /// their quotes stripped but escapes intact; git only quotes when needed.
  static (String?, String?) _pathsFromHeader(String header) {
    final rest = header.substring('diff --git '.length);
    final match = RegExp(r'^"?a/(.*?)"? "?b/(.*?)"?$').firstMatch(rest);
    if (match == null) {
      return (null, null);
    }
    return (match.group(1), match.group(2));
  }

  static String? _stripPrefix(String path) {
    var value = path;
    final tab = value.indexOf('\t');
    if (tab >= 0) {
      value = value.substring(0, tab);
    }
    if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
      value = value.substring(1, value.length - 1);
    }
    if (value == '/dev/null') {
      return null;
    }
    if (value.startsWith('a/') || value.startsWith('b/')) {
      return value.substring(2);
    }
    return value;
  }

  static Iterable<String> _splitLines(String text) sync* {
    if (text.isEmpty) {
      return;
    }
    var start = 0;
    while (start < text.length) {
      var end = text.indexOf('\n', start);
      if (end < 0) {
        end = text.length;
      }
      var line = text.substring(start, end);
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }
      yield line;
      start = end + 1;
    }
  }
}

enum DiffFileStatus { modified, added, deleted, renamed, copied }

class DiffFile {
  const DiffFile({
    required this.oldPath,
    required this.newPath,
    required this.status,
    required this.hunks,
    this.binary = false,
    this.meta = const [],
  });

  /// Path before the change; null for added files.
  final String? oldPath;

  /// Path after the change; null for deleted files.
  final String? newPath;
  final DiffFileStatus status;
  final List<DiffHunk> hunks;
  final bool binary;

  /// Header lines (`index`, mode changes, …) kept for completeness.
  final List<String> meta;

  /// The path to show and to open: the new path unless the file was deleted.
  String get displayPath => newPath ?? oldPath ?? '(unknown)';

  int get additions => hunks.fold(0, (total, hunk) => total + hunk.additions);
  int get deletions => hunks.fold(0, (total, hunk) => total + hunk.deletions);
}

class DiffHunk {
  const DiffHunk({
    required this.header,
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.lines,
    this.section = '',
  });

  /// The full `@@ … @@` line.
  final String header;
  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;

  /// The function/section context git appends after the second `@@`.
  final String section;
  final List<DiffLine> lines;

  int get additions =>
      lines.where((line) => line.kind == DiffLineKind.addition).length;
  int get deletions =>
      lines.where((line) => line.kind == DiffLineKind.deletion).length;
}

enum DiffLineKind { context, addition, deletion, meta }

class DiffLine {
  const DiffLine({
    required this.kind,
    required this.text,
    this.oldLineNumber,
    this.newLineNumber,
  });

  final DiffLineKind kind;

  /// Line content without the leading `+`, `-` or space.
  final String text;
  final int? oldLineNumber;
  final int? newLineNumber;

  @override
  bool operator ==(Object other) =>
      other is DiffLine &&
      other.kind == kind &&
      other.text == text &&
      other.oldLineNumber == oldLineNumber &&
      other.newLineNumber == newLineNumber;

  @override
  int get hashCode => Object.hash(kind, text, oldLineNumber, newLineNumber);

  @override
  String toString() =>
      'DiffLine(${kind.name}, $oldLineNumber/$newLineNumber, '
      '${text.length > 30 ? '${text.substring(0, 30)}…' : text})';
}

class _DiffFileBuilder {
  _DiffFileBuilder((String?, String?) headerPaths)
    : headerOld = headerPaths.$1,
      headerNew = headerPaths.$2;

  final String? headerOld;
  final String? headerNew;
  String? oldPath;
  String? newPath;
  DiffFileStatus status = DiffFileStatus.modified;
  bool binary = false;
  final List<String> meta = [];
  final List<DiffHunk> hunks = [];

  DiffFile build() {
    final resolvedOld = status == DiffFileStatus.added
        ? null
        : oldPath ?? headerOld;
    final resolvedNew = status == DiffFileStatus.deleted
        ? null
        : newPath ?? headerNew;
    return DiffFile(
      oldPath: resolvedOld,
      newPath: resolvedNew,
      status: status,
      hunks: List.unmodifiable(hunks),
      binary: binary,
      meta: List.unmodifiable(meta),
    );
  }
}

class _DiffHunkBuilder {
  _DiffHunkBuilder({
    required this.header,
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.section,
  }) : oldCursor = oldStart,
       newCursor = newStart;

  static final _headerPattern = RegExp(
    r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@ ?(.*)$',
  );

  factory _DiffHunkBuilder.fromHeader(String header) {
    final match = _headerPattern.firstMatch(header);
    if (match == null) {
      return _DiffHunkBuilder(
        header: header,
        oldStart: 0,
        oldCount: 0,
        newStart: 0,
        newCount: 0,
        section: '',
      );
    }
    return _DiffHunkBuilder(
      header: header,
      oldStart: int.parse(match.group(1)!),
      oldCount: int.tryParse(match.group(2) ?? '') ?? 1,
      newStart: int.parse(match.group(3)!),
      newCount: int.tryParse(match.group(4) ?? '') ?? 1,
      section: match.group(5) ?? '',
    );
  }

  final String header;
  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final String section;
  int oldCursor;
  int newCursor;
  final List<DiffLine> lines = [];

  void add(DiffLine line) => lines.add(line);

  DiffHunk build() => DiffHunk(
    header: header,
    oldStart: oldStart,
    oldCount: oldCount,
    newStart: newStart,
    newCount: newCount,
    section: section,
    lines: List.unmodifiable(lines),
  );
}
