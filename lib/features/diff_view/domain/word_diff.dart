import 'package:conduit/features/diff_view/domain/unified_diff.dart';

/// A run of characters inside a diff line, flagged when it differs from the
/// paired line on the other side of the change.
class WordDiffSpan {
  const WordDiffSpan(this.text, {this.changed = false});

  final String text;
  final bool changed;

  @override
  bool operator ==(Object other) =>
      other is WordDiffSpan && other.text == text && other.changed == changed;

  @override
  int get hashCode => Object.hash(text, changed);

  @override
  String toString() => changed ? '[$text]' : text;
}

/// Lines longer than this are not word-diffed: the O(n·m) token alignment
/// would be wasted on minified assets and the highlight would not help.
const wordDiffMaxLineLength = 1000;

/// Word-level highlights for the deletion/addition pairs of [hunk].
///
/// Inside a hunk, git prints a block of `-` lines followed by a block of `+`
/// lines for each change; the i-th deletion is paired with the i-th addition
/// of the same block. Returns spans keyed by the line's index in
/// `hunk.lines`; lines without a pair are absent and render plain.
Map<int, List<WordDiffSpan>> wordDiffHunk(DiffHunk hunk) {
  final result = <int, List<WordDiffSpan>>{};
  final lines = hunk.lines;
  var index = 0;
  while (index < lines.length) {
    if (lines[index].kind != DiffLineKind.deletion) {
      index++;
      continue;
    }
    final deletions = <int>[];
    while (index < lines.length &&
        lines[index].kind == DiffLineKind.deletion) {
      deletions.add(index++);
    }
    final additions = <int>[];
    while (index < lines.length &&
        lines[index].kind == DiffLineKind.addition) {
      additions.add(index++);
    }
    final pairs = deletions.length < additions.length
        ? deletions.length
        : additions.length;
    for (var pair = 0; pair < pairs; pair++) {
      final old = lines[deletions[pair]].text;
      final fresh = lines[additions[pair]].text;
      if (old.length > wordDiffMaxLineLength ||
          fresh.length > wordDiffMaxLineLength) {
        continue;
      }
      final (oldSpans, newSpans) = wordDiffPair(old, fresh);
      result[deletions[pair]] = oldSpans;
      result[additions[pair]] = newSpans;
    }
  }
  return result;
}

/// Aligns [oldText] and [newText] token by token (words, runs of spaces,
/// single punctuation characters) and marks the tokens that only appear on
/// one side.
(List<WordDiffSpan>, List<WordDiffSpan>) wordDiffPair(
  String oldText,
  String newText,
) {
  final oldTokens = tokenizeForWordDiff(oldText);
  final newTokens = tokenizeForWordDiff(newText);
  final matched = _longestCommonSubsequence(oldTokens, newTokens);
  return (
    _spansFor(oldTokens, matched.map((pair) => pair.$1).toSet()),
    _spansFor(newTokens, matched.map((pair) => pair.$2).toSet()),
  );
}

final _tokenPattern = RegExp(r'[A-Za-z0-9_]+|\s+|.', dotAll: true);

List<String> tokenizeForWordDiff(String text) =>
    _tokenPattern.allMatches(text).map((match) => match.group(0)!).toList();

List<WordDiffSpan> _spansFor(List<String> tokens, Set<int> unchanged) {
  final spans = <WordDiffSpan>[];
  final buffer = StringBuffer();
  bool? bufferChanged;
  for (var index = 0; index < tokens.length; index++) {
    final changed = !unchanged.contains(index);
    if (bufferChanged != null && bufferChanged != changed) {
      spans.add(WordDiffSpan(buffer.toString(), changed: bufferChanged));
      buffer.clear();
    }
    bufferChanged = changed;
    buffer.write(tokens[index]);
  }
  if (buffer.isNotEmpty) {
    spans.add(WordDiffSpan(buffer.toString(), changed: bufferChanged!));
  }
  return spans;
}

/// Classic dynamic-programming LCS returning the matched index pairs.
List<(int, int)> _longestCommonSubsequence(List<String> a, List<String> b) {
  final rows = a.length + 1;
  final cols = b.length + 1;
  final table = List.generate(rows, (_) => List<int>.filled(cols, 0));
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      table[i][j] = a[i] == b[j]
          ? table[i + 1][j + 1] + 1
          : (table[i + 1][j] > table[i][j + 1]
                ? table[i + 1][j]
                : table[i][j + 1]);
    }
  }
  final pairs = <(int, int)>[];
  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      pairs.add((i, j));
      i++;
      j++;
    } else if (table[i + 1][j] >= table[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return pairs;
}
