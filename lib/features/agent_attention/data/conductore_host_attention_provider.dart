import 'dart:convert';

import 'package:conduit/core/app_failure.dart';
import 'package:conduit/features/agent_attention/data/remote_tool_command.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention_provider.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';

/// Reads agent state from the Conductore host companion daemon
/// (`conductore-hostd`), which watches Claude Code sessions through their
/// hooks and can answer permission prompts on the phone's behalf.
///
/// Contract (protocol version 1, `host/README.md` in the companion repo):
/// every command prints one JSON document on stdout and exits 0; on failure
/// it exits 1 with `{"error": "..."}`; exit 127 means the CLI is missing.
/// Commands run as `sh -c 'PATH="$HOME/.local/bin:...:$PATH" exec
/// conductore-hostd ...'` because SSH exec shells rarely have
/// `~/.local/bin` on PATH.
///
/// - `status` → `{"version": 1, "seq": N, "source": "daemon|snapshot|none",
///   "agents": [...]}`, agents sorted newest `updatedAt` first.
/// - `events --since N --timeout 55` → long-poll printing one JSON object
///   per line and exiting: `{"seq", "type": "change", "sessionId",
///   "reason", "agent": {...}}`, `{"seq", "type": "remove", "sessionId",
///   "agent": null}`, `{"type": "timeout", "seq"}` (nothing happened), or
///   `{"type": "snapshot", "version", "seq", "agents": [...]}` (the cursor
///   was not covered; replace everything).
/// - `decide <requestId> allow|deny|always` → `{"ok": true, ...}` or exit 1
///   with `unknown request <id>` / `request expired; answer it in the
///   terminal`.
/// - `focus <sessionId>`, `version`, `doctor`.
///
/// Agent: `{"sessionId", "name", "cwd", "tmux": {"session", "window",
/// "paneId", "windowName"} | null, "herdr": {"workspaceId", "tabId",
/// "paneId", "name"} | null, "state": "working|waiting_input|
/// needs_permission|ended", "lastEvent", "lastToolName", "lastMessage",
/// "startedAt", "updatedAt", "endedAt", "pending": [{"id", "toolName",
/// "summary", "toolInput", "createdAt"}]}` (timestamps in epoch ms), plus
/// the optional `kind` (`claude`, `codex`, `opencode`...), `project` (git
/// repository name) and `usage` (`{"contextUsedPct", "contextTokens",
/// "windowLabel", "limits": [{"label", "usedPct", "resetsAt"}]}`, see
/// `docs/usage-proposal.md`); a daemon without them still parses. An
/// agent in `needs_permission` with an empty `pending` list has a prompt
/// waiting in the terminal that the phone can no longer answer.
class ConductoreHostAttentionProvider extends AgentAttentionProvider {
  const ConductoreHostAttentionProvider();

  static const _commandTimeout = Duration(seconds: 10);

  /// How long the host holds an `events` long-poll before returning an
  /// empty batch. Well under the SSH keepalive so the channel stays warm.
  static const watchTimeout = Duration(seconds: 55);

  /// The runner's own deadline for a long-poll: the host timeout plus room
  /// for a slow exit, after which the channel is presumed hung.
  static const _watchCommandTimeout = Duration(seconds: 70);

  static const _tool = 'conductore-hostd';

  /// Wraps `conductore-hostd [args]` in the shared PATH wrapper so a
  /// user-local install (npm global prefix, `~/.local/bin`, mise shims) is
  /// found from a non-interactive SSH shell.
  static String remoteCommand(String args) => remoteToolCommand(_tool, args);

  /// `conductore-hostd doctor`, for the host form's "Set up companion"
  /// check.
  static final doctorCommand = remoteCommand('doctor');

  @override
  String get id => 'conductore';

  @override
  String get label => 'Conductore companion';

  @override
  bool get supportsWatch => true;

  @override
  Future<bool> isAvailable(AgentCommandRunner runner) async {
    try {
      final result = await runner.run(
        remoteCommand('version'),
        timeout: _commandTimeout,
      );
      return result.exitCode == 0 && result.stdout.trim().isNotEmpty;
    } catch (_) {
      // A connection problem is not "not installed", but the caller has
      // nothing better to do than fall back; the next poll surfaces the
      // error itself.
      return false;
    }
  }

  @override
  Future<AgentAttentionSnapshot> fetchAgents(AgentCommandRunner runner) async {
    final result = await runner.run(
      remoteCommand('status'),
      timeout: _commandTimeout,
    );
    _checkResult(result);
    return parseSnapshot(result.stdout);
  }

  @override
  Future<AgentChangeBatch?> watchAgents(
    AgentCommandRunner runner, {
    required int? since,
  }) async {
    final result = await runner.run(
      remoteCommand(
        'events --since ${since ?? 0} --timeout ${watchTimeout.inSeconds}',
      ),
      timeout: _watchCommandTimeout,
    );
    _checkResult(result);
    final batch = parseEvents(result.stdout);
    return batch.isEmpty ? null : batch;
  }

