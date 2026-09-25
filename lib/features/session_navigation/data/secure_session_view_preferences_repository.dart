import 'dart:convert';

import 'package:conduit/features/session_navigation/domain/session_view_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// [SessionViewPreferences] in the app's secure storage. Only host ids and
/// target keys go in here, never secrets.
class SecureSessionViewPreferencesRepository
    implements SessionViewPreferencesRepository {
  const SecureSessionViewPreferencesRepository(this._storage);

  static const _key = 'conduit.session_views.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<SessionViewPreferences> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return const SessionViewPreferences();
      return SessionViewPreferences.fromJson(jsonDecode(raw));
    } catch (_) {
      // Unreadable storage: every session opens in the terminal.
      return const SessionViewPreferences();
    }
  }

  @override
  Future<void> save(SessionViewPreferences preferences) async {
    try {
      await _storage.write(key: _key, value: jsonEncode(preferences.toJson()));
    } catch (_) {
      // The choice still holds for this run.
    }
  }
}
