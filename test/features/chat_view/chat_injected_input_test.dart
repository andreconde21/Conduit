import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/chat_view/domain/chat_items.dart';
import 'package:conduit/features/chat_view/domain/chat_transcript.dart';
import 'package:conduit/features/chat_view/domain/chat_user_input.dart';
import 'package:conduit/features/chat_view/presentation/chat_view_controller.dart';
import 'package:conduit/features/chat_view/presentation/chat_view_page.dart';
import 'package:conduit/features/voice/domain/voice_preferences.dart';
import 'package:conduit/features/voice/presentation/read_aloud_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';
import '../voice/fake_tts.dart';
import 'chat_fixtures.dart';

// Synthetic shapes of what Claude Code writes as `user` lines; no real
// transcript content.
const teammate =
    'Another Claude session sent a message:\n'
    '<teammate-message teammate_id="builder-1" color="blue" '
    'summary="Parser fixed, tests green">\n'
    'The parser is fixed.\nline 2\nline 3\nline 4\nline 5\nline 6\n'
    '</teammate-message>\n\n'
    '<teammate-message teammate_id="builder-1" color="blue">\n'
    '{"type":"idle_notification","from":"builder-1",'
    '"timestamp":"2026-01-01T00:00:00Z","idleReason":"available",'
    '"result":"Done and reported."}\n'
    '</teammate-message>';
const crossSession =
    '<cross-session-message from="docs-writer">Readme updated.'
    '</cross-session-message>';
const task =
    '<task-notification>\n<task-id>t1</task-id>\n<status>completed</status>\n'
    '<summary>Background command "Build the app" completed (exit code 0)'
    '</summary>\n</task-notification>';
const failedTask =
    '<task-notification><status>failed</status></task-notification>';
const reminder =
    '<system-reminder>Internal note for the model.</system-reminder>';
const notification = '[SYSTEM NOTIFICATION - NOT USER INPUT] Something ran.';
const bashIn = '<bash-input>git status</bash-input>';
const bashOut =
    '<bash-stdout>On branch main</bash-stdout><bash-stderr></bash-stderr>';
const slash =
    '<command-message>review is running…</command-message>\n'
    '<command-name>/review</command-name>\n<command-args>42</command-args>';
const whileWorking =
    'The user sent a new message while you were working:\n'
    'also update the docs\n\n'
    'IMPORTANT: After completing your current task, you MUST address the '
    "user's message above. Do not ignore it.";
const pasted =
    'Look at this log:\n<pasted_content id="ab12">\nerror 1\nerror 2\n'
    'error 3\nerror 4\n</pasted_content>';

List<ChatItem> build(List<Map<String, Object?>> lines) => ChatItemBuilder.build(
  [for (final line in lines) TranscriptParser.parseEntry(line)!],
);

AgentCommandResult ok(String stdout) =>
    AgentCommandResult(stdout: stdout, stderr: '', exitCode: 0);

