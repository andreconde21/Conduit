import 'dart:async';

import 'package:conduit/core/app_failure.dart';
import 'package:conduit/features/diff_view/domain/git_diff_source.dart';
import 'package:conduit/features/diff_view/domain/unified_diff.dart';
import 'package:flutter/foundation.dart';

enum DiffViewPhase { idle, loading, ready, failed }

/// State for one Git diff tab: the directory being diffed, the latest
/// snapshot, and which of the two diffs (working tree or index) is shown.
class DiffViewController extends ChangeNotifier {
  DiffViewController(this._source, {String? initialPath})
    : _path = initialPath ?? '';

  final GitDiffSource _source;

  String _path;
  DiffViewPhase _phase = DiffViewPhase.idle;
  GitDiffSnapshot? _snapshot;
  String? _error;
  bool _showStaged = false;
  final Set<String> _collapsed = {};
  bool _disposed = false;
  int _generation = 0;
  int _collapseRevision = 0;

  String get path => _path;
  DiffViewPhase get phase => _phase;
  GitDiffSnapshot? get snapshot => _snapshot;
  String? get error => _error;
  bool get showStaged => _showStaged;
  bool get isLoading => _phase == DiffViewPhase.loading;

  /// The diff currently selected by the staged/unstaged toggle.
  UnifiedDiff? get diff {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return null;
    }
    return _showStaged ? snapshot.staged : snapshot.unstaged;
  }

  bool get diffTruncated {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return false;
    }
    return _showStaged
        ? snapshot.stagedTruncated
        : snapshot.unstagedTruncated;
  }

  bool isCollapsed(DiffFile file) => _collapsed.contains(_fileKey(file));

  /// Bumped whenever the collapsed set changes, so views can cache derived
  /// layouts keyed on it.
  int get collapseRevision => _collapseRevision;

  void toggleCollapsed(DiffFile file) {
    final key = _fileKey(file);
    if (!_collapsed.remove(key)) {
      _collapsed.add(key);
    }
    _collapseRevision++;
    notifyListeners();
  }

  void setShowStaged(bool staged) {
    if (_showStaged == staged) {
      return;
    }
    _showStaged = staged;
    notifyListeners();
  }

  /// Absolute path of [file] on the host, for opening it in a file tab.
  String? absolutePathFor(DiffFile file) {
    final root = _snapshot?.repositoryRoot;
    final relative = file.newPath ?? file.oldPath;
    if (root == null || relative == null) {
      return null;
    }
    return root.endsWith('/') ? '$root$relative' : '$root/$relative';
  }

  /// Detects the working directory (when none is set yet) and loads it.
  Future<void> start() async {
    if (_path.trim().isEmpty) {
      _setLoading();
      try {
        _path = await _source.detectWorkingDirectory();
      } catch (error) {
        _fail(error);
        return;
      }
    }
    await refresh();
  }

  Future<void> refresh() => load(_path);

  Future<void> load(String path) async {
    final generation = ++_generation;
    _path = path;
    _setLoading();
    try {
      final snapshot = await _source.load(path);
      if (_disposed || generation != _generation) {
        return;
      }
      _snapshot = snapshot;
      _error = null;
      _phase = DiffViewPhase.ready;
      notifyListeners();
    } catch (error) {
      if (_disposed || generation != _generation) {
        return;
      }
      _fail(error);
    }
  }

  void _setLoading() {
    _phase = DiffViewPhase.loading;
    _error = null;
    notifyListeners();
  }

  void _fail(Object error) {
    _phase = DiffViewPhase.failed;
    _error = error is AppFailure ? error.userMessage : error.toString();
    notifyListeners();
  }

  String _fileKey(DiffFile file) =>
      '${_showStaged ? 's' : 'u'}:${file.oldPath}→${file.newPath}';

  @override
  void dispose() {
    _disposed = true;
    unawaited(_source.close());
    super.dispose();
  }
}
