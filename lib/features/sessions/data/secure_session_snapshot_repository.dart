import 'dart:convert';

import 'package:conduit/features/sessions/domain/session_snapshot.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps the open-session list in secure storage, next to the saved hosts.
class SecureSessionSnapshotRepository implements SessionSnapshotRepository {
  const SecureSessionSnapshotRepository(this._storage);

  static const storageKey = 'conductore.open_sessions.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<SessionSnapshot> load() async {
    final raw = await _storage.read(key: storageKey);
    if (raw == null || raw.isEmpty) return SessionSnapshot.empty;
    try {
      return SessionSnapshot.fromJson(jsonDecode(raw));
    } catch (_) {
      // A damaged list is not worth failing the app start over.
      return SessionSnapshot.empty;
    }
  }

  @override
  Future<void> save(SessionSnapshot snapshot) async {
    if (snapshot.isEmpty) {
      await clear();
      return;
    }
    await _storage.write(key: storageKey, value: jsonEncode(snapshot.toJson()));
  }

  @override
  Future<void> clear() => _storage.delete(key: storageKey);
}
