// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:conduit/core/app_failure.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention_notifier.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention_provider.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/agent_attention/domain/agent_permission_actions.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/terminal/presentation/terminal_session_controller.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';
import 'package:flutter/foundation.dart';

/// Builds a command runner for one host; injected so tests can fake the
/// remote side.
typedef AgentCommandRunnerFactory = AgentCommandRunner Function(SavedHost host);

/// Monitoring status for one host, as shown by the dashboard.
class AgentHostStatus {
  const AgentHostStatus({
    this.loading = false,
    this.agents = const [],
    this.error,
    this.unavailableReason,
    this.updatedAt,
  });

  final bool loading;
  final List<AgentInfo> agents;

  /// Transient fetch error (connection loss, malformed output).
  final String? error;

  /// Set when the provider tooling is missing/too old; polling has stopped.
  final String? unavailableReason;

  final DateTime? updatedAt;
}

/// Watches enabled, connected hosts for agent state changes.
///
/// Polling is deliberately conservative: one in-flight fetch per host
/// (ticks are skipped while a fetch runs), a fixed interval that backs off
/// after consecutive failures, paused while the app is backgrounded,
/// stopped when the session disconnects or closes, and stopped entirely for
/// a host whose provider tooling is missing. Hosts that log in with a
/// hardware key are listed but never polled: every poll would open a new
/// SSH connection and ask for a key touch.
///
/// Each host picks its provider once per connection from its
/// [SavedHost.agentMonitor] setting: Herdr, the Conductore companion, or
/// automatically (the companion when its CLI answers `version`, else
/// Herdr). A provider that supports it is additionally watched through a
/// long-poll while the app is in the foreground, so a permission prompt
/// shows up within a second instead of at the next 15 s poll; the periodic
/// poll keeps running as the fallback (and is all that runs in the
/// background).
///
/// Notifications are edge-triggered on state *transitions* by stable agent
/// identity — the first snapshot after monitoring starts never notifies,
/// and an unchanged state is never re-notified. A provider-reported state
/// sequence counts as a transition too, so an agent that was answered and
/// blocked again between two polls still notifies. Pending permission
/// requests are notified once per request id (including on the first
/// snapshot: an unanswered prompt is actionable whenever it is seen) and
/// the notification is cancelled when the request disappears.
class AgentAttentionController extends ChangeNotifier {
  AgentAttentionController({
    required TerminalWorkspaceController workspace,
    required AgentCommandRunnerFactory runnerFactory,
    required AgentAttentionProvider provider,
    AgentAttentionProvider? companionProvider,
    AgentAttentionNotifier? notifier,
    Duration pollInterval = const Duration(seconds: 15),
    Duration watchRestartDelay = const Duration(milliseconds: 500),
  }) : _workspace = workspace,
       _runnerFactory = runnerFactory,
       _provider = provider,
       _companionProvider = companionProvider,
       _notifier = notifier,
       _pollInterval = pollInterval,
       _watchRestartDelay = watchRestartDelay {
    _workspace.addListener(_syncMonitors);
    _syncMonitors();
  }

  final TerminalWorkspaceController _workspace;
  final AgentCommandRunnerFactory _runnerFactory;

  /// The default (Herdr) provider.
  final AgentAttentionProvider _provider;

  /// The Conductore companion provider, when the app ships one.
  final AgentAttentionProvider? _companionProvider;
  final AgentAttentionNotifier? _notifier;
  final Duration _pollInterval;

  /// Pause between two long-polls, so a host that answers instantly cannot
  /// spin the loop.
  final Duration _watchRestartDelay;

  final Map<String, _HostMonitor> _monitors = {};
  final Set<String> _deciding = {};
  bool _appActive = true;
  bool _foreground = true;
  bool _disposed = false;

  /// Longest run of skipped ticks after repeated failures (with the default
  /// interval: a poll every 75 s instead of every 15 s).
  static const _maxBackoffTicks = 4;

  static const _decisionTimeout = Duration(seconds: 15);

  @visibleForTesting
  static const hardwareKeyUnavailableReason =
      'Agent monitoring is off for hardware-key logins: each poll would '
      'open a new connection and ask for a key touch. Use a password or '
      'private key for this machine to monitor its agents.';

  /// The default provider (used for hosts that have not resolved theirs).
  AgentAttentionProvider get provider => _provider;

