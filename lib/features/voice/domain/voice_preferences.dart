import 'dart:convert';

/// Read-aloud and continuous-dictation settings (Settings → Speech).
///
/// Stored as one JSON value next to the other app preferences, so adding a
/// field never needs a new storage key. Unknown or malformed fields fall
/// back to their defaults.
class VoicePreferences {
  const VoicePreferences({
    this.readAloudByDefault = false,
    this.ttsLanguage = '',
    this.ttsVoice = '',
    this.ttsRate = 1.0,
    this.ttsPitch = 1.0,
    this.continuousDictation = true,
    this.dictationSilenceSeconds = defaultSilenceSeconds,
    this.dictationMaxMinutes = defaultMaxMinutes,
    this.muteRestartBeeps = true,
    this.readAloudSessions = const {},
  });

  static const defaults = VoicePreferences();

  static const defaultSilenceSeconds = 8;
  static const defaultMaxMinutes = 5;
  static const minSilenceSeconds = 3;
  static const maxSilenceSeconds = 60;
  static const minMaxMinutes = 1;
  static const maxMaxMinutes = 30;
  static const minRate = 0.5;
  static const maxRate = 2.0;
  static const minPitch = 0.5;
  static const maxPitch = 2.0;

  /// How many per-session speaker toggles are remembered (oldest dropped).
  static const maxRememberedSessions = 40;

  /// Whether Chat View opens with "Read replies aloud" on for a session
  /// whose speaker toggle was never touched.
  final bool readAloudByDefault;

  /// BCP-47 tag replies are spoken in; empty follows the dictation
  /// language (and that, when empty, the device locale).
  final String ttsLanguage;

  /// Engine voice name; empty picks the best offline voice for the
  /// language.
  final String ttsVoice;

  /// Speech rate, 1.0 is the engine's normal speed.
  final double ttsRate;

  /// Voice pitch, 1.0 is the engine's normal pitch.
  final double ttsPitch;

  /// Keep dictating across pauses until the user taps stop (the
  /// recognizer is restarted after each phrase).
  final bool continuousDictation;

  /// Continuous dictation pauses itself after this much silence.
  final int dictationSilenceSeconds;

  /// Hard cap on one continuous dictation session.
  final int dictationMaxMinutes;

  /// Briefly mutes the recognizer's start/stop earcon while it restarts
  /// between phrases (best effort; see SpeechRecognitionBridge.kt).
  final bool muteRestartBeeps;

  /// The Chat View speaker toggle per session id, most recent last.
  final Map<String, bool> readAloudSessions;

  Duration get dictationSilence => Duration(seconds: dictationSilenceSeconds);
  Duration get dictationMaxSession => Duration(minutes: dictationMaxMinutes);

  /// Whether Chat View should read [sessionId] aloud.
  bool readAloudFor(String sessionId) =>
      readAloudSessions[sessionId] ?? readAloudByDefault;

  /// Remembers the speaker toggle for [sessionId], keeping only the most
  /// recent [maxRememberedSessions].
  VoicePreferences withSessionReadAloud(String sessionId, bool enabled) {
    final sessions = Map<String, bool>.of(readAloudSessions)
      ..remove(sessionId)
      ..[sessionId] = enabled;
    while (sessions.length > maxRememberedSessions) {
      sessions.remove(sessions.keys.first);
    }
    return copyWith(readAloudSessions: sessions);
  }

  /// The language to speak in, given the dictation language.
  String effectiveTtsLanguage(String dictationLanguage) =>
      ttsLanguage.isNotEmpty ? ttsLanguage : dictationLanguage;