void main() {
  group('parse', () {
    test('teammate messages and idle notifications', () {
      final parts = ChatUserInput.parse(teammate);
      expect(parts, hasLength(2));
      final message = parts[0] as AgentMessagePart;
      expect(message.from, 'builder-1');
      expect(message.summary, 'Parser fixed, tests green');
      expect(message.body, startsWith('The parser is fixed.'));
      expect(message.idle, isFalse);
      final idle = parts[1] as AgentMessagePart;
      expect(idle.idle, isTrue);
      expect(idle.body, 'Done and reported.');
    });

    test('cross-session messages', () {
      final part = ChatUserInput.parse(crossSession).single as AgentMessagePart;
      expect(part.from, 'docs-writer');
      expect(part.session, isTrue);
      expect(part.body, 'Readme updated.');
    });

    test('a message cut off by the host keeps its sender', () {
      final part =
          ChatUserInput.parse(
                'Another Claude session sent a message:\n'
                '<teammate-message teammate_id="x-2" summary="Long">Body…',
              ).single
              as AgentMessagePart;
      expect(part.from, 'x-2');
      expect(part.body, 'Body…');
    });

    test('task notifications', () {
      final done = ChatUserInput.parse(task).single as TaskPart;
      expect(
        done.summary,
        'Background command "Build the app" completed '
        '(exit code 0)',
      );
      expect(done.status, 'completed');
      final failed = ChatUserInput.parse(failedTask).single as TaskPart;
      expect(failed.summary, 'Background task failed');
    });

    test('system reminders and notifications are hidden', () {
      expect(ChatUserInput.parse(reminder), isEmpty);
      expect(ChatUserInput.parse(notification), isEmpty);
      final text =
          ChatUserInput.parse('fix it\n$reminder').single as UserTextPart;
      expect(text.text, 'fix it');
    });

    test('shell commands, slash commands and wrapped user text', () {
      expect(
        (ChatUserInput.parse(bashIn).single as ShellInputPart).command,
        'git status',
      );
      final out = ChatUserInput.parse(bashOut).single as ShellOutputPart;
      expect(out.stdout, 'On branch main');
      expect(
        (ChatUserInput.parse(slash).single as SlashCommandPart).command,
        '/review 42',
      );
      expect(
        (ChatUserInput.parse(whileWorking).single as UserTextPart).text,
        'also update the docs',
      );
    });

    test('pasted content is set apart from the text', () {
      final part = ChatUserInput.parse(pasted).single as UserTextPart;
      expect(part.text, 'Look at this log:');
      expect(part.pasted.single, startsWith('error 1'));
    });

    test('unknown tags fall back to the user text', () {
      final part =
          ChatUserInput.parse('<weird-tag>hello</weird-tag>').single
              as UserTextPart;
      expect(part.text, '<weird-tag>hello</weird-tag>');
    });
  });

  test('items: shell output joins its command; kinds map to items', () {
    final items = build([
      userLine('t1', teammate),
      userLine('c1', crossSession),
      userLine('k1', task),
      userLine('r1', reminder),
      userLine('b1', bashIn),
      userLine('b2', bashOut),
      userLine('s1', slash),
      userLine('w1', whileWorking),
      userLine('p1', pasted),
    ]);
    expect(items.map((i) => i.runtimeType), [
      ChatAgentMessage,
      ChatAgentMessage,
      ChatAgentMessage,
      ChatTaskNotice,
      ChatShellCommand,
      ChatUserMessage,
      ChatUserMessage,
      ChatUserMessage,
    ]);
    final shell = items[4] as ChatShellCommand;
    expect(shell.stdout, 'On branch main');
    expect(shell.failed, isFalse);
    expect((items[5] as ChatUserMessage).isCommand, isTrue);
    expect((items[6] as ChatUserMessage).text, 'also update the docs');
    expect((items[7] as ChatUserMessage).pasted, hasLength(1));
  });

  test('reading aloud skips injected inputs', () async {
    final tts = FakeTts();
    final reader = ReadAloudController(
      tts: tts,
      preferences: () => VoicePreferences.defaults,
      enabled: true,
    );
    addTearDown(reader.dispose);
    reader.observe(const [], const [], 'waiting_input');
    final items = build([
      userLine('t1', teammate),
      userLine('c1', crossSession),
      userLine('k1', task),
      userLine('b1', bashIn),
      userLine('b2', bashOut),
      userLine('s1', slash),
    ]);
    reader.observe(items, const [], 'working');
    reader.observe(items, const [], 'waiting_input');
    await pumpEventQueue();
    expect(tts.spoken, isEmpty);
  });

  testWidgets('Chat View renders each kind distinctly', (tester) async {
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = ChatViewController(
      runner: ScriptedAgentCommandRunner([
        ok(
          page([
            userLine('t1', teammate),
            userLine('c1', crossSession),
            userLine('k1', task),
            userLine('r1', reminder),
            userLine('b1', bashIn),
            userLine('b2', bashOut),
            userLine('s1', slash),
            userLine('w1', whileWorking),
            userLine('p1', pasted),
          ]),
        ),
      ]),
      sessionId: 's-1',
      pollInterval: const Duration(days: 1),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ChatViewPage(controller: controller, onOpenTerminal: () {}),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('From agent builder-1'), findsOneWidget);
    expect(find.text('Parser fixed, tests green'), findsOneWidget);
    expect(find.text('Show more'), findsOneWidget);
    await tester.tap(find.text('Show more'));
    await tester.pump();
    expect(find.text('Show less'), findsOneWidget);
    expect(find.text('builder-1 is idle'), findsOneWidget);
    expect(find.text('From session docs-writer'), findsOneWidget);
    expect(find.textContaining('Build the app'), findsOneWidget);
    expect(find.textContaining('Internal note'), findsNothing);
    expect(find.text('You ran'), findsOneWidget);
    expect(find.text('git status'), findsOneWidget);
    await tester.tap(find.text('git status'));
    await tester.pump();
    expect(find.text('On branch main'), findsOneWidget);
    expect(find.byKey(const ValueKey('slash-command-chip')), findsOneWidget);
    expect(find.text('also update the docs'), findsOneWidget);
    expect(find.textContaining('IMPORTANT'), findsNothing);
    expect(find.text('Look at this log:'), findsOneWidget);
    expect(find.text('Pasted text · 4 lines'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