  /// The provider [hostId] resolved to, or the default before its first
  /// poll.
  AgentAttentionProvider providerFor(String hostId) =>
      _monitors[hostId]?.provider ?? _provider;

  /// Hosts currently monitored, in workspace order.
  List<SavedHost> get monitoredHosts => [
    for (final session in _workspace.sessions)
      if (_monitors.containsKey(session.host.id)) session.host,
  ];

  bool isMonitoring(String hostId) => _monitors.containsKey(hostId);

  AgentHostStatus? statusFor(String hostId) => _monitors[hostId]?.status;

  /// Whether a decision for [requestId] is in flight.
  bool isDeciding(String requestId) => _deciding.contains(requestId);

  /// Whether [hostId] is currently on its long-poll (foreground only).
  @visibleForTesting
  bool isWatching(String hostId) => _monitors[hostId]?.watching ?? false;

  /// Agents needing attention across every monitored host.
  int get attentionCount {
    var count = 0;
    for (final monitor in _monitors.values) {
      for (final agent in monitor.status.agents) {
        if (agent.state.needsAttention) {
          count += 1;
        }
      }
    }
    return count;
  }

  /// Pauses polling while the app is backgrounded and resumes (with an
  /// immediate refresh) when it returns. Known agent states are kept, so
  /// transitions that happened in the background still notify exactly once.
  void setAppActive(bool active) {
    if (_appActive == active || _disposed) {
      return;
    }
    _appActive = active;
    for (final monitor in _monitors.values) {
      if (active) {
        // Hosts marked unavailable stay stopped; a manual refresh or a
        // reconnect gives them another chance.
        if (monitor.status.unavailableReason == null) {
          _startTimer(monitor);
          unawaited(_poll(monitor));
        }
      } else {
        monitor.timer?.cancel();
        monitor.timer = null;
      }
    }
  }

  /// Switches between the long-poll (foreground) and periodic polling
  /// only (background). On Android polling itself stays active in the
  /// background (see [setAppActive]); the long-poll is foreground-only so
  /// a backgrounded app does not hold an exec channel open for minutes.
  void setAppForeground(bool foreground) {
    if (_foreground == foreground || _disposed) {
      return;
    }
    _foreground = foreground;
    if (!foreground) {
      // Loops notice on their next iteration; the in-flight long-poll
      // returns by itself within the provider's timeout.
      return;
    }
    for (final monitor in _monitors.values) {
      if (_shouldWatch(monitor)) {
        unawaited(_watchLoop(monitor));
      }
    }
  }

  Future<void> refresh(String hostId) async {
    final monitor = _monitors[hostId];
    if (monitor == null || !monitor.pollable) {
      return;
    }
    // A manual refresh gives an unavailable provider another chance and
    // skips any failure backoff.
    monitor.consecutiveFailures = 0;
    monitor.skipTicks = 0;
    if (monitor.status.unavailableReason != null) {
      // The tooling may have been installed since: pick the provider again.
      monitor.provider = null;
      monitor.status = const AgentHostStatus(loading: true);
      if (_appActive) {
        _startTimer(monitor);
      }
    }
    await _poll(monitor);
  }

  /// Sends the provider's focus command for [agent], if there is one.
  Future<void> focusAgent(String hostId, AgentInfo agent) async {
    final monitor = _monitors[hostId];
    if (monitor == null) {
      return;
    }
    final command = (monitor.provider ?? _provider).focusCommand(agent);
    if (command == null) {
      return;
    }
    try {
      await monitor.runner.run(command, timeout: const Duration(seconds: 10));
    } catch (_) {
      // Focus is best-effort; the agent may have exited since the last poll.
    }
  }

  /// Answers [request] on [hostId] with [verdict]. Throws an [AppFailure]
  /// when the host is not monitored, its provider cannot decide, or the
  /// host rejected the decision; on success the request is dropped from
  /// the dashboard right away and the host is polled for the new state.
  Future<void> decide(
    String hostId,
    PendingPermissionRequest request,
    PermissionVerdict verdict,
  ) async {
    final monitor = _monitors[hostId];
    if (monitor == null) {
      throw const AppFailure('This machine is not being monitored.');
    }
    final provider = monitor.provider ?? await _resolveProvider(monitor);
    await _sendDecision(monitor.runner, provider, request, verdict);
    if (_disposed) {
      return;
    }
    _removeRequest(monitor, request.id);
    notifyListeners();
    unawaited(_poll(monitor));
  }

