import 'dart:convert';

import 'package:conduit/features/sessions/domain/connect_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists connect-picker preferences next to the saved hosts, as one JSON
/// object keyed by host id.
class SecureConnectPreferencesRepository
    implements ConnectPreferencesRepository {
  const SecureConnectPreferencesRepository(this._storage);

  /// The storage entry (one JSON object keyed by host id), read and
  /// written whole by device sync.
  static const storageKey = 'conduit.connect_preferences.v1';
  static const _key = storageKey;

  final FlutterSecureStorage _storage;

  @override
  Future<ConnectPreferences> load(String hostId) async {
    final all = await _loadAll();
    return ConnectPreferences.fromJson(all[hostId]);
  }

  @override
  Future<void> save(String hostId, ConnectPreferences preferences) async {
    final all = await _loadAll();
    all[hostId] = preferences.toJson();
    await _storage.write(key: _key, value: jsonEncode(all));
  }

  Future<Map<String, Object?>> _loadAll() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) {
      return {};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, Object?>.from(decoded);
      }
    } catch (_) {
      // Unreadable preferences are not worth failing a connect over.
    }
    return {};
  }
}
