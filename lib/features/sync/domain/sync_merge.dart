import 'package:conduit/features/sync/domain/canonical_json.dart';
import 'package:conduit/features/sync/domain/sync_category.dart';
import 'package:conduit/features/sync/domain/sync_record.dart';
import 'package:flutter/foundation.dart';

/// What this device knew about one record after its last sync: the record
/// as merged, and the hash of the local value it was applied as (null when
/// it was never applied here, for instance while its category was off).
///
/// Comparing today's local value with [localHash] (not with the record)
/// tells a real local edit apart from a value the app stores differently,
/// like a hub machine whose login stays on each device.
@immutable
class SyncBaseEntry {
  const SyncBaseEntry({required this.record, this.localHash});

  final SyncRecord record;
  final String? localHash;

  Map<String, Object?> toJson() => {
    'r': record.toJson(),
    if (localHash != null) 'h': localHash,
  };

  static SyncBaseEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final record = SyncRecord.fromJson(json['r']);
    if (record == null) return null;
    final hash = json['h'];
    return SyncBaseEntry(
      record: record,
      localHash: hash is String ? hash : null,
    );
  }
}

enum SyncConflictKind {
  /// Both this device and another one changed the item since the last sync.
  concurrentEdit,

  /// This device's own copy met the hub's at its first sync.
  firstSync,
}

/// An item both sides changed; the newer edit won and the other value is
/// kept here so it can be looked at or restored.
@immutable
class SyncConflict {
  const SyncConflict({
    required this.key,
    required this.kind,
    required this.keptLocal,
    required this.localValue,
    required this.remoteValue,
    required this.remoteDevice,
  });

  final String key;
  final SyncConflictKind kind;

  /// True when this device's edit won.
  final bool keptLocal;
  final Object? localValue;
  final Object? remoteValue;
  final String remoteDevice;

  /// The value that lost, which "Keep mine" puts back for a local loss.
  Object? get lostValue => keptLocal ? remoteValue : localValue;
}

@immutable
class SyncMergeResult {
  const SyncMergeResult({
    required this.merged,
    required this.toApply,
    required this.pushNeeded,
    required this.conflicts,
    required this.localEdits,
    required this.counter,
  });

  /// Every record after the merge: what the hub should hold.
  final Map<String, SyncRecord> merged;

  /// Local changes to make: key to new value, null to delete. Only keys of
  /// enabled categories.
  final Map<String, Object?> toApply;

  /// Whether [merged] differs from what the hub holds.
  final bool pushNeeded;
  final List<SyncConflict> conflicts;

  /// Keys this device changed since its last sync.
  final Set<String> localEdits;

  /// The highest Lamport counter seen; persist it for the next merge.
  final int counter;
}