  /// Completes a notification action tap: answers the request on [host]
  /// (through its monitor when connected, else over a one-off connection)
  /// and dismisses the notification, or rewrites it to say the decision
  /// failed. Never throws.
  Future<void> completePermissionAction(
    AgentPermissionAction action,
    SavedHost? host,
  ) async {
    final notifier = _notifier;
    final verdict = PermissionVerdict.values
        .where((value) => value.wireName == action.verdict)
        .firstOrNull;
    final notificationId = action.notificationId.isNotEmpty
        ? action.notificationId
        : permissionNotificationId(action.hostId, action.requestId);
    Future<void> failed(String reason) async {
      await notifier?.show(
        id: notificationId,
        title: 'Permission decision failed',
        body:
            'Open Conductore to answer the request'
            '${host == null ? '' : ' on ${host.name}'}. $reason',
      );
    }

    if (host == null) {
      await failed('The machine is no longer saved.');
      return;
    }
    if (verdict == null) {
      await failed('Unknown action.');
      return;
    }
    final request = PendingPermissionRequest(
      id: action.requestId,
      toolName: '',
      summary: '',
    );
    final monitor = _monitors[host.id];
    try {
      if (monitor != null) {
        final provider = monitor.provider ?? await _resolveProvider(monitor);
        await _sendDecision(monitor.runner, provider, request, verdict);
        _removeRequest(monitor, action.requestId);
        unawaited(_poll(monitor));
      } else {
        final provider = _companionProvider;
        if (provider == null) {
          throw const AppFailure(
            'This build has no Conductore companion support.',
          );
        }
        final runner = _runnerFactory(host);
        try {
          await _sendDecision(runner, provider, request, verdict);
        } finally {
          unawaited(runner.close());
        }
      }
    } catch (error) {
      await failed(error.toString());
      return;
    } finally {
      if (!_disposed) {
        notifyListeners();
      }
    }
    await notifier?.cancel(id: notificationId);
  }

  /// Notification id for one pending request (stable per request, so a
  /// re-seen request replaces instead of stacking).
  static String permissionNotificationId(String hostId, String requestId) =>
      '$hostId:perm:$requestId';

  Future<void> _sendDecision(
    AgentCommandRunner runner,
    AgentAttentionProvider provider,
    PendingPermissionRequest request,
    PermissionVerdict verdict,
  ) async {
    final command = provider.decideCommand(request, verdict);
    if (command == null) {
      throw AppFailure(
        '${provider.label} cannot answer permission requests from the phone.',
      );
    }
    if (!_deciding.add(request.id)) {
      throw const AppFailure('This request is already being answered.');
    }
    notifyListeners();
    try {
      final result = await runner.run(command, timeout: _decisionTimeout);
      if (result.exitCode != null && result.exitCode != 0) {
        throw AppFailure(
          'The decision was not accepted.',
          _firstLine(
            result.stdout.trim().isNotEmpty ? result.stdout : result.stderr,
          ),
        );
      }
    } finally {
      _deciding.remove(request.id);
    }
  }

  static String _firstLine(String text) {
    final line = text.trim().split('\n').first;
    return line.length > 200 ? line.substring(0, 200) : line;
  }

  /// Drops [requestId] from the host's dashboard state and cancels its
  /// notification (the host confirmed the decision; the next poll agrees).
  void _removeRequest(_HostMonitor monitor, String requestId) {
    final agents = [
      for (final agent in monitor.status.agents)
        if (agent.pendingRequests.any((request) => request.id == requestId))
          AgentInfo(
            id: agent.id,
            name: agent.name,
            state: agent.pendingRequests.length > 1
                ? agent.state
                : AgentAttentionState.working,
            kind: agent.kind,
            workspace: agent.workspace,
            tab: agent.tab,
            pane: agent.pane,
            stateChangedAt: agent.stateChangedAt,
            stateSequence: agent.stateSequence,
            pendingRequests: [
              for (final request in agent.pendingRequests)
                if (request.id != requestId) request,
            ],
          )
        else
          agent,
    ];
    monitor.status = AgentHostStatus(
      agents: agents,
      updatedAt: monitor.status.updatedAt,
    );
    if (monitor.notifiedRequests.remove(requestId)) {
      unawaited(
        _notifier?.cancel(
              id: permissionNotificationId(monitor.host.id, requestId),
            ) ??
            Future<void>.value(),
      );
    }
  }

