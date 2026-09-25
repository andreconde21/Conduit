import 'dart:convert';

/// Synthetic `conductore-hostd transcript` output, shaped like the host's
/// normalized Claude Code lines (not copied from a real session).
Map<String, Object?> userLine(
  String uuid,
  Object content, {
  bool sidechain = false,
  bool meta = false,
  bool compact = false,
}) => {
  'type': 'user',
  'uuid': uuid,
  'parentUuid': null,
  'timestamp': '2026-09-25T10:00:00.000Z',
  'isSidechain': sidechain,
  'isMeta': ?(meta ? true : null),
  'isCompactSummary': ?(compact ? true : null),
  'message': {'role': 'user', 'content': content},
};

Map<String, Object?> assistantLine(
  String uuid,
  List<Map<String, Object?>> content, {
  bool sidechain = false,
}) => {
  'type': 'assistant',
  'uuid': uuid,
  'parentUuid': null,
  'timestamp': '2026-09-25T10:00:05.000Z',
  'isSidechain': sidechain,
  'message': {'role': 'assistant', 'model': 'claude-x', 'content': content},
};

Map<String, Object?> text(String value) => {'type': 'text', 'text': value};

Map<String, Object?> thinking() => {'type': 'thinking', 'hasText': true};

Map<String, Object?> toolUse(
  String id,
  String name,
  Map<String, Object?> input,
) => {'type': 'tool_use', 'id': id, 'name': name, 'input': input};

Map<String, Object?> toolResult(
  String id,
  String content, {
  bool error = false,
  int images = 0,
}) => {
  'type': 'tool_result',
  'tool_use_id': id,
  'is_error': error,
  'content': content,
  'images': ?(images > 0 ? images : null),
};

String page(
  List<Map<String, Object?>> entries, {
  int offset = 100,
  int? size,
  int start = 0,
  String state = 'waiting_input',
  List<Map<String, Object?>> pending = const [],
  bool reset = false,
}) => jsonEncode({
  'sessionId': 's-1',
  'agent': {
    'name': 'api',
    'state': state,
    'lastMessage': null,
    'startedAt': 1790286139217,
    'updatedAt': 1790286139530,
    'endedAt': null,
    'pending': pending,
  },
  'offset': offset,
  'size': size ?? offset,
  'start': start,
  'skipped': 0,
  'reset': ?(reset ? true : null),
  'entries': entries,
});
