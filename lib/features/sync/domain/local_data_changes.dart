import 'package:flutter/foundation.dart';

/// Announces that this device's saved data was replaced from outside the
/// app's own screens: a backup import or a sync pull. Controllers and pages
/// that cached something from storage at start (trusted host keys, the
/// home page's machine filter, the home boards) listen and reload in place,
/// so the imported machines work without a restart.
class LocalDataChanges extends ChangeNotifier {
  Set<String> _lastKeys = const {};
  int _revision = 0;

  /// Sync record keys (see `SyncKeys`) touched by the last change; empty
  /// when unknown (an old-format backup).
  Set<String> get lastKeys => _lastKeys;

  /// Bumped on every [announce].
  int get revision => _revision;

  /// Tells listeners that [keys] were written. An empty set means "some
  /// data changed" and reloads everything.
  void announce([Set<String> keys = const {}]) {
    _lastKeys = Set.unmodifiable(keys);
    _revision += 1;
    notifyListeners();
  }
}
