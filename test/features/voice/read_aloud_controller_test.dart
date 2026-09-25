import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/chat_view/domain/chat_items.dart';
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
}
