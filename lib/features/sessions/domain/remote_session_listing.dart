import 'dart:convert';

import 'package:conduit/features/agent_attention/data/herdr_attention_provider.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';

/// One tmux session as reported by `tmux list-sessions`.
class TmuxSessionInfo {
  const TmuxSessionInfo({
    required this.name,
    this.attachedClients = 0,
    this.windows = 1,
    this.lastActivity,
  });

  final String name;
  final int attachedClients;
  final int windows;
  final DateTime? lastActivity;

  bool get isAttached => attachedClients > 0;

  @override
  bool operator ==(Object other) =>
      other is TmuxSessionInfo &&
      other.name == name &&
      other.attachedClients == attachedClients &&
      other.windows == windows &&
      other.lastActivity == lastActivity;

  @override
  int get hashCode => Object.hash(name, attachedClients, windows, lastActivity);
}

/// One Herdr tab as reported by `herdr tab list`.
class HerdrTabInfo {
  const HerdrTabInfo({
    required this.id,
    required this.workspaceId,
    this.label = '',
    this.number,
    this.agentStatus = '',
    this.focused = false,
  });

  final String id;
  final String workspaceId;
  final String label;
  final int? number;
  final String agentStatus;
  final bool focused;

  @override
  bool operator ==(Object other) =>
      other is HerdrTabInfo &&
      other.id == id &&
      other.workspaceId == workspaceId &&
      other.label == label &&
      other.number == number &&
      other.agentStatus == agentStatus &&
      other.focused == focused;

  @override
  int get hashCode =>
      Object.hash(id, workspaceId, label, number, agentStatus, focused);
}

/// One Herdr workspace as reported by `herdr workspace list`.
class HerdrWorkspaceInfo {
  const HerdrWorkspaceInfo({
    required this.id,
    required this.label,
    this.number,
    this.agentStatus = '',
    this.focused = false,
    this.tabCount = 1,
    this.activeTabId = '',
    this.tabs = const [],
  });

  final String id;
  final String label;
  final int? number;

  /// Raw Herdr agent status (`idle`, `working`, `blocked`, `done`,
  /// `unknown`), empty when not reported.
  final String agentStatus;
  final bool focused;
  final int tabCount;
  final String activeTabId;
  final List<HerdrTabInfo> tabs;

  HerdrWorkspaceInfo withTabs(List<HerdrTabInfo> tabs) => HerdrWorkspaceInfo(
    id: id,
    label: label,
    number: number,
    agentStatus: agentStatus,
    focused: focused,
    tabCount: tabCount,
    activeTabId: activeTabId,
    tabs: tabs,
  );

  @override
  bool operator ==(Object other) =>
      other is HerdrWorkspaceInfo &&
      other.id == id &&
      other.label == label &&
      other.number == number &&
      other.agentStatus == agentStatus &&
      other.focused == focused &&
      other.tabCount == tabCount &&
      other.activeTabId == activeTabId;

  @override
  int get hashCode => Object.hash(
    id,
    label,
    number,
    agentStatus,
    focused,
    tabCount,
    activeTabId,
  );
}

/// Outcome of listing sessions of one kind on a host.
sealed class RemoteListing<T> {
  const RemoteListing();
}

class RemoteListingAvailable<T> extends RemoteListing<T> {
  const RemoteListingAvailable(this.items);

  final List<T> items;
}

/// The tool is not installed (or not on PATH) on the host.
class RemoteListingNotInstalled<T> extends RemoteListing<T> {
  const RemoteListingNotInstalled();
}

/// The tool exists but its server is not running; [startCommand] launches
/// it as a fresh session.
class RemoteListingNotRunning<T> extends RemoteListing<T> {
  const RemoteListingNotRunning(this.message);

  final String message;
}

class RemoteListingFailed<T> extends RemoteListing<T> {
  const RemoteListingFailed(this.message);

  final String message;
}

