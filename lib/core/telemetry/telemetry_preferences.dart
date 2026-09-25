import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Settings › Privacy, per device. Never synced or backed up: each device
/// asks (and remembers) for itself.
class TelemetryPreferences {
  const TelemetryPreferences({
    this.crashReports = true,
    this.usageStats = true,
    this.noticeSeen = false,
  });

  /// "Send crash reports" (GlitchTip).
  final bool crashReports;

  /// "Send anonymous usage stats" (Plausible).
  final bool usageStats;

  /// The one-time notice on home was dismissed.
  final bool noticeSeen;

  TelemetryPreferences copyWith({
    bool? crashReports,
    bool? usageStats,
    bool? noticeSeen,
  }) => TelemetryPreferences(
    crashReports: crashReports ?? this.crashReports,
    usageStats: usageStats ?? this.usageStats,
    noticeSeen: noticeSeen ?? this.noticeSeen,
  );

  Map<String, Object?> toJson() => {
    'crashReports': crashReports,
    'usageStats': usageStats,
    'noticeSeen': noticeSeen,
  };

  /// Missing keys keep their defaults (both switches on).
  static TelemetryPreferences fromJson(Object? json) {
    if (json is! Map) return const TelemetryPreferences();
    return TelemetryPreferences(
      crashReports: json['crashReports'] != false,
      usageStats: json['usageStats'] != false,
      noticeSeen: json['noticeSeen'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TelemetryPreferences &&
      other.crashReports == crashReports &&
      other.usageStats == usageStats &&
      other.noticeSeen == noticeSeen;

  @override
  int get hashCode => Object.hash(crashReports, usageStats, noticeSeen);
}

abstract class TelemetryPreferencesStore {
  Future<TelemetryPreferences> load();
  Future<void> save(TelemetryPreferences preferences);
}

/// In secure storage under its own key, outside every sync record.
class SecureTelemetryPreferencesStore implements TelemetryPreferencesStore {
  const SecureTelemetryPreferencesStore(this._storage);

  static const storageKey = 'telemetry_preferences_v1';

  final FlutterSecureStorage _storage;

  @override
  Future<TelemetryPreferences> load() async {
    try {
      final raw = await _storage.read(key: storageKey);
      if (raw == null || raw.isEmpty) return const TelemetryPreferences();
      return TelemetryPreferences.fromJson(jsonDecode(raw));
    } on Object {
      return const TelemetryPreferences();
    }
  }

  @override
  Future<void> save(TelemetryPreferences preferences) =>
      _storage.write(key: storageKey, value: jsonEncode(preferences.toJson()));
}

/// For tests and the inert default controller.
class MemoryTelemetryPreferencesStore implements TelemetryPreferencesStore {
  MemoryTelemetryPreferencesStore([this.value = const TelemetryPreferences()]);

  TelemetryPreferences value;

  @override
  Future<TelemetryPreferences> load() async => value;

  @override
  Future<void> save(TelemetryPreferences preferences) async =>
      value = preferences;
}
