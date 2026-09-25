import 'package:conduit/features/chat_view/domain/chat_items.dart';
import 'package:conduit/features/chat_view/domain/chat_tool_activity.dart';
import 'package:conduit/features/voice/domain/voice_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

ChatToolCall call(
  String id,
  String name,
  ChatToolKind kind, {
  Map<String, Object?> input = const {},
  bool error = false,
}) => ChatToolCall(
  id,
  name: name,
  input: input,
  kind: kind,
  result: ChatToolResult(content: 'ok', isError: error),
);

ChatToolCall bash(String id, {bool error = false}) =>
    call(id, 'Bash', ChatToolKind.bash, error: error);

ChatToolCall edit(String id, String path) =>
    call(id, 'Edit', ChatToolKind.edit, input: {'file_path': path});

List<String> shape(List<ChatThreadEntry> entries) => [
  for (final entry in entries)
    switch (entry) {
      ChatItemEntry(:final item) => item.id,
      final ChatToolGroup group =>
        'group(${group.items.map((i) => i.id).join(',')})',
    },
];

void main() {
  const prompt = ChatUserMessage('u1', text: 'fix it');
  const intro = ChatAssistantText('a1', text: 'Looking.');
  const outro = ChatAssistantText('a2', text: 'Fixed.');
  const question = ChatQuestion(
    'q1',
    questions: [ChatQuestionPrompt(question: 'Ship it?')],
  );
  const error = ChatNotice('n1', kind: ChatNoticeKind.error, text: 'API error');

  final thread = <ChatItem>[
    prompt,
    intro,
    bash('t1'),
    const ChatThinking('th1'),
    bash('t2'),
    edit('t3', 'lib/a.dart'),
    edit('t4', 'lib/a.dart'),
    edit('t5', 'lib/b.dart'),
    const ChatThinking('th2'),
    outro,
    bash('t6'),
    question,
    bash('t7', error: true),
    error,
  ];

  test('Show all keeps every item', () {
    expect(
      shape(ChatToolActivity.arrange(thread, ToolActivity.all)),
      thread.map((item) => item.id).toList(),
    );
  });

  test('Collapsed folds runs of two or more tool rows into one', () {
    final entries = ChatToolActivity.arrange(thread, ToolActivity.collapsed);
    expect(shape(entries), [
      'u1',
      'a1',
      'group(t1,th1,t2,t3,t4,t5)',
      'th2',
      'a2',
      't6',
      'q1',
      't7',
      'n1',
    ]);
    final group = entries.whereType<ChatToolGroup>().single;
    expect(group.label, 'Ran 2 commands, edited 2 files');
    expect(group.id, 'tools-t1');
    expect(group.failed, 0);
  });

  test('group labels count kinds and failures', () {
    final group = ChatToolGroup([
      bash('b1', error: true),
      const ChatShellCommand('s1', command: 'ls'),
      call('r1', 'Read', ChatToolKind.read, input: {'file_path': 'x'}),
      call('g1', 'Grep', ChatToolKind.search),
      call('w1', 'WebFetch', ChatToolKind.web),
      call('k1', 'Task', ChatToolKind.task),
      call('o1', 'mcp', ChatToolKind.other),
    ]);
    expect(
      group.label,
      'Ran 2 commands, read 1 file, searched once, used the web once, '
      'ran 1 agent, used 1 tool',
    );
    expect(group.failed, 1);
  });

  test('Hidden drops tool rows but keeps questions, errors and failed '
      'tools', () {
    expect(shape(ChatToolActivity.arrange(thread, ToolActivity.hidden)), [
      'u1',
      'a1',
      'th1',
      'th2',
      'a2',
      'q1',
      't7',
      'n1',
    ]);
  });
}
