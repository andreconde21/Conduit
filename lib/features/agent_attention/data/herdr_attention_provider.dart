import 'dart:convert';

import 'package:conduit/core/app_failure.dart';
import 'package:conduit/features/agent_attention/data/remote_tool_command.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention_provider.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';

/// Reads agent state from Herdr's documented machine-readable CLI
/// (`herdr agent list` prints JSON; effective agent states are `idle`,
/// `working`, `blocked`, `done`, and `unknown`).
///
/// Verified against Herdr 0.9.1, whose list entries look like
/// `{"agent": "claude", "name": "reviewer", "agent_status": "working",
/// "pane_id": "w1:p1", "tab_id": "w1:t1", "workspace_id": "w1",
/// "terminal_title_stripped": "...", "state_change_seq": 42}` inside a
/// `{"id": ..., "result": {"agents": [...]}}` envelope; `name` is only
/// present for agents that were given a live name.
class HerdrAttentionProvider extends AgentAttentionProvider {
  const HerdrAttentionProvider();

  static const _commandTimeout = Duration(seconds: 10);

  /// Wraps `herdr [args]` in the shared PATH wrapper (see
  /// [remoteToolCommand]) so user-local installs are found from a
  /// non-interactive SSH shell.
  static String remoteCommand(String herdrArgs) =>
      remoteToolCommand('herdr', herdrArgs);

  @override
  String get id => 'herdr';

  @override
  String get label => 'Herdr';

  @override
  Future<AgentAttentionSnapshot> fetchAgents(AgentCommandRunner runner) async {
    final result = await runner.run(
      remoteCommand('agent list'),
      timeout: _commandTimeout,
    );
    final stderr = result.stderr.trim();
    if (result.exitCode == 127 ||
        stderr.contains('command not found') ||
        stderr.contains('herdr: not found')) {
      throw const AgentProviderUnavailable(
        'Herdr is not installed on this machine.',
      );
    }
    if (result.exitCode == 2) {
      // Herdr exits 2 for CLI usage errors — an older build without
      // `agent list`.
      throw const AgentProviderUnavailable(
        'This Herdr version does not support "herdr agent list".',
      );
    }
    if (result.exitCode != null && result.exitCode != 0) {
      throw _serverFailure(stderr);
    }
    return AgentAttentionSnapshot(agents: parseAgentList(result.stdout));
  }

  /// Herdr focus targets are a pane id or a unique live agent name — never
  /// a bare agent kind or a terminal title, which is what the display name
  /// falls back to for unnamed agents. Prefer the pane id (always reported
  /// and stable), and only trust the name when it fits Herdr's live-name
  /// grammar.
  @override
  String? focusCommand(AgentInfo agent) {
    final pane = agent.pane;
    final target = pane != null && pane.isNotEmpty
        ? pane
        : _liveAgentName.hasMatch(agent.name)
        ? agent.name
        : null;
    if (target == null) {
      return null;
    }
    return remoteCommand('agent focus ${shellQuoteArgument(target)}');
  }

  static final _liveAgentName = RegExp(r'^[a-z][a-z0-9_-]{0,31}$');

