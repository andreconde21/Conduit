/// Events streamed by a [SpeechRecognizer] during one listening session.
sealed class SpeechEvent {
  const SpeechEvent();

  /// Parses the map shape produced by the Android bridge. Unknown or
  /// malformed events are dropped (null) so a bridge change cannot crash the
  /// composer.
  static SpeechEvent? fromMap(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    switch (raw['type']) {
      case 'status':
        return switch (raw['value']) {
          'ready' => const SpeechReady(),
          'listening' => const SpeechListening(),
          'ended' => const SpeechEnded(),
          _ => null,
        };
      case 'partial':
        final text = raw['text'];
        return text is String ? SpeechPartial(text) : null;
      case 'result':
        final text = raw['text'];
        return SpeechResult(text is String ? text : '');
      case 'error':
        final code = raw['code'];
        final message = raw['message'];
        return SpeechError(
          code: code is int ? code : -1,
          message: message is String ? message : 'Speech recognition failed.',
        );
    }
    return null;
  }
}

/// The recognizer is capturing audio and waiting for speech.
class SpeechReady extends SpeechEvent {
  const SpeechReady();
}

/// Speech has been detected.
class SpeechListening extends SpeechEvent {
  const SpeechListening();
}

/// The user stopped talking; a final [SpeechResult] (or error) follows.
class SpeechEnded extends SpeechEvent {
  const SpeechEnded();
}

/// A provisional transcript that later partials or the result replace.
class SpeechPartial extends SpeechEvent {
  const SpeechPartial(this.text);

  final String text;
}

/// The final transcript of the session; the recognizer is released.
class SpeechResult extends SpeechEvent {
  const SpeechResult(this.text);

  final String text;
}

/// The session failed; the recognizer is released.
class SpeechError extends SpeechEvent {
  const SpeechError({required this.code, required this.message});

  /// Android `SpeechRecognizer.ERROR_*` code, or -1 when unknown.
  final int code;
  final String message;

  static const int noMatch = 7;
  static const int speechTimeout = 6;
  static const int insufficientPermissions = 9;

  /// Silence and "nothing recognized" are ordinary outcomes of a short
  /// session, not failures the user needs to read about.
  bool get isQuiet => code == noMatch || code == speechTimeout;
}
