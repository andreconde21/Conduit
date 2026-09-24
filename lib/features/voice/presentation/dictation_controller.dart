import 'dart:async';

import 'package:conduit/features/voice/domain/speech_event.dart';
import 'package:conduit/features/voice/domain/speech_recognizer.dart';
import 'package:flutter/foundation.dart';

enum DictationStatus {
  /// Not listening; tapping the mic starts a session.
  idle,

  /// The system microphone permission dialog is showing.
  requestingPermission,

  /// `start` was issued; waiting for the recognizer to be ready.
  starting,

  /// Capturing audio; partial transcripts are flowing.
  listening,

  /// Audio capture ended (tap or end of speech); waiting for the final
  /// transcript.
  finishing,
}

/// Callbacks a dictation session delivers text through. The owner of the
/// text field (composer sheet or inline bar) supplies them when it starts a
/// session, so whichever field the user tapped receives the transcript.
class DictationSink {
  const DictationSink({
    required this.onBegin,
    required this.onPartial,
    required this.onFinish,
    required this.onCancel,
  });

  final VoidCallback onBegin;
  final ValueChanged<String> onPartial;
  final ValueChanged<String> onFinish;
  final VoidCallback onCancel;
}

/// Drives one [SpeechRecognizer] session at a time and exposes its state to
/// the mic button. Errors surface on [message]; a denied microphone
/// permission is remembered on [permissionDenied] so the button can explain
/// itself instead of silently doing nothing.
class DictationController extends ChangeNotifier {
  DictationController(this._recognizer, {required this.language});

  final SpeechRecognizer _recognizer;

  /// Resolves the BCP-47 tag to listen in; empty means the device locale.
  final String Function() language;

  DictationStatus _status = DictationStatus.idle;
  bool _available = true;
  bool _permissionDenied = false;
  String? _message;
  String _lastPartial = '';
  DictationSink? _sink;
  StreamSubscription<SpeechEvent>? _subscription;
  bool _disposed = false;

  DictationStatus get status => _status;
  bool get isActive => _status != DictationStatus.idle;
  bool get isAvailable => _available;
  bool get permissionDenied => _permissionDenied;

  /// The last error to show near the mic; cleared on the next start.
  String? get message => _message;

  /// Whether the given sink owns the running session.
  bool owns(DictationSink sink) => identical(_sink, sink);

  /// Probes the platform once; the mic is hidden when no recognizer exists.
  Future<void> checkAvailability() async {
    final available = await _recognizer.isAvailable();
    if (_disposed || available == _available) {
      return;
    }
    _available = available;
    notifyListeners();
  }

  /// Starts a session feeding [sink], or stops the running one when [sink]
  /// owns it. A tap on the mic always maps to this.
  Future<void> toggle(DictationSink sink) {
    if (_status == DictationStatus.idle) {
      return start(sink);
    }
    if (owns(sink)) {
      return stop();
    }
    return Future<void>.value();
  }

  Future<void> start(DictationSink sink) async {
    if (_status != DictationStatus.idle) {
      return;
    }
    _message = null;
    _sink = sink;
    _lastPartial = '';
    if (!await _recognizer.hasPermission()) {
      _setStatus(DictationStatus.requestingPermission);
      final granted = await _recognizer.requestPermission();
      if (_disposed) {
        return;
      }
      if (!granted) {
        _permissionDenied = true;
        _message = 'Microphone access is needed to dictate.';
        _sink = null;
        _setStatus(DictationStatus.idle);
        return;
      }
    }
    _permissionDenied = false;
    _subscription ??= _recognizer.events.listen(_handleEvent);
    sink.onBegin();
    _setStatus(DictationStatus.starting);
    try {
      await _recognizer.start(language: language());
    } catch (error) {
      _fail('Could not start speech recognition.');
    }
  }

  /// Ends audio capture; the final transcript still arrives.
  Future<void> stop() async {
    if (_status != DictationStatus.starting &&
        _status != DictationStatus.listening) {
      return;
    }
    _setStatus(DictationStatus.finishing);
    try {
      await _recognizer.stop();
    } catch (error) {
      _fail('Could not stop speech recognition.');
    }
  }

  /// Drops the session, keeping whatever partial text was already inserted.
  Future<void> cancel() async {
    if (_status == DictationStatus.idle) {
      return;
    }
    final sink = _sink;
    _sink = null;
    _setStatus(DictationStatus.idle);
    sink?.onFinish(_lastPartial);
    try {
      await _recognizer.cancel();
    } catch (_) {
      // Nothing left to release.
    }
  }

  void _handleEvent(SpeechEvent event) {
    if (_disposed || _status == DictationStatus.idle) {
      return;
    }
    switch (event) {
      case SpeechReady() || SpeechListening():
        if (_status == DictationStatus.starting) {
          _setStatus(DictationStatus.listening);
        }
      case SpeechEnded():
        if (_status != DictationStatus.finishing) {
          _setStatus(DictationStatus.finishing);
        }
      case SpeechPartial(:final text):
        _lastPartial = text;
        _sink?.onPartial(text);
      case SpeechResult(:final text):
        final sink = _sink;
        _sink = null;
        _setStatus(DictationStatus.idle);
        sink?.onFinish(text.isEmpty ? _lastPartial : text);
      case final SpeechError error:
        if (error.isQuiet && _lastPartial.isNotEmpty) {
          // A pause after speaking: keep the partial as the result.
          final sink = _sink;
          _sink = null;
          _setStatus(DictationStatus.idle);
          sink?.onFinish(_lastPartial);
        } else {
          _permissionDenied = error.code == SpeechError.insufficientPermissions;
          _fail(error.isQuiet ? null : error.message);
        }
    }
  }

  void _fail(String? message) {
    final sink = _sink;
    _sink = null;
    _message = message;
    _setStatus(DictationStatus.idle);
    sink?.onCancel();
  }

  void _setStatus(DictationStatus status) {
    if (_disposed) {
      return;
    }
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    if (_status != DictationStatus.idle) {
      unawaited(_recognizer.cancel().catchError((_) {}));
    }
    super.dispose();
  }
}
