import 'package:conduit/features/chat_view/domain/chat_items.dart';
import 'package:conduit/features/chat_view/domain/chat_tool_summary.dart';
import 'package:conduit/features/chat_view/domain/chat_transcript.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_fixtures.dart';

List<ChatItem> build(List<Map<String, Object?>> entries) =>
    ChatItemBuilder.build(TranscriptParser.parsePage(page(entries)).entries);

void main() {
  test('parses the page envelope and the agent status', () {
    final parsed = TranscriptParser.parsePage(
      page(
        [userLine('u1', 'hi')],
        offset: 40,
        size: 90,
        start: 12,
        state: 'needs_permission',
        pending: [
          {
            'id': 'req-1',
            'toolName': 'Bash',
            'summary': 'rm -rf build',
            'toolInput': {'command': 'rm -rf build'},
            'createdAt': 1790286139530,
          },
        ],
        reset: true,
      ),
    );
    expect(parsed.offset, 40);
    expect(parsed.size, 90);
    expect(parsed.start, 12);
    expect(parsed.reset, isTrue);
    expect(parsed.agent!.state, 'needs_permission');
    expect(parsed.agent!.name, 'api');
    expect(parsed.agent!.pending.single.summary, 'rm -rf build');
    expect(parsed.agent!.pending.single.toolInput, contains('"command"'));
    expect(parsed.agent!.startedAt!.millisecondsSinceEpoch, 1790286139217);
  });

  test('prompt and reply become user and assistant bubbles', () {
    final items = build([
      userLine('u1', 'fix the bug'),
      assistantLine('a1', [text('Looking at it.')]),
    ]);
    expect(items, hasLength(2));
    expect((items[0] as ChatUserMessage).text, 'fix the bug');
    expect((items[1] as ChatAssistantText).text, 'Looking at it.');
  });

  test(
    'tool_use and tool_result pair up by id; results never render alone',
    () {
      final items = build([
        assistantLine('a1', [
          toolUse('t1', 'Bash', {'command': 'npm test', 'description': 'Run'}),
        ]),
        userLine('u1', [toolResult('t1', 'Exit code 1\nFAIL x', error: true)]),
        assistantLine('a2', [
          toolUse('t2', 'Read', {'file_path': '/w/a.dart'}),
        ]),
      ]);
      expect(items, hasLength(2));
      final bash = items[0] as ChatToolCall;
      expect(bash.kind, ChatToolKind.bash);
      expect(bash.failed, isTrue);
      expect(bash.result!.content, startsWith('Exit code 1'));
      final summary = ChatToolSummary.of(bash);
      expect(summary.subject, 'npm test');
      expect(summary.detail, 'Run');
      expect(summary.exitCode, 1);
      final read = items[1] as ChatToolCall;
      expect(read.running, isTrue);
      expect(ChatToolSummary.of(read).subject, '/w/a.dart');
    },
  );

  test('a successful Bash result reports exit 0 and an output tail', () {
    final items = build([
      assistantLine('a1', [
        toolUse('t1', 'Bash', {'command': 'seq 10'}),
      ]),
      userLine('u1', [
        toolResult('t1', List.generate(10, (i) => '$i').join('\n')),
      ]),
    ]);
    final summary = ChatToolSummary.of(items.single as ChatToolCall);
    expect(summary.exitCode, 0);
    expect(summary.resultPreview, '…\n4\n5\n6\n7\n8\n9');
  });

  test('Edit and Write produce a small +/- preview', () {
    final items = build([
      assistantLine('a1', [
        toolUse('t1', 'Edit', {
          'file_path': '/w/a.dart',
          'old_string': 'int x = 1;',
          'new_string': 'int x = 2;\nint y = 3;',
        }),
        toolUse('t2', 'Write', {
          'file_path': '/w/new.txt',
          'content': List.generate(20, (i) => 'line $i').join('\n'),
        }),
      ]),
    ]);
    final edit = ChatToolSummary.of(items[0] as ChatToolCall);
    expect(edit.subject, '/w/a.dart');
    expect(edit.diff.map((l) => '${l.sign}${l.text}'), [
      '-int x = 1;',
      '+int x = 2;',
      '+int y = 3;',
    ]);
    final write = ChatToolSummary.of(items[1] as ChatToolCall);
    expect(write.detail, '20 lines');
    expect(write.diff.first.text, 'line 0');
    expect(write.diff.last.text, '… 8 more');
  });

  test('thinking is flagged, consecutive steps merge, and no text leaks', () {
    final items = build([
      assistantLine('a1', [thinking()]),
      assistantLine('a2', [thinking()]),
      assistantLine('a3', [text('Done.')]),
    ]);
    expect(items, hasLength(2));
    expect((items[0] as ChatThinking).count, 2);
  });

  test('ExitPlanMode becomes a plan card with its approval status', () {
    List<ChatItem> plan(Map<String, Object?>? result) => build([
      assistantLine('a1', [
        toolUse('p1', 'ExitPlanMode', {'plan': '# Plan\n- step'}),
      ]),
      if (result != null) userLine('u1', [result]),
    ]);
    final pending = plan(null).single as ChatPlan;
    expect(pending.plan, '# Plan\n- step');
    expect(pending.status, ChatPlanStatus.pending);
    expect(
      (plan(toolResult('p1', 'User approved')).single as ChatPlan).status,
      ChatPlanStatus.approved,
    );
    final rejected =
        plan(toolResult('p1', 'keep planning', error: true)).single as ChatPlan;
    expect(rejected.status, ChatPlanStatus.rejected);
    expect(rejected.feedback, 'keep planning');
  });

  test('TodoWrite becomes a checklist', () {
    final items = build([
      assistantLine('a1', [
        toolUse('t1', 'TodoWrite', {
          'todos': [
            {'content': 'Write tests', 'status': 'completed'},
            {'content': 'Fix bug', 'status': 'in_progress'},
            {'content': 'Ship', 'status': 'pending'},
          ],
        }),
      ]),
    ]);
    final todos = (items.single as ChatTodoList).todos;
    expect(todos.map((t) => t.status), [
      ChatTodoStatus.completed,
      ChatTodoStatus.inProgress,
      ChatTodoStatus.pending,
    ]);
  });

  test('AskUserQuestion carries options and the answer once given', () {
    final items = build([
      assistantLine('a1', [
        toolUse('q1', 'AskUserQuestion', {
          'questions': [
            {
              'question': 'Which DB?',
              'header': 'Database',
              'multiSelect': false,
              'options': [
                {'label': 'Postgres', 'description': 'relational'},
                {'label': 'SQLite'},
              ],
            },
          ],
        }),
      ]),
    ]);
    final question = items.single as ChatQuestion;
    expect(question.answered, isFalse);
    expect(question.questions.single.options.map((o) => o.label), [
      'Postgres',
      'SQLite',
    ]);
  });

  test('sidechain tool calls fold into the running Task card', () {
    final items = build([
      assistantLine('a1', [
        toolUse('task1', 'Task', {
          'description': 'Find usages',
          'subagent_type': 'Explore',
          'prompt': 'Search the repo',
        }),
      ]),
      assistantLine('s1', [
        toolUse('g1', 'Grep', {'pattern': 'foo'}),
      ], sidechain: true),
      userLine('s2', [toolResult('g1', 'Found 3 files')], sidechain: true),
      assistantLine('s3', [text('subagent chatter')], sidechain: true),
      userLine('u1', [toolResult('task1', 'Three usages.')]),
    ]);
    expect(items, hasLength(1));
    final task = items.single as ChatToolCall;
    expect(task.kind, ChatToolKind.task);
    expect(task.children.single.name, 'Grep');
    expect(
      ChatToolSummary.of(task.children.single).resultPreview,
      'Found 3 files',
    );
    final summary = ChatToolSummary.of(task);
    expect(summary.title, 'Explore');
    expect(summary.subject, 'Find usages');
  });

  test('meta lines, command wrappers, interrupts and compaction', () {
    final items = build([
      userLine('m1', 'Base directory for this skill', meta: true),
      userLine(
        'c1',
        '<command-name>/review</command-name>\n'
            '<command-message>review</command-message>\n'
            '<command-args>123</command-args>',
      ),
      userLine('c2', '<local-command-stdout>ok</local-command-stdout>'),
      userLine('b1', '<bash-input>ls</bash-input>'),
      userLine('i1', [text('[Request interrupted by user]')]),
      userLine('k1', 'This session is being continued', compact: true),
      userLine('img', [
        text('see this'),
        {'type': 'image', 'omitted': true},
      ]),
    ]);
    expect(items.map((i) => i.runtimeType), [
      ChatUserMessage,
      ChatUserMessage,
      ChatNotice,
      ChatNotice,
      ChatUserMessage,
    ]);
    expect((items[0] as ChatUserMessage).text, '/review 123');
    expect((items[0] as ChatUserMessage).isCommand, isTrue);
    expect((items[1] as ChatUserMessage).text, '! ls');
    expect((items[2] as ChatNotice).kind, ChatNoticeKind.interrupted);
    expect((items[3] as ChatNotice).kind, ChatNoticeKind.compacted);
    expect((items[4] as ChatUserMessage).imageCount, 1);
  });

  test('MCP tools get a readable title', () {
    final items = build([
      assistantLine('a1', [
        toolUse('m1', 'mcp__github__create_issue', {'title': 'Bug'}),
      ]),
    ]);
    final summary = ChatToolSummary.of(items.single as ChatToolCall);
    expect(summary.title, 'github: create_issue');
    expect(summary.subject, 'Bug');
  });
}
