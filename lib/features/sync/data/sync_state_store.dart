import 'dart:convert';

import 'package:conduit/features/sync/data/sync_crypto.dart';
import 'package:conduit/features/sync/domain/sync_config.dart';
import 'package:conduit/features/sync/domain/sync_merge.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where this device keeps its sync setup, the derived key (so the
/// passphrase is asked once per device), the last merged records and the
/// activity list.
abstract interface class SyncStateStore {
  Future<SyncConfig?> loadConfig();
  Future<void> saveConfig(SyncConfig? config);
  Future<SyncKey?> loadKey();
  Future<void> saveKey(SyncKey? key);
  Future<Map<String, SyncBaseEntry>> loadBase();
  Future<void> saveBase(Map<String, SyncBaseEntry> base);
  Future<List<SyncActivityEntry>> loadActivity();
  Future<void> saveActivity(List<SyncActivityEntry> entries);
}

/// [SyncStateStore] in the platform keystore/keychain, like the saved
/// machines themselves.
class SecureSyncStateStore implements SyncStateStore {
  const SecureSyncStateStore(this._storage);

  static const _configKey = 'conductore.sync.config.v1';
  static const _keyKey = 'conductore.sync.key.v1';
  static const _baseKey = 'conductore.sync.base.v1';
  static const _activityKey = 'conductore.sync.activity.v1';

  final FlutterSecureStorage _storage;

  Future<Object?> _read(String key) async {
    final raw = await _storage.read(key: key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String key, Object? value) => value == null
      ? _storage.delete(key: key)
      : _storage.write(key: key, value: jsonEncode(value));

  @override
  Future<SyncConfig?> loadConfig() async =>
      SyncConfig.fromJson(await _read(_configKey));

  @override
  Future<void> saveConfig(SyncConfig? config) =>
      _write(_configKey, config?.toJson());

  @override
  Future<SyncKey?> loadKey() async => SyncKey.fromJson(await _read(_keyKey));

  @override
  Future<void> saveKey(SyncKey? key) => _write(_keyKey, key?.toJson());

  @override
  Future<Map<String, SyncBaseEntry>> loadBase() async {
    final raw = await _read(_baseKey);
    final base = <String, SyncBaseEntry>{};
    for (final item in raw is List ? raw : const []) {
      final entry = SyncBaseEntry.fromJson(item);
      if (entry != null) base[entry.record.key] = entry;
    }
    return base;
  }

  @override
  Future<void> saveBase(Map<String, SyncBaseEntry> base) => _write(
    _baseKey,
    base.isEmpty ? null : [for (final entry in base.values) entry.toJson()],
  );

  @override
  Future<List<SyncActivityEntry>> loadActivity() async {
    final raw = await _read(_activityKey);
    return [
      for (final item in raw is List ? raw : const [])
        ?SyncActivityEntry.fromJson(item),
    ];
  }

  @override
  Future<void> saveActivity(List<SyncActivityEntry> entries) => _write(
    _activityKey,
    entries.isEmpty ? null : [for (final entry in entries) entry.toJson()],
  );
}

class InMemorySyncStateStore implements SyncStateStore {
  SyncConfig? config;
  SyncKey? key;
  Map<String, SyncBaseEntry> base = {};
  List<SyncActivityEntry> activity = [];

  @override
  Future<SyncConfig?> loadConfig() async => config;
  @override
  Future<void> saveConfig(SyncConfig? config) async => this.config = config;
  @override
  Future<SyncKey?> loadKey() async => key;
  @override
  Future<void> saveKey(SyncKey? key) async => this.key = key;
  @override
  Future<Map<String, SyncBaseEntry>> loadBase() async => Map.of(base);
  @override
  Future<void> saveBase(Map<String, SyncBaseEntry> base) async =>
      this.base = Map.of(base);
  @override
  Future<List<SyncActivityEntry>> loadActivity() async => List.of(activity);
  @override
  Future<void> saveActivity(List<SyncActivityEntry> entries) async =>
      activity = List.of(entries);
}
