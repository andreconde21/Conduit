import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/chat_view/domain/chat_items.dart';
import 'package:conduit/features/chat_view/domain/chat_transcript.dart';
import 'package:conduit/features/chat_view/domain/chat_working.dart';
import 'package:conduit/features/chat_view/presentation/chat_view_controller.dart';
import 'package:conduit/features/chat_view/presentation/chat_view_page.dart';
import 'package:conduit/features/chat_view/presentation/widgets/chat_working_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';
import 'chat_fixtures.dart';

AgentCommandResult ok(String stdout) =>
    AgentCommandResult(stdout: stdout, stderr: '', exitCode: 0);

ChatToolCall call(
  String id,
  String name,
  Map<String, Object?> input, {
  bool done = false,
}) => ChatToolCall(
  id,
  name: name,
  input: input,
  kind: ChatItemBuilder.toolKind(name),
  result: done ? const ChatToolResult(content: 'ok', isError: false) : null,
);

const working = ChatAgentStatus(state: 'working');
final prompt = ChatUserMessage(
  'u',
  text: 'go',
  timestamp: DateTime.utc(2026, 9, 25, 10),
);

void main() {
  group('ChatWorking.of', () {
    test('hidden while waiting, asking for approval or ended', () {
      for (final state in ['waiting_input', 'needs_permission', 'ended']) {
        expect(
          ChatWorking.of(ChatAgentStatus(state: state), [prompt]),
          isNull,
          reason: state,
        );
      }
    });

    test('hidden the moment the reply text arrives', () {
      expect(
        ChatWorking.of(working, [
          prompt,
          const ChatAssistantText('a', text: 'Done.'),
        ]),
        isNull,
      );
    });

    test('shown for a working state, a working event or a pending prompt', () {
      final shown = ChatWorking.of(working, [prompt])!;
      expect(shown.label, 'Thinking…');
      expect(shown.since, DateTime.utc(2026, 9, 25, 10));
      expect(
        ChatWorking.of(
          const ChatAgentStatus(state: 'unknown', lastEvent: 'PostToolUse'),
          const [],
        ),
        isNotNull,
      );
      expect(ChatWorking.of(null, [prompt]), isNotNull);
      expect(
        ChatWorking.of(null, [
          call('t', 'Bash', {'command': 'ls'}),
        ]),
        isNotNull,
      );
      expect(ChatWorking.of(null, [call('t', 'Bash', {}, done: true)]), isNull);
    });

    test('labels per tool', () {
      String label(List<ChatItem> items, [ChatAgentStatus agent = working]) =>
          ChatWorking.labelFor(agent, items);
      expect(
        label([
          call('b', 'Bash', {'command': 'npm test\necho done'}),
        ]),
        'Running: npm test',
      );
      expect(
        label([
          call('e', 'Edit', {'file_path': '/home/a/app/src/routes/todos.ts'}),
        ]),
        'Editing src/routes/todos.ts',
      );
      expect(
        label([
          call('w', 'Write', {'file_path': 'notes.md'}),
        ]),
        'Writing notes.md',
      );
      expect(
        label([
          call('r1', 'Read', {'file_path': '/a.dart'}, done: true),
          const ChatThinking('th'),
          call('r2', 'Read', {'file_path': '/b.dart'}),
          call('r3', 'Read', {'file_path': '/c.dart'}),
        ]),
        'Reading 3 files',
      );
      expect(
        label([
          call('r', 'Read', {'file_path': '/x/y.dart'}),
        ]),
        'Reading x/y.dart',
      );
      expect(
        label([
          call('g', 'Grep', {'pattern': 'x'}),
        ]),
        'Searching the code',
      );
      expect(
        label([
          call('s', 'WebSearch', {'query': 'x'}),
        ]),
        'Searching the web',
      );
      expect(
        label([
          call('t', 'Task', {'description': 'Review the diff'}),
        ]),
        'Running an agent: Review the diff',
      );
      expect(
        label([
          call('m', 'mcp__github__create_issue', {'title': 'x'}),
        ]),
        'Using github: create_issue',
      );
      expect(
        label(
          [prompt],
          const ChatAgentStatus(
            state: 'working',
            lastEvent: 'PreToolUse',
            lastToolName: 'WebFetch',
          ),
        ),
        'Searching the web',
      );
      expect(label([call('b', 'Bash', {}, done: true)]), 'Thinking…');
    });

    test('elapsed format', () {
      expect(ChatWorking.elapsed(const Duration(seconds: 42)), '42s');
      expect(ChatWorking.elapsed(const Duration(seconds: 185)), '3m 05s');
      expect(ChatWorking.elapsed(const Duration(minutes: 62)), '1h 02m');
      expect(ChatWorking.elapsed(const Duration(seconds: -3)), '0s');
    });
  });

  testWidgets('the timer ticks every second', (tester) async {
    var now = DateTime.utc(2026, 9, 25, 10, 0, 42);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatWorkingIndicator(
            working: const ChatWorking(label: 'Running: npm test'),
            since: DateTime.utc(2026, 9, 25, 10),
            now: () => now,
          ),
        ),
      ),
    );
    expect(
      find.text('Running: npm test · 42s', findRichText: true),
      findsOneWidget,
    );
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.text('Running: npm test · 43s', findRichText: true),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduced motion shows still dots', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(body: TypingDots(color: Colors.blue)),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('typing-dots-static')), findsOneWidget);
    // Nothing animates, so the tree settles.
    await tester.pumpAndSettle();
  });

  testWidgets('Chat View shows the indicator while working and hides it '
      'when the reply arrives', (tester) async {
    final controller = ChatViewController(
      runner: ScriptedAgentCommandRunner([
        ok(
          page([
            userLine('u1', 'run the tests'),
            assistantLine('a1', [
              toolUse('t1', 'Bash', {'command': 'npm test'}),
            ]),
          ], state: 'working'),
        ),
        ok(
          page(
            [
              userLine('r1', [toolResult('t1', 'ok')]),
              assistantLine('a2', [text('All green.')]),
            ],
            offset: 200,
          ),
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
    expect(
      find.byKey(const ValueKey('chat-working-indicator')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Running: npm test', findRichText: true),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('typing-dots')), findsOneWidget);

    await controller.refresh();
    await tester.pump();
    expect(find.byKey(const ValueKey('chat-working-indicator')), findsNothing);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with reduced motion the page indicator is static', (
    tester,
  ) async {
    final controller = ChatViewController(
      runner: ScriptedAgentCommandRunner([
        ok(page([userLine('u1', 'think hard')], state: 'working')),
      ]),
      sessionId: 's-1',
      pollInterval: const Duration(days: 1),
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: ChatViewPage(controller: controller, onOpenTerminal: () {}),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('typing-dots-static')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('chat-working-indicator')),
        matching: find.textContaining('Thinking…', findRichText: true),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
