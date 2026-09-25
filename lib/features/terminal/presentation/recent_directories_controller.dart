import 'dart:async';

import 'package:conduit/features/terminal/domain/recent_directories.dart';
import 'package:flutter/foundation.dart';

/// The recent-directories lists of every saved host, cached in memory and
/// persisted through [RecentDirectoriesStore].
///
/// Writes are chained so two quick reports (an OSC 7 burst, an agent poll)
/// never interleave their read-modify-write of the shared storage entry.
class RecentDirectoriesController extends ChangeNotifier {
  RecentDirectoriesController(this._store);

  final RecentDirectoriesStore _store;
  final Map<String, List<String>> _cache = {};
  final Map<String, Future<List<String>>> _loading = {};
  Future<void> _writes = Future<void>.value();
  bool _disposed = false;

  /// The cached list for [hostId] (a saved host id), empty until [load].
  List<String> directoriesFor(String hostId) =>
      List.unmodifiable(_cache[hostId] ?? const <String>[]);

  /// Reads [hostId]'s list from storage once and caches it.
  Future<List<String>> load(String hostId) {
    final cached = _cache[hostId];
    if (cached != null) {
      return Future.value(List.unmodifiable(cached));
    }
    return _loading[hostId] ??= _store
        .read(hostId)
        .then((value) {
          _loading.remove(hostId);
          // A record() that finished first already holds the newer list.
          final list = _cache[hostId] ??= [
            for (final directory in value) ?normalizeRecentDirectory(directory),
          ].take(maxRecentDirectories).toList();
          return List<String>.unmodifiable(list);
        })
        .catchError((Object _) {
          _loading.remove(hostId);
          return List<String>.unmodifiable(_cache[hostId] ??= []);
        });
  }

  /// Records [directory] for [hostId]; see [pushRecentDirectory] for
  /// [promote].
  Future<void> record(String hostId, String directory, {bool promote = true}) {
    final completer = Completer<void>();
    _writes = _writes.then((_) async {
      try {
        final current = await load(hostId);
        final updated = pushRecentDirectory(
          current,
          directory,
          promote: promote,
        );
        if (listEquals(updated, current)) {
          return;
        }
        _cache[hostId] = updated;
        if (!_disposed) {
          notifyListeners();
        }
        await _store.write(hostId, updated);
      } catch (_) {
        // Persisting is best effort; the in-memory list still updated.
      } finally {
        completer.complete();
      }
    });
    return completer.future;
  }

  /// Drops [directory] from [hostId]'s list (a stale entry).
  Future<void> remove(String hostId, String directory) {
    final completer = Completer<void>();
    _writes = _writes.then((_) async {
      try {
        final current = await load(hostId);
        final updated = [
          for (final existing in current)
            if (existing != directory) existing,
        ];
        if (updated.length == current.length) {
          return;
        }
        _cache[hostId] = updated;
        if (!_disposed) {
          notifyListeners();
        }
        await _store.write(hostId, updated);
      } catch (_) {
        // Best effort, as above.
      } finally {
        completer.complete();
      }
    });
    return completer.future;
  }

  /// Replaces [hostId]'s list with one from another device (sync); an
  /// empty list forgets it.
  Future<void> replace(String hostId, List<String> directories) {
    final completer = Completer<void>();
    _writes = _writes.then((_) async {
      try {
        final updated = [
          for (final directory in directories)
            ?normalizeRecentDirectory(directory),
        ].take(maxRecentDirectories).toList();
        _cache[hostId] = updated;
        if (!_disposed) {
          notifyListeners();
        }
        await _store.write(hostId, updated);
      } catch (_) {
        // Best effort, as above.
      } finally {
        completer.complete();
      }
    });
    return completer.future;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
