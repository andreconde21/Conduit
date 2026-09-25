import 'package:conduit/features/chat_view/domain/chat_items.dart';
import 'package:conduit/features/voice/domain/voice_preferences.dart';

/// One row of the thread as shown: a chat item, or a run of tool rows
/// folded into one (see [ChatToolActivity.arrange]).
sealed class ChatThreadEntry {
  const ChatThreadEntry();
}

class ChatItemEntry extends ChatThreadEntry {
  const ChatItemEntry(this.item);

  final ChatItem item;
}

/// Consecutive tool calls and shell commands of a turn (with the thinking
/// between them), shown as one compact row: "Ran 4 commands, edited 2
/// files".
class ChatToolGroup extends ChatThreadEntry {
  const ChatToolGroup(this.items);

  final List<ChatItem> items;

  /// Stable while the run grows: named after its first item.
  String get id => 'tools-${items.first.id}';

  Iterable<ChatItem> get _tools =>
      items.where((item) => item is ChatToolCall || item is ChatShellCommand);

  int get failed => _tools.where(_failed).length;

  bool get running => items.any((item) => item is ChatToolCall && item.running);

  String get label {
    var commands = 0;
    var searches = 0;
    var web = 0;
    var agents = 0;
    var other = 0;
    final edited = <String>{};
    final read = <String>{};
    var editedCalls = 0;
    var readCalls = 0;
    for (final item in _tools) {
      if (item is ChatShellCommand) {
        commands += 1;
        continue;
      }
      final call = item as ChatToolCall;
      final path = call.input['file_path'] ?? call.input['notebook_path'];
      switch (call.kind) {
        case ChatToolKind.bash:
          commands += 1;
        case ChatToolKind.edit || ChatToolKind.write:
          editedCalls += 1;
          if (path is String) edited.add(path);
        case ChatToolKind.read:
          readCalls += 1;
          if (path is String) read.add(path);
        case ChatToolKind.search:
          searches += 1;
        case ChatToolKind.web:
          web += 1;
        case ChatToolKind.task:
          agents += 1;
        case ChatToolKind.other:
          other += 1;
      }
    }
    // Distinct files when the calls name them.
    final editedFiles = edited.isEmpty ? editedCalls : edited.length;
    final readFiles = read.isEmpty ? readCalls : read.length;
    final parts = [
      if (commands > 0) 'ran ${_count(commands, 'command')}',
      if (editedFiles > 0) 'edited ${_count(editedFiles, 'file')}',
      if (readFiles > 0) 'read ${_count(readFiles, 'file')}',
      if (searches > 0) 'searched ${_count(searches, 'time')}',
      if (web > 0) 'used the web ${_count(web, 'time')}',
      if (agents > 0) 'ran ${_count(agents, 'agent')}',
      if (other > 0) 'used ${_count(other, 'tool')}',
    ];
    final text = parts.join(', ');
    return text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
  }

  static String _count(int n, String noun) =>
      n == 1 ? (noun == 'time' ? 'once' : '1 $noun') : '$n ${noun}s';
}

bool _isTool(ChatItem item) => item is ChatToolCall || item is ChatShellCommand;

bool _failed(ChatItem item) => switch (item) {
  ChatToolCall() => item.failed,
  ChatShellCommand() => item.failed,
  _ => false,
};

abstract final class ChatToolActivity {
  /// The thread's rows for [mode]:
  /// - [ToolActivity.all]: every item.
  /// - [ToolActivity.collapsed]: each run of two or more consecutive tool
  ///   rows (thinking in between belongs to the run) becomes one
  ///   [ChatToolGroup].
  /// - [ToolActivity.hidden]: no tool rows, except failed ones (errors
  ///   always show). Approvals are not thread items and always show;
  ///   questions, plans and notices are never tool rows.
  static List<ChatThreadEntry> arrange(
    List<ChatItem> items,
    ToolActivity mode,
  ) {
    switch (mode) {
      case ToolActivity.all:
        return [for (final item in items) ChatItemEntry(item)];
      case ToolActivity.hidden:
        return [
          for (final item in items)
            if (!_isTool(item) || _failed(item)) ChatItemEntry(item),
        ];
      case ToolActivity.collapsed:
        final entries = <ChatThreadEntry>[];
        final run = <ChatItem>[];
        void flush() {
          // Thinking after the last tool is not part of the run.
          var end = run.length;
          while (end > 0 && run[end - 1] is ChatThinking) {
            end -= 1;
          }
          final tools = run.take(end).where(_isTool).length;
          if (tools >= 2) {
            entries.add(ChatToolGroup(run.sublist(0, end)));
            entries.addAll(run.skip(end).map(ChatItemEntry.new));
          } else {
            entries.addAll(run.map(ChatItemEntry.new));
          }
          run.clear();
        }

        for (final item in items) {
          if (_isTool(item) || (item is ChatThinking && run.isNotEmpty)) {
            run.add(item);
          } else {
            flush();
            entries.add(ChatItemEntry(item));
          }
        }
        flush();
        return entries;
    }
  }
}
