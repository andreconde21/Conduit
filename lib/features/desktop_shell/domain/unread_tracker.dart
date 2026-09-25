import 'dart:math' as math;

import 'package:conduit/features/agent_attention/domain/agent_attention.dart';

/// Which rows of the sidebar have news the user has not looked at yet.
///
/// Everything is keyed by sidebar node key (see `sidebar_tree.dart`) and
/// measured in "activity marks": milliseconds since the epoch, only ever
/// increasing per key. A row is unread when its latest activity is newer
/// than what the user saw, or when the user marked it unread.
///
/// Sources call [observe] with the time something happened (tmux's
/// `session_activity`, a terminal's output) or [observeState] with a
/// signature that changes when something happened (an agent's state). The
/// first observation of a key is a baseline: rows that already existed
/// when the app met them are not news.
///
/// Rows on screen ([setViewed]) are read: whatever happens there while
/// they are shown is seen as it happens. The state survives restarts
/// ([toJson]), so an agent that finished while the app was closed is
/// unread on the next start.
class UnreadTracker {
  UnreadTracker({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// Latest activity per key.
  final Map<String, int> _activity = {};

  /// Activity the user has seen per key.
  final Map<String, int> _seen = {};

  /// The last state signature per key ([observeState]).
  final Map<String, String> _signatures = {};

  /// Marked unread by hand ("Mark as unread").
  final Set<String> _manual = {};

  /// Key prefixes on screen now.
  Set<String> _viewed = const {};

  /// Entries older than this are dropped when saving.
  static const retention = Duration(days: 21);

  /// At most this many keys are kept (the most recent).
  static const maxEntries = 2000;

  int _now() => _clock().millisecondsSinceEpoch;

  bool isUnread(String key) =>
      _manual.contains(key) || (_activity[key] ?? 0) > (_seen[key] ?? 0);

  /// Whether [key] or anything under it is on screen.
  bool isViewed(String key) => _viewed.any((prefix) => _covers(prefix, key));

  static bool _covers(String prefix, String key) =>
      key == prefix || key.startsWith('$prefix/');

  /// Records activity at [mark] (epoch milliseconds) for [key]. Returns
  /// whether anything changed.
  bool observe(String key, int mark) {
    final known = _activity[key];
    if (known == null && !_seen.containsKey(key)) {
      // First sight: a baseline, not news.
      _activity[key] = mark;
      _seen[key] = mark;
      return false;
    }
    if (known != null && mark <= known) return false;
    _activity[key] = mark;
    if (isViewed(key)) {
      _seen[key] = mark;
      _manual.remove(key);
      return false;
    }
    return true;
  }

  /// Records [signature] for [key]; a different signature than last time is
  /// activity now, unless [news] is false (the change is not worth a bold
  /// row, like an agent starting to work). Returns whether the row became
  /// unread.
  bool observeState(String key, String signature, {bool news = true}) {
    final previous = _signatures[key];
    _signatures[key] = signature;
    if (previous == null) {
      if (!_activity.containsKey(key)) {
        final now = _now();
        _activity[key] = now;
        _seen[key] = now;
      }
      return false;
    }
    if (previous == signature || !news) return false;
    final mark = math.max(_now(), (_activity[key] ?? 0) + 1);
    return observe(key, mark);
  }

  /// The rows on screen: [prefixes] and everything under them are read now
  /// and stay read while they are shown.
  bool setViewed(Set<String> prefixes) {
    _viewed = prefixes;
    var changed = false;
    for (final key in {..._activity.keys, ..._manual}) {
      if (!isViewed(key)) continue;
      changed = _markRead(key) || changed;
    }
    return changed;
  }

  /// "Mark as read": [key] and every key under it.
  bool markRead(String key) {
    var changed = false;
    for (final other in {..._activity.keys, ..._manual}) {
      if (_covers(key, other)) changed = _markRead(other) || changed;
    }
    return changed;
  }

  bool _markRead(String key) {
    final activity = _activity[key];
    final wasUnread = isUnread(key);
    if (activity != null) _seen[key] = activity;
    _manual.remove(key);
    return wasUnread;
  }

  /// "Mark as unread".
  bool markUnread(String key) => _manual.add(key);

  /// Keys unread now (for tests and the next-unread search).
  Set<String> get unreadKeys => {
    for (final key in _activity.keys)
      if (isUnread(key)) key,
    ..._manual,
  };

  Map<String, Object?> toJson() {
    final cutoff = _now() - retention.inMilliseconds;
    final keys =
        _activity.entries
            .where(
              (entry) => entry.value >= cutoff || _manual.contains(entry.key),
            )
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final kept = keys.take(maxEntries).map((entry) => entry.key).toSet();
    return {
      'activity': {for (final key in kept) key: _activity[key]},
      'seen': {
        for (final key in kept)
          if (_seen[key] != null) key: _seen[key],
      },
      'signatures': {
        for (final key in kept)
          if (_signatures[key] != null) key: _signatures[key],
      },
      'manual': [..._manual],
    };
  }

  /// Restores [toJson]'s state (replacing what is tracked).
  void load(Object? json) {
    _activity.clear();
    _seen.clear();
    _signatures.clear();
    _manual.clear();
    if (json is! Map) return;
    void ints(Object? raw, Map<String, int> into) {
      if (raw is! Map) return;
      for (final MapEntry(:key, :value) in raw.entries) {
        if (key is String && value is num) into[key] = value.toInt();
      }
    }

    ints(json['activity'], _activity);
    ints(json['seen'], _seen);
    final signatures = json['signatures'];
    if (signatures is Map) {
      for (final MapEntry(:key, :value) in signatures.entries) {
        if (key is String && value is String) _signatures[key] = value;
      }
    }
    final manual = json['manual'];
    if (manual is List) {
      _manual.addAll(manual.whereType<String>());
    }
  }
}

/// Whether an agent moving to [state] is news for the unread markers: it
/// finished, went idle, or needs the user. Starting to work is not.
bool agentStateIsNews(AgentAttentionState state) =>
    state != AgentAttentionState.working &&
    state != AgentAttentionState.unknown;
