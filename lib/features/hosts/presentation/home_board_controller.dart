// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:conduit/core/app_failure.dart';
import 'package:conduit/features/agent_attention/data/herdr_attention_provider.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention_provider.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_controller.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/sessions/domain/remote_session_listing.dart';
import 'package:flutter/foundation.dart';

/// Where the home board is for the selected machine.
enum HomeBoardPhase {
  /// No machine selected, or a machine the board does not list (local).
  idle,

  /// Listing waits for an explicit request: the login uses a hardware key
  /// (each connection asks for a touch) or the machine was never connected
  /// (its host key would have to be trusted first). See
  /// [HomeBoardController.requestReason].
  awaitingRequest,

  /// First fetch in flight; nothing to show yet.
  loading,

  /// Workspaces (and their agent panes) are listed.
  ready,

  /// Herdr is not installed on the machine; polling has stopped.
  notInstalled,

  /// Herdr is installed but its server is not running.
  notRunning,

  /// The last fetch failed; [HomeBoardState.workspaces] may hold stale data.
  failed,
}

/// Why the board waits for an explicit request before listing.
enum HomeBoardRequestReason {
  /// Each new connection asks for a hardware-key touch.
  hardwareKey,

  /// The machine was never connected, so its host key is not trusted yet.
  neverConnected,
}

/// One Herdr pane that runs an agent, with its tab resolved to a label.
@immutable
class HomeBoardPane {
  const HomeBoardPane({required this.agent, this.tabLabel = ''});

  final AgentInfo agent;

  /// Label of the pane's Herdr tab; empty when unknown.
  final String tabLabel;

  /// Human title of the pane: the agent's live name or terminal title.
  String get title => agent.name;
}

/// One Herdr workspace with the agent panes inside it.
@immutable
class HomeBoardWorkspace {
  const HomeBoardWorkspace({required this.workspace, this.panes = const []});

  final HerdrWorkspaceInfo workspace;
  final List<HomeBoardPane> panes;

  String get id => workspace.id;
  String get label => workspace.label;

  /// Most urgent agent state in the workspace (panes first, then Herdr's
  /// own workspace-level status).
  AgentAttentionState? get summary {
    AgentAttentionState? best;
    for (final pane in panes) {
      final state = pane.agent.state;
      if (best == null || homeBoardPriority(state) < homeBoardPriority(best)) {
        best = state;
      }
    }
    return best ?? herdrStatusToState(workspace.agentStatus);
  }
}

/// Snapshot rendered by the home board.
@immutable
class HomeBoardState {
  const HomeBoardState({
    this.phase = HomeBoardPhase.idle,
    this.workspaces = const [],
    this.message,
    this.updatedAt,
    this.refreshing = false,
  });

  final HomeBoardPhase phase;
  final List<HomeBoardWorkspace> workspaces;

  /// Error or availability text for [HomeBoardPhase.failed],
  /// [HomeBoardPhase.notInstalled] and [HomeBoardPhase.notRunning].
  final String? message;
  final DateTime? updatedAt;

  /// A fetch is running while older data is on screen.
  final bool refreshing;

  int get paneCount =>
      workspaces.fold(0, (count, workspace) => count + workspace.panes.length);

  int get attentionCount => workspaces.fold(
    0,
    (count, workspace) =>
        count +
        workspace.panes.where((pane) => pane.agent.state.needsAttention).length,
  );

  HomeBoardState copyWith({
    HomeBoardPhase? phase,
    List<HomeBoardWorkspace>? workspaces,
    String? message,
    bool clearMessage = false,
    DateTime? updatedAt,
    bool? refreshing,
  }) {
    return HomeBoardState(
      phase: phase ?? this.phase,
      workspaces: workspaces ?? this.workspaces,
      message: clearMessage ? null : message ?? this.message,
      updatedAt: updatedAt ?? this.updatedAt,
      refreshing: refreshing ?? this.refreshing,
    );
  }
}

/// Sort key for agent states: lower is more urgent.
int homeBoardPriority(AgentAttentionState state) => switch (state) {
  AgentAttentionState.needsInput => 0,
  AgentAttentionState.blocked => 1,
  AgentAttentionState.working => 2,
  AgentAttentionState.finished => 3,
  AgentAttentionState.idle => 4,
  AgentAttentionState.unknown => 5,
};

