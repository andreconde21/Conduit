import 'dart:async';

import 'package:conduit/features/agent_attention/data/remote_tool_command.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_controller.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/terminal/presentation/recent_directories_controller.dart';
import 'package:conduit/features/terminal/presentation/terminal_session_controller.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';

/// Feeds [RecentDirectoriesController] from three sources:
///
/// - the shell's OSC 7 working-directory reports, per session;
/// - tmux: when a tmux session stops being connected (detach, disconnect,
///   close), the active pane's `#{pane_current_path}` is read over a
///   separate exec channel (tmux keeps running, so this works after the
///   interactive session is gone);
/// - the Conductore companion's agents (`conductore-hostd status` `cwd`,
///   surfaced by [AgentAttentionController] as the agent's workspace),
///   added without reordering since they arrive on every poll.
///
/// Everything is keyed by the saved host id, so a tmux target, a Herdr
/// target and a plain shell of one machine share one list.
class RecentDirectoryTracker {
  RecentDirectoryTracker({
    required this.workspace,
    required this.directories,
    this.runnerFactory,
    this.agentAttention,
  }) {
    workspace.addListener(_syncSessions);
    agentAttention?.addListener(_collectAgentDirectories);
    _syncSessions();
    _collectAgentDirectories();
  }

  final TerminalWorkspaceController workspace;
  final RecentDirectoriesController directories;
  final AgentCommandRunnerFactory? runnerFactory;
  final AgentAttentionController? agentAttention;

  static const tmuxQueryTimeout = Duration(seconds: 8);

  final Map<TerminalSessionController, _SessionWatch> _sessions = {};
  bool _disposed = false;

  void _syncSessions() {
    final current = workspace.sessions.toSet();
    _sessions.removeWhere((session, watch) {
      if (current.contains(session)) {
        return false;
      }
      // Closing a tab removes it before disconnecting it, so the status
      // change below would never be seen: capture on the way out instead.
      if (watch.wasConnected) {
        unawaited(_captureTmuxDirectory(session));
      }
      watch.cancel();
      return true;
    });
    for (final session in current) {
      _sessions[session] ??= _SessionWatch(session, this);
    }
  }

  void _collectAgentDirectories() {
    final attention = agentAttention;
    if (attention == null || _disposed) {
      return;
    }
    for (final host in attention.monitoredHosts) {
      final agents = attention.statusFor(host.id)?.agents ?? const [];
      for (final agent in agents) {
        final cwd = agent.workspace;
        if (cwd != null && cwd.startsWith('/')) {
          unawaited(
            directories.record(baseHostId(host.id), cwd, promote: false),
          );
        }
      }
    }
  }

  void _recordFromSession(TerminalSessionController session, String dir) {
    if (_disposed) {
      return;
    }
    unawaited(directories.record(baseHostId(session.host.id), dir));
  }

  /// The tmux session a terminal session attaches to, or null when it does
  /// not run tmux.
  static String? tmuxSessionNameOf(SavedHost host) {
    if (!host.startTmuxOnConnect || host.isLocal) {
      return null;
    }
    final name = host.tmuxSessionName.trim();
    return name.isEmpty ? defaultTmuxSessionName : name;
  }

  Future<void> _captureTmuxDirectory(TerminalSessionController session) async {
    final host = session.host;
    final tmuxSession = tmuxSessionNameOf(host);
    final factory = runnerFactory;
    // Hardware-key logins would ask for a key touch for this lookup.
    if (tmuxSession == null ||
        factory == null ||
        host.authMethod == SshAuthMethod.hardwareKey ||
        _disposed) {
      return;
    }
    AgentCommandRunner? runner;
    try {
      runner = factory(host);
      final result = await runner.run(
        remoteToolCommand(
          'tmux',
          "display-message -p -t ${shellQuoteArgument('$tmuxSession:')} "
              "'#{pane_current_path}'",
        ),
        timeout: tmuxQueryTimeout,
      );
      if (result.exitCode == 0) {
        final dir = result.stdout.trim().split('\n').first;
        _recordFromSession(session, dir);
      }
    } catch (_) {
      // The host may be unreachable after a network drop; nothing to add.
    } finally {
      unawaited(runner?.close());
    }
  }

  void dispose() {
    _disposed = true;
    workspace.removeListener(_syncSessions);
    agentAttention?.removeListener(_collectAgentDirectories);
    for (final watch in _sessions.values) {
      watch.cancel();
    }
    _sessions.clear();
  }
}

class _SessionWatch {
  _SessionWatch(this.session, this.tracker)
    : _wasConnected = session.isConnected {
    _subscription = session.workingDirectoryReports.listen(
      (dir) => tracker._recordFromSession(session, dir),
    );
    session.addListener(_handleSessionChanged);
  }

  final TerminalSessionController session;
  final RecentDirectoryTracker tracker;
  late final StreamSubscription<String> _subscription;
  bool _wasConnected;

  bool get wasConnected => _wasConnected;

  void _handleSessionChanged() {
    final connected = session.isConnected;
    if (_wasConnected && !connected) {
      unawaited(tracker._captureTmuxDirectory(session));
    }
    _wasConnected = connected;
  }

  void cancel() {
    unawaited(_subscription.cancel());
    session.removeListener(_handleSessionChanged);
  }
}
