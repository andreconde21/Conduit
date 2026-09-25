import 'dart:convert';

/// `conductore-hostd status` as a real machine running Herdr returned it
/// (names, paths, ids and messages redacted): six live Claude sessions over
/// five workspaces, Herdr's own ids (`wX`, `wX:t1`, `wX:p1`), and a stale
/// entry still listed for pane `wX:p1` after a newer Claude took the pane.
/// Workspace `w5` is edited to hold two sessions in two panes of one tab.
String liveHerdrStatusJson() => jsonEncode({
  'version': 1,
  'seq': 4376,
  'source': 'daemon',
  'agents': [
    _agent('s-mobile', 'Mobile', 'wX', 't1', 'p1', updatedAt: 1790332913703),
    _agent('s-api', 'Api', 'w7', 't1', 'p1', updatedAt: 1790332776943),
    // Older session in the same pane as s-mobile; no transcript, no usage.
    _agent(
      's-stale',
      'tmp',
      'wX',
      't1',
      'p1',
      updatedAt: 1790327318719,
      transcript: false,
    ),
    _agent(
      's-root',
      'root',
      'w4',
      't4',
      'p4',
      state: 'waiting_input',
      updatedAt: 1790326235007,
    ),
    _agent('s-left', 'Left', 'w5', 't3', 'p3', updatedAt: 1790330000000),
    _agent('s-right', 'Right', 'w5', 't3', 'p5', updatedAt: 1790331000000),
  ],
});

Map<String, Object?> _agent(
  String id,
  String name,
  String workspace,
  String tab,
  String pane, {
  required int updatedAt,
  String state = 'working',
  bool transcript = true,
}) => {
  'sessionId': id,
  'name': name,
  'cwd': '/home/user/$name',
  'tmux': null,
  'herdr': {
    'workspaceId': workspace,
    'tabId': '$workspace:$tab',
    'paneId': '$workspace:$pane',
    'name': null,
  },
  'state': state,
  'lastEvent': 'PreToolUse',
  'lastToolName': 'Bash',
  'lastMessage': 'Claude is waiting for your input',
  'startedAt': updatedAt - 1000000,
  'updatedAt': updatedAt,
  'endedAt': null,
  'pending': <Object?>[],
  'transcriptPath': transcript ? '/home/user/.claude/projects/$id.jsonl' : null,
  if (transcript)
    'usage': {
      'contextUsedPct': 48,
      'contextTokens': 478601,
      'windowLabel': '1M',
      'limits': [
        {'label': '7d', 'usedPct': 80, 'resetsAt': 1790542800000},
      ],
    },
};
