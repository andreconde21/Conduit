import 'dart:convert';
import 'dart:io';

import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/this_computer/domain/this_computer_settings.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps the settings of "This computer" in secure storage, under a key of
/// its own: the saved-machine list (and so backups and device sync) never
/// sees it.
class SecureThisComputerStore implements ThisComputerStore {
  const SecureThisComputerStore(this._storage);

  static const storageKey = 'conductore.this_computer.v1';

  final FlutterSecureStorage _storage;

  /// The machine entry of the device the app runs on.
  static SavedHost defaultHost() {
    final env = Platform.environment;
    String hostname;
    try {
      hostname = Platform.localHostname;
    } catch (_) {
      hostname = 'localhost';
    }
    return SavedHost.thisComputer(
      hostname: hostname,
      username: env['USER'] ?? env['USERNAME'] ?? '',
    );
  }

  @override
  Future<ThisComputerSettings> load() async {
    final defaults = defaultHost();
    try {
      final raw = await _storage.read(key: storageKey);
      if (raw == null || raw.isEmpty) {
        return ThisComputerSettings(host: defaults);
      }
      return ThisComputerSettings.fromJson(jsonDecode(raw), defaults: defaults);
    } catch (_) {
      return ThisComputerSettings(host: defaults);
    }
  }

  @override
  Future<void> save(ThisComputerSettings settings) =>
      _storage.write(key: storageKey, value: jsonEncode(settings.toJson()));
}
