import 'dart:async';

import 'package:conduit/features/agent_attention/presentation/agent_attention_controller.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/terminal/domain/tmux_navigator.dart';
import 'package:conduit/features/terminal/presentation/terminal_session_controller.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';

/// Opens deep links (a notification, the inbox, the home-screen widget) at
/// a companion agent's exact tmux pane.
///
/// tmux keeps a current window and pane per session, and a client attached
/// to the session shows them. So the app activates (or opens) the tab
/// attached to the agent's tmux session first, then makes the agent's pane
/// current with `tmux select-window -t %N ';' select-pane -t %N` over a
/// background command channel: the same thing `conductore-hostd focus`
/// does, without depending on the companion being installed.
class TmuxSessionFocus {
  TmuxSessionFocus({required this.workspace, required this.runnerFactory});

  final TerminalWorkspaceController workspace;
  final AgentCommandRunnerFactory runnerFactory;

  /// The tmux session an app session attaches to, or null when it does not
  /// start tmux (Herdr targets, directories, plain shells).
  static String? tmuxSessionOf(TerminalSessionController session) {
    final host = session.host;
    if (!host.startTmuxOnConnect) {
      return null;
    }
    final name = host.tmuxSessionName.trim();
    return name.isEmpty ? defaultTmuxSessionName : name;
  }

  /// An open app session on [host] attached to [sessionName], preferring
  /// one opened on that tmux target.
  TerminalSessionController? sessionFor(SavedHost host, String sessionName) {
    TerminalSessionController? any;
    for (final session in workspace.sessions) {
      if (baseHostId(session.host.id) != host.id ||
          tmuxSessionOf(session) != sessionName) {
        continue;
      }
      if (ConnectTarget.fromSessionHostId(session.host.id)?.kind ==
          ConnectTargetKind.tmux) {
        return session;
      }
      any ??= session;
    }
    return any;
  }

  /// Shows [location] on [host]: activates the tab attached to its tmux
  /// session (reconnecting it when it dropped), or opens one with [open],
  /// then selects the pane. Returns the session to show, or null when
  /// nothing was open and [open] is null.
  Future<TerminalSessionController?> openAgentLocation(
    SavedHost host,
    TmuxAgentLocation location, {
    TerminalSessionController Function(ConnectTarget target)? open,
  }) async {
    var session = sessionFor(host, location.sessionName);
    if (session != null) {
      workspace.activate(session);
      if (session.shouldConnect) {
        unawaited(session.connect());
      }
    } else if (open != null) {
      session = open(ConnectTarget.tmux(location.sessionName));
    } else {
      return null;
    }
    if (!host.isLocal && host.authMethod != SshAuthMethod.hardwareKey) {
      // Not awaited: the caller shows the terminal straight away, and the
      // attach shows whatever pane is current once the command lands.
      unawaited(_selectPane(host, location.paneId));
    }
    return session;
  }

  Future<void> _selectPane(SavedHost host, String paneId) async {
    final runner = runnerFactory(host);
    try {
      await TmuxNavigator.focusAgentPane(runner, paneId);
    } finally {
      unawaited(runner.close());
    }
  }
}
