import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/chat_view/domain/chat_items.dart';
import 'package:conduit/features/chat_view/domain/chat_tool_summary.dart';

/// Turns chat content into text that sounds natural when spoken: Markdown
/// syntax is dropped, code blocks become a short cue, lists become
/// sentences, and tool activity collapses into one line.
abstract final class SpeechText {
  /// Longest single utterance handed to the engine (Android caps input at
  /// about 4000 characters).
  static const maxUtterance = 3000;

  static final _fence = RegExp(r'^\s*(```|~~~)');
  static final _heading = RegExp(r'^\s{0,3}#{1,6}\s+');
  static final _bullet = RegExp(
    r'^\s*(?:[-*+]|\d{1,3}[.)])\s+(?:\[[ xX]\]\s+)?',
  );
  static final _quote = RegExp(r'^\s*>+\s?');
  static final _rule = RegExp(r'^\s*(?:[-*_]\s*){3,}$');
  static final _tableRow = RegExp(r'^\s*\|.*\|\s*$');
  static final _sentenceEnd = RegExp(r'[.!?:;…]$');

  /// Plain speech for a Markdown reply.
  static String fromMarkdown(String markdown) {
    final sentences = <String>[];
    final paragraph = <String>[];

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      _addSentence(sentences, paragraph.join(' '));
      paragraph.clear();
    }

