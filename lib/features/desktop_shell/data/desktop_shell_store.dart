import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the desktop shell keeps its per-device state (sidebar width and
/// arrangement, split layout, unread markers). Never synced or backed up:
/// it describes this window on this device.
abstract interface class DesktopShellStore {
  Future<Map<String, Object?>?> load();
  Future<void> save(Map<String, Object?> state);
}

/// [DesktopShellStore] in the app's secure storage, next to the other
/// preferences.
class SecureDesktopShellStore implements DesktopShellStore {
  const SecureDesktopShellStore(this._storage);

  static const storageKey = 'conduit.desktop_shell.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<Map<String, Object?>?> load() async {
    try {
      final raw = await _storage.read(key: storageKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : null;
    } catch (_) {
      // Unreadable: start with the defaults.
      return null;
    }
  }

  @override
  Future<void> save(Map<String, Object?> state) async {
    try {
      await _storage.write(key: storageKey, value: jsonEncode(state));
    } catch (_) {
      // Remembering the layout is a nicety; the shell keeps working.
    }
  }
}

/// [DesktopShellStore] in memory (tests, screenshots).
class InMemoryDesktopShellStore implements DesktopShellStore {
  InMemoryDesktopShellStore([this.state]);

  Map<String, Object?>? state;
  int saves = 0;

  @override
  Future<Map<String, Object?>?> load() async => state == null
      ? null
      : jsonDecode(jsonEncode(state)) as Map<String, Object?>;

  @override
  Future<void> save(Map<String, Object?> state) async {
    saves += 1;
    this.state = jsonDecode(jsonEncode(state)) as Map<String, Object?>;
  }
}
