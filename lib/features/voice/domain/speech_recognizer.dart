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
  /// locale. Outcomes arrive on [events].
  Future<void> start({String? language});

  /// Stops capturing audio; the final result still arrives on [events].
  Future<void> stop();

  /// Abandons the session without a result.
  Future<void> cancel();

  Stream<SpeechEvent> get events;
}