/// Commands and parsers for the connect picker's tmux and Herdr listings.
///
/// Parsing is separated from running so the picker can be unit tested
/// against captured output; the commands are documented here because they
/// are what the phone actually runs on the machine over a dedicated SSH
/// exec channel before the interactive session starts.
abstract final class RemoteSessionListing {
  /// Field separator in the tmux format string. A tab cannot appear in a
  /// session name (tmux rejects it), so splitting is unambiguous.
  static const _tmuxSeparator = '\t';

  /// `tmux list-sessions` with one tab-separated line per session:
  /// name, attached client count, window count, last activity (epoch s).
  ///
  /// `-F` uses a literal tab via `#{t:...}`-free syntax: the format string
  /// is passed through `printf` so the shell expands `\t`.
  static const tmuxListCommand =
      r'''tmux list-sessions -F "$(printf '#{session_name}\t#{session_attached}\t#{session_windows}\t#{session_activity}')"''';

  /// `herdr workspace list` (JSON), wrapped with the same PATH fix the agent
  /// dashboard uses so user-local installs are found.
  static final herdrWorkspaceListCommand = HerdrAttentionProvider.remoteCommand(
    'workspace list',
  );

  /// `herdr tab list` (JSON), for tab labels inside each workspace.
  static final herdrTabListCommand = HerdrAttentionProvider.remoteCommand(
    'tab list',
  );

  static RemoteListing<TmuxSessionInfo> interpretTmux(
    AgentCommandResult result,
  ) {
    final stderr = result.stderr.trim();
    if (result.exitCode == 127 || _looksNotInstalled(stderr, 'tmux')) {
      return const RemoteListingNotInstalled();
    }
    if (result.exitCode != null && result.exitCode != 0) {
      // tmux exits 1 with "no server running on ..." (or "error connecting
      // to ...") when no session exists yet: that is an empty list, not an
      // error.
      if (stderr.contains('no server running') ||
          stderr.contains('error connecting') ||
          stderr.contains('No such file or directory')) {
        return const RemoteListingAvailable([]);
      }
      return RemoteListingFailed(
        stderr.isEmpty ? 'tmux exited with ${result.exitCode}.' : stderr,
      );
    }
    return RemoteListingAvailable(parseTmuxSessions(result.stdout));
  }