  VoicePreferences copyWith({
    bool? readAloudByDefault,
    String? ttsLanguage,
    String? ttsVoice,
    double? ttsRate,
    double? ttsPitch,
    bool? continuousDictation,
    int? dictationSilenceSeconds,
    int? dictationMaxMinutes,
    bool? muteRestartBeeps,
    Map<String, bool>? readAloudSessions,
  }) {
    return VoicePreferences(
      readAloudByDefault: readAloudByDefault ?? this.readAloudByDefault,
      ttsLanguage: ttsLanguage ?? this.ttsLanguage,
      ttsVoice: ttsVoice ?? this.ttsVoice,
      ttsRate: (ttsRate ?? this.ttsRate).clamp(minRate, maxRate).toDouble(),
      ttsPitch: (ttsPitch ?? this.ttsPitch)
          .clamp(minPitch, maxPitch)
          .toDouble(),
      continuousDictation: continuousDictation ?? this.continuousDictation,
      dictationSilenceSeconds:
          (dictationSilenceSeconds ?? this.dictationSilenceSeconds).clamp(
            minSilenceSeconds,
            maxSilenceSeconds,
          ),
      dictationMaxMinutes: (dictationMaxMinutes ?? this.dictationMaxMinutes)
          .clamp(minMaxMinutes, maxMaxMinutes),
      muteRestartBeeps: muteRestartBeeps ?? this.muteRestartBeeps,
      readAloudSessions: readAloudSessions ?? this.readAloudSessions,
    );
  }

  /// JSON for storage. [includeSessions] is false for backups: the
  /// per-session toggles are device-local noise.
  Map<String, Object?> toJson({bool includeSessions = true}) => {
    'readAloudByDefault': readAloudByDefault,
    'ttsLanguage': ttsLanguage,
    'ttsVoice': ttsVoice,
    'ttsRate': ttsRate,
    'ttsPitch': ttsPitch,
    'continuousDictation': continuousDictation,
    'dictationSilenceSeconds': dictationSilenceSeconds,
    'dictationMaxMinutes': dictationMaxMinutes,
    'muteRestartBeeps': muteRestartBeeps,
    if (includeSessions) 'readAloudSessions': readAloudSessions,
  };

  /// Parses [toJson]; [fallback] supplies fields the map lacks (a backup
  /// restore keeps this device's per-session toggles).
  static VoicePreferences fromJson(
    Object? raw, {
    VoicePreferences fallback = defaults,
  }) {
    if (raw is! Map) {
      return fallback;
    }
    T pick<T>(String key, T current) {
      final value = raw[key];
      return value is T ? value : current;
    }

    double number(String key, double current) {
      final value = raw[key];
      return value is num ? value.toDouble() : current;
    }

    int integer(String key, int current) {
      final value = raw[key];
      return value is num ? value.round() : current;
    }

    final rawSessions = raw['readAloudSessions'];
    return fallback.copyWith(
      readAloudByDefault: pick(
        'readAloudByDefault',
        fallback.readAloudByDefault,
      ),
      ttsLanguage: pick('ttsLanguage', fallback.ttsLanguage).trim(),
      ttsVoice: pick('ttsVoice', fallback.ttsVoice).trim(),
      ttsRate: number('ttsRate', fallback.ttsRate),
      ttsPitch: number('ttsPitch', fallback.ttsPitch),
      continuousDictation: pick(
        'continuousDictation',
        fallback.continuousDictation,
      ),
      dictationSilenceSeconds: integer(
        'dictationSilenceSeconds',
        fallback.dictationSilenceSeconds,
      ),
      dictationMaxMinutes: integer(
        'dictationMaxMinutes',
        fallback.dictationMaxMinutes,
      ),
      muteRestartBeeps: pick('muteRestartBeeps', fallback.muteRestartBeeps),
      readAloudSessions: rawSessions is Map
          ? {
              for (final entry in rawSessions.entries)
                if (entry.key is String && entry.value is bool)
                  entry.key as String: entry.value as bool,
            }
          : null,
    );
  }

  String encode() => jsonEncode(toJson());

  static VoicePreferences decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return defaults;
    }
    try {
      return fromJson(jsonDecode(raw));
    } catch (_) {
      return defaults;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is VoicePreferences && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;
}
