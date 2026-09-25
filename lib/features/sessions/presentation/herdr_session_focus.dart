import 'dart:async';

import 'package:conduit/features/agent_attention/presentation/agent_attention_controller.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/terminal/domain/herdr_keymap.dart';
import 'package:conduit/features/terminal/domain/herdr_remote_control.dart';
import 'package:conduit/features/terminal/presentation/terminal_session_controller.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';
import 'package:flutter/foundation.dart';

/// Keeps the app's Herdr sessions pointed at the right place.
///
/// Herdr has one focused workspace per server, shared by every client
/// attached to it (checked against Herdr 0.9.1 with two clients). Two app
/// tabs attached to different workspaces of the same server would therefore
/// both show whichever was focused last. This class:
///
/// * remembers which workspace each app session is on, updating it from
///   Herdr when the user leaves the tab (they may have moved around inside
///   Herdr), and focuses it again when the tab becomes active;
/// * opens deep links (a notification, the home board, the agent sheet)
///   at the exact workspace, tab and pane of an agent, reusing an open
///   session when there is one;
/// * hands out one [HerdrRemoteControl] per Herdr server for the terminal
///   gestures and the navigator, so they share one command channel and run
///   in order.
///
/// Hosts that cannot take a background command channel (the local shell,
/// security-key logins where every connection asks for a touch) get no
/// control: gestures fall back to key bindings and nothing re-focuses.
class HerdrSessionFocus {
  HerdrSessionFocus({
    required TerminalWorkspaceController workspace,
    required this.runnerFactory,
    this.reattachRefocusDelay = const Duration(seconds: 2),
  }) : _workspace = workspace {
    _active = workspace.activeSession;
    workspace.addListener(_handleWorkspaceChanged);
  }

  final TerminalWorkspaceController _workspace;
  final AgentCommandRunnerFactory runnerFactory;

  /// How long after a (re)connect the exact pane is focused again: the
  /// session's startup command focuses its own workspace as it attaches.
  final Duration reattachRefocusDelay;

  final _controls = <String, HerdrRemoteControl>{};

  /// Workspace each app session is on, by the session's host id.
  final _workspaces = <String, String>{};
  TerminalSessionController? _active;
  final _timers = <Timer>{};
  bool _disposed = false;

  /// The Herdr server behind [session]: `<saved host id>|<session name>`.
  static String serverKey(TerminalSessionController session) {
    final target = ConnectTarget.fromSessionHostId(session.host.id);
    final herdrSession = target?.kind == ConnectTargetKind.herdr
        ? target!.session
        : '';
    return '${baseHostId(session.host.id)}|$herdrSession';
  }

  /// The Herdr target [session] was opened on, or null for tmux and shells.
  static ConnectTarget? herdrTargetOf(TerminalSessionController session) {
    final target = ConnectTarget.fromSessionHostId(session.host.id);
    return target?.kind == ConnectTargetKind.herdr ? target : null;
  }

  static bool _drivable(SavedHost host) =>
      !host.isLocal && host.authMethod != SshAuthMethod.hardwareKey;

  /// The command channel for [session]'s Herdr server; null when the host
  /// cannot be driven in the background.
  HerdrRemoteControl? controlFor(TerminalSessionController session) {
    if (_disposed || !_drivable(session.host)) {
      return null;
    }
    final key = serverKey(session);
    return _controls[key] ??= HerdrRemoteControl(
      runnerFactory: () => runnerFactory(session.host),
      session: herdrTargetOf(session)?.session ?? '',
    );
  }

  /// When each machine's keymap was last asked for (by saved host id).
  final _keymapAttempts = <String, DateTime>{};

  /// How long a failed keymap read waits before it is tried again.
  static const keymapRetryInterval = Duration(minutes: 5);

  /// Reads the Herdr key bindings of [session]'s machine once (read-only),
  /// for every key-labelled shortcut and key fallback; until then, and when
  /// the read fails, Herdr's defaults apply. Cheap to call on every build.
  void ensureKeymap(TerminalSessionController session) {
    final hostId = baseHostId(session.host.id);
    if (HerdrKeymapCache.instance.has(hostId)) {
      return;
    }
    final control = controlFor(session);
    final last = _keymapAttempts[hostId];
    final now = DateTime.now();
    if (control == null ||
        (last != null && now.difference(last) < keymapRetryInterval)) {
      return;
    }
    _keymapAttempts[hostId] = now;
    unawaited(HerdrKeymapCache.instance.loadWith(hostId, control.readKeymap));
  }

  /// The workspace [session] is on, as far as the app knows.
  String? workspaceOf(TerminalSessionController session) {
    final known = _workspaces[session.host.id];
    if (known != null) {
      return known;
    }
    final target = herdrTargetOf(session);
    return target == null || target.name.isEmpty ? null : target.name;
  }

