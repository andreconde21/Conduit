/// Parsed `git status --porcelain=v2 --branch` output.
class GitStatus {
  const GitStatus({
    this.branch,
    this.upstream,
    this.ahead = 0,
    this.behind = 0,
    this.detached = false,
    this.entries = const [],
  });

  /// Current branch name; null when detached or on an unborn branch.
  final String? branch;
  final String? upstream;
  final int ahead;
  final int behind;
  final bool detached;
  final List<GitStatusEntry> entries;

  int get stagedCount => entries.where((entry) => entry.isStaged).length;
  int get unstagedCount => entries.where((entry) => entry.isUnstaged).length;
  int get untrackedCount => entries
      .where((entry) => entry.kind == GitStatusEntryKind.untracked)
      .length;
  int get conflictedCount => entries
      .where((entry) => entry.kind == GitStatusEntryKind.unmerged)
      .length;

  bool get isClean => entries.isEmpty;

  static GitStatus parse(String text) {
    String? branch;
    String? upstream;
    var ahead = 0;
    var behind = 0;
    var detached = false;
    final entries = <GitStatusEntry>[];
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trimRight();
      if (line.isEmpty) {
        continue;
      }
      if (line.startsWith('# ')) {
        final parts = line.substring(2).split(' ');
        switch (parts.first) {
          case 'branch.head':
            final value = parts.skip(1).join(' ');
            if (value == '(detached)') {
              detached = true;
            } else if (value != '(unknown)') {
              branch = value;
            }
          case 'branch.upstream':
            upstream = parts.skip(1).join(' ');
          case 'branch.ab':
            for (final token in parts.skip(1)) {
              if (token.startsWith('+')) {
                ahead = int.tryParse(token.substring(1)) ?? 0;
              } else if (token.startsWith('-')) {
                behind = int.tryParse(token.substring(1)) ?? 0;
              }
            }
        }
        continue;
      }
      final entry = GitStatusEntry.parseLine(line);
      if (entry != null) {
        entries.add(entry);
      }
    }
    return GitStatus(
      branch: branch,
      upstream: upstream,
      ahead: ahead,
      behind: behind,
      detached: detached,
      entries: List.unmodifiable(entries),
    );
  }
}

enum GitStatusEntryKind { changed, renamed, unmerged, untracked, ignored }

class GitStatusEntry {
  const GitStatusEntry({
    required this.kind,
    required this.path,
    this.originalPath,
    this.indexStatus = '.',
    this.workTreeStatus = '.',
  });

  final GitStatusEntryKind kind;
  final String path;

  /// For renames and copies, the path before the change.
  final String? originalPath;

  /// `X` of the porcelain `XY` pair: the staged change, `.` for none.
  final String indexStatus;

  /// `Y` of the porcelain `XY` pair: the unstaged change, `.` for none.
  final String workTreeStatus;

  bool get isStaged =>
      (kind == GitStatusEntryKind.changed ||
          kind == GitStatusEntryKind.renamed) &&
      indexStatus != '.';
  bool get isUnstaged =>
      (kind == GitStatusEntryKind.changed ||
          kind == GitStatusEntryKind.renamed) &&
      workTreeStatus != '.';

  static GitStatusEntry? parseLine(String line) {
    final type = line.isEmpty ? '' : line[0];
    switch (type) {
      case '1':
        // 1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>
        final fields = line.split(' ');
        if (fields.length < 9) {
          return null;
        }
        return GitStatusEntry(
          kind: GitStatusEntryKind.changed,
          indexStatus: fields[1][0],
          workTreeStatus: fields[1][1],
          path: fields.sublist(8).join(' '),
        );
      case '2':
        // 2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <X><score> <path><tab><origPath>
        final fields = line.split(' ');
        if (fields.length < 10) {
          return null;
        }
        final paths = fields.sublist(9).join(' ').split('\t');
        return GitStatusEntry(
          kind: GitStatusEntryKind.renamed,
          indexStatus: fields[1][0],
          workTreeStatus: fields[1][1],
          path: paths.first,
          originalPath: paths.length > 1 ? paths[1] : null,
        );
      case 'u':
        // u <XY> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>
        final fields = line.split(' ');
        if (fields.length < 11) {
          return null;
        }
        return GitStatusEntry(
          kind: GitStatusEntryKind.unmerged,
          indexStatus: fields[1][0],
          workTreeStatus: fields[1][1],
          path: fields.sublist(10).join(' '),
        );
      case '?':
        return GitStatusEntry(
          kind: GitStatusEntryKind.untracked,
          path: line.substring(2),
        );
      case '!':
        return GitStatusEntry(
          kind: GitStatusEntryKind.ignored,
          path: line.substring(2),
        );
    }
    return null;
  }
}