/// Three-way merge of this device's data with the hub's.
///
/// 1. Local change detection: every key of an enabled category whose
///    local value hash differs from [base] becomes a new record stamped
///    now; a key that was applied here and is gone becomes a tombstone.
/// 2. Per-record last-writer-wins against [remote] (null when the hub has
///    no data yet) on [SyncClock]. A key edited on both sides since the
///    base is reported as a conflict; the losing value is kept in it.
/// 3. Keys where the winner differs from the local value are returned in
///    [SyncMergeResult.toApply].
///
/// Records of disabled or unknown categories pass through untouched, so a
/// device never drops what it does not show.
///
/// A category syncing for the first time on this device ([initialized]
/// lacks it) while the hub has data stamps the local copies with
/// [SyncClock.unknown]: the hub's version wins on overlap, and the local
/// one is kept in a [SyncConflictKind.firstSync] conflict.
SyncMergeResult mergeSync({
  required Map<String, SyncBaseEntry> base,
  required Map<String, Object?> local,
  required Set<SyncCategory> enabled,
  required Set<SyncCategory> initialized,
  required Map<String, SyncRecord>? remote,
  required String deviceId,
  required int now,
  required int counter,
  Duration tombstoneLifetime = const Duration(days: 180),
}) {
  var lamport = counter;
  for (final entry in base.values) {
    if (entry.record.clock.counter > lamport) {
      lamport = entry.record.clock.counter;
    }
  }
  for (final record in remote?.values ?? const <SyncRecord>[]) {
    if (record.clock.counter > lamport) lamport = record.clock.counter;
  }

  bool isEnabled(String key) {
    final category = SyncCategory.ofKey(key);
    return category != null && enabled.contains(category);
  }

  SyncClock stamp(String key) {
    lamport += 1;
    final previous = base[key]?.record.clock.time ?? 0;
    return SyncClock(
      // An edit always beats the version it replaces, even when this
      // device's clock went backwards since.
      time: now > previous ? now : previous + 1,
      counter: lamport,
      device: deviceId,
    );
  }

  // 1. This device's records.
  final localRecords = <String, SyncRecord>{};
  final localEdits = <String>{};
  final unknownAge = <String>{};
  for (final key in {...base.keys, ...local.keys}) {
    final baseEntry = base[key];
    if (!isEnabled(key)) {
      if (baseEntry != null) localRecords[key] = baseEntry.record;
      continue;
    }
    final category = SyncCategory.ofKey(key)!;
    final hasLocal = local.containsKey(key) && local[key] != null;
    if (hasLocal) {
      final value = local[key];
      final hash = valueHash(value);
      if (baseEntry != null && baseEntry.localHash == hash) {
        localRecords[key] = baseEntry.record;
        continue;
      }
      final firstSight = baseEntry == null
          ? remote != null && !initialized.contains(category)
          : baseEntry.localHash == null;
      if (firstSight) {
        unknownAge.add(key);
        final unknown = SyncRecord(
          key: key,
          value: value,
          clock: SyncClock.unknown,
        );
        localRecords[key] = baseEntry == null
            ? unknown
            : SyncRecord.newer(baseEntry.record, unknown);
        continue;
      }
      localEdits.add(key);
      localRecords[key] = SyncRecord(key: key, value: value, clock: stamp(key));
    } else if (baseEntry != null) {
      if (!baseEntry.record.deleted && baseEntry.localHash != null) {
        localEdits.add(key);
        localRecords[key] = SyncRecord(
          key: key,
          value: null,
          clock: stamp(key),
        );
      } else {
        localRecords[key] = baseEntry.record;
      }
    }
  }

  // 2. Last-writer-wins against the hub.
  final merged = <String, SyncRecord>{};
  final conflicts = <SyncConflict>[];
  final remoteRecords = remote ?? const <String, SyncRecord>{};
  for (final key in {...localRecords.keys, ...remoteRecords.keys}) {
    final mine = localRecords[key];
    final theirs = remoteRecords[key];
    if (mine == null) {
      merged[key] = theirs!;
      continue;
    }
    if (theirs == null) {
      merged[key] = mine;
      continue;
    }
    final winner = SyncRecord.newer(mine, theirs);
    merged[key] = winner;
    final differs = mine.hash != theirs.hash;
    if (!differs) continue;
    if (localEdits.contains(key) && theirs.clock != base[key]?.record.clock) {
      conflicts.add(
        SyncConflict(
          key: key,
          kind: SyncConflictKind.concurrentEdit,
          keptLocal: identical(winner, mine),
          localValue: mine.value,
          remoteValue: theirs.value,
          remoteDevice: theirs.clock.device,
        ),
      );
    } else if (unknownAge.contains(key) && !identical(winner, mine)) {
      conflicts.add(
        SyncConflict(
          key: key,
          kind: SyncConflictKind.firstSync,
          keptLocal: false,
          localValue: mine.value,
          remoteValue: theirs.value,
          remoteDevice: theirs.clock.device,
        ),
      );
    }
  }

  // Old tombstones go; a device offline longer than this may bring the
  // item back, which beats keeping every delete forever.
  final oldest = now - tombstoneLifetime.inMilliseconds;
  merged.removeWhere(
    (_, record) =>
        record.deleted && record.clock.time > 0 && record.clock.time < oldest,
  );

  // 3. What changes here.
  final toApply = <String, Object?>{};
  for (final key in {...merged.keys, ...local.keys}) {
    if (!isEnabled(key)) continue;
    final record = merged[key];
    final localValue = local[key];
    if (record == null || record.deleted) {
      if (localValue != null) toApply[key] = null;
    } else if (record.hash != valueHash(localValue)) {
      toApply[key] = record.value;
    }
  }

  var pushNeeded = remote == null;
  if (!pushNeeded) {
    for (final entry in merged.entries) {
      final theirs = remoteRecords[entry.key];
      if (theirs == null ||
          theirs.clock != entry.value.clock ||
          theirs.hash != entry.value.hash) {
        pushNeeded = true;
        break;
      }
    }
    if (!pushNeeded) {
      pushNeeded = remoteRecords.keys.any((key) => !merged.containsKey(key));
    }
  }

  return SyncMergeResult(
    merged: merged,
    toApply: toApply,
    pushNeeded: pushNeeded,
    conflicts: conflicts,
    localEdits: localEdits,
    counter: lamport,
  );
}
