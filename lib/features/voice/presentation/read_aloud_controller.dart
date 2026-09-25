// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:collection';

import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/chat_view/domain/chat_items.dart';
import 'package:conduit/features/voice/domain/speech_text.dart';
import 'package:conduit/features/voice/domain/text_to_speech.dart';
import 'package:conduit/features/voice/domain/voice_preferences.dart';
import 'package:flutter/foundation.dart';

/// Reads Claude's answers aloud in Chat View, like a conversation: not
/// every item, only what a listener needs.
///
/// [observe] is fed the thread and the agent state after every poll.
/// When a turn ends (the agent waits for input or has ended, with no
/// approval pending), the turn's final answer (the assistant text after
/// its last tool call, see [SpeechText.finalAnswer]) is spoken, cleaned
/// for speech and capped (see [SpeechText.cap]). Intermediate text, tool
/// activity and the working label are never spoken. New approval requests
/// and AskUserQuestion prompts are announced as they appear.
///
/// The first call only records what is there, so opening a chat never
/// re-reads its history. A turn that ends while reading is off, or while
/// [suppressed] (the user is dictating), is marked as heard and not read
/// later. Utterances queue and play one at a time.
///
/// [conversation] (the Talk loop) reads even when [enabled] is off and
/// phrases announcements with how to answer by voice.
class ReadAloudController extends ChangeNotifier {
  ReadAloudController({
    required TextToSpeech tts,
    required this.preferences,
    this.dictationLanguage = _noLanguage,
    bool enabled = false,
  }) : _tts = tts,
       _enabled = enabled;

  static String _noLanguage() => '';

  final TextToSpeech _tts;

  /// Current voice settings (voice, rate, pitch, language).
  final VoicePreferences Function() preferences;

  /// The dictation language, spoken in when no speech language is set.
  final String Function() dictationLanguage;

  bool _enabled;
  bool _suppressed = false;
  bool _available = true;
  bool _conversation = false;
  bool _primed = false;
  final Set<String> _seenItems = {};
  final Set<String> _seenRequests = {};

  /// Assistant text ids already read (or deliberately skipped).
  final Set<String> _heard = {};

  final Queue<String> _queue = Queue();
  String? _currentId;
  Timer? _watchdog;
  int _counter = 0;
  StreamSubscription<TtsEvent>? _events;
  bool _disposed = false;

  bool get enabled => _enabled;

  /// Whether the Talk loop is running (reads regardless of [enabled]).
  bool get conversation => _conversation;
  set conversation(bool value) {
    if (_conversation == value) return;
    _conversation = value;
    if (!value && !_enabled) stop();
    notifyListeners();
  }

  bool get _active => (_enabled || _conversation) && !_suppressed;

  /// Speaking or about to: the Talk loop waits for this to clear.
  bool get busy => _currentId != null || _queue.isNotEmpty;

  /// Whether an utterance is playing right now.
  bool get speaking => _currentId != null;

  /// Whether the device has a text-to-speech engine (the toggle hides
  /// otherwise).
  bool get isAvailable => _available;

  /// Utterances waiting behind the current one (for tests and the UI).
  int get queued => _queue.length;

  /// While true (the user is dictating), nothing is spoken and new items
  /// are skipped. Turning it on stops speech at once.
  bool get suppressed => _suppressed;
  set suppressed(bool value) {
    if (_suppressed == value) return;
    _suppressed = value;
    if (value) stop();
  }

  Future<void> checkAvailability() async {
    final available = await _tts.isAvailable();
    if (_disposed || available == _available) return;
    _available = available;
    notifyListeners();
  }

  /// Whether the phone's screen is on (false once it turns off).
  Future<bool> screenOn() => _tts.isInteractive();

