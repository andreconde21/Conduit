/// One installed offline voice of the system text-to-speech engine.
class TtsVoice {
  const TtsVoice({required this.id, required this.locale, this.quality = 0});

  /// Engine voice name, passed back to [TextToSpeech.speak].
  final String id;

  /// BCP-47 tag of the voice.
  final String locale;

  /// Engine quality score (higher is better).
  final int quality;

  static TtsVoice? fromMap(Object? raw) {
    if (raw is! Map || raw['id'] is! String) {
      return null;
    }
    return TtsVoice(
      id: raw['id'] as String,
      locale: raw['locale'] is String ? raw['locale'] as String : '',
      quality: raw['quality'] is int ? raw['quality'] as int : 0,
    );
  }
}

/// Progress of the utterance [id] (the id given to [TextToSpeech.speak]).
sealed class TtsEvent {
  const TtsEvent(this.id);

  final String id;

  static TtsEvent? fromMap(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final id = raw['id'] is String ? raw['id'] as String : '';
    return switch (raw['type']) {
      'start' => TtsStarted(id),
      'done' => TtsDone(id),
      'stopped' => TtsStopped(id),
      'interrupted' => const TtsInterrupted(),
      'error' => TtsFailed(
        id,
        raw['message'] is String
            ? raw['message'] as String
            : 'Text-to-speech failed.',
      ),
      _ => null,
    };
  }
}

class TtsStarted extends TtsEvent {
  const TtsStarted(super.id);
}

class TtsDone extends TtsEvent {
  const TtsDone(super.id);
}

/// The utterance was cut short by [TextToSpeech.stop] or a newer speak.
class TtsStopped extends TtsEvent {
  const TtsStopped(super.id);
}

/// Another app (a call, a navigation prompt) took the audio for good.
class TtsInterrupted extends TtsEvent {
  const TtsInterrupted() : super('');
}

class TtsFailed extends TtsEvent {
  const TtsFailed(super.id, this.message);

  final String message;
}

/// On-device text-to-speech. One utterance plays at a time; queueing is
/// the caller's job (see ReadAloudController).
abstract class TextToSpeech {
  Future<bool> isAvailable();

  /// Offline voices for [language] (a BCP-47 tag; empty lists them all).
  Future<List<TtsVoice>> voices({String language = ''});

  /// Speaks [text], replacing whatever is playing. [language] empty uses
  /// the device locale; [voice] empty picks the best offline voice.
  Future<void> speak(
    String text, {
    required String id,
    String language = '',
    String voice = '',
  });

  Future<void> stop();

  Future<void> setRate(double rate);

  Future<void> setPitch(double pitch);

  /// Whether the screen is on (false while the phone is locked/off).
  Future<bool> isInteractive();

  Stream<TtsEvent> get events;
}
