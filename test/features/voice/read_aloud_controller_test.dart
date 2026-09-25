import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/chat_view/domain/chat_items.dart';
import 'package:conduit/features/voice/domain/voice_preferences.dart';
import 'package:conduit/features/voice/presentation/read_aloud_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_tts.dart';

ChatAssistantText reply(String id, String text) =>
    ChatAssistantText(id, text: text);

ChatToolCall bash(String id) => ChatToolCall(
  id,
  name: 'Bash',
  input: const {'command': 'ls'},
  kind: ChatToolKind.bash,
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

  test('never re-reads the history present on open', () async {
    controller.observe([reply('a', 'Old one'), reply('b', 'Old two')]);
    await pumpEventQueue();
    expect(tts.spoken, isEmpty);

    controller.observe([
      reply('a', 'Old one'),
      reply('b', 'Old two'),
      reply('c', 'New **reply**'),
    ]);
    await pumpEventQueue();
    expect(tts.spoken, ['New reply.']);
    expect(tts.languages, ['pt-PT']);
    expect(tts.rate, 1.3);
    expect(tts.pitch, 0.8);
  });

  test('older pages loaded by scrolling up are not read', () async {
    controller.observe([reply('c', 'Latest')]);
    controller.observe([
      reply('a', 'Older'),
      reply('b', 'Old'),
      reply('c', 'Latest'),
    ]);
    await pumpEventQueue();
    expect(tts.spoken, isEmpty);
  });

  test('queues utterances and plays them one at a time', () async {
    controller.observe(const []);
    controller.observe([reply('a', 'First.'), reply('b', 'Second.')]);
    await pumpEventQueue();
    expect(tts.spoken, ['First.']);
    expect(controller.speaking, isTrue);
    expect(controller.queued, 1);

    tts.done();
    await pumpEventQueue();
    expect(tts.spoken, ['First.', 'Second.']);
    tts.done();
    await pumpEventQueue();
    expect(controller.speaking, isFalse);
  });

  test('tool runs collapse into one cue before the next reply', () async {
    controller.observe(const []);
    controller.observe([bash('t1'), bash('t2')]);
    controller.observe([
      bash('t1'),
      bash('t2'),
      bash('t3'),
      reply('r', 'Done.'),
    ]);
    await pumpEventQueue();
    expect(tts.spoken, ['Ran 3 commands.']);
    tts.done();
    await pumpEventQueue();
    expect(tts.spoken, ['Ran 3 commands.', 'Done.']);
  });

  testWidgets('a tool run with no reply is spoken after a quiet spell', (
    tester,
  ) async {
    {
      final c = ReadAloudController(
        tts: tts,
        preferences: () => prefs,
        enabled: true,
      );
      c.observe(const []);
      c.observe([bash('t1')]);
      await tester.pump();
      expect(tts.spoken, isEmpty);
      await tester.pump(const Duration(seconds: 5));
      expect(tts.spoken, ['Ran a command.']);
      c.dispose();
    }
  });

  test('announces pending approvals once and open questions', () async {
    controller.observe(const []);
    const request = PendingPermissionRequest(
      id: 'p1',
      toolName: 'Bash',
      summary: 'rm -rf build',
    );
    controller.observe(const [], [request]);
    controller.observe(const [], [request]);
    await pumpEventQueue();
    expect(tts.spoken, ['Claude needs your approval: Bash, rm -rf build.']);
    tts.done();

    controller.observe([
      const ChatQuestion(
        'q1',
        questions: [ChatQuestionPrompt(question: 'Ship it?')],
      ),
    ]);
    await pumpEventQueue();
    expect(tts.spoken.last, 'Claude is asking: Ship it?');
  });

  test(
    'stop and dictation drop the queue; items meanwhile are skipped',
    () async {
      controller.observe(const []);
      controller.observe([reply('a', 'One.'), reply('b', 'Two.')]);
      await pumpEventQueue();
      expect(tts.spoken, ['One.']);

      controller.suppressed = true; // the user started dictating
      expect(tts.stops, 1);
      expect(controller.speaking, isFalse);
      expect(controller.queued, 0);

      controller.observe([
        reply('a', 'One.'),
        reply('b', 'Two.'),
        reply('c', 'Three.'),
      ]);
      controller.suppressed = false;
      await pumpEventQueue();
      // A late "done" for the stopped utterance changes nothing.
      tts.done();
      await pumpEventQueue();
      expect(tts.spoken, ['One.']);

      controller.observe([
        reply('a', 'One.'),
        reply('b', 'Two.'),
        reply('c', 'Three.'),
        reply('d', 'Four.'),
      ]);
      await pumpEventQueue();
      expect(tts.spoken, ['One.', 'Four.']);
    },
  );

  test(
    'turning the toggle off stops at once; nothing is read while off',
    () async {
      controller.observe(const []);
      controller.observe([reply('a', 'Speaking.')]);
      await pumpEventQueue();
      controller.setEnabled(false);
      expect(tts.stops, 1);
      controller.observe([reply('a', 'Speaking.'), reply('b', 'Missed.')]);
      controller.setEnabled(true);
      await pumpEventQueue();
      expect(tts.spoken, ['Speaking.']);
    },
  );

  testWidgets('a stalled engine does not block the queue', (tester) async {
    {
      final c = ReadAloudController(
        tts: tts,
        preferences: () => prefs,
        enabled: true,
      );
      c.observe(const []);
      c.observe([reply('a', 'First.'), reply('b', 'Second.')]);
      await tester.pump();
      expect(tts.spoken, ['First.']);
      await tester.pump(const Duration(seconds: 30));
      expect(tts.spoken, ['First.', 'Second.']);
      c.dispose();
    }
  });
}