  void _syncMonitors() {
    if (_disposed) {
      return;
    }
    final wanted = <String, TerminalSessionController>{
      for (final session in _workspace.sessions)
        if (session.host.agentAttentionEnabled &&
            !session.host.isLocal &&
            session.isConnected)
          session.host.id: session,
    };

    for (final hostId in _monitors.keys.toList()) {
      if (!wanted.containsKey(hostId)) {
        _stopMonitor(hostId);
      }
    }
    for (final MapEntry(key: hostId, value: session) in wanted.entries) {
      if (!_monitors.containsKey(hostId)) {
        _startMonitor(session);
      }
    }
    notifyListeners();
  }

  void _startMonitor(TerminalSessionController session) {
    final monitor = _HostMonitor(
      host: session.host,
      session: session,
      runner: _runnerFactory(session.host),
    );
    _monitors[session.host.id] = monitor;
    // React to this session disconnecting even when the workspace itself
    // does not notify.
    session.addListener(_syncMonitors);
    if (session.host.authMethod == SshAuthMethod.hardwareKey) {
      monitor.pollable = false;
      monitor.status = AgentHostStatus(
        unavailableReason: hardwareKeyUnavailableReason,
        updatedAt: DateTime.now(),
      );
      return;
    }
    if (_appActive) {
      _startTimer(monitor);
      unawaited(_poll(monitor));
    }
  }

  void _stopMonitor(String hostId) {
    final monitor = _monitors.remove(hostId);
    if (monitor == null) {
      return;
    }
    monitor.session.removeListener(_syncMonitors);
    monitor.timer?.cancel();
    monitor.timer = null;
    unawaited(monitor.runner.close());
  }

  void _startTimer(_HostMonitor monitor) {
    monitor.timer?.cancel();
    monitor.timer = Timer.periodic(_pollInterval, (_) => _onTick(monitor));
  }

  void _onTick(_HostMonitor monitor) {
    if (monitor.skipTicks > 0) {
      monitor.skipTicks -= 1;
      return;
    }
    if (monitor.watching && _foreground) {
      // The long-poll delivers changes as they happen; the periodic poll is
      // only the fallback while it is not running.
      return;
    }
    unawaited(_poll(monitor));
  }

  /// Polls [hostId] immediately, ignoring any failure backoff.
  @visibleForTesting
  Future<void> pollNow(String hostId) async {
    final monitor = _monitors[hostId];
    if (monitor != null) {
      await _poll(monitor);
    }
  }

  /// Simulates one periodic tick for [hostId], honoring the failure backoff.
  @visibleForTesting
  Future<void> tickNow(String hostId) async {
    final monitor = _monitors[hostId];
    if (monitor == null) {
      return;
    }
    if (monitor.skipTicks > 0) {
      monitor.skipTicks -= 1;
      return;
    }
    await _poll(monitor);
  }

  /// Picks the provider for [monitor] from the host setting, probing the
  /// companion when the setting is automatic. Cached for the life of the
  /// connection.
  Future<AgentAttentionProvider> _resolveProvider(_HostMonitor monitor) async {
    final cached = monitor.provider;
    if (cached != null) {
      return cached;
    }
    final companion = _companionProvider;
    final resolved = switch (monitor.host.agentMonitor) {
      AgentMonitorKind.herdr => _provider,
      AgentMonitorKind.companion => companion ?? _provider,
      AgentMonitorKind.auto =>
        companion != null && await companion.isAvailable(monitor.runner)
            ? companion
            : _provider,
    };
    // Another resolution may have finished while probing.
    return monitor.provider ??= resolved;
  }