  /// Parses `herdr agent list` output into agent records.
  ///
  /// Tolerates the envelope evolving across versions: a bare JSON array, an
  /// `{"agents": [...]}` object, or a `{"result": {"agents": [...]}}`
  /// envelope all work, unknown fields are ignored, and malformed entries
  /// are skipped rather than failing the whole snapshot. Completely
  /// unparseable output raises [AppFailure].
  static List<AgentInfo> parseAgentList(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const [];
    }
    Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      throw const AppFailure('Herdr returned output that is not JSON.');
    }
    if (decoded is Map && decoded['error'] is Map) {
      // Herdr normally reports errors on stderr with a non-zero exit, but a
      // JSON error envelope on stdout is unambiguous too.
      throw _serverFailure(trimmed);
    }
    final items = _extractAgentItems(decoded);
    if (items == null) {
      throw const AppFailure('Herdr returned JSON in an unexpected shape.');
    }
    final agents = <AgentInfo>[];
    for (final item in items) {
      final agent = _parseAgent(item);
      if (agent != null) {
        agents.add(agent);
      }
    }
    return agents;
  }

  static List<Object?>? _extractAgentItems(Object? decoded) {
    if (decoded is List) {
      return decoded;
    }
    if (decoded is Map) {
      for (final key in const ['agents', 'result']) {
        final value = decoded[key];
        if (value is List) {
          return value;
        }
        if (value is Map) {
          final nested = value['agents'];
          if (nested is List) {
            return nested;
          }
        }
      }
      // An object without any recognizable agent list — treat an explicit
      // empty result as no agents.
      if (decoded['result'] == null && decoded['agents'] == null) {
        return null;
      }
      return const [];
    }
    return null;
  }

  static AgentInfo? _parseAgent(Object? item) {
    if (item is! Map) {
      return null;
    }
    // `agent` is the kind (e.g. `claude`); the live name is optional and a
    // stripped terminal title is the next best human label.
    final liveName = _string(item, const ['name', 'agent_name']) ?? '';
    final pane = _string(item, const ['pane_id', 'pane']);
    final id = pane?.isNotEmpty == true ? pane! : liveName;
    if (id.isEmpty) {
      return null;
    }
    final name = liveName.isNotEmpty
        ? liveName
        : _string(item, const ['terminal_title_stripped', 'terminal_title']) ??
              id;
    return AgentInfo(
      id: id,
      name: name,
      kind:
          _string(item, const ['kind', 'agent_kind', 'agent_type', 'agent']) ??
          '',
      state: _parseState(
        _string(item, const ['state', 'agent_status', 'status']),
      ),
      workspace: _string(item, const ['workspace_id', 'workspace']),
      tab: _string(item, const ['tab_id', 'tab']),
      pane: pane,
      stateChangedAt: _parseTimestamp(
        item['state_changed_at'] ?? item['since'] ?? item['updated_at'],
      ),
      stateSequence: _int(
        item['state_change_seq'] ??
            item['state_seq'] ??
            item['seq'] ??
            item['status_seq'],
      ),
    );
  }

  static AgentAttentionState _parseState(String? raw) {
    return switch (raw?.toLowerCase()) {
      'working' || 'running' || 'busy' => AgentAttentionState.working,
      // Herdr reports `blocked` when it recognizes an approval or question
      // UI — the agent is waiting on a human.
      'blocked' || 'waiting' || 'needs_input' => AgentAttentionState.needsInput,
      'done' || 'finished' => AgentAttentionState.finished,
      'idle' || 'ready' => AgentAttentionState.idle,
      _ => AgentAttentionState.unknown,
    };
  }

  static String? _string(Map<Object?, Object?> item, List<String> keys) {
    for (final key in keys) {
      final value = item[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  static int? _int(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static DateTime? _parseTimestamp(Object? value) {
    if (value is int) {
      try {
        // Interpret plausibly-sized integers as epoch milliseconds; absurd
        // values are dropped rather than failing the whole snapshot.
        if (value > 100000000000) {
          return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
        }
        return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
      } on ArgumentError {
        return null;
      }
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  /// Maps Herdr's `{"error": {"code", "message"}}` output to a failure. The
  /// one code a user can act on from the phone gets its own wording; the
  /// rest surface Herdr's message.
  static AppFailure _serverFailure(String raw) {
    if (raw.isEmpty) {
      return const AppFailure('Herdr reported an error.', 'no error output');
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          if (error['code'] == 'server_not_running') {
            return const AppFailure(
              'Herdr is not running on this machine. Start it with "herdr" '
              'to monitor its agents.',
            );
          }
          if (error['message'] is String) {
            return AppFailure(
              'Herdr reported an error.',
              error['message'] as String,
            );
          }
        }
        if (decoded['message'] is String) {
          return AppFailure(
            'Herdr reported an error.',
            decoded['message'] as String,
          );
        }
      }
    } catch (_) {
      // Fall through to the raw text.
    }
    return AppFailure(
      'Herdr reported an error.',
      raw.length > 200 ? raw.substring(0, 200) : raw,
    );
  }
}
