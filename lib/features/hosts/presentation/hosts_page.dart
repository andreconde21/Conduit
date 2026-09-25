import 'dart:async';

import 'package:conduit/core/presentation/conduit_brand.dart';
import 'package:conduit/core/presentation/system_navigation_insets.dart';
import 'package:conduit/core/presentation/theme_sheet.dart';
import 'package:conduit/core/theme/terminal_appearance.dart';
import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_controller.dart';
import 'package:conduit/features/app_lock/presentation/app_lock_controller.dart';
import 'package:conduit/features/backup/data/app_backup_service.dart';
import 'package:conduit/features/companion_setup/presentation/companion_setup_page.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/hosts/presentation/home_board_controller.dart';
import 'package:conduit/features/hosts/presentation/host_form_page.dart';
import 'package:conduit/features/hosts/presentation/hosts_controller.dart';
import 'package:conduit/features/hosts/presentation/widgets/home_chrome.dart';
import 'package:conduit/features/hosts/presentation/widgets/home_session_grid.dart';
import 'package:conduit/features/hosts/presentation/widgets/host_card.dart';
import 'package:conduit/features/hosts/presentation/widgets/machine_switcher.dart';
import 'package:conduit/features/hosts/presentation/widgets/message_state.dart';
import 'package:conduit/features/local_shell/domain/local_shell_instance.dart';
import 'package:conduit/features/local_shell/presentation/local_shell_controller.dart';
import 'package:conduit/features/local_shell/presentation/local_shell_instance_page.dart';
import 'package:conduit/features/local_shell/presentation/local_shell_setup_page.dart';
import 'package:conduit/features/local_shell/presentation/widgets/local_shell_section.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/sessions/presentation/session_connect_flow.dart';
import 'package:conduit/features/sessions/presentation/session_grid_page.dart'
    show summarizeAgentState;
import 'package:conduit/features/sftp/domain/file_export.dart';
import 'package:conduit/features/sftp/domain/sftp_bookmarks_repository.dart';
import 'package:conduit/features/sftp/domain/sftp_repository.dart';
import 'package:conduit/features/sftp/presentation/sftp_browser_page.dart';
import 'package:conduit/features/terminal/domain/host_key_prompt.dart';
import 'package:conduit/features/terminal/domain/host_key_verifier.dart';
import 'package:conduit/features/terminal/domain/ssh_terminal_repository.dart';
import 'package:conduit/features/terminal/presentation/host_key_prompt_coordinator.dart';
import 'package:conduit/features/terminal/presentation/host_key_prompt_dialog.dart';
import 'package:conduit/features/terminal/presentation/terminal_page.dart';
import 'package:conduit/features/terminal/presentation/terminal_session_controller.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';
import 'package:conduit/features/terminal/presentation/trusted_keys_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

/// The home page, Moshi-style: a slim bar (lock, machine chip, settings),
/// then a two-column grid of large live previews of every open session,
/// followed by the selected machine's Herdr workspaces that are not open in
/// the app yet (or one notice saying why they cannot be listed). The local
/// shell and counters sit in a collapsed "More" area at the bottom.
class HostsPage extends StatefulWidget {
  const HostsPage({
    required this.hostsController,
    required this.lockController,
    required this.terminalRepository,
    required this.workspaceController,
    required this.localShellController,
    required this.themeController,
    required this.hostKeyVerifier,
    required this.promptCoordinator,
    required this.sftpRepository,
    required this.sftpBookmarksRepository,
    required this.agentAttention,
    required this.backupService,
    required this.fileExport,
    this.connectFlow,
    this.homeBoard,
    this.previewRefreshInterval = const Duration(seconds: 2),
    this.paneRefocusDelay = const Duration(seconds: 4),
    super.key,
  });

  final HostsController hostsController;
  final AppLockController lockController;
  final SshTerminalRepository terminalRepository;
  final TerminalWorkspaceController workspaceController;
  final LocalShellController localShellController;
  final ThemeController themeController;
  final HostKeyVerifier hostKeyVerifier;
  final HostKeyPromptCoordinator promptCoordinator;
  final SftpRepository sftpRepository;
  final SftpBookmarksRepository sftpBookmarksRepository;
  final AgentAttentionController agentAttention;
  final AppBackupService backupService;
  final FileExport fileExport;

