import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/chat_view/domain/chat_items.dart';
import 'package:conduit/features/voice/domain/text_to_speech.dart';
import 'package:conduit/features/voice/domain/voice_preferences.dart';
import 'package:conduit/features/voice/presentation/read_aloud_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_tts.dart';

ChatAssistantText reply(String id, String text) =>
    ChatAssistantText(id, text: text);

ChatUserMessage prompt(String id) => ChatUserMessage(id, text: 'go');

ChatToolCall bash(String id) => ChatToolCall(
  id,
  name: 'Bash',
  input: const {'command': 'ls'},
  kind: ChatToolKind.bash,
);

const request = PendingPermissionRequest(
  id: 'p1',
  toolName: 'Bash',
  summary: 'npm test',
);

void main() {
  late FakeTts tts;
  late VoicePreferences prefs;
  late ReadAloudController controller;

  setUp(() {
    tts = FakeTts();
    prefs = VoicePreferences.defaults.copyWith(ttsRate: 1.3, ttsPitch: 0.8);
    controller = ReadAloudController(
      tts: tts,
      preferences: () => prefs,
      dictationLanguage: () => 'pt-PT',
      enabled: true,
    );
  });

  tearDown(() => controller.dispose());

  test('never re-reads the answer already on screen when opened', () async {
    final thread = [prompt('u1'), reply('a', 'Old answer.')];
    controller.observe(thread, const [], 'waiting_input');
    controller.observe(thread, const [], 'waiting_input');
    await pumpEventQueue();
    expect(tts.spoken, isEmpty);
  });

  test('reads only the final answer once the turn ends', () async {
    controller.observe([prompt('u1')], const [], 'working');
    final midTurn = [
      prompt('u1'),
      reply('a1', 'Let me look at the **tests**.'),
      bash('t1'),
      bash('t2'),
    ];
    controller.observe(midTurn, const [], 'working');
    await pumpEventQueue();
    expect(tts.spoken, isEmpty, reason: 'no chatter or tool output');

    final done = [
      ...midTurn,
      reply('a2', 'Fixed the `parser`.'),
      reply('a3', 'All tests pass.'),
    ];
    controller.observe(done, const [], 'working');
    await pumpEventQueue();
    expect(tts.spoken, isEmpty, reason: 'still working');

    controller.observe(done, const [], 'waiting_input');
    controller.observe(done, const [], 'waiting_input');
    await pumpEventQueue();
    expect(tts.spoken, ['Fixed the parser. All tests pass.']);
    expect(tts.languages, ['pt-PT']);
    expect(tts.rate, 1.3);
    expect(tts.pitch, 0.8);
  });

  test('long answers are capped', () async {
    controller.observe([prompt('u1')], const [], 'working');
    final long = List.filled(60, 'This sentence is filler.').join(' ');
    controller.observe([prompt('u1'), reply('a', long)], const [], 'ended');
    await pumpEventQueue();
    expect(tts.spoken.single, endsWith('…the rest is on screen.'));
    expect(tts.spoken.single.length, lessThan(700));
  });

  test('announces approvals once and open questions', () async {
    controller.observe([prompt('u1')], const [], 'working');
    controller.observe([prompt('u1')], const [request], 'needs_permission');
    controller.observe([prompt('u1')], const [request], 'needs_permission');
    await pumpEventQueue();
    expect(tts.spoken, ['Claude needs your approval to run npm test.']);
    tts.done();

    controller.observe(
      [
        prompt('u1'),
        const ChatQuestion(
          'q1',
          questions: [ChatQuestionPrompt(question: 'Ship it?')],
        ),
      ],
      const [],
      'waiting_input',
    );
    await pumpEventQueue();
    expect(tts.spoken.last, 'Claude is asking: Ship it?');
  });

  test('queues utterances and plays them one at a time', () async {
    controller.observe([prompt('u1')], const [], 'working');
    controller.observe(
      [prompt('u1'), reply('a', 'Answer.')],
      const [request],
      'needs_permission',
    );
    controller.observe(
      [prompt('u1'), reply('a', 'Answer.')],
      const [],
      'waiting_input',
    );
    await pumpEventQueue();
    expect(tts.spoken, ['Claude needs your approval to run npm test.']);
    expect(controller.busy, isTrue);
    tts.done();
    await pumpEventQueue();
    expect(tts.spoken.last, 'Answer.');
    tts.done();
    await pumpEventQueue();
    expect(controller.busy, isFalse);
  });

  test('dictation and stop drop speech; a turn that ended meanwhile is not '
      'read later', () async {
    controller.observe([prompt('u1')], const [], 'working');
    controller.observe([prompt('u1')], const [request], 'needs_permission');
    await pumpEventQueue();
    expect(tts.spoken, hasLength(1));

    controller.suppressed = true;
    expect(tts.stops, 1);
    expect(controller.busy, isFalse);
    final done = [prompt('u1'), reply('a', 'Missed.')];
    controller.observe(done, const [], 'waiting_input');
    controller.suppressed = false;
    controller.observe(done, const [], 'waiting_input');
    tts.done(); // A late "done" for the stopped utterance changes nothing.
    await pumpEventQueue();
    expect(tts.spoken, hasLength(1));
  });

  test('turning the toggle off stops at once', () async {
    controller.observe([prompt('u1')], const [], 'working');
    controller.observe(
      [prompt('u1'), reply('a', 'Speaking.')],
      const [],
      'waiting_input',
    );
    await pumpEventQueue();
    controller.setEnabled(false);
    expect(tts.stops, 1);
    controller.observe(
      [prompt('u1'), reply('a', 'Speaking.'), prompt('u2'), reply('b', 'No.')],
      const [],
      'waiting_input',
    );
    controller.setEnabled(true);
    await pumpEventQueue();
    expect(tts.spoken, ['Speaking.']);
  });

  test(
    'the Talk loop reads while the toggle is off, with answer hints',
    () async {
      controller
        ..setEnabled(false)
        ..conversation = true;
      controller.observe([prompt('u1')], const [], 'working');
      controller.observe([prompt('u1')], const [request], 'needs_permission');
      await pumpEventQueue();
      expect(
        tts.spoken.single,
        'Claude needs your approval to run npm test. '
        'Say allow, deny, or always.',
      );
    },
  );

  testWidgets('a stalled engine does not block the queue', (tester) async {
    final c = ReadAloudController(
      tts: tts,
      preferences: () => prefs,
      enabled: true,
    );
    c.observe([prompt('u1')], const [], 'working');
    c.observe([prompt('u1')], const [request], 'needs_permission');
    c.observe([prompt('u1'), reply('a', 'Second.')], const [], 'waiting_input');
    await tester.pump();
    expect(tts.spoken, hasLength(1));
    await tester.pump(const Duration(seconds: 30));
    expect(tts.spoken.last, 'Second.');
    c.dispose();
  });

  test('a new message arriving mid-speech queues behind it', () async {
    controller.observe([prompt('u1')], const [], 'working');
    final first = [prompt('u1'), reply('a', 'First answer.')];
    controller.observe(first, const [], 'waiting_input');
    await pumpEventQueue();
    expect(tts.spoken, ['First answer.']);
    tts.emit(TtsStarted(tts.ids.last));

    // More polls while it speaks: the agent flips back to working, a new
    // reply and an approval arrive.
    final second = [...first, prompt('u2'), reply('b', 'Second answer.')];
    controller.observe(second, const [], 'working');
    controller.observe(second, const [], 'waiting_input');
    controller.observe(second, const [request], 'needs_permission');
    await pumpEventQueue();
    expect(tts.stops, 0, reason: 'nothing is cut off');
    expect(tts.spoken, ['First answer.'], reason: 'nothing is flushed');
    expect(controller.speaking, isTrue);
    expect(controller.queued, 2);

    tts.done();
    await pumpEventQueue();
    expect(tts.spoken.last, 'Second answer.');
    tts.done();
    await pumpEventQueue();
    expect(tts.spoken.last, 'Claude needs your approval to run npm test.');
  });

  test('a short audio interruption (a notification, a ringtone) pauses and '
      'resumes from the sentence it cut, keeping the queue', () async {
    controller.observe([prompt('u1')], const [], 'working');
    controller.observe(
      [prompt('u1'), reply('a', 'One is done. Two is next. Three last.')],
      const [request],
      'needs_permission',
    );
    controller.observe(
      [prompt('u1'), reply('a', 'One is done. Two is next. Three last.')],
      const [],
      'waiting_input',
    );
    await pumpEventQueue();
    expect(tts.spoken, ['Claude needs your approval to run npm test.']);
    tts.done();
    await pumpEventQueue();
    expect(tts.spoken.last, 'One is done. Two is next. Three last.');
    final id = tts.ids.last;
    tts.emit(TtsStarted(id));

    // Cut in the middle of "Two is next".
    tts.emit(TtsPaused(id, offset: 17));
    tts.emit(TtsStopped(id)); // The engine reports the cut too.
    await pumpEventQueue();
    expect(controller.busy, isTrue, reason: 'the reply is kept');
    expect(controller.speaking, isFalse);
    expect(tts.spoken, hasLength(2), reason: 'waits for the audio back');
    expect(tts.stops, 0);

    tts.emit(const TtsResumed());
    await pumpEventQueue();
    expect(tts.spoken.last, 'Two is next. Three last.');
    tts.done();
    await pumpEventQueue();
    expect(controller.busy, isFalse);
  });

  test('a call or another app taking the audio for good stops', () async {
    controller.observe([prompt('u1')], const [], 'working');
    controller.observe([prompt('u1')], const [request], 'needs_permission');
    controller.observe(
      [prompt('u1'), reply('a', 'Answer.')],
      const [],
      'waiting_input',
    );
    await pumpEventQueue();
    tts.emit(const TtsInterrupted());
    await pumpEventQueue();
    expect(controller.busy, isFalse);
    expect(tts.spoken, hasLength(1));
  });

  testWidgets('audio that never comes back is given up after a while', (
    tester,
  ) async {
    final c = ReadAloudController(
      tts: tts,
      preferences: () => prefs,
      enabled: true,
    );
    c.observe([prompt('u1')], const [], 'working');
    c.observe([prompt('u1'), reply('a', 'Answer.')], const [], 'ended');
    await tester.pump();
    tts.emit(TtsPaused(tts.ids.last));
    await tester.pump(const Duration(minutes: 1));
    expect(c.busy, isTrue);
    await tester.pump(const Duration(minutes: 5));
    expect(c.busy, isFalse);
    expect(tts.spoken, hasLength(1));
    c.dispose();
  });

  testWidgets('the watchdog does not cut a long reply the engine started '
      'late', (tester) async {
    final c = ReadAloudController(
      tts: tts,
      preferences: () => prefs,
      enabled: true,
    );
    final long = List.filled(24, 'This sentence is filler.').join(' ');
    c.observe([prompt('u1')], const [], 'working');
    c.observe([prompt('u1')], const [request], 'needs_permission');
    await tester.pump();
    tts.done();
    await tester.pump();
    expect(tts.spoken, hasLength(1));
    c.observe([prompt('u1'), reply('a', long)], const [], 'waiting_input');
    c.observe(
      [prompt('u1'), reply('a', long)],
      const [
        PendingPermissionRequest(id: 'p2', toolName: 'Bash', summary: 'ls'),
      ],
      'needs_permission',
    );
    await tester.pump();
    expect(tts.spoken, hasLength(2));
    // A slow engine (first use, a large voice) starts nine seconds late
    // and speaks slowly.
    await tester.pump(const Duration(seconds: 9));
    tts.emit(TtsStarted(tts.ids.last));
    await tester.pump(const Duration(seconds: 75));
    expect(tts.spoken, hasLength(2), reason: 'still speaking: never cut');
    tts.done();
    await tester.pump();
    expect(tts.spoken, hasLength(3));
    c.dispose();
  });
}
