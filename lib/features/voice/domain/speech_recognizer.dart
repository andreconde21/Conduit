import 'package:conduit/features/voice/domain/speech_event.dart';

/// On-device speech-to-text. Exactly one listening session runs at a time;
/// [events] carries the transcript and lifecycle of the current session.
abstract class SpeechRecognizer {
  /// Whether the platform has any recognition service at all.
  Future<bool> isAvailable();

  Future<bool> hasPermission();

  /// Shows the system microphone permission prompt when needed; resolves to
  /// the resulting grant state.
  Future<bool> requestPermission();

  /// Begins listening. [language] is a BCP-47 tag; null uses the device
  /// locale. Outcomes arrive on [events]. [options] tunes the silence
  /// handling; a restart within a continuous session sets
  /// [SpeechListenOptions.restart].
  Future<void> start({
    String? language,
    SpeechListenOptions options = const SpeechListenOptions(),
  });

  /// Stops capturing audio; the final result still arrives on [events].
  Future<void> stop();

  /// Abandons the session without a result.
  Future<void> cancel();

  Stream<SpeechEvent> get events;

  /// Opens the system screen where a speech service is chosen (Android's
  /// voice input settings); false when there is none to open.
  Future<bool> openSettings();
}

/// Per-start recognizer tuning passed to the platform.
class SpeechListenOptions {
  const SpeechListenOptions({
    this.continuous = false,
    this.restart = false,
    this.muteRestartBeeps = false,
    this.completeSilenceMillis,
    this.possiblyCompleteSilenceMillis,
    this.minimumLengthMillis,
  });

  /// Part of a continuous session: the platform keeps its recognizer
  /// between phrases so a restart is quick.
  final bool continuous;

  /// This start follows a finished phrase of the same session.
  final bool restart;

  /// Mute the recognizer's earcons around restarts (best effort).
  final bool muteRestartBeeps;

  /// RecognizerIntent silence extras; many recognizers (Google's on-device
  /// one included) ignore them, hence the restarts.
  final int? completeSilenceMillis;
  final int? possiblyCompleteSilenceMillis;
  final int? minimumLengthMillis;

  Map<String, Object?> toMap() => {
    'continuous': continuous,
    'restart': restart,
    'muteBeeps': muteRestartBeeps,
    'completeSilenceMillis': ?completeSilenceMillis,
    'possiblyCompleteSilenceMillis': ?possiblyCompleteSilenceMillis,
    'minimumLengthMillis': ?minimumLengthMillis,
  };
}