  Future<void> _poll(_HostMonitor monitor) async {
    if (_disposed ||
        monitor.fetching ||
        !monitor.pollable ||
        !_monitors.containsKey(monitor.host.id)) {
      return;
    }
    if (!monitor.session.isConnected) {
      _syncMonitors();
      return;
    }
    monitor.fetching = true;
    try {
      final provider = await _resolveProvider(monitor);
      final snapshot = await provider.fetchAgents(monitor.runner);
      if (_disposed || !_monitors.containsKey(monitor.host.id)) {
        return;
      }
      await _applySnapshot(monitor, snapshot);
      monitor.consecutiveFailures = 0;
      monitor.skipTicks = 0;
      if (_shouldWatch(monitor)) {
        unawaited(_watchLoop(monitor));
      }
    } on AgentProviderUnavailable catch (unavailable) {
      monitor.status = AgentHostStatus(
        unavailableReason: unavailable.message,
        updatedAt: DateTime.now(),
      );
      // No point polling a machine without the tooling; a manual refresh or
      // reconnect starts over.
      monitor.timer?.cancel();
      monitor.timer = null;
    } catch (error) {
      monitor.status = AgentHostStatus(
        agents: monitor.status.agents,
        error: error.toString(),
        updatedAt: DateTime.now(),
      );
      // Each failure typically means a reconnect attempt on the next poll;
      // stretch the interval so a flaky link is not hammered.
      monitor.consecutiveFailures += 1;
      monitor.skipTicks = monitor.consecutiveFailures.clamp(
        0,
        _maxBackoffTicks,
      );
    } finally {
      monitor.fetching = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  bool _shouldWatch(_HostMonitor monitor) {
    return !_disposed &&
        _appActive &&
        _foreground &&
        !monitor.watching &&
        monitor.pollable &&
        monitor.status.unavailableReason == null &&
        monitor.status.error == null &&
        (monitor.provider?.supportsWatch ?? false) &&
        _monitors.containsKey(monitor.host.id) &&
        monitor.session.isConnected;
  }

  /// Long-polls the host for changes until the app leaves the foreground,
  /// the host disconnects, or a poll fails (the periodic poll then takes
  /// over with its backoff, and its next success restarts the loop).
  Future<void> _watchLoop(_HostMonitor monitor) async {
    if (monitor.watching) {
      return;
    }
    monitor.watching = true;
    try {
      while (true) {
        final provider = monitor.provider;
        if (_disposed ||
            !_appActive ||
            !_foreground ||
            provider == null ||
            !provider.supportsWatch ||
            !_monitors.containsKey(monitor.host.id) ||
            !monitor.session.isConnected) {
          return;
        }
        try {
          final snapshot = await provider.watchAgents(
            monitor.runner,
            since: monitor.lastSequence,
          );
          if (_disposed || !_monitors.containsKey(monitor.host.id)) {
            return;
          }
          if (snapshot != null) {
            await _applySnapshot(monitor, snapshot);
            monitor.consecutiveFailures = 0;
            monitor.skipTicks = 0;
            notifyListeners();
          }
        } on AgentProviderUnavailable catch (unavailable) {
          monitor.status = AgentHostStatus(
            unavailableReason: unavailable.message,
            updatedAt: DateTime.now(),
          );
          monitor.timer?.cancel();
          monitor.timer = null;
          notifyListeners();
          return;
        } catch (error) {
          if (_disposed || !_monitors.containsKey(monitor.host.id)) {
            return;
          }
          monitor.status = AgentHostStatus(
            agents: monitor.status.agents,
            error: error.toString(),
            updatedAt: DateTime.now(),
          );
          monitor.consecutiveFailures += 1;
          monitor.skipTicks = monitor.consecutiveFailures.clamp(
            0,
            _maxBackoffTicks,
          );
          notifyListeners();
          return;
        }
        if (_watchRestartDelay > Duration.zero) {
          await Future<void>.delayed(_watchRestartDelay);
        }
      }
    } finally {
      monitor.watching = false;
    }
  }

  Future<void> _applySnapshot(
    _HostMonitor monitor,
    AgentAttentionSnapshot snapshot,
  ) async {
    final sequence = snapshot.sequence;
    final lastSequence = monitor.lastSequence;
    if (sequence != null && lastSequence != null && sequence < lastSequence) {
      // A long-poll that returned after a newer periodic poll.
      return;
    }
    if (sequence != null) {
      monitor.lastSequence = sequence;
    }
    final previousStates = monitor.lastStates;
    final notify = monitor.sawInitialSnapshot;
    // Commit the new states before notifying so a throwing notifier can
    // never cause the same transition to notify twice on the next poll.
    monitor.lastStates = {
      for (final agent in snapshot.agents)
        agent.id: (state: agent.state, sequence: agent.stateSequence),
    };
    monitor.sawInitialSnapshot = true;
    monitor.status = AgentHostStatus(
      agents: snapshot.agents,
      updatedAt: DateTime.now(),
    );
    if (notify) {
      await _notifyTransitions(monitor, snapshot, previousStates);
    }
    await _syncPermissionNotifications(monitor, snapshot);
  }

  Future<void> _notifyTransitions(
    _HostMonitor monitor,
    AgentAttentionSnapshot snapshot,
    Map<String, _AgentMark> previousStates,
  ) async {
    final notifier = _notifier;
    if (notifier == null) {
      return;
    }
    final host = monitor.host;
    for (final agent in snapshot.agents) {
      final previous = previousStates[agent.id];
      if (previous != null && !_isTransition(previous, agent)) {
        continue;
      }
      // A pending permission request gets its own actionable notification.
      final needsInput =
          agent.state.needsAttention &&
          host.agentNotifyInput &&
          agent.pendingRequests.isEmpty;
      final finished =
          agent.state == AgentAttentionState.finished &&
          host.agentNotifyFinished;
      if (!needsInput && !finished) {
        continue;
      }
      await notifier.show(
        id: '${host.id}:${agent.id}',
        title: needsInput ? 'Agent needs input' : 'Agent finished',
        // Lock-screen safe: only the agent's display label and machine name.
        body: '${agent.name} on ${host.name}',
      );
    }
  }

  /// Posts one actionable notification per new pending request and cancels
  /// the ones whose request is gone (answered elsewhere, or the agent
  /// exited).
  Future<void> _syncPermissionNotifications(
    _HostMonitor monitor,
    AgentAttentionSnapshot snapshot,
  ) async {
    final notifier = _notifier;
    if (notifier == null) {
      return;
    }
    final host = monitor.host;
    final seen = <String>{};
    for (final agent in snapshot.agents) {
      for (final request in agent.pendingRequests) {
        seen.add(request.id);
        if (!host.agentNotifyInput ||
            monitor.notifiedRequests.contains(request.id)) {
          continue;
        }
        // Commit before showing so a throwing notifier cannot re-notify.
        monitor.notifiedRequests.add(request.id);
        // The generic "needs input" notification for this agent (if any)
        // is superseded by the actionable one.
        await notifier.cancel(id: '${host.id}:${agent.id}');
        await notifier.showPermissionRequest(
          id: permissionNotificationId(host.id, request.id),
          title: 'Claude needs permission: ${request.toolName}',
          body: '${request.summary} (on ${host.name})',
          hostId: host.id,
          requestId: request.id,
        );
      }
    }
    for (final requestId in monitor.notifiedRequests.toList()) {
      if (!seen.contains(requestId)) {
        monitor.notifiedRequests.remove(requestId);
        await notifier.cancel(id: permissionNotificationId(host.id, requestId));
      }
    }
  }

  /// A state change, or the same state reached again (the provider bumped
  /// its sequence, e.g. blocked → answered → blocked again within one poll
  /// interval).
  static bool _isTransition(_AgentMark previous, AgentInfo agent) {
    if (previous.state != agent.state) {
      return true;
    }
    final sequence = agent.stateSequence;
    return sequence != null &&
        previous.sequence != null &&
        sequence != previous.sequence;
  }

  @override
  void dispose() {
    _disposed = true;
    _workspace.removeListener(_syncMonitors);
    for (final hostId in _monitors.keys.toList()) {
      _stopMonitor(hostId);
    }
    super.dispose();
  }
}

class _HostMonitor {
  _HostMonitor({
    required this.host,
    required this.session,
    required this.runner,
  });

  final SavedHost host;
  final TerminalSessionController session;
  final AgentCommandRunner runner;

  Timer? timer;
  bool fetching = false;

  /// Set while the long-poll loop runs.
  bool watching = false;

  /// Provider picked for this connection; null until the first poll.
  AgentAttentionProvider? provider;

  /// False for hosts that are listed but must never be polled.
  bool pollable = true;
  bool sawInitialSnapshot = false;
  int consecutiveFailures = 0;
  int skipTicks = 0;
  int? lastSequence;
  Map<String, _AgentMark> lastStates = const {};

  /// Request ids that currently have a permission notification showing.
  final Set<String> notifiedRequests = {};
  AgentHostStatus status = const AgentHostStatus(loading: true);
}

typedef _AgentMark = ({AgentAttentionState state, int? sequence});