/// Maps Herdr's raw `agent_status` (`idle`, `working`, `blocked`, `done`,
/// `unknown`) to a state; null when there is nothing to report.
AgentAttentionState? herdrStatusToState(String raw) {
  return switch (raw.toLowerCase()) {
    'working' || 'running' || 'busy' => AgentAttentionState.working,
    'blocked' || 'waiting' || 'needs_input' => AgentAttentionState.needsInput,
    'done' || 'finished' => AgentAttentionState.finished,
    'idle' || 'ready' => AgentAttentionState.idle,
    _ => null,
  };
}

/// Live board of one machine's Herdr workspaces and agent panes for the
/// home page.
///
/// It polls over its own on-demand exec channel (so it works before any
/// terminal session exists), only while [setVisible] says the home page is
/// on screen, one fetch at a time, backing off after failures. The channel
/// is closed whenever the board is hidden or switches machine. Hardware-key
/// machines are listed only after [requestLoad]: every new connection asks
/// for a key touch.
class HomeBoardController extends ChangeNotifier {
  HomeBoardController({
    required AgentCommandRunnerFactory runnerFactory,
    AgentAttentionProvider provider = const HerdrAttentionProvider(),
    Duration pollInterval = const Duration(seconds: 5),
  }) : _runnerFactory = runnerFactory,
       _provider = provider,
       _pollInterval = pollInterval;

  final AgentCommandRunnerFactory _runnerFactory;
  final AgentAttentionProvider _provider;
  final Duration _pollInterval;

  static const _timeout = Duration(seconds: 10);
  static const _maxBackoffTicks = 4;

  /// Consecutive failures after which polling stops until [refresh]: a
  /// rejected host key or a machine that is down should not keep asking.
  static const _maxFailures = 3;

  SavedHost? _host;
  AgentCommandRunner? _runner;
  Timer? _timer;
  bool _visible = false;
  bool _requested = false;

  /// The machine was reached before even though its saved record has no
  /// last-connected time (a trusted host key, an open session): it lists
  /// on its own.
  bool _connectedBefore = false;

  /// Generation of the fetch in flight, or null when idle.
  int? _fetchingGeneration;
  bool _disposed = false;
  int _generation = 0;
  int _failures = 0;
  int _skipTicks = 0;
  HomeBoardState _state = const HomeBoardState();

  SavedHost? get host => _host;
  HomeBoardState get state => _state;
  bool get visible => _visible;

  /// Whether the board waits for [requestLoad] before listing.
  bool get _needsRequest => requestReason != null;

  /// Why listing waits for [requestLoad], or null when it polls on its own.
  HomeBoardRequestReason? get requestReason {
    final host = _host;
    if (host == null || _requested) return null;
    if (host.authMethod == SshAuthMethod.hardwareKey) {
      return HomeBoardRequestReason.hardwareKey;
    }
    if (host.lastConnectedAt == null && !_connectedBefore) {
      return HomeBoardRequestReason.neverConnected;
    }
    return null;
  }

  bool get _listable => _host != null && !_host!.isLocal;

  /// Shows [host] on the board. Selecting the same machine again only
  /// refreshes its saved details; a different one starts over.
  ///
  /// [connectedBefore] marks a machine the app has reached before (its host
  /// key is trusted, or a session is open) so it lists without a request
  /// even when its saved record lost the last-connected time.
  void selectHost(SavedHost? host, {bool connectedBefore = false}) {
    if (_disposed) return;
    if (host?.id == _host?.id) {
      final wasWaiting = _needsRequest;
      _host = host;
      _connectedBefore = _connectedBefore || connectedBefore;
      // A first connection trusts the host key; the board can start.
      if (wasWaiting && !_needsRequest) {
        _state = HomeBoardState(phase: _initialPhase());
        notifyListeners();
        _start();
      }
      return;
    }
    _generation += 1;
    _stopTimer();
    unawaited(_closeRunner());
    _host = host;
    _requested = false;
    _connectedBefore = connectedBefore;
    _failures = 0;
    _skipTicks = 0;
    _state = HomeBoardState(phase: _initialPhase());
    notifyListeners();
    _start();
  }