  /// Connect picker (tmux / Herdr / recent / skip); null connects to a plain
  /// shell like before.
  final SessionConnectFlow? connectFlow;

  /// Live Herdr board for the selected machine. When null the page builds
  /// one from [connectFlow]'s runner factory (and hides the board without
  /// a connect flow).
  final HomeBoardController? homeBoard;

  /// How often session preview tiles are re-captured while visible.
  final Duration previewRefreshInterval;

  /// After opening a new session for a pane, the pane is focused again
  /// once Herdr has attached.
  final Duration paneRefocusDelay;

  @override
  State<HostsPage> createState() => _HostsPageState();
}

class _HostsPageState extends State<HostsPage> with WidgetsBindingObserver {
  bool _terminalPageOpen = false;
  bool _showingHostKeyPrompt = false;
  bool _appResumed = true;
  bool _routeVisible = true;
  bool? _moreExpanded;
  bool _largeTiles = false;
  String? _selectedHostId;

  /// `host:port` of every trusted host key: machines reached before list
  /// their Herdr workspaces without asking.
  Set<String> _trustedEndpoints = const {};
  HomeBoardController? _ownedBoard;
  Timer? _previewTimer;
  Timer? _refocusTimer;

  HomeBoardController? get _board => widget.homeBoard ?? _ownedBoard;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final flow = widget.connectFlow;
    if (widget.homeBoard == null && flow != null) {
      _ownedBoard = HomeBoardController(
        runnerFactory: flow.runnerFactory,
        provider: widget.agentAttention.provider,
      );
    }
    widget.hostsController.addListener(_syncSelection);
    widget.workspaceController.addListener(_syncSelection);
    flow?.terminalRequests.addListener(_handleTerminalRequest);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(widget.hostsController.load());
      unawaited(widget.localShellController.refresh());
      _handlePromptChanged();
      _syncSelection();
      _syncVisibility();
      unawaited(_loadTrustedEndpoints());
    });
    widget.promptCoordinator.addListener(_handlePromptChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Routes pushed on top (terminal, forms, SFTP) put this page offstage
    // with tickers disabled; that is the signal to pause live polling.
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible != _routeVisible) {
      _routeVisible = visible;
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncVisibility());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    _syncVisibility();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.hostsController.removeListener(_syncSelection);
    widget.workspaceController.removeListener(_syncSelection);
    widget.connectFlow?.terminalRequests.removeListener(_handleTerminalRequest);
    widget.promptCoordinator.removeListener(_handlePromptChanged);
    widget.promptCoordinator.rejectAll();
    _previewTimer?.cancel();
    _refocusTimer?.cancel();
    widget.homeBoard?.setVisible(false);
    _ownedBoard?.dispose();
    super.dispose();
  }

  void _syncVisibility() {
    if (!mounted) return;
    final visible = _appResumed && _routeVisible;
    _board?.setVisible(visible);
    if (visible) {
      // Back from the terminal a first connection may have trusted a key.
      unawaited(_loadTrustedEndpoints());
      _previewTimer ??= Timer.periodic(widget.previewRefreshInterval, (_) {
        if (mounted && widget.workspaceController.hasSessions) {
          setState(() {});
        }
      });
    } else {
      _previewTimer?.cancel();
      _previewTimer = null;
    }
  }

  /// The machine the page shows: the one picked in the switcher, else the
  /// active session's machine, else the most recently connected one.
  SavedHost? get _selectedHost {
    final hosts = widget.hostsController.hosts;
    if (hosts.isEmpty) return null;
    final picked = _selectedHostId;
    if (picked != null) {
      final match = hosts.where((host) => host.id == picked).firstOrNull;
      if (match != null) return match;
    }
    final active = widget.workspaceController.activeSession;
    if (active != null) {
      final id = baseHostId(active.host.id);
      final match = hosts.where((host) => host.id == id).firstOrNull;
      if (match != null) return match;
    }
    SavedHost? latest;
    for (final host in hosts) {
      final at = host.lastConnectedAt;
      if (at == null) continue;
      if (latest == null || at.isAfter(latest.lastConnectedAt!)) {
        latest = host;
      }
    }
    return latest ?? widget.hostsController.sortedHosts.first;
  }

  void _syncSelection() {
    if (!mounted) return;
    final host = _selectedHost;
    if (host == null && _selectedHostId != null) {
      _selectedHostId = null;
    }
    _board?.selectHost(
      host,
      connectedBefore: host != null && _connectedBefore(host),
    );
  }

  bool _connectedBefore(SavedHost host) =>
      _trustedEndpoints.contains('${host.host.trim()}:${host.port}') ||
      _sessionsFor(host).isNotEmpty;

  Future<void> _loadTrustedEndpoints() async {
    try {
      final records = await widget.hostKeyVerifier.loadTrustedKeys();
      if (!mounted) return;
      _trustedEndpoints = {for (final record in records) record.key};
      _syncSelection();
    } catch (_) {
      // Unreadable key store: never-connected machines just wait for a tap.
    }
  }

  List<TerminalSessionController> _sessionsFor(SavedHost host) => [
    for (final session in widget.workspaceController.sessions)
      if (baseHostId(session.host.id) == host.id) session,
  ];

  void _handlePromptChanged() {
    if (_showingHostKeyPrompt || !mounted) return;
    if (widget.promptCoordinator.current == null) return;
    _showingHostKeyPrompt = true;
    Future<void>.microtask(() async {
      try {
        while (true) {
          final next = widget.promptCoordinator.current;
          if (next == null) break;
          final decision = await _requestHostKeyDecision(next);
          widget.promptCoordinator.resolve(next, decision);
        }
      } finally {
        _showingHostKeyPrompt = false;
      }
    });
  }

  Future<HostKeyDecision> _requestHostKeyDecision(
    HostKeyPromptRequest request,
  ) async {
    if (!mounted) return HostKeyDecision.reject;
    return await showHostKeyPromptDialog(context: context, request: request) ??
        HostKeyDecision.reject;
  }

  Future<void> _refreshAll() async {
    await widget.hostsController.load();
    await _board?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.themeController.palette;
    final board = _board;
    return Scaffold(
      body: ConduitBackdrop(
        palette: palette,
        child: SafeArea(
          bottom: shouldApplyBottomSafeArea(context),
          child: RefreshIndicator(
            color: Theme.of(context).colorScheme.primary,
            onRefresh: _refreshAll,
            child: ListenableBuilder(
              listenable: Listenable.merge([
                widget.hostsController,
                widget.workspaceController,
                widget.themeController,
                widget.agentAttention,
                ?board,
              ]),
              builder: (context, _) {
                final host = _selectedHost;
                return CustomScrollView(
                  key: const ValueKey('home-scroll'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: HomeTopBar(
                        onLock: _lock,
                        onSettings: () => _openSettings(host),
                        machine: host == null ? null : _machineChip(host),
                      ),
                    ),
                    ..._buildMain(context, host),
                    SliverToBoxAdapter(child: _buildMore(context)),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _machineChip(SavedHost host) {
    return MachineChip(
      host: host,
      sessionCount: _sessionsFor(host).length,
      hostCount: widget.hostsController.hosts.length,
      otherAttentionCount: _otherAttentionCount(host),
      onSwitch: _switchMachine,
      onMenu: (choice) => _handleMenu(choice, host),
    );
  }

  List<Widget> _buildMain(BuildContext context, SavedHost? host) {
    final controller = widget.hostsController;
    if (controller.isLoading && controller.hosts.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }
    if (controller.errorMessage != null && controller.hosts.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: MessageState(
            icon: Icons.error_outline,
            title: 'Something went wrong',
            message: controller.errorMessage!,
            actionLabel: 'Retry',
            onAction: controller.load,
          ),
        ),
      ];
    }
    if (host == null) {
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate.fixed([
              const _MachineSectionHeader(),
              const SizedBox(height: 24),
              MessageState(
                icon: Icons.dns_outlined,
                title: 'No saved machines yet',
                message:
                    'Add an SSH or Mosh server and Conductore will keep its '
                    'credentials in your device’s secure storage.',
                actionLabel: 'Add machine',
                onAction: _openForm,
              ),
            ]),
          ),
        ),
      ];
    }

    final palette = widget.themeController.palette;
    final brightness = Theme.of(context).brightness;
    final fontFamily = widget.themeController.terminalFont.fontFamily;
    final width = MediaQuery.sizeOf(context).width;
    final metrics = HomeGridMetrics.of(width, large: _largeTiles);
    final sessions = widget.workspaceController.sessions;
    final active = widget.workspaceController.activeSession;
    final board = _board;
    final boardState = board?.state;
    final boardWorkspaces = boardState?.workspaces ?? const [];
    final hostSessions = _sessionsFor(host);
    final attached = _attachedWorkspaceIds(hostSessions);
    final dormant = [
      for (final workspace in boardWorkspaces)
        if (!attached.contains(workspace.id)) workspace,
    ];
    final notice = boardState == null
        ? null
        : HomeBoardNotice.of(
            boardState,
            requestReason: board!.requestReason,
            hasOpenHerdrSession: hostSessions.any(
              (session) =>
                  ConnectTarget.fromSessionHostId(session.host.id)?.kind ==
                  ConnectTargetKind.herdr,
            ),
          );
    const gutter = HomeGridMetrics.horizontalPadding;

    return [
      SliverToBoxAdapter(
        child: _SectionHeader(
          label: 'SESSIONS',
          detail: sessions.isEmpty ? 'none open' : '${sessions.length} open',
          trailing: IconButton(
            tooltip: _largeTiles ? 'Two columns' : 'Large tiles',
            icon: Icon(
              _largeTiles
                  ? Icons.grid_view_rounded
                  : Icons.view_agenda_outlined,
            ),
            onPressed: () => setState(() => _largeTiles = !_largeTiles),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(gutter, 4, gutter, 8),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: metrics.columns,
            mainAxisSpacing: 18,
            crossAxisSpacing: HomeGridMetrics.spacing,
            mainAxisExtent: metrics.sessionExtent,
          ),
          delegate: SliverChildBuilderDelegate((context, index) {
            if (index == sessions.length) {
              return HomeAddTile(
                palette: palette,
                brightness: brightness,
                label: sessions.isEmpty ? 'Connect' : 'New session',
                onTap: () => _connect(host, forcePicker: true),
              );
            }
            final session = sessions[index];
            final sameMachine = baseHostId(session.host.id) == host.id;
            return HomeSessionTile(
              key: ValueKey('home-session-${session.host.id}'),
              session: session,
              info: HomeSessionInfo.of(
                session,
                workspaces: sameMachine ? boardWorkspaces : const [],
                agentState: summarizeAgentState(
                  widget.agentAttention.statusFor(session.host.id),
                  session.host.id,
                ),
              ),
              palette: palette,
              brightness: brightness,
              fontFamily: fontFamily,
              selected: session == active,
              onTap: () {
                widget.workspaceController.activate(session);
                unawaited(_openTerminalWorkspace());
              },
              onLongPress: () => _showSessionActions(session),
            );
          }, childCount: sessions.length + 1),
        ),
      ),
      if (notice != null)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(gutter, 4, gutter, 8),
          sliver: SliverToBoxAdapter(
            child: HomeBoardNoticeTile(
              notice: notice,
              palette: palette,
              brightness: brightness,
              onAction: notice.action == null
                  ? null
                  : () => _handleNoticeAction(host, notice.action!),
            ),
          ),
        ),
      if (dormant.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: _SectionHeader(
            label: 'HERDR',
            detail: dormant.length == 1
                ? '1 workspace not open'
                : '${dormant.length} workspaces not open',
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(gutter, 4, gutter, 8),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: metrics.columns,
              mainAxisSpacing: HomeGridMetrics.spacing,
              crossAxisSpacing: HomeGridMetrics.spacing,
              mainAxisExtent: metrics.dormantExtent,
            ),
            delegate: SliverChildListDelegate([
              for (final workspace in dormant)
                DormantWorkspaceTile(
                  key: ValueKey('dormant-${workspace.id}'),
                  workspace: workspace,
                  palette: palette,
                  brightness: brightness,
                  onTap: () => _openPane(host, workspace, null),
                  onLongPress: workspace.panes.isEmpty
                      ? null
                      : () => _showWorkspacePanes(host, workspace),
                ),
            ]),
          ),
        ),
      ],
    ];
  }

  void _handleNoticeAction(SavedHost host, HomeBoardNoticeAction action) {
    final board = _board;
    switch (action) {
      case HomeBoardNoticeAction.request:
        board?.requestLoad();
      case HomeBoardNoticeAction.retry:
        if (board != null) unawaited(board.refresh());
      case HomeBoardNoticeAction.startHerdr:
        unawaited(
          _openTarget(host, const ConnectTarget.herdr(workspaceId: '')),
        );
      case HomeBoardNoticeAction.openShell:
        unawaited(_openTarget(host, const ConnectTarget.shell()));
    }
  }

  /// Lists a dormant workspace's agent panes; tapping one opens the
  /// workspace focused on that pane.
  Future<void> _showWorkspacePanes(
    SavedHost host,
    HomeBoardWorkspace workspace,
  ) async {
    final pane = await showModalBottomSheet<HomeBoardPane>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(herdrIcon, color: herdrGreen),
                title: Text(
                  workspace.label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text('Open the workspace at an agent'),
              ),
              const Divider(height: 1),
              for (final pane in workspace.panes)
                ListTile(
                  key: ValueKey('pane-${pane.agent.pane ?? pane.agent.id}'),
                  title: Text(
                    pane.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    [
                      if (pane.tabLabel.isNotEmpty) pane.tabLabel,
                      pane.agent.kind,
                    ].join(' › '),
                  ),
                  trailing: AgentStateChip(state: pane.agent.state),
                  onTap: () => Navigator.of(context).pop(pane),
                ),
            ],
          ),
        ),
      ),
    );
    if (pane == null || !mounted) return;
    await _openPane(host, workspace, pane);
  }

  Future<void> _openSettings(SavedHost? host) async {
    final choice = await showHomeSettingsSheet(
      context,
      machineName: host?.name,
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case HomeSettingsChoice.appearance:
        await showThemeSheet(
          context: context,
          controller: widget.themeController,
          backupService: widget.backupService,
        );
      case HomeSettingsChoice.trustedKeys:
        await _openTrustedKeys();
      case HomeSettingsChoice.agentHooks:
        if (host != null) await showCompanionSetup(context, host);
      case HomeSettingsChoice.lock:
        await _lock();
    }
  }

  static Set<String> _attachedWorkspaceIds(
    List<TerminalSessionController> sessions,
  ) {
    final ids = <String>{};
    for (final session in sessions) {
      final target = ConnectTarget.fromSessionHostId(session.host.id);
      if (target != null && target.kind == ConnectTargetKind.herdr) {
        ids.add(target.name);
      }
    }
    return ids;
  }

  int _otherAttentionCount(SavedHost selected) {
    var count = 0;
    for (final host in widget.agentAttention.monitoredHosts) {
      if (baseHostId(host.id) == selected.id) continue;
      final agents = widget.agentAttention.statusFor(host.id)?.agents;
      if (agents == null) continue;
      count += agents.where((agent) => agent.state.needsAttention).length;
    }
    return count;
  }

  Widget _buildMore(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasHosts = widget.hostsController.hosts.isNotEmpty;
    final expanded = _moreExpanded ?? !hasHosts;
    final showLocalShell = widget.themeController.showLocalShell;
    final activeInstanceIds = widget.workspaceController.sessions
        .map((session) => localShellInstanceIdFromHostId(session.host.id))
        .whereType<String>()
        .toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18),
          child: Divider(height: 24),
        ),
        InkWell(
          onTap: () => setState(() => _moreExpanded = !expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 12, 6),
            child: Row(
              children: [
                Text(
                  'MORE',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    showLocalShell
                        ? 'Local shell and counters'
                        : 'Machine and session counters',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: HomeStats(
              hostCount: widget.hostsController.hosts.length,
              activeSessionCount: widget.workspaceController.sessions.length,
              onOpenSessions: widget.workspaceController.hasSessions
                  ? _openTerminalWorkspace
                  : null,
            ),
          ),
          if (showLocalShell)
            LocalShellSection(
              controller: widget.localShellController,
              activeInstanceIds: activeInstanceIds,
              onAdd: _openLocalShellSetup,
              onOpenInstance: _openLocalSession,
              onManageInstance: _openLocalShellInstance,
            ),
        ],
      ],
    );
  }

  Future<void> _switchMachine() async {
    final result = await showMachinePicker(
      context: context,
      hostsController: widget.hostsController,
      selectedHostId: _selectedHost?.id,
      liveHostIds: {
        for (final session in widget.workspaceController.sessions)
          baseHostId(session.host.id),
      },
    );
    if (!mounted || result == null) return;
    switch (result) {
      case MachinePicked(:final host):
        setState(() => _selectedHostId = host.id);
        _syncSelection();
      case MachineAddRequested():
        await _openForm();
      case MachineActionRequested(:final host, :final action):
        await _handleHostAction(action, host);
    }
  }

  Future<void> _handleMenu(MachineMenuChoice choice, SavedHost host) async {
    if (choice == MachineMenuChoice.agentHooks) {
      await showCompanionSetup(context, host);
      return;
    }
    final action = choice.hostAction;
    if (action == null) {
      await _openForm();
      return;
    }
    await _handleHostAction(action, host);
  }

  /// Opens (or activates) the Herdr session for [workspace] and focuses
  /// [pane] in it (or the whole workspace when [pane] is null).
  Future<void> _openPane(
    SavedHost host,
    HomeBoardWorkspace workspace,
    HomeBoardPane? pane,
  ) async {
    final flow = widget.connectFlow;
    if (flow != null) {
      // Lands on the exact workspace, tab and pane: reuses (and if needed
      // reconnects) an open Herdr tab, or attaches a new one focused there.
      await flow.openAgentLocation(
        host,
        workspaceId: workspace.id,
        tabId: pane?.agent.tab ?? '',
        paneId: pane?.agent.pane ?? '',
        label: workspace.label,
      );
      if (!mounted) return;
      await _openTerminalWorkspace();
      return;
    }
    final board = _board;
    final existing = _herdrSessionFor(host, workspace.id);
    if (existing != null) {
      widget.workspaceController.activate(existing);
      if (board != null) {
        if (pane != null) {
          unawaited(board.focusPane(pane.agent));
        } else {
          unawaited(board.focusWorkspace(workspace.id));
        }
      }
      await _openTerminalWorkspace();
      return;
    }
    if (pane != null && board != null) {
      // Focus over the socket before attaching, and once more after the
      // new client is up (its startup focuses the workspace).
      await board.focusPane(pane.agent);
      _refocusTimer?.cancel();
      _refocusTimer = Timer(widget.paneRefocusDelay, () {
        unawaited(board.focusPane(pane.agent));
      });
    }
    await _openTarget(
      host,
      ConnectTarget.herdr(workspaceId: workspace.id, label: workspace.label),
    );
  }

  /// An open Herdr session on [host], preferring one attached to
  /// [workspaceId].
  TerminalSessionController? _herdrSessionFor(
    SavedHost host,
    String workspaceId,
  ) {
    TerminalSessionController? anyHerdr;
    for (final session in _sessionsFor(host)) {
      final target = ConnectTarget.fromSessionHostId(session.host.id);
      if (target == null || target.kind != ConnectTargetKind.herdr) continue;
      if (target.name == workspaceId) return session;
      anyHerdr ??= session;
    }
    return anyHerdr;
  }

  Future<void> _openTarget(SavedHost host, ConnectTarget target) async {
    await widget.hostsController.markConnected(host);
    final flow = widget.connectFlow;
    if (flow != null) {
      flow.open(host, target);
    } else {
      widget.workspaceController.open(
        target.apply(host),
        startupCommand: target.startupCommand,
      );
    }
    if (!mounted) return;
    await _openTerminalWorkspace();
  }

  Future<void> _showSessionActions(TerminalSessionController session) async {
    final action = await showModalBottomSheet<_SessionAction>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                session.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(session.host.endpoint),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: const Text('Reconnect'),
              onTap: () => Navigator.of(context).pop(_SessionAction.reconnect),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: const Text('Rename'),
              onTap: () => Navigator.of(context).pop(_SessionAction.rename),
            ),
            ListTile(
              leading: const Icon(Icons.close_rounded),
              title: const Text('Close session'),
              onTap: () => Navigator.of(context).pop(_SessionAction.close),
            ),
          ],
        ),
      ),
    );
    switch (action) {
      case _SessionAction.reconnect:
        await session.disconnect();
        await session.connect();
      case _SessionAction.rename:
        await _renameSession(session);
      case _SessionAction.close:
        await widget.workspaceController.close(session);
      case null:
        break;
    }
  }

  Future<void> _renameSession(TerminalSessionController session) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(
        initial: session.customTitle ?? session.title,
        fallback: session.host.name,
      ),
    );
    if (name == null || !mounted) return;
    setState(() => session.rename(name));
  }

  /// A deep link (notification, widget, agent sheet) opened a session.
  void _handleTerminalRequest() {
    if (mounted && widget.workspaceController.hasSessions) {
      unawaited(_openTerminalWorkspace());
    }
  }

  Future<void> _openTerminalWorkspace() async {
    if (_terminalPageOpen) return;
    _terminalPageOpen = true;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TerminalPage(
          workspace: widget.workspaceController,
          themeController: widget.themeController,
          sftpRepository: widget.sftpRepository,
          agentAttention: widget.agentAttention,
          hostKeyVerifier: widget.hostKeyVerifier,
          connectFlow: widget.connectFlow,
        ),
      ),
    );
    _terminalPageOpen = false;
  }

  Future<void> _openLocalShellSetup() async {
    final request = await Navigator.of(context).push<LocalShellSetupRequest>(
      MaterialPageRoute(
        builder: (_) =>
            LocalShellSetupPage(controller: widget.localShellController),
      ),
    );
    if (request == null) return;
    unawaited(
      widget.localShellController.installNew(
        request.distroId,
        name: request.name,
      ),
    );
  }

  void _openLocalShellInstance(LocalShellInstance instance) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LocalShellInstancePage(
          controller: widget.localShellController,
          instanceId: instance.id,
          onOpenSession: (instance) =>
              _openLocalSession(instance, forceNew: true),
          onCloseSessions: _closeLocalSession,
        ),
      ),
    );
  }

  Future<void> _openLocalSession(
    LocalShellInstance instance, {
    bool forceNew = false,
  }) async {
    if (widget.localShellController.sharedStorageFeatureEnabled &&
        !widget.localShellController.sharedStorageAccessGranted) {
      await widget.localShellController.requestSharedStorageAccess();
      if (!widget.localShellController.sharedStorageAccessGranted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Grant file access, then open the shell again.'),
          ),
        );
        return;
      }
    }
    final existing = widget.workspaceController.sessions
        .where(
          (session) =>
              localShellInstanceIdFromHostId(session.host.id) == instance.id,
        )
        .toList();
    if (!forceNew && existing.isNotEmpty) {
      widget.workspaceController.activate(existing.first);
    } else {
      widget.workspaceController.open(
        widget.localShellController.localHost(
          instance,
          sessionNumber: existing.length + 1,
        ),
      );
    }
    unawaited(widget.localShellController.markOpened(instance.id));
    if (!mounted) return;
    await _openTerminalWorkspace();
  }

  Future<void> _closeLocalSession(String instanceId) async {
    final sessions = widget.workspaceController.sessions.where(
      (session) =>
          localShellInstanceIdFromHostId(session.host.id) == instanceId,
    );
    for (final session in List.of(sessions)) {
      await widget.workspaceController.close(session);
    }
  }

  Future<void> _openTrustedKeys() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TrustedKeysPage(
          verifier: widget.hostKeyVerifier,
          themeController: widget.themeController,
        ),
      ),
    );
  }

  Future<void> _openFiles(SavedHost host) async {
    await widget.hostsController.markConnected(host);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SftpBrowserPage(
          host: host,
          repository: widget.sftpRepository,
          fileExport: widget.fileExport,
          themeController: widget.themeController,
          bookmarksRepository: widget.sftpBookmarksRepository,
        ),
      ),
    );
  }

  Future<void> _connect(SavedHost host, {bool forcePicker = false}) async {
    final flow = widget.connectFlow;
    if (flow == null) {
      await widget.hostsController.markConnected(host);
      widget.workspaceController.open(host);
    } else {
      final session = await flow.connect(
        context,
        host,
        forcePicker: forcePicker,
      );
      if (session == null) return;
    }
    if (!mounted) return;
    await _openTerminalWorkspace();
  }

  Future<void> _lock() async {
    await widget.workspaceController.closeAll();
    widget.lockController.lock();
  }

  Future<void> _openForm([SavedHost? host]) async {
    final savedHost = await Navigator.of(context).push<SavedHost>(
      MaterialPageRoute(
        builder: (_) =>
            HostFormPage(host: host, themeController: widget.themeController),
      ),
    );
    if (savedHost != null) {
      await widget.hostsController.upsert(savedHost);
      if (host == null && mounted) {
        // A newly added machine becomes the one on screen.
        setState(() => _selectedHostId = savedHost.id);
        _syncSelection();
      }
    }
  }

  Future<void> _handleHostAction(HostAction action, SavedHost host) async {
    switch (action) {
      case HostAction.connectTo:
        await _connect(host, forcePicker: true);
      case HostAction.files:
        await _openFiles(host);
      case HostAction.edit:
        await _openForm(host);
      case HostAction.duplicate:
        await _duplicate(host);
      case HostAction.copyAddress:
        await Clipboard.setData(ClipboardData(text: host.endpoint));
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Copied ${host.endpoint}')));
      case HostAction.delete:
        await _confirmDelete(host);
    }
  }

  Future<void> _duplicate(SavedHost host) async {
    final keepSecrets = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Duplicate machine'),
        content: const Text(
          'Copy the saved password and key material into the new machine?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Without secrets'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Copy secrets'),
          ),
        ],
      ),
    );
    if (keepSecrets == null) return;
    final base = keepSecrets
        ? host
        : host.copyWith(password: '', privateKey: '', passphrase: '');
    await widget.hostsController.upsert(
      base.copyWith(
        id: const Uuid().v4(),
        name: '${host.name} Copy',
        clearLastConnectedAt: true,
      ),
    );
  }

  Future<void> _confirmDelete(SavedHost host) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete machine?'),
        content: Text('Conductore will forget “${host.name}”.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete ?? false) {
      await widget.hostsController.remove(host);
      if (_selectedHostId == host.id && mounted) {
        setState(() => _selectedHostId = null);
        _syncSelection();
      }
    }
  }
}

enum _SessionAction { reconnect, rename, close }

class _MachineSectionHeader extends StatelessWidget {
  const _MachineSectionHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Saved machines',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'SSH and Mosh connections you have saved.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, this.detail, this.trailing});

  final String label;
  final String? detail;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        HomeGridMetrics.horizontalPadding + 2,
        trailing == null ? 14 : 6,
        6,
        trailing == null ? 4 : 0,
      ),
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              color: muted,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.2,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                detail!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
          ] else
            const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial, required this.fallback});

  final String initial;
  final String fallback;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename session'),
      content: TextField(
        controller: _text,
        autofocus: true,
        decoration: InputDecoration(hintText: widget.fallback),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(''),
          child: const Text('Reset'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_text.text),
          child: const Text('Rename'),
        ),
      ],
    );
  }
}