    var inFence = false;
    var inTable = false;
    for (final line in markdown.replaceAll('\r\n', '\n').split('\n')) {
      if (_fence.hasMatch(line)) {
        if (!inFence) {
          flushParagraph();
          sentences.add('Code block.');
        }
        inFence = !inFence;
        continue;
      }
      if (inFence) continue;
      if (_tableRow.hasMatch(line)) {
        if (!inTable) {
          flushParagraph();
          sentences.add('Table.');
          inTable = true;
        }
        continue;
      }
      inTable = false;
      if (line.trim().isEmpty || _rule.hasMatch(line)) {
        flushParagraph();
        continue;
      }
      if (_heading.hasMatch(line)) {
        flushParagraph();
        _addSentence(sentences, line.replaceFirst(_heading, ''));
        continue;
      }
      if (_bullet.hasMatch(line)) {
        flushParagraph();
        _addSentence(sentences, line.replaceFirst(_bullet, ''));
        continue;
      }
      paragraph.add(line.replaceFirst(_quote, ''));
    }
    flushParagraph();
    return sentences.join(' ');
  }

  static void _addSentence(List<String> sentences, String raw) {
    final text = inline(raw).trim();
    if (text.isEmpty) return;
    sentences.add(_sentenceEnd.hasMatch(text) ? text : '$text.');
  }

  static final _image = RegExp(r'!\[([^\]]*)\]\([^)]*\)');
  static final _link = RegExp(r'\[([^\]]+)\]\([^)]*\)');
  static final _refLink = RegExp(r'\[([^\]]+)\]\[[^\]]*\]');
  static final _autoLink = RegExp(r'<(https?://[^>\s]+)>');
  static final _url = RegExp(r'https?://[^\s)>\]]+');
  static final _code = RegExp(r'`+([^`]+?)`+');
  static final _html = RegExp(r'</?[a-zA-Z][^>]*>');
  static final _strong = RegExp(r'(\*\*|__)(.+?)\1');
  static final _em = RegExp(r'(?<![\w*])\*(?!\s)([^*]+?)\*(?!\w)');
  static final _underscoreEm = RegExp(r'(?<!\w)_(?!\s)([^_]+?)_(?!\w)');
  static final _strike = RegExp(r'~~(.+?)~~');
  static final _spaces = RegExp(r'\s+');

  /// Inline Markdown to words: links read as their text, URLs as their
  /// host, inline code as words, emphasis markers dropped.
  static String inline(String text) {
    var out = text
        .replaceAllMapped(_image, (m) => m[1]!)
        .replaceAllMapped(_link, (m) => m[1]!)
        .replaceAllMapped(_refLink, (m) => m[1]!)
        .replaceAllMapped(_autoLink, (m) => _host(m[1]!))
        .replaceAllMapped(_url, (m) => _host(m[0]!));
    // Code before emphasis, so `snake_case` is not read as emphasis.
    out = out.replaceAllMapped(_code, (m) => codeWords(m[1]!));
    out = out
        .replaceAll(_html, '')
        .replaceAllMapped(_strong, (m) => m[2]!)
        .replaceAllMapped(_strike, (m) => m[1]!)
        .replaceAllMapped(_em, (m) => m[1]!)
        .replaceAllMapped(_underscoreEm, (m) => m[1]!)
        .replaceAll(r'\', '');
    return out.replaceAll(_spaces, ' ').trim();
  }

  static String _host(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host ?? '';
    if (host.isEmpty) return 'a link';
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  static final _camel = RegExp(r'(?<=[a-z0-9])(?=[A-Z])');

  /// Inline code as words: `snake_case` → "snake case", `camelCase` →
  /// "camel Case", `lib/foo/bar.dart` → "lib foo bar.dart", `run()` → "run".
  static String codeWords(String code) {
    return code
        .replaceAll('()', '')
        .replaceAll(RegExp(r'[_/\\]+'), ' ')
        .replaceAll(RegExp(r'(?<!\w)--?(?=\w)'), '')
        .replaceAll(RegExp(r'[{}\[\]<>()$`|;=*#"]'), ' ')
        .split(_camel)
        .join(' ')
        .replaceAll(_spaces, ' ')
        .trim();
  }

  /// Splits [text] into utterances no longer than [maxUtterance], breaking
  /// at sentence ends, then at spaces.
  static List<String> chunk(String text, {int max = maxUtterance}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const [];
    if (trimmed.length <= max) return [trimmed];
    final chunks = <String>[];
    var rest = trimmed;
    while (rest.length > max) {
      final window = rest.substring(0, max);
      var cut = window.lastIndexOf(RegExp(r'[.!?]\s'));
      if (cut < max ~/ 3) cut = window.lastIndexOf(' ');
      if (cut <= 0) cut = max - 1;
      chunks.add(rest.substring(0, cut + 1).trim());
      rest = rest.substring(cut + 1).trim();
    }
    if (rest.isNotEmpty) chunks.add(rest);
    return chunks;
  }

  /// One short line for a run of tool calls, e.g. "Ran 3 commands and
  /// edited todos.ts." Null when there is nothing worth saying.
  static String? toolCue(List<ChatItem> items) {
    var commands = 0;
    final edited = <String>[];
    final read = <String>[];
    var searches = 0;
    var web = 0;
    var agents = 0;
    var todos = false;
    final other = <String>[];
    for (final item in items) {
      switch (item) {
        case ChatTodoList():
          todos = true;
        case ChatToolCall(:final kind, :final input, :final name):
          final path = _pathOf(input);
          switch (kind) {
            case ChatToolKind.bash:
              if (name == 'Bash') commands += 1;
            case ChatToolKind.edit || ChatToolKind.write:
              _addUnique(edited, path);
            case ChatToolKind.read:
              _addUnique(read, path);
            case ChatToolKind.search:
              searches += 1;
            case ChatToolKind.web:
              web += 1;
            case ChatToolKind.task:
              agents += 1;
            case ChatToolKind.other:
              _addUnique(other, ChatToolSummary.of(item).title);
          }
        default:
          break;
      }
    }
    final parts = <String>[
      if (commands > 0)
        commands == 1 ? 'ran a command' : 'ran $commands commands',
      if (edited.isNotEmpty)
        edited.length == 1
            ? 'edited ${edited.single.isEmpty ? 'a file' : edited.single}'
            : 'edited ${edited.length} files',
      if (read.isNotEmpty)
        read.length == 1
            ? 'read ${read.single.isEmpty ? 'a file' : read.single}'
            : 'read ${read.length} files',
      if (searches > 0)
        searches == 1 ? 'searched the code' : 'searched $searches times',
      if (web > 0) 'looked something up online',
      if (agents > 0)
        agents == 1 ? 'started an agent' : 'started $agents agents',
      if (todos) 'updated the to-do list',
      if (other.isNotEmpty)
        other.length == 1
            ? 'used ${other.single}'
            : 'used ${other.length} tools',
    ];
    if (parts.isEmpty) return null;
    final joined = parts.length == 1
        ? parts.single
        : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
    return '${joined[0].toUpperCase()}${joined.substring(1)}.';
  }

  static String? _pathOf(Map<String, Object?> input) {
    for (final key in const ['file_path', 'notebook_path', 'path']) {
      final value = input[key];
      if (value is String && value.trim().isNotEmpty) {
        final parts = value.trim().split(RegExp(r'[/\\]'));
        return parts.lastWhere((p) => p.isNotEmpty, orElse: () => value);
      }
    }
    return null;
  }

  static void _addUnique(List<String> list, String? value) {
    final entry = value ?? '';
    if (!list.contains(entry)) list.add(entry);
  }

  static const _maxSummary = 160;

  /// "Claude needs your approval: Bash, npm test."
  static String approval(PendingPermissionRequest request) {
    final summary = _clip(inline(request.summary));
    final tool = request.toolName.startsWith('mcp__')
        ? request.toolName.substring(5).replaceFirst('__', ' ')
        : request.toolName;
    return summary.isEmpty
        ? 'Claude needs your approval: $tool.'
        : 'Claude needs your approval: $tool, ${_end(summary)}';
  }

  /// "Claude is asking: Which database? Options: Postgres, or SQLite."
  static String? question(ChatQuestion question) {
    final prompts = question.questions;
    if (prompts.isEmpty) return null;
    final parts = <String>[];
    for (final prompt in prompts) {
      final text = _end(_clip(inline(prompt.question)));
      final labels = [
        for (final option in prompt.options.take(4)) inline(option.label),
      ].where((label) => label.isNotEmpty).toList();
      parts.add(
        labels.isEmpty
            ? text
            : '$text Options: ${labels.length == 1 ? labels.single : '${labels.sublist(0, labels.length - 1).join(', ')}, or ${labels.last}'}.',
      );
    }
    return 'Claude is asking: ${parts.join(' ')}';
  }

  /// A pending ExitPlanMode.
  static const planReady = 'Claude has a plan ready for your review.';

  static String _clip(String text) => text.length <= _maxSummary
      ? text
      : '${text.substring(0, _maxSummary).trimRight()}…';

  static String _end(String text) =>
      text.isEmpty || _sentenceEnd.hasMatch(text) ? text : '$text.';
}
