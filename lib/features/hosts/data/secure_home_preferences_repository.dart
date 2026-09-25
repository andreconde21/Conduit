import 'dart:convert';

import 'package:conduit/features/hosts/domain/home_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// [HomePreferences] in the app's secure storage, next to the saved hosts.
class SecureHomePreferencesRepository implements HomePreferencesRepository {
  const SecureHomePreferencesRepository(this._storage);

  static const _key = 'conduit.home_preferences.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<HomePreferences> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return const HomePreferences();
      return HomePreferences.fromJson(jsonDecode(raw));
    } catch (_) {
      // Unreadable or missing storage: start from the defaults.
      return const HomePreferences();
    }
  }

  @override
  Future<void> save(HomePreferences preferences) async {
    try {
      await _storage.write(key: _key, value: jsonEncode(preferences.toJson()));
    } catch (_) {
      // Remembering the layout is a nicety; the page keeps working.
    }
  }
}