  /// Turns reading on or off. Off stops speech immediately.
  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!value) {
      stop();
    }
    notifyListeners();
  }

  /// Stops speaking and drops everything queued. Items already seen stay
  /// seen.
  void stop() {
    final wasSpeaking = _currentId != null || _queue.isNotEmpty;
    _queue.clear();
    _currentId = null;
    _watchdog?.cancel();
    if (wasSpeaking) {
      unawaited(_tts.stop().catchError((Object _) {}));
      if (!_disposed) notifyListeners();
    }
  }

  /// Feeds the current thread, pending approvals and the agent [state]
  /// (`working`, `waiting_input`, `needs_permission`, `ended`). See the
  /// class docs.
  void observe(
    List<ChatItem> items, [
    List<PendingPermissionRequest> pending = const [],
    String? state,
  ]) {
    if (_disposed) return;
    if (!_primed) {
      _primed = true;
      _seenItems.addAll(items.map((item) => item.id));
      _seenRequests.addAll(pending.map((request) => request.id));
      _heard.addAll(items.whereType<ChatAssistantText>().map((i) => i.id));
      return;
    }
    var lastSeen = -1;
    for (var i = items.length - 1; i >= 0; i--) {
      if (_seenItems.contains(items[i].id)) {
        lastSeen = i;
        break;
      }
    }
    final fresh = <ChatItem>[
      for (var i = lastSeen + 1; i < items.length; i++)
        if (!_seenItems.contains(items[i].id)) items[i],
    ];
    _seenItems.addAll(items.map((item) => item.id));
    final newRequests = [
      for (final request in pending)
        if (_seenRequests.add(request.id)) request,
    ];
    final speak = _active;
    for (final item in fresh) {
      if (!speak) break;
      switch (item) {
        case ChatQuestion() when !item.answered:
          _enqueue(SpeechText.question(item, hint: _conversation));
        case ChatPlan(:final status) when status == ChatPlanStatus.pending:
          _enqueue(SpeechText.planReady);
        default:
          break;
      }
    }
    if (speak) {
      for (final request in newRequests) {
        _enqueue(SpeechText.approval(request, hint: _conversation));
      }
    }
    final turnEnded =
        (state == 'waiting_input' || state == 'ended') && pending.isEmpty;
    if (turnEnded) {
      final answer = SpeechText.finalAnswer(
        items,
      ).where((text) => !_heard.contains(text.id)).toList();
      _heard.addAll(answer.map((text) => text.id));
      if (speak && answer.isNotEmpty) {
        _enqueue(
          SpeechText.cap(
            answer.map((text) => SpeechText.fromMarkdown(text.text)).join(' '),
          ),
        );
      }
    }
  }

  /// Speaks [text] now (queued behind anything playing), e.g. the Talk
  /// loop asking again.
  void say(String text) => _enqueue(text);

  void _enqueue(String? text) {
    if (text == null) return;
    final chunks = SpeechText.chunk(text);
    if (chunks.isEmpty) return;
    _queue.addAll(chunks);
    _listen();
    unawaited(_pump());
  }

  void _listen() {
    _events ??= _tts.events.listen(_onEvent, onError: (Object _) {});
  }

  Future<void> _pump() async {
    if (_disposed || _currentId != null || _queue.isEmpty) return;
    final text = _queue.removeFirst();
    final id = 'read-aloud-${_counter++}';
    _currentId = id;
    notifyListeners();
    final prefs = preferences();
    // A reply the engine never finishes (or never reports on) must not
    // stall the queue: move on after a generous estimate.
    _watchdog?.cancel();
    _watchdog = Timer(
      const Duration(seconds: 10) +
          Duration(milliseconds: (text.length * 120 / prefs.ttsRate).round()),
      () => _finish(id),
    );
    try {
      await _tts.setRate(prefs.ttsRate);
      await _tts.setPitch(prefs.ttsPitch);
      if (_currentId != id) return;
      await _tts.speak(
        text,
        id: id,
        language: prefs.effectiveTtsLanguage(dictationLanguage()),
        voice: prefs.ttsVoice,
      );
    } catch (_) {
      _finish(id);
    }
  }

  void _onEvent(TtsEvent event) {
    switch (event) {
      case TtsDone(:final id) || TtsFailed(:final id) || TtsStopped(:final id):
        _finish(id);
      case TtsInterrupted():
        // A call or another app took the audio: drop the backlog.
        stop();
      case TtsStarted():
        break;
    }
  }

  void _finish(String id) {
    if (_currentId != id || _disposed) return;
    _watchdog?.cancel();
    _currentId = null;
    notifyListeners();
    unawaited(_pump());
  }

  @override
  void dispose() {
    stop();
    _disposed = true;
    _watchdog?.cancel();
    unawaited(_events?.cancel());
    super.dispose();
  }
}
