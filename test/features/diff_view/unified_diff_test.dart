import 'dart:io';

import 'package:conduit/features/diff_view/domain/unified_diff.dart';
import 'package:flutter_test/flutter_test.dart';

String fixture(String name) =>
    File('test/features/diff_view/fixtures/$name').readAsStringSync();

void main() {
  group('UnifiedDiff.parse', () {
    late UnifiedDiff diff;

    setUp(() => diff = UnifiedDiff.parse(fixture('sample.diff')));

    test('splits files and keeps their order', () {
      expect(diff.files.map((file) => file.displayPath), [
        'lib/app.dart',
        'README.md',
        'old.txt',
        'docs/b.md',
        'assets/logo.png',
        r'sp ace/f\303\274.txt',
      ]);
    });

    test('parses hunks with line numbers on both sides', () {
      final app = diff.files.first;
      expect(app.status, DiffFileStatus.modified);
      expect(app.hunks, hasLength(2));
      final first = app.hunks.first;
      expect(first.oldStart, 1);
      expect(first.oldCount, 6);
      expect(first.newStart, 1);
      expect(first.newCount, 7);
      expect(first.section, 'class App {');
      expect(first.lines, [
        const DiffLine(
          kind: DiffLineKind.context,
          text: "import 'a.dart';",
          oldLineNumber: 1,
          newLineNumber: 1,
        ),
        const DiffLine(
          kind: DiffLineKind.deletion,
          text: "import 'b.dart';",
          oldLineNumber: 2,
        ),
        const DiffLine(
          kind: DiffLineKind.addition,
          text: "import 'b.dart';",
          newLineNumber: 2,
        ),
        const DiffLine(
          kind: DiffLineKind.addition,
          text: "import 'c.dart';",
          newLineNumber: 3,
        ),
        const DiffLine(
          kind: DiffLineKind.context,
          text: '',
          oldLineNumber: 3,
          newLineNumber: 4,
        ),
        const DiffLine(
          kind: DiffLineKind.context,
          text: 'void main() {',
          oldLineNumber: 4,
          newLineNumber: 5,
        ),
        const DiffLine(
          kind: DiffLineKind.deletion,
          text: "  runApp(const App(title: 'Old'));",
          oldLineNumber: 5,
        ),
        const DiffLine(
          kind: DiffLineKind.addition,
          text: "  runApp(const App(title: 'New'));",
          newLineNumber: 6,
        ),
        const DiffLine(
          kind: DiffLineKind.context,
          text: '}',
          oldLineNumber: 6,
          newLineNumber: 7,
        ),
      ]);
      expect(app.hunks.last.oldStart, 20);
      expect(app.hunks.last.newStart, 21);
      expect(app.additions, 4);
      expect(app.deletions, 2);
    });

    test('recognises added files and the no-newline marker', () {
      final readme = diff.files[1];
      expect(readme.status, DiffFileStatus.added);
      expect(readme.oldPath, isNull);
      expect(readme.newPath, 'README.md');
      expect(readme.hunks.single.lines.last.kind, DiffLineKind.meta);
      expect(readme.hunks.single.lines.last.text, startsWith(r'\ No newline'));
      expect(readme.additions, 2);
    });

    test('recognises deleted files', () {
      final old = diff.files[2];
      expect(old.status, DiffFileStatus.deleted);
      expect(old.newPath, isNull);
      expect(old.oldPath, 'old.txt');
      expect(old.displayPath, 'old.txt');
      expect(old.deletions, 1);
    });

    test('recognises pure renames without hunks', () {
      final renamed = diff.files[3];
      expect(renamed.status, DiffFileStatus.renamed);
      expect(renamed.oldPath, 'docs/a.md');
      expect(renamed.newPath, 'docs/b.md');
      expect(renamed.hunks, isEmpty);
    });

    test('flags binary files', () {
      final logo = diff.files[4];
      expect(logo.binary, isTrue);
      expect(logo.hunks, isEmpty);
      expect(logo.meta, contains(startsWith('Binary files')));
    });

    test('handles quoted paths', () {
      final quoted = diff.files.last;
      expect(quoted.newPath, r'sp ace/f\303\274.txt');
      expect(quoted.hunks.single.lines, hasLength(2));
    });

    test('totals additions and deletions across files', () {
      expect(diff.additions, 4 + 2 + 0 + 0 + 0 + 1);
      expect(diff.deletions, 2 + 0 + 1 + 0 + 0 + 1);
    });

    test('empty input yields no files', () {
      expect(UnifiedDiff.parse('').isEmpty, isTrue);
      expect(UnifiedDiff.parse('\n').isEmpty, isTrue);
    });

    test('tolerates CRLF and a single-line hunk header', () {
      final parsed = UnifiedDiff.parse(
        'diff --git a/x b/x\r\n--- a/x\r\n+++ b/x\r\n@@ -1 +1 @@\r\n-a\r\n+b\r\n',
      );
      final hunk = parsed.files.single.hunks.single;
      expect(hunk.oldCount, 1);
      expect(hunk.newCount, 1);
      expect(hunk.lines.map((line) => line.text), ['a', 'b']);
    });

    test('keeps text that precedes the first header visible', () {
      final parsed = UnifiedDiff.parse('warning: something\n');
      expect(parsed.files.single.meta, ['warning: something']);
      expect(parsed.files.single.displayPath, '(unknown)');
    });
  });
}
