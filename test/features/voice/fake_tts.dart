import 'dart:async';

import 'package:conduit/features/voice/domain/text_to_speech.dart';

/// Records what would be spoken; [done] finishes the current utterance.
class FakeTts implements TextToSpeech {
  final spoken = <String>[];
  final ids = <String>[];
  final languages = <String>[];
  var stops = 0;
  double? rate;
  double? pitch;
  var interactive = true;
  final _events = StreamController<TtsEvent>.broadcast(sync: true);

  void done() => _events.add(TtsDone(ids.last));

  @override
  Stream<TtsEvent> get events => _events.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> isInteractive() async => interactive;

  @override
  Future<void> setPitch(double pitch) async => this.pitch = pitch;

  @override
  Future<void> setRate(double rate) async => this.rate = rate;

  @override
  Future<void> speak(
    String text, {
    required String id,
    String language = '',
    String voice = '',
  }) async {
    spoken.add(text);
    ids.add(id);
    languages.add(language);
  }

  @override
  Future<void> stop() async => stops += 1;

  @override
  Future<List<TtsVoice>> voices({String language = ''}) async => const [];
}
