import 'package:conduit/features/chat_view/domain/chat_items.dart';
import 'package:conduit/features/chat_view/domain/chat_tool_summary.dart';
import 'package:conduit/features/chat_view/domain/chat_transcript.dart';

/// What Chat View shows while Claude is busy: a live label and when the
/// turn started.
class ChatWorking {
  const ChatWorking({required this.label, this.since});

  /// "Thinking…", "Running: npm test", "Editing src/routes/todos.ts", ...
  final String label;

  /// When the turn started (the prompt's timestamp), if known.
  final DateTime? since;

  static const _workingEvents = {
    'UserPromptSubmit',
    'PreToolUse',
    'PostToolUse',
  };

  /// The working state of the thread, or null when Claude is not working:
  /// it waits for input or approval, has ended, or its reply just arrived.
  static ChatWorking? of(ChatAgentStatus? agent, List<ChatItem> items) {
    final state = agent?.state;
    if (state == 'waiting_input' ||
        state == 'needs_permission' ||
        state == 'ended') {
      return null;
    }
    final last = items.lastOrNull;
    if (last is ChatAssistantText) {
      return null; // The reply is on screen.
    }
    final working =
        state == 'working' ||
        _workingEvents.contains(agent?.lastEvent) ||
        (last is ChatUserMessage && !last.isCommand) ||
        (last is ChatToolCall && last.running);
    if (!working) {
      return null;
    }
    return ChatWorking(label: labelFor(agent, items), since: _turnStart(items));
  }

  /// The one-line activity label for the latest event.
  static String labelFor(ChatAgentStatus? agent, List<ChatItem> items) {
    final last = items.lastOrNull;
    if (last is ChatToolCall && last.running) {
      return _toolLabel(last, items);
    }
    final tool = agent?.lastToolName;
    if (agent?.lastEvent == 'PreToolUse' && tool != null && tool.isNotEmpty) {
      return _nameLabel(tool);
    }
    return 'Thinking…';
  }

  static String _toolLabel(ChatToolCall call, List<ChatItem> items) {
    String? input(String key) {
      final value = call.input[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    switch (call.name) {
      case 'Bash':
        final command = input('command');
        return command == null
            ? 'Running a command'
            : 'Running: ${_clip(command)}';
      case 'Edit' || 'MultiEdit' || 'NotebookEdit':
        final path = input('file_path') ?? input('notebook_path');
        return path == null ? 'Editing a file' : 'Editing ${shortPath(path)}';
      case 'Write':
        final path = input('file_path');
        return path == null ? 'Writing a file' : 'Writing ${shortPath(path)}';
      case 'Read':
        final reads = _trailing(items, (item) => item.name == 'Read');
        if (reads > 1) return 'Reading $reads files';
        final path = input('file_path') ?? input('notebook_path');
        return path == null ? 'Reading a file' : 'Reading ${shortPath(path)}';
      case 'Grep' || 'Glob' || 'LS':
        return 'Searching the code';
      case 'WebSearch' || 'WebFetch':
        return 'Searching the web';
      case 'Task' || 'Agent':
        final agents = _trailing(
          items,
          (item) => item.kind == ChatToolKind.task,
        );
        if (agents > 1) return 'Running $agents agents';
        final description = input('description');
        return description == null
            ? 'Running an agent'
            : 'Running an agent: ${_clip(description)}';
    }
    return 'Using ${ChatToolSummary.of(call).title}';
  }

  static String _nameLabel(String tool) => switch (tool) {
    'Bash' => 'Running a command',
    'Edit' || 'MultiEdit' || 'NotebookEdit' => 'Editing a file',
    'Write' => 'Writing a file',
    'Read' => 'Reading a file',
    'Grep' || 'Glob' || 'LS' => 'Searching the code',
    'WebSearch' || 'WebFetch' => 'Searching the web',
    'Task' || 'Agent' => 'Running an agent',
    _ when tool.startsWith('mcp__') =>
      'Using ${tool.substring(5).replaceFirst('__', ': ')}',
    _ => 'Using $tool',
  };

  /// Consecutive tool calls at the end of the thread matching [test].
  static int _trailing(List<ChatItem> items, bool Function(ChatToolCall) test) {
    var count = 0;
    for (var i = items.length - 1; i >= 0; i--) {
      final item = items[i];
      if (item is ChatThinking) continue;
      if (item is! ChatToolCall || !test(item)) break;
      count += 1;
    }
    return count;
  }

  static DateTime? _turnStart(List<ChatItem> items) {
    for (var i = items.length - 1; i >= 0; i--) {
      final item = items[i];
      if (item is ChatUserMessage) return item.timestamp;
    }
    return null;
  }

  /// The last three segments of [path]: `src/routes/todos.ts`.
  static String shortPath(String path) {
    final parts = path.split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty);
    final list = parts.toList();
    return list.length <= 3
        ? list.join('/')
        : list.sublist(list.length - 3).join('/');
  }

  static String _clip(String text) {
    final line = text.split('\n').first.trim();
    return line.length <= 48 ? line : '${line.substring(0, 47)}…';
  }

  /// "42s", "3m 05s", "1h 02m".
  static String elapsed(Duration d) {
    if (d.isNegative) return '0s';
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    if (d.inHours < 1) {
      return '${d.inMinutes}m ${(d.inSeconds % 60).toString().padLeft(2, '0')}s';
    }
    return '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';
  }
}
