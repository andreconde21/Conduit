import 'dart:convert';

import 'package:conduit/features/live_preview/domain/live_preview_port_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Per-host preview ports in the same secure storage as the other
/// preferences, as one JSON map under a versioned key.
class SecureLivePreviewPortStore implements LivePreviewPortStore {
  const SecureLivePreviewPortStore(this._storage);

  static const _key = 'conduit.live_preview_ports.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<int?> read(String hostId) async {
    final ports = await _load();
    return ports[hostId];
  }

  @override
  Future<void> write(String hostId, int port) async {
    final ports = await _load();
    ports[hostId] = port;
    await _storage.write(key: _key, value: jsonEncode(ports));
  }

  Future<Map<String, int>> _load() async {
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
          if (entry.value is int) entry.key.toString(): entry.value as int,
      };
    } on FormatException {
      return {};
    }
  }
}