  /// Starts polling while the home page is on screen and the app is in
  /// the foreground; stops it (and closes the channel) otherwise.
  void setVisible(bool visible) {
    if (_disposed || visible == _visible) return;
    _visible = visible;
    if (visible) {
      _start();
    } else {
      _stopTimer();
      _generation += 1;
      unawaited(_closeRunner());
      if (_state.refreshing || _state.phase == HomeBoardPhase.loading) {
        _state = _state.copyWith(
          refreshing: false,
          phase: _state.phase == HomeBoardPhase.loading
              ? _initialPhase()
              : null,
        );
        notifyListeners();
      }
    }
  }

  /// Lists a hardware-key machine (one key touch), then keeps polling it.
  void requestLoad() {
    if (_disposed || !_listable) return;
    _requested = true;
    _failures = 0;
    _skipTicks = 0;
    _start(force: true);
  }

  /// Fetches now, skipping any failure backoff. A no-op for hardware-key
  /// machines that have not been requested yet.
  Future<void> refresh() async {
    if (_disposed || !_listable || _needsRequest) return;
    _failures = 0;
    _skipTicks = 0;
    if (_timer == null && _visible) {
      _startTimer();
    }
    await _fetch();
  }

  /// Focuses [agent]'s pane in Herdr (`herdr agent focus <pane>`).
  Future<void> focusPane(AgentInfo agent) async {
    final command = _provider.focusCommand(agent);
    if (command == null) return;
    await _runBestEffort(command);
  }

  /// Focuses a whole workspace in Herdr.
  Future<void> focusWorkspace(String workspaceId) async {
    if (workspaceId.isEmpty) return;
    await _runBestEffort(
      HerdrAttentionProvider.remoteCommand(
        'workspace focus ${ConnectTarget.shellQuote(workspaceId)}',
      ),
    );
  }

  Future<void> _runBestEffort(String command) async {
    final host = _host;
    if (_disposed || host == null || host.isLocal) return;
    try {
      final runner = _runner ??= _runnerFactory(host);
      await runner.run(command, timeout: _timeout);
    } catch (_) {
      // Focus is a nicety: the pane may be gone since the last poll.
    }
    if (!_visible && !_disposed) {
      // Sent from behind the terminal page: do not keep the channel open.
      await _closeRunner();
    }
  }

  HomeBoardPhase _initialPhase() {
    if (!_listable) return HomeBoardPhase.idle;
    if (_needsRequest) return HomeBoardPhase.awaitingRequest;
    return HomeBoardPhase.loading;
  }

