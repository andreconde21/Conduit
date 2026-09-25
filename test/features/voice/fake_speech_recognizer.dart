import 'dart:async';

import 'package:conduit/features/voice/domain/speech_event.dart';
import 'package:conduit/features/voice/domain/speech_recognizer.dart';

/// Records starts/stops; tests push recognizer events with [emit].
class FakeSpeechRecognizer implements SpeechRecognizer {
  final starts = <SpeechListenOptions>[];
  var stops = 0;
  var cancels = 0;
  var permission = true;
  final _events = StreamController<SpeechEvent>.broadcast(sync: true);

  void emit(SpeechEvent event) => _events.add(event);

  /// Says [text] as one finished phrase.
  void say(String text) {
    emit(const SpeechReady());
    emit(const SpeechListening());
    emit(SpeechPartial(text));
    emit(SpeechResult(text));
  }

  @override
  Stream<SpeechEvent> get events => _events.stream;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<bool> requestPermission() async => permission;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> start({
    String? language,
    SpeechListenOptions options = const SpeechListenOptions(),
  }) async => starts.add(options);

  @override
  Future<void> stop() async => stops += 1;

  @override
  Future<void> cancel() async => cancels += 1;
}