  @override
  String? focusCommand(AgentInfo agent) {
    if (agent.id.isEmpty) {
      return null;
    }
    return remoteCommand('focus ${shellQuoteArgument(agent.id)}');
  }

  @override
  String? decideCommand(
    PendingPermissionRequest request,
    PermissionVerdict verdict,
  ) {
    if (request.id.isEmpty) {
      return null;
    }
    return remoteCommand(
      'decide ${shellQuoteArgument(request.id)} ${verdict.wireName}',
    );
  }

  /// Maps exit codes to the two conditions the controller distinguishes:
  /// not installed (monitoring stops) versus a reported error (retried).
  static void _checkResult(AgentCommandResult result) {
    final stderr = result.stderr.trim();
    if (result.exitCode == 127 ||
        stderr.contains('command not found') ||
        stderr.contains('$_tool: not found')) {
      throw const AgentProviderUnavailable(
        'The Conductore companion is not installed on this machine. Run '
        '"conductore-hostd install" there, or switch this machine to Herdr.',
      );
    }
    if (result.exitCode != null && result.exitCode != 0) {
      throw failureFrom(result.stdout, stderr);
    }
  }

  /// Turns the `{"error": "..."}` output (or bare stderr) into a failure.
  static AppFailure failureFrom(String stdout, String stderr) {
    for (final raw in [stdout.trim(), stderr]) {
      if (raw.isEmpty) {
        continue;
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['error'] is String) {
          return AppFailure(
            'The Conductore companion reported an error.',
            decoded['error'] as String,
          );
        }
      } catch (_) {
        // Not JSON; fall through to the raw text.
      }
      return AppFailure(
        'The Conductore companion reported an error.',
        raw.length > 200 ? raw.substring(0, 200) : raw,
      );
    }
    return const AppFailure(
      'The Conductore companion reported an error.',
      'no error output',
    );
  }

  /// Parses one `status` document.
  static AgentAttentionSnapshot parseSnapshot(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const AppFailure('The Conductore companion returned no output.');
    }
    final snapshot = _parseSnapshotLine(trimmed);
    if (snapshot == null) {
      throw const AppFailure(
        'The Conductore companion returned JSON in an unexpected shape.',
      );
    }
    return snapshot;
  }

  /// Parses `events` output: `change` / `remove` lines in order, possibly
  /// after a `snapshot` line; a `timeout` line carries nothing to apply.
  /// Lines of an unknown type are skipped so a newer daemon can add them.
  static AgentChangeBatch parseEvents(String raw) {
    AgentAttentionSnapshot? snapshot;
    var changes = <AgentChange>[];
    for (final line in const LineSplitter().convert(raw)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(trimmed);
      } catch (_) {
        throw const AppFailure(
          'The Conductore companion returned output that is not JSON.',
        );
      }
      if (decoded is! Map) {
        continue;
      }
      if (decoded['error'] is String) {
        throw failureFrom(trimmed, '');
      }
      switch (decoded['type']) {
        case 'snapshot':
          final parsed = _parseSnapshotLine(trimmed);
          if (parsed != null) {
            // Everything before a snapshot is superseded by it.
            snapshot = parsed;
            changes = [];
          }
        case 'change':
          final agent = _parseAgent(decoded['agent']);
          final sequence = _int(decoded['seq']);
          if (agent != null && sequence != null) {
            changes.add(
              AgentChange(sequence: sequence, agentId: agent.id, agent: agent),
            );
          }
        case 'remove':
          final id = _string(decoded['sessionId']);
          final sequence = _int(decoded['seq']);
          if (id != null && sequence != null) {
            changes.add(
              AgentChange(sequence: sequence, agentId: id, agent: null),
            );
          }
        default:
          // `timeout`, or a type this build does not know.
          break;
      }
    }
    return AgentChangeBatch(snapshot: snapshot, changes: changes);
  }

  /// Renders `doctor` JSON as one line per check for the host form.
  static String formatDoctor(String raw) {
    try {
      final decoded = jsonDecode(raw.trim());
      if (decoded is Map && decoded['checks'] is List) {
        final lines = <String>[
          if (_string(decoded['user']) case final user?) 'user: $user',
          for (final check in decoded['checks'] as List)
            if (check is Map)
              '${check['ok'] == true ? '[ok]' : '[!!]'} '
                  '${check['name'] ?? '?'}'
                  '${_string(check['detail']) == null ? '' : ': ${check['detail']}'}',
        ];
        return lines.join('\n');
      }
      if (decoded is Map && decoded['error'] is String) {
        return 'error: ${decoded['error']}';
      }
    } catch (_) {
      // Not JSON: show it as is.
    }
    return raw.trim();
  }

  static AgentAttentionSnapshot? _parseSnapshotLine(String line) {
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } catch (_) {
      throw const AppFailure(
        'The Conductore companion returned output that is not JSON.',
      );
    }
    if (decoded is! Map) {
      return null;
    }
    if (decoded['error'] is String) {
      throw failureFrom(line, '');
    }
    final items = decoded['agents'];
    if (items is! List) {
      return null;
    }
    final agents = <AgentInfo>[];
    for (final item in items) {
      final agent = _parseAgent(item);
      if (agent != null) {
        agents.add(agent);
      }
    }
    return AgentAttentionSnapshot(
      agents: agents,
      sequence: _int(decoded['seq']),
    );
  }

  static AgentInfo? _parseAgent(Object? item) {
    if (item is! Map) {
      return null;
    }
    final id = _string(item['sessionId']);
    if (id == null) {
      return null;
    }
    final cwd = _string(item['cwd']);
    final name = _string(item['name']) ?? _basename(cwd) ?? id;
    final tmux = item['tmux'];
    final herdr = item['herdr'];
    // `workspace` is a Herdr workspace id (the home board and deep links
    // match it against Herdr's); the cwd is never one.
    String? workspace;
    String? tab;
    String? pane;
    if (tmux is Map) {
      final session = _string(tmux['session']);
      final window = tmux['window'];
      if (session != null) {
        tab = window == null ? session : '$session:$window';
      }
      pane = _string(tmux['paneId']);
    } else if (herdr is Map) {
      workspace = _string(herdr['workspaceId']);
      tab = _string(herdr['tabId']);
      pane = _string(herdr['paneId']);
    }
    final pendingRaw = item['pending'];
    final pending = <PendingPermissionRequest>[
      if (pendingRaw is List)
        for (final entry in pendingRaw) ?_parseRequest(entry),
    ];
    return AgentInfo(
      id: id,
      name: name,
      kind: _string(item['kind']) ?? 'claude',
      state: parseState(_string(item['state']), pending: pending),
      workspace: workspace,
      tab: tab,
      pane: pane,
      stateChangedAt: _timestamp(item['updatedAt']),
      pendingRequests: pending,
      lastMessage: _string(item['lastMessage']),
      // The inbox groups by project: the cwd's basename stands in for one.
      project: _string(item['project']) ?? _basename(cwd),
      usage: parseUsage(item['usage']),
    );
  }

  /// Parses the optional `usage` record; anything malformed is dropped
  /// field by field so a partial report still shows what it has.
  static AgentUsage? parseUsage(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final limitsRaw = raw['limits'];
    final usage = AgentUsage(
      contextUsedPct: _percent(raw['contextUsedPct']),
      contextTokens: _int(raw['contextTokens']),
      windowLabel: _string(raw['windowLabel']),
      limits: [
        if (limitsRaw is List)
          for (final entry in limitsRaw)
            if (entry is Map &&
                _string(entry['label']) != null &&
                _percent(entry['usedPct'], max: 1000) != null)
              AgentRateLimit(
                label: _string(entry['label'])!,
                usedPct: _percent(entry['usedPct'], max: 1000)!,
                resetsAt: _timestamp(entry['resetsAt']),
              ),
      ],
    );
    return usage.isEmpty ? null : usage;
  }

  static double? _percent(Object? value, {double max = 100}) {
    if (value is! num || value.isNaN) {
      return null;
    }
    return value.toDouble().clamp(0, max).toDouble();
  }

  /// Maps the companion's states onto the shared attention states. A
  /// permission prompt is "needs input" with the request attached (so the
  /// dashboard, widget and notifications all treat it as attention).
  static AgentAttentionState parseState(
    String? raw, {
    List<PendingPermissionRequest> pending = const [],
  }) {
    return switch (raw?.toLowerCase()) {
      'working' => AgentAttentionState.working,
      'needs_permission' || 'waiting_input' => AgentAttentionState.needsInput,
      'ended' => AgentAttentionState.finished,
      'idle' => AgentAttentionState.idle,
      _ =>
        pending.isNotEmpty
            ? AgentAttentionState.needsInput
            : AgentAttentionState.unknown,
    };
  }

  static PendingPermissionRequest? _parseRequest(Object? entry) {
    if (entry is! Map) {
      return null;
    }
    final id = _string(entry['id']);
    if (id == null) {
      return null;
    }
    final toolName = _string(entry['toolName']) ?? 'tool';
    return PendingPermissionRequest(
      id: id,
      toolName: toolName,
      summary: _string(entry['summary']) ?? toolName,
      toolInput: formatToolInput(entry['toolInput']),
      createdAt: _timestamp(entry['createdAt']),
    );
  }

  /// Pretty-prints a tool input for the sheet, capped so a large file write
  /// cannot flood the phone.
  static String formatToolInput(Object? input) {
    if (input == null) {
      return '';
    }
    final text = input is String
        ? input
        : const JsonEncoder.withIndent('  ').convert(input);
    const limit = PendingPermissionRequest.maxToolInputLength;
    if (text.length <= limit) {
      return text;
    }
    return '${text.substring(0, limit)}\n… (${text.length - limit} more '
        'characters)';
  }

  static String? _basename(String? path) {
    if (path == null) {
      return null;
    }
    final parts = path.split('/').where((part) => part.isNotEmpty);
    return parts.isEmpty ? null : parts.last;
  }

  static String? _string(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  static int? _int(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static DateTime? _timestamp(Object? value) {
    final millis = _int(value);
    if (millis == null || millis <= 0) {
      return null;
    }
    try {
      return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    } on ArgumentError {
      return null;
    }
  }
}
