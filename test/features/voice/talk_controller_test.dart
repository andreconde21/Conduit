import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/chat_view/domain/chat_items.dart';
import 'package:conduit/features/voice/domain/speech_event.dart';
import 'package:conduit/features/voice/domain/voice_preferences.dart';
import 'package:conduit/features/voice/presentation/dictation_controller.dart';
import 'package:conduit/features/voice/presentation/read_aloud_controller.dart';
import 'package:conduit/features/voice/presentation/talk_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_speech_recognizer.dart';
import 'fake_tts.dart';

ChatUserMessage prompt(String id, String text) =>
    ChatUserMessage(id, text: text);

ChatAssistantText reply(String id, String text) =>
    ChatAssistantText(id, text: text);

const request = PendingPermissionRequest(
  id: 'p1',
  toolName: 'Bash',
  summary: 'npm test',
);

void main() {
  late FakeSpeechRecognizer mic;
  late FakeTts tts;
  late DictationController dictation;
  late ReadAloudController readAloud;
  late TalkController talk;
  late List<String> sent;
  late List<(String, PermissionVerdict)> decided;
  late List<int> answered;

  /// Feeds a poll to the reader and the loop, as the page does.
  void poll(
    List<ChatItem> items, [
    List<PendingPermissionRequest> pending = const [],
    String state = 'waiting_input',
  ]) {
    readAloud.observe(items, pending, state);
    talk.update(items, pending, state);
  }

  Future<void> settle(
    WidgetTester tester, [
    Duration by = Duration.zero,
  ]) async {
    await tester.pump(by);
    await tester.pump();
  }

  Future<void> setUpTalk(WidgetTester tester) async {
    mic = FakeSpeechRecognizer();
    tts = FakeTts();
    sent = [];
    decided = [];
    answered = [];
    dictation = DictationController(mic, language: () => 'en-US');
    readAloud = ReadAloudController(
      tts: tts,
      preferences: () => VoicePreferences.defaults,
    );
    talk = TalkController(
      dictation: dictation,
      readAloud: readAloud,
      send: (text) async => sent.add(text),
      decide: (r, v) async => decided.add((r.id, v)),
      answer: (n) async => answered.add(n),
      options: () => const DictationOptions(
        continuous: true,
        silenceTimeout: Duration(seconds: 2),
      ),
    );
    addTearDown(() {
      talk.dispose();
      readAloud.dispose();
      dictation.dispose();
    });
    // The page primes the reader with the thread on open.
    poll([prompt('u0', 'hi'), reply('a0', 'Hello.')]);
  }

  testWidgets('listen, pause, countdown, send, stay quiet, read the final '
      'answer, listen again', (tester) async {
    await setUpTalk(tester);
    talk.start();
    await settle(tester);
    expect(talk.phase, TalkPhase.listening);
    expect(mic.starts.single.continuous, isTrue);

    // Nothing said yet: silence does not end the turn.
    await settle(tester, const Duration(seconds: 5));
    expect(talk.phase, TalkPhase.listening);

    mic.emit(const SpeechReady());
    mic.emit(const SpeechPartial('run the'));
    await settle(tester);
    expect(talk.transcript, 'run the');
    mic.emit(const SpeechResult('run the tests'));
    await settle(tester, const Duration(seconds: 3));
    expect(talk.phase, TalkPhase.confirming);
    expect(talk.transcript, 'run the tests');
    expect(sent, isEmpty);
    await settle(tester, const Duration(seconds: 1));
    expect(talk.countdown.inMilliseconds, lessThan(2000));
    await settle(tester, const Duration(seconds: 2));
    expect(sent, ['run the tests']);
    expect(talk.phase, TalkPhase.waiting);

    // Claude works: nothing is spoken.
    final working = [
      prompt('u0', 'hi'),
      reply('a0', 'Hello.'),
      prompt('u1', 'run the tests'),
      reply('a1', 'Running them.'),
      ChatToolCall(
        't1',
        name: 'Bash',
        input: const {'command': 'npm test'},
        kind: ChatToolKind.bash,
      ),
    ];
    poll(working, const [], 'working');
    await settle(tester);
    expect(tts.spoken, isEmpty);
    expect(talk.phase, TalkPhase.waiting);

    // The turn ends: only the final answer is read, then it listens again.
    final startsBefore = mic.starts.length;
    poll([...working, reply('a2', 'All **12** tests pass.')]);
    await settle(tester);
    expect(talk.phase, TalkPhase.speaking);
    expect(tts.spoken, ['All 12 tests pass.']);
    expect(
      mic.starts,
      hasLength(startsBefore),
      reason: 'the mic waits for the voice',
    );
    tts.done();
    await settle(tester, const Duration(milliseconds: 500));
    expect(talk.phase, TalkPhase.listening);
    expect(mic.starts, hasLength(startsBefore + 1));
    expect(mic.starts.last.restart, isFalse);
    talk.stop();
  });

  testWidgets('cancelling in the countdown keeps the text unsent', (
    tester,
  ) async {
    await setUpTalk(tester);
    talk.start();
    await settle(tester);
    mic.say('delete everything');
    await settle(tester, const Duration(seconds: 3));
    expect(talk.phase, TalkPhase.confirming);
    expect(talk.stop(), 'delete everything');
    await settle(tester, const Duration(seconds: 3));
    expect(sent, isEmpty);
    expect(talk.phase, TalkPhase.off);
    expect(readAloud.conversation, isFalse);
  });

  testWidgets('approvals are announced and answered by voice', (tester) async {
    await setUpTalk(tester);
    talk.start();
    await settle(tester);
    mic.say('clean the build');
    await settle(tester, const Duration(seconds: 5));
    expect(sent, ['clean the build']);

    final thread = [
      prompt('u0', 'hi'),
      reply('a0', 'Hello.'),
      prompt('u1', 'x'),
    ];
    poll(thread, const [request], 'needs_permission');
    await settle(tester);
    expect(
      tts.spoken.single,
      'Claude needs your approval to run npm test. '
      'Say allow, deny, or always.',
    );
    tts.done();
    await settle(tester, const Duration(milliseconds: 500));
    expect(talk.phase, TalkPhase.listening);
    expect(talk.target, isA<TalkApproval>());

    // Unclear: it asks again.
    mic.say('hmm maybe');
    await settle(tester, const Duration(seconds: 3));
    expect(tts.spoken.last, 'Say allow, deny, or always.');
    tts.done();
    await settle(tester, const Duration(milliseconds: 500));
    mic.say('yes allow it');
    await settle(tester, const Duration(seconds: 3));
    expect(decided, [('p1', PermissionVerdict.allow)]);
    expect(talk.phase, TalkPhase.waiting);
    talk.stop();
  });

  testWidgets('questions are answered by option number or name', (
    tester,
  ) async {
    await setUpTalk(tester);
    talk.start();
    await settle(tester);
    mic.say('set up the database');
    await settle(tester, const Duration(seconds: 5));
    poll([
      prompt('u0', 'hi'),
      reply('a0', 'Hello.'),
      prompt('u1', 'set up the database'),
      const ChatQuestion(
        'q1',
        questions: [
          ChatQuestionPrompt(
            question: 'Which database?',
            options: [
              ChatQuestionOption(label: 'Postgres'),
              ChatQuestionOption(label: 'SQLite'),
            ],
          ),
        ],
      ),
    ]);
    await settle(tester);
    expect(tts.spoken.single, contains('Options: 1, Postgres; 2, SQLite.'));
    tts.done();
    await settle(tester, const Duration(milliseconds: 500));
    expect(talk.target, isA<TalkQuestion>());
    mic.say('SQLite');
    await settle(tester, const Duration(seconds: 3));
    expect(answered, [2]);
    talk.stop();
  });

  testWidgets('an ended session ends the loop after the answer', (
    tester,
  ) async {
    await setUpTalk(tester);
    talk.start();
    await settle(tester);
    mic.say('wrap up');
    await settle(tester, const Duration(seconds: 5));
    poll(
      [
        prompt('u0', 'hi'),
        reply('a0', 'Hello.'),
        prompt('u1', 'wrap up'),
        reply('a1', 'Bye.'),
      ],
      const [],
      'ended',
    );
    await settle(tester);
    tts.done();
    await settle(tester, const Duration(milliseconds: 500));
    expect(tts.spoken, ['Bye.']);
    expect(talk.phase, TalkPhase.off);
  });

  testWidgets('no microphone permission stops the loop', (tester) async {
    await setUpTalk(tester);
    mic.permission = false;
    talk.start();
    await settle(tester);
    expect(talk.phase, TalkPhase.off);
    expect(talk.message, contains('Microphone'));
  });
}