  /// Records that [session] now shows [workspaceId] (after a gesture or a
  /// navigator jump moved it).
  void noteWorkspace(TerminalSessionController session, String workspaceId) {
    if (workspaceId.isNotEmpty) {
      _workspaces[session.host.id] = workspaceId;
    }
  }

  void _handleWorkspaceChanged() {
    final sessions = _workspace.sessions;
    _workspaces.removeWhere(
      (hostId, _) => !sessions.any((session) => session.host.id == hostId),
    );
    final next = _workspace.activeSession;
    final previous = _active;
    if (next == previous) {
      return;
    }
    _active = next;
    if (next != null) {
      unawaited(_refocus(previous, next));
    }
  }

  Future<void> _refocus(
    TerminalSessionController? previous,
    TerminalSessionController next,
  ) async {
    final target = herdrTargetOf(next);
    final control = target == null ? null : controlFor(next);
    if (target == null || control == null) {
      return;
    }
    final workspaceId = workspaceOf(next);
    if (workspaceId == null) {
      return;
    }
    final samePrevious =
        previous != null &&
        _workspace.sessions.contains(previous) &&
        herdrTargetOf(previous) != null &&
        serverKey(previous) == serverKey(next);
    final String? leftOn;
    if (samePrevious) {
      // Learn where the tab we are leaving ended up before moving Herdr.
      // The control runs commands in order, so this reads the old focus.
      final remembered = control.focusedWorkspaceId();
      final focus = control.focusWorkspace(workspaceId);
      leftOn = await remembered;
      await focus;
    } else {
      leftOn = null;
      await control.focusWorkspace(workspaceId);
    }
    if (leftOn != null && previous != null) {
      noteWorkspace(previous, leftOn);
    }
  }

  /// Opens the app at an agent's exact place on [host]: its workspace, tab
  /// and pane in the default Herdr session.
  ///
  /// Reuses an open Herdr session on that server (the one already on the
  /// workspace if any), reconnecting it when it dropped; otherwise opens a
  /// new one whose attach command focuses the place first. Returns the
  /// session to show, or null when [open] is null and nothing was open.
  Future<TerminalSessionController?> openAgentLocation(
    SavedHost host, {
    required String workspaceId,
    String tabId = '',
    String paneId = '',
    String label = '',
    TerminalSessionController Function(ConnectTarget target)? open,
  }) async {
    final existing = _herdrSessionFor(host, workspaceId);
    if (existing != null) {
      // Recorded first, so the switch-over focuses the right workspace.
      noteWorkspace(existing, workspaceId);
      _workspace.activate(existing);
      final control = controlFor(existing);
      final reconnect = existing.shouldConnect;
      if (reconnect) {
        unawaited(existing.connect());
      }
      if (control != null) {
        // Not awaited: the caller shows the terminal straight away.
        unawaited(
          control.focusLocation(
            workspaceId: workspaceId,
            tabId: tabId,
            paneId: paneId,
          ),
        );
        if (reconnect) {
          _later(
            () => control.focusLocation(
              workspaceId: workspaceId,
              tabId: tabId,
              paneId: paneId,
            ),
          );
        }
      }
      return existing;
    }
    if (open == null || workspaceId.isEmpty) {
      return null;
    }
    // One app tab per workspace: the pane (or tab) only steers this attach.
    return open(
      ConnectTarget.herdr(
        workspaceId: workspaceId,
        label: label,
        tabId: paneId.isEmpty ? tabId : '',
        paneId: paneId,
      ),
    );
  }

  /// An open Herdr session on [host]'s default server, preferring one that
  /// is on [workspaceId].
  TerminalSessionController? _herdrSessionFor(
    SavedHost host,
    String workspaceId,
  ) {
    TerminalSessionController? any;
    for (final session in _workspace.sessions) {
      if (baseHostId(session.host.id) != host.id) {
        continue;
      }
      final target = herdrTargetOf(session);
      if (target == null || target.session.isNotEmpty) {
        continue;
      }
      if (workspaceId.isNotEmpty && workspaceOf(session) == workspaceId) {
        return session;
      }
      any ??= session;
    }
    return any;
  }

  void _later(Future<void> Function() action) {
    late final Timer timer;
    timer = Timer(reattachRefocusDelay, () {
      _timers.remove(timer);
      if (!_disposed) {
        unawaited(action());
      }
    });
    _timers.add(timer);
  }

  @visibleForTesting
  Iterable<HerdrRemoteControl> get controls => _controls.values;

  Future<void> dispose() async {
    _disposed = true;
    _workspace.removeListener(_handleWorkspaceChanged);
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    final controls = List.of(_controls.values);
    _controls.clear();
    for (final control in controls) {
      await control.close();
    }
  }
}
