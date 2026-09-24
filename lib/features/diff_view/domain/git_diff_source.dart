import 'package:conduit/features/diff_view/domain/git_status.dart';
import 'package:conduit/features/diff_view/domain/unified_diff.dart';

/// Unified diffs above this size are cut on the host before download; the
/// view shows a notice instead of choking the phone on a generated-file
/// churn.
const gitDiffMaxBytes = 2 * 1024 * 1024;

/// One fetch of a working directory's git state.
class GitDiffSnapshot {
  const GitDiffSnapshot({
    required this.path,
    required this.repositoryRoot,
    this.status,
    this.unstaged = const UnifiedDiff([]),
    this.staged = const UnifiedDiff([]),
    this.unstagedTruncated = false,
    this.stagedTruncated = false,
  });

  /// The directory the diff was requested for, as typed by the user.
  final String path;

  /// Absolute path of the repository containing [path]; null when [path] is
  /// not inside a git work tree.
  final String? repositoryRoot;
  final GitStatus? status;
  final UnifiedDiff unstaged;
  final UnifiedDiff staged;
  final bool unstagedTruncated;
  final bool stagedTruncated;

  bool get isGitRepository => repositoryRoot != null;
}

/// Reads git diffs for a host without touching the interactive terminal.
abstract class GitDiffSource {
  /// Best guess of the directory the user's shell or agent is working in.
  Future<String> detectWorkingDirectory();

  Future<GitDiffSnapshot> load(String path);

  /// Releases any underlying connection. The source must not be used after.
  Future<void> close();
}