  /// Parses tab-separated `tmux list-sessions` lines. Lines that do not fit
  /// the format are skipped; the attached count defaults to 0.
  static List<TmuxSessionInfo> parseTmuxSessions(String raw) {
    final sessions = <TmuxSessionInfo>[];
    for (final line in const LineSplitter().convert(raw)) {
      if (line.trim().isEmpty) {
        continue;
      }
      final fields = line.split(_tmuxSeparator);
      final name = fields.first.trim();
      if (name.isEmpty) {
        continue;
      }
      final activity = fields.length > 3
          ? int.tryParse(fields[3].trim())
          : null;
      sessions.add(
        TmuxSessionInfo(
          name: name,
          attachedClients: fields.length > 1
              ? int.tryParse(fields[1].trim()) ?? 0
              : 0,
          windows: fields.length > 2 ? int.tryParse(fields[2].trim()) ?? 1 : 1,
          lastActivity: activity == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  activity * 1000,
                  isUtc: true,
                ),
        ),
      );
    }
    return sessions;
  }

  static RemoteListing<HerdrWorkspaceInfo> interpretHerdrWorkspaces(
    AgentCommandResult result,
  ) {
    final stderr = result.stderr.trim();
    if (result.exitCode == 127 || _looksNotInstalled(stderr, 'herdr')) {
      return const RemoteListingNotInstalled();
    }
    final combined = result.stdout.trim().isNotEmpty
        ? result.stdout.trim()
        : stderr;
    if (_isServerNotRunning(combined)) {
      return const RemoteListingNotRunning(
        'Herdr is not running on this machine.',
      );
    }
    if (result.exitCode != null && result.exitCode != 0) {
      return RemoteListingFailed(
        stderr.isEmpty ? 'herdr exited with ${result.exitCode}.' : stderr,
      );
    }
    try {
      return RemoteListingAvailable(parseHerdrWorkspaces(result.stdout));
    } on FormatException catch (error) {
      return RemoteListingFailed(error.message);
    }
  }

  /// Parses `herdr workspace list` output.
  ///
  /// Accepts the `{"id": ..., "result": {"workspaces": [...]}}` envelope of
  /// Herdr 0.9, a bare `{"workspaces": [...]}` object, or a bare array.
  /// Throws [FormatException] when the output is not JSON at all.
  static List<HerdrWorkspaceInfo> parseHerdrWorkspaces(String raw) {
    final items = _decodeList(raw, 'workspaces');
    final workspaces = <HerdrWorkspaceInfo>[];
    for (final item in items) {
      if (item is! Map) {
        continue;
      }
      final id = _string(item, const ['workspace_id', 'id']);
      if (id == null) {
        continue;
      }
      workspaces.add(
        HerdrWorkspaceInfo(
          id: id,
          label: _string(item, const ['label', 'name']) ?? id,
          number: _int(item['number']),
          agentStatus: _string(item, const ['agent_status', 'status']) ?? '',
          focused: item['focused'] == true,
          tabCount: _int(item['tab_count']) ?? 1,
          activeTabId: _string(item, const ['active_tab_id']) ?? '',
        ),
      );
    }
    return workspaces;
  }

  /// Parses `herdr tab list` output (same envelope rules as workspaces).
  static List<HerdrTabInfo> parseHerdrTabs(String raw) {
    final items = _decodeList(raw, 'tabs');
    final tabs = <HerdrTabInfo>[];
    for (final item in items) {
      if (item is! Map) {
        continue;
      }
      final id = _string(item, const ['tab_id', 'id']);
      final workspaceId = _string(item, const ['workspace_id']);
      if (id == null || workspaceId == null) {
        continue;
      }
      tabs.add(
        HerdrTabInfo(
          id: id,
          workspaceId: workspaceId,
          label: _string(item, const ['label', 'name']) ?? '',
          number: _int(item['number']),
          agentStatus: _string(item, const ['agent_status', 'status']) ?? '',
          focused: item['focused'] == true,
        ),
      );
    }
    return tabs;
  }

  /// Attaches tab records to their workspaces, keeping workspace order and
  /// sorting tabs by number.
  static List<HerdrWorkspaceInfo> attachTabs(
    List<HerdrWorkspaceInfo> workspaces,
    List<HerdrTabInfo> tabs,
  ) {
    return [
      for (final workspace in workspaces)
        workspace.withTabs(
          tabs.where((tab) => tab.workspaceId == workspace.id).toList()
            ..sort((a, b) => (a.number ?? 0).compareTo(b.number ?? 0)),
        ),
    ];
  }

  static List<Object?> _decodeList(String raw, String key) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const [];
    }
    Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      throw const FormatException('Herdr returned output that is not JSON.');
    }
    if (decoded is List) {
      return decoded;
    }
    if (decoded is Map) {
      final direct = decoded[key];
      if (direct is List) {
        return direct;
      }
      final result = decoded['result'];
      if (result is Map && result[key] is List) {
        return result[key] as List;
      }
      if (result is List) {
        return result;
      }
      if (decoded['error'] is Map) {
        final message = (decoded['error'] as Map)['message'];
        throw FormatException(
          message is String ? message : 'Herdr reported an error.',
        );
      }
      return const [];
    }
    throw const FormatException('Herdr returned JSON in an unexpected shape.');
  }

  static bool _looksNotInstalled(String stderr, String tool) {
    return stderr.contains('command not found') ||
        stderr.contains('$tool: not found') ||
        stderr.contains('$tool: No such file');
  }

  static bool _isServerNotRunning(String text) {
    if (text.isEmpty) {
      return false;
    }
    if (text.contains('server_not_running')) {
      return true;
    }
    final lower = text.toLowerCase();
    return lower.contains('server is not running') ||
        lower.contains('no herdr server') ||
        lower.contains('not running');
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
}