  void _start({bool force = false}) {
    if (!_visible || !_listable || _needsRequest) return;
    if (!force && _state.phase == HomeBoardPhase.notInstalled) return;
    if (_state.phase == HomeBoardPhase.awaitingRequest ||
        _state.phase == HomeBoardPhase.idle) {
      _state = _state.copyWith(phase: HomeBoardPhase.loading);
      notifyListeners();
    }
    _startTimer();
    unawaited(_fetch());
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_pollInterval, (_) {
      if (_skipTicks > 0) {
        _skipTicks -= 1;
        return;
      }
      unawaited(_fetch());
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _closeRunner() async {
    final runner = _runner;
    _runner = null;
    if (runner != null) {
      try {
        await runner.close();
      } catch (_) {
        // Already gone.
      }
    }
  }

  /// Runs one listing for the current machine. Visible for tests so they
  /// can drive polls without timers.
  @visibleForTesting
  Future<void> pollNow() => _fetch();

  Future<void> _fetch() async {
    final host = _host;
    if (_disposed ||
        _fetchingGeneration == _generation ||
        host == null ||
        !_listable ||
        _needsRequest) {
      return;
    }
    final generation = _generation;
    _fetchingGeneration = generation;
    if (_state.phase != HomeBoardPhase.loading && !_state.refreshing) {
      _state = _state.copyWith(refreshing: true);
      notifyListeners();
    }
    try {
      final runner = _runner ??= _runnerFactory(host);
      final next = await _load(runner);
      if (_disposed || generation != _generation) return;
      _state = next;
      _failures = 0;
      _skipTicks = 0;
      if (next.phase == HomeBoardPhase.notInstalled) {
        // No point polling a machine without Herdr; pull-to-refresh or
        // switching machines tries again.
        _stopTimer();
      }
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _failures += 1;
      _skipTicks = _failures.clamp(0, _maxBackoffTicks);
      if (_failures >= _maxFailures) {
        _stopTimer();
      }
      _state = HomeBoardState(
        phase: HomeBoardPhase.failed,
        workspaces: _state.workspaces,
        message: error is AppFailure ? error.toString() : '$error',
        updatedAt: _state.updatedAt,
      );
      // A broken channel reconnects on the next poll.
      unawaited(_closeRunner());
    } finally {
      if (_fetchingGeneration == generation) {
        _fetchingGeneration = null;
      }
      if (!_disposed && generation == _generation) notifyListeners();
    }
  }

  Future<HomeBoardState> _load(AgentCommandRunner runner) async {
    final workspaceResult = await runner.run(
      RemoteSessionListing.herdrWorkspaceListCommand,
      timeout: _timeout,
    );
    final listing = RemoteSessionListing.interpretHerdrWorkspaces(
      workspaceResult,
    );
    switch (listing) {
      case RemoteListingNotInstalled<HerdrWorkspaceInfo>():
        return HomeBoardState(
          phase: HomeBoardPhase.notInstalled,
          message: 'Herdr is not installed on this machine.',
          updatedAt: DateTime.now(),
        );
      case RemoteListingNotRunning<HerdrWorkspaceInfo>(:final message):
        return HomeBoardState(
          phase: HomeBoardPhase.notRunning,
          message: message,
          updatedAt: DateTime.now(),
        );
      case RemoteListingFailed<HerdrWorkspaceInfo>(:final message):
        throw AppFailure(message);
      case RemoteListingAvailable<HerdrWorkspaceInfo>(:final items):
        final tabs = await _loadTabs(runner);
        final agents = await _loadAgents(runner);
        return HomeBoardState(
          phase: HomeBoardPhase.ready,
          workspaces: buildBoard(items, tabs, agents),
          updatedAt: DateTime.now(),
        );
    }
  }

  Future<List<HerdrTabInfo>> _loadTabs(AgentCommandRunner runner) async {
    try {
      final result = await runner.run(
        RemoteSessionListing.herdrTabListCommand,
        timeout: _timeout,
      );
      if (result.exitCode != null && result.exitCode != 0) return const [];
      return RemoteSessionListing.parseHerdrTabs(result.stdout);
    } on AppFailure {
      rethrow;
    } catch (_) {
      // Tab labels are a nicety; the board still shows workspaces.
      return const [];
    }
  }

  Future<List<AgentInfo>> _loadAgents(AgentCommandRunner runner) async {
    try {
      final snapshot = await _provider.fetchAgents(runner);
      return snapshot.agents;
    } on AgentProviderUnavailable {
      // An older Herdr without `agent list`: workspaces only.
      return const [];
    }
  }

  /// Groups [agents] under their [workspaces], resolving tab labels.
  /// Agents whose workspace is not listed are dropped; workspace order is
  /// Herdr's; panes are ordered by tab number, then pane id.
  static List<HomeBoardWorkspace> buildBoard(
    List<HerdrWorkspaceInfo> workspaces,
    List<HerdrTabInfo> tabs,
    List<AgentInfo> agents,
  ) {
    final tabsById = {for (final tab in tabs) tab.id: tab};
    return [
      for (final workspace in workspaces)
        HomeBoardWorkspace(
          workspace: workspace,
          panes:
              [
                for (final agent in agents)
                  if (agent.workspace == workspace.id)
                    HomeBoardPane(
                      agent: agent,
                      tabLabel: _tabLabel(tabsById[agent.tab]),
                    ),
              ]..sort((a, b) {
                final byTab = (tabsById[a.agent.tab]?.number ?? 0).compareTo(
                  tabsById[b.agent.tab]?.number ?? 0,
                );
                if (byTab != 0) return byTab;
                return (a.agent.pane ?? a.agent.id).compareTo(
                  b.agent.pane ?? b.agent.id,
                );
              }),
        ),
    ];
  }

  static String _tabLabel(HerdrTabInfo? tab) {
    if (tab == null) return '';
    if (tab.label.isNotEmpty) return tab.label;
    return tab.number == null ? '' : 'Tab ${tab.number}';
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTimer();
    unawaited(_closeRunner());
    super.dispose();
  }
}
