import 'package:conduit/features/sync/domain/canonical_json.dart';
import 'package:conduit/features/sync/domain/sync_category.dart';
import 'package:flutter/foundation.dart';

/// When a record was last written and by whom: wall-clock milliseconds,
/// then a Lamport counter, then the device id, compared in that order.
///
/// The counter breaks ties between devices whose clocks agree to the
/// millisecond and orders edits from a device whose clock went backwards.
/// Time 0 marks a record whose age is unknown (a device's own data at its
/// first sync against an existing hub), which loses to any real edit.
@immutable
class SyncClock implements Comparable<SyncClock> {
  const SyncClock({
    required this.time,
    required this.counter,
    required this.device,
  });

  static const unknown = SyncClock(time: 0, counter: 0, device: '');

  final int time;
  final int counter;
  final String device;

  @override
  int compareTo(SyncClock other) {
    final byTime = time.compareTo(other.time);
    if (byTime != 0) return byTime;
    final byCounter = counter.compareTo(other.counter);
    if (byCounter != 0) return byCounter;
    return device.compareTo(other.device);
  }

  @override
  bool operator ==(Object other) =>
      other is SyncClock &&
      other.time == time &&
      other.counter == counter &&
      other.device == device;

  @override
  int get hashCode => Object.hash(time, counter, device);

  @override
  String toString() => 'SyncClock($time, $counter, $device)';
}

/// One synced item: a saved machine, a setting, a snippet… A null [value]
/// is a tombstone, kept so a delete wins over an older copy elsewhere.
@immutable
class SyncRecord {
  const SyncRecord({
    required this.key,
    required this.value,
    required this.clock,
  });

  final String key;
  final Object? value;
  final SyncClock clock;

  bool get deleted => value == null;

  SyncCategory? get category => SyncCategory.ofKey(key);

  String? get hash => valueHash(value);

  Map<String, Object?> toJson() => {
    'k': key,
    if (value != null) 'v': value,
    't': clock.time,
    'c': clock.counter,
    'd': clock.device,
  };

  static SyncRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final key = json['k'];
    final time = json['t'];
    final counter = json['c'];
    final device = json['d'];
    if (key is! String || key.isEmpty || time is! int || counter is! int) {
      return null;
    }
    return SyncRecord(
      key: key,
      value: json['v'],
      clock: SyncClock(
        time: time,
        counter: counter,
        device: device is String ? device : '',
      ),
    );
  }

  /// The newer of [a] and [b]; equal clocks fall back to the value hash so
  /// every device picks the same one.
  static SyncRecord newer(SyncRecord a, SyncRecord b) {
    final byClock = a.clock.compareTo(b.clock);
    if (byClock != 0) return byClock > 0 ? a : b;
    return (a.hash ?? '').compareTo(b.hash ?? '') >= 0 ? a : b;
  }
}

/// The decrypted contents of a bundle: every record plus a revision the
/// hub bumps on each push.
@immutable
class SyncDocument {
  const SyncDocument({
    required this.records,
    this.revision = 0,
    this.vaultId,
    this.deviceId = '',
    this.createdAt,
  });

  static const format = 'conductore.records';
  static const version = 1;

  final Map<String, SyncRecord> records;
  final int revision;
  final String? vaultId;
  final String deviceId;
  final DateTime? createdAt;

  Map<String, Object?> toJson() => {
    'format': format,
    'version': version,
    'revision': revision,
    if (vaultId != null) 'vault': vaultId,
    'device': deviceId,
    'createdAt': (createdAt ?? DateTime.now()).toUtc().toIso8601String(),
    'records': [
      for (final key in records.keys.toList()..sort()) records[key]!.toJson(),
    ],
  };

  /// Reads a document, refusing ones a newer app wrote in a format this
  /// build cannot merge safely.
  static SyncDocument fromJson(Object? json) {
    if (json is! Map || json['format'] != format) {
      throw const SyncFormatException('This is not Conductore sync data.');
    }
    final documentVersion = json['version'];
    if (documentVersion is! int || documentVersion < 1) {
      throw const SyncFormatException('This sync data is damaged.');
    }
    if (documentVersion > version) {
      throw const SyncFormatException(
        'This sync data comes from a newer Conductore. Update the app.',
      );
    }
    final records = <String, SyncRecord>{};
    final raw = json['records'];
    if (raw is List) {
      for (final item in raw) {
        final record = SyncRecord.fromJson(item);
        if (record == null) continue;
        final existing = records[record.key];
        records[record.key] = existing == null
            ? record
            : SyncRecord.newer(existing, record);
      }
    }
    final revision = json['revision'];
    final vault = json['vault'];
    final device = json['device'];
    return SyncDocument(
      records: records,
      revision: revision is int ? revision : 0,
      vaultId: vault is String ? vault : null,
      deviceId: device is String ? device : '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    );
  }
}

class SyncFormatException implements Exception {
  const SyncFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}
