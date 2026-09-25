import 'dart:convert';

import 'package:conduit/features/terminal/domain/recent_directories.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Per-host recent directories in the same secure storage as the other
/// per-host preferences, as one JSON map (host id -> list) under a
/// versioned key.
class SecureRecentDirectoriesStore implements RecentDirectoriesStore {
  const SecureRecentDirectoriesStore(this._storage);

  static const _key = 'conduit.recent_directories.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<List<String>> read(String hostId) async {
    final all = await _load();
    return all[hostId] ?? const [];
  }

  @override
  Future<void> write(String hostId, List<String> directories) async {
    final all = await _load();
    if (directories.isEmpty) {
      all.remove(hostId);
    } else {
      all[hostId] = directories.take(maxRecentDirectories).toList();
    }
    await _storage.write(key: _key, value: jsonEncode(all));
  }

  Future<Map<String, List<String>>> _load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) {
      return {};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return {};
      }
      return {
        for (final entry in decoded.entries)
          if (entry.value is List)
            entry.key.toString(): [
              for (final item in entry.value as List)
                if (item is String) item,
            ],
      };
    } on FormatException {
      return {};
    }
  }
}
