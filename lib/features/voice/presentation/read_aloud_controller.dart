// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:collection';

import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/chat_view/domain/chat_items.dart';
import 'package:conduit/features/voice/domain/speech_text.dart';
import 'package:conduit/features/voice/domain/text_to_speech.dart';
import 'package:conduit/features/voice/domain/voice_preferences.dart';
import 'package:flutter/foundation.dart';

/// Reads Chat View replies aloud as they arrive.
///
/// [observe] is fed the thread after every poll. The first call only
/// records what is already there, so opening a chat never re-reads its
/// history; later calls speak the items that appeared after the newest one
/// already seen (older pages loaded by scrolling up are never read).
///
/// Assistant text is spoken as plain speech (see [SpeechText]); runs of
/// tool calls collapse into one cue ("Ran 3 commands and edited
/// todos.ts."), spoken before the next reply or after a short quiet
/// spell; pending approvals and AskUserQuestion prompts are announced.
/// Utterances queue and play one at a time. Anything that arrives while
/// read-aloud is off or [suppressed] (the user is dictating) is skipped,
/// not saved for later.
class ReadAloudController extends ChangeNotifier {
  ReadAloudController({
    required TextToSpeech tts,
    required this.preferences,
    this.dictationLanguage = _noLanguage,
    bool enabled = false,
    this.toolCueDelay = const Duration(seconds: 4),
  }) : _tts = tts,
       _enabled = enabled;

  static String _noLanguage() => '';

  final TextToSpeech _tts;

  /// Current voice settings (voice, rate, pitch, language).
  final VoicePreferences Function() preferences;

  /// The dictation language, spoken in when no speech language is set.
  final String Function() dictationLanguage;

  /// How long a run of tool calls waits for a reply before its cue is
  /// spoken on its own.
  final Duration toolCueDelay;

  bool _enabled;
  bool _suppressed = false;
  bool _available = true;
  bool _primed = false;
  final Set<String> _seenItems = {};
  final Set<String> _seenRequests = {};
  final List<ChatItem> _toolRun = [];
  Timer? _toolTimer;

  final Queue<String> _queue = Queue();
  String? _currentId;
  Timer? _watchdog;
  int _counter = 0;
  StreamSubscription<TtsEvent>? _events;
  bool _disposed = false;

  bool get enabled => _enabled;

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
    _toolTimer?.cancel();
    _toolRun.clear();
    final wasSpeaking = _currentId != null || _queue.isNotEmpty;
    _queue.clear();
    _currentId = null;
    _watchdog?.cancel();
    if (wasSpeaking) {
      unawaited(_tts.stop().catchError((Object _) {}));
      if (!_disposed) notifyListeners();
    }
  }

  /// Feeds the current thread and pending approvals. See the class docs.
  void observe(
    List<ChatItem> items, [
    List<PendingPermissionRequest> pending = const [],
  ]) {
    if (_disposed) return;
    if (!_primed) {
      _primed = true;
      _seenItems.addAll(items.map((item) => item.id));
      _seenRequests.addAll(pending.map((request) => request.id));
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
    if (!_enabled || _suppressed) {
      return;
    }
    for (final item in fresh) {
      switch (item) {
        case ChatToolCall() || ChatTodoList():
          _toolRun.add(item);
        case ChatAssistantText(:final text):
          _flushToolRun();
          _enqueue(SpeechText.fromMarkdown(text));
        case ChatQuestion() when !item.answered:
          _flushToolRun();
          _enqueue(SpeechText.question(item));
        case ChatPlan(:final status) when status == ChatPlanStatus.pending:
          _flushToolRun();
          _enqueue(SpeechText.planReady);
        case ChatNotice(:final kind, :final text)
            when kind == ChatNoticeKind.error:
          _flushToolRun();
          _enqueue('Error. ${SpeechText.inline(text)}');
        default:
          break;
      }
    }
    for (final request in newRequests) {
      _flushToolRun();
      _enqueue(SpeechText.approval(request));
    }
    if (_toolRun.isNotEmpty) {
      _toolTimer?.cancel();
      _toolTimer = Timer(toolCueDelay, () {
        if (_enabled && !_suppressed) _flushToolRun();
      });
    }
  }

  void _flushToolRun() {
    _toolTimer?.cancel();
    if (_toolRun.isEmpty) return;
    final cue = SpeechText.toolCue(_toolRun);
    _toolRun.clear();
    _enqueue(cue);
  }

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
    _toolTimer?.cancel();
    _watchdog?.cancel();
    unawaited(_events?.cancel());
    super.dispose();
  }
}
