import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/hosts/presentation/home_board_controller.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/sessions/presentation/live_terminal_preview.dart';
import 'package:conduit/features/sessions/presentation/terminal_preview.dart';
import 'package:conduit/features/terminal/presentation/terminal_session_controller.dart';
import 'package:flutter/material.dart';

/// Herdr's colour on the home page (workspace labels, the Herdr glyph).
const herdrGreen = Color(0xFF3FB950);

/// Glyph used for Herdr across the app.
const herdrIcon = Icons.pets_rounded;

/// Sizes of the home grid for a given content width: two columns on a
/// phone (one in the large layout), more on tablets.
@immutable
class HomeGridMetrics {
  const HomeGridMetrics._({
    required this.columns,
    required this.tileWidth,
    required this.sessionExtent,
    required this.dormantExtent,
  });

  factory HomeGridMetrics.of(double width, {bool large = false}) {
    final base = width >= 900
        ? 4
        : width >= 600
        ? 3
        : 2;
    final columns = large ? (base - 1).clamp(1, 3) : base;
    final inner = width - horizontalPadding * 2;
    final tileWidth = (inner - spacing * (columns - 1)) / columns;
    return HomeGridMetrics._(
      columns: columns,
      tileWidth: tileWidth,
      // A 4:5 preview plus the title and workspace lines below it.
      sessionExtent: tileWidth * 1.25 + labelHeight,
      dormantExtent: 118,
    );
  }

  static const horizontalPadding = 16.0;
  static const spacing = 12.0;
  static const labelHeight = 52.0;

  final int columns;
  final double tileWidth;
  final double sessionExtent;
  final double dormantExtent;
}

/// Summary of one app session for its home tile.
@immutable
class HomeSessionInfo {
  const HomeSessionInfo({
    required this.target,
    required this.targetLabel,
    required this.agentState,
  });

  /// What the session is attached to (null for a plain session).
  final ConnectTarget? target;

  /// Workspace / tmux session / directory shown under the title.
  final String targetLabel;

  /// Most urgent agent state for the session, if any agent is known.
  final AgentAttentionState? agentState;

  bool get isHerdr => target?.kind == ConnectTargetKind.herdr;

  /// Builds the info for [session]. [workspaces] (the home board for the
  /// session's machine) supplies live Herdr workspace names; the name baked
  /// into the session title is the fallback.
  static HomeSessionInfo of(
    TerminalSessionController session, {
    List<HomeBoardWorkspace> workspaces = const [],
    AgentAttentionState? agentState,
  }) {
    final target = ConnectTarget.fromSessionHostId(session.host.id);
    var label = '';
    AgentAttentionState? boardState;
    if (target != null && target.kind != ConnectTargetKind.shell) {
      if (target.kind == ConnectTargetKind.herdr && target.name.isNotEmpty) {
        final live = workspaces.where((w) => w.id == target.name).firstOrNull;
        if (live != null) {
          label = live.label;
          boardState = live.summary;
        }
      }
      if (label.isEmpty) {
        final name = session.host.name;
        final cut = name.lastIndexOf(': ');
        label = cut > 0 && cut + 2 < name.length
            ? name.substring(cut + 2)
            : target.title;
      }
    }
    return HomeSessionInfo(
      target: target,
      targetLabel: label,
      agentState: agentState ?? boardState,
    );
  }
}

/// A large live tile for one open session: a scaled-down render of its
/// screen in the terminal's own colours, a status dot, the title and the
/// transport badge over the top, and the title plus Herdr workspace below.
class HomeSessionTile extends StatelessWidget {
  const HomeSessionTile({
    required this.session,
    required this.info,
    required this.palette,
    required this.brightness,
    required this.fontFamily,
    required this.onTap,
    required this.onLongPress,
    this.selected = false,
    super.key,
  });

  final TerminalSessionController session;
  final HomeSessionInfo info;
  final AppPalette palette;
  final Brightness brightness;
  final String fontFamily;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final terminalTheme = palette.terminalThemeFor(brightness);
    final foreground = palette.foregroundFor(brightness);
    final muted = palette.mutedForegroundFor(brightness);
    final preview = StyledTerminalPreview.capture(session.terminal);
    final radius = BorderRadius.circular(18);
    final state = info.agentState;
    final attention = state != null && state.needsAttention;
    return Semantics(
      button: true,
      label: '${session.title}, ${_statusLabel(session.status)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Material(
              color: terminalTheme.background,
              shape: RoundedRectangleBorder(
                borderRadius: radius,
                side: BorderSide(
                  color: attention
                      ? agentStateColor(context, state).withValues(alpha: 0.8)
                      : selected
                      ? palette.accent.withValues(alpha: 0.75)
                      : palette.hairlineFor(brightness),
                  width: attention || selected ? 1.5 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                onLongPress: onLongPress,
                child: Stack(
                  children: [
                    Positioned.fill(
                      top: 30,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                        child: LiveTerminalPreview(
                          preview: preview,
                          theme: terminalTheme,
                          fontFamily: fontFamily,
                          placeholder: _placeholderFor(session.status),
                          placeholderColor: muted,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: _TileHeader(
                        title: session.title,
                        dotColor: _dotColor(context, session.status, state),
                        background: terminalTheme.background,
                        foreground: terminalTheme.foreground,
                        badge: TransportBadge.forSession(session),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            session.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: foreground,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: 20,
            child: Row(
              children: [
                if (info.targetLabel.isNotEmpty) ...[
                  Icon(
                    _targetIcon(info.target),
                    size: 15,
                    color: info.isHerdr ? herdrGreen : muted,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      info.targetLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: info.isHerdr ? herdrGreen : muted,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ] else
                  Flexible(
                    child: Text(
                      session.host.endpoint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: muted, fontSize: 12.5),
                    ),
                  ),
                if (state != null &&
                    state != AgentAttentionState.idle &&
                    state != AgentAttentionState.unknown) ...[
                  const SizedBox(width: 6),
                  AgentStateChip(state: state, dense: true),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static IconData _targetIcon(ConnectTarget? target) => switch (target?.kind) {
    ConnectTargetKind.herdr => herdrIcon,
    ConnectTargetKind.tmux => Icons.terminal_rounded,
    ConnectTargetKind.directory => Icons.folder_outlined,
    _ => Icons.terminal_rounded,
  };

  static String _statusLabel(TerminalConnectionStatus status) =>
      switch (status) {
        TerminalConnectionStatus.idle => 'not connected',
        TerminalConnectionStatus.connecting => 'connecting',
        TerminalConnectionStatus.connected => 'connected',
        TerminalConnectionStatus.disconnected => 'disconnected',
        TerminalConnectionStatus.failed => 'connection failed',
      };

  static String? _placeholderFor(TerminalConnectionStatus status) =>
      switch (status) {
        TerminalConnectionStatus.idle => 'Not connected',
        TerminalConnectionStatus.connecting => 'Connecting…',
        TerminalConnectionStatus.connected => null,
        TerminalConnectionStatus.disconnected => 'Disconnected',
        TerminalConnectionStatus.failed => 'Connection failed',
      };

  /// Agent needing input wins; otherwise the connection state.
  static Color _dotColor(
    BuildContext context,
    TerminalConnectionStatus status,
    AgentAttentionState? state,
  ) {
    if (state != null && state.needsAttention) {
      return agentStateColor(context, state);
    }
    return switch (status) {
      TerminalConnectionStatus.connected => const Color(0xFF22C55E),
      TerminalConnectionStatus.connecting => const Color(0xFFEAB308),
      TerminalConnectionStatus.failed => Theme.of(context).colorScheme.error,
      TerminalConnectionStatus.idle ||
      TerminalConnectionStatus.disconnected => const Color(0xFF64748B),
    };
  }
}

class _TileHeader extends StatelessWidget {
  const _TileHeader({
    required this.title,
    required this.dotColor,
    required this.background,
    required this.foreground,
    required this.badge,
  });

  final String title;
  final Color dotColor;
  final Color background;
  final Color foreground;
  final Widget badge;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [background, background.withValues(alpha: 0.85)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(9, 7, 6, 5),
        child: Row(
          children: [
            Container(
              key: const ValueKey('home-tile-dot'),
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(
                  color: foreground.withValues(alpha: 0.9),
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                ),
              ),
            ),
            const SizedBox(width: 4),
            badge,
          ],
        ),
      ),
    );
  }
}

/// Pill naming how the session is carried: Mosh (teal), SSH (blue) or the
/// on-device shell.
class TransportBadge extends StatelessWidget {
  const TransportBadge({required this.label, required this.color, super.key});

  factory TransportBadge.forSession(TerminalSessionController session) {
    final host = session.host;
    if (host.isLocal) {
      return const TransportBadge(label: 'Local', color: Color(0xFF64748B));
    }
    return host.useMosh
        ? const TransportBadge(label: 'Mosh', color: moshTeal)
        : const TransportBadge(label: 'SSH', color: sshBlue);
  }

  static const moshTeal = Color(0xFF0D9488);
  static const sshBlue = Color(0xFF2563EB);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}

/// The "+" tile: opens the connect picker for the selected machine.
class HomeAddTile extends StatelessWidget {
  const HomeAddTile({
    required this.palette,
    required this.brightness,
    required this.onTap,
    this.label = 'New session',
    super.key,
  });

  final AppPalette palette;
  final Brightness brightness;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final muted = palette.mutedForegroundFor(brightness);
    final radius = BorderRadius.circular(18);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Material(
            color: palette.panelFor(brightness).withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(color: palette.borderFor(brightness)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('home-add-tile'),
              onTap: onTap,
              child: Center(
                child: Icon(Icons.add_rounded, size: 40, color: palette.accent),
              ),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: muted,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 23),
      ],
    );
  }
}

/// A Herdr workspace on the selected machine that has no session in the
/// app yet: its name, pane and tab counts, and chips for its agents.
class DormantWorkspaceTile extends StatelessWidget {
  const DormantWorkspaceTile({
    required this.workspace,
    required this.palette,
    required this.brightness,
    required this.onTap,
    this.onLongPress,
    super.key,
  });

  final HomeBoardWorkspace workspace;
  final AppPalette palette;
  final Brightness brightness;
  final VoidCallback onTap;

  /// Lists the workspace's agent panes (null when there are none).
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final foreground = palette.foregroundFor(brightness);
    final muted = palette.mutedForegroundFor(brightness);
    final counts = <AgentAttentionState, int>{};
    for (final pane in workspace.panes) {
      counts.update(pane.agent.state, (count) => count + 1, ifAbsent: () => 1);
    }
    final states = counts.keys.toList()
      ..sort((a, b) => homeBoardPriority(a).compareTo(homeBoardPriority(b)));
    final summary = workspace.summary;
    final attention = summary != null && summary.needsAttention;
    final panes = workspace.panes.length;
    final tabs = workspace.workspace.tabCount;
    final details = [
      if (panes > 0) panes == 1 ? '1 agent' : '$panes agents',
      if (tabs > 0) tabs == 1 ? '1 tab' : '$tabs tabs',
    ].join(' · ');
    return Material(
      color: palette.panelFor(brightness),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: attention
              ? agentStateColor(context, summary).withValues(alpha: 0.6)
              : palette.hairlineFor(brightness),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(herdrIcon, size: 16, color: herdrGreen),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      workspace.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(Icons.play_arrow_rounded, size: 18, color: muted),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                details.isEmpty ? 'Not open in the app' : details,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: muted, fontSize: 12),
              ),
              const Spacer(),
              SizedBox(
                height: 22,
                child: ClipRect(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      if (states.isEmpty && summary != null)
                        AgentStateChip(state: summary, dense: true),
                      for (final state in states)
                        AgentStateChip(
                          state: state,
                          dense: true,
                          label: counts[state]! > 1
                              ? '${AgentStateChip.labelFor(state)} '
                                    '×${counts[state]}'
                              : null,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the home page shows when the Herdr board cannot list workspaces.
enum HomeBoardNoticeAction {
  /// List a machine that waits for an explicit request.
  request,

  /// Try listing again.
  retry,

  /// Open a session that starts Herdr.
  startHerdr,

  /// Open a plain shell.
  openShell,
}

/// One compact notice about the board, with the action that resolves it.
@immutable
class HomeBoardNotice {
  const HomeBoardNotice({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.action,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final HomeBoardNoticeAction? action;

  /// A fetch is running (spinner instead of an icon).
  final bool busy;

  /// The notice for [state], or null when the board has workspaces to show
  /// or nothing to say (no machine, a local machine).
  static HomeBoardNotice? of(
    HomeBoardState state, {
    HomeBoardRequestReason? requestReason,
    bool hasOpenHerdrSession = false,
  }) {
    switch (state.phase) {
      case HomeBoardPhase.idle:
        return null;
      case HomeBoardPhase.awaitingRequest:
        return requestReason == HomeBoardRequestReason.hardwareKey
            ? const HomeBoardNotice(
                icon: Icons.usb_rounded,
                title: 'Hardware-key login',
                message:
                    'Listing Herdr workspaces opens a connection and asks '
                    'for a key touch.',
                actionLabel: 'List workspaces',
                action: HomeBoardNoticeAction.request,
              )
            : const HomeBoardNotice(
                icon: Icons.verified_user_outlined,
                title: 'Not connected yet',
                message:
                    'Listing Herdr workspaces connects to this machine and '
                    'may ask you to trust its host key.',
                actionLabel: 'List workspaces',
                action: HomeBoardNoticeAction.request,
              );
      case HomeBoardPhase.loading:
        return const HomeBoardNotice(
          icon: Icons.sync_rounded,
          title: 'Listing Herdr workspaces…',
          message: 'Connecting to the machine.',
          busy: true,
        );
      case HomeBoardPhase.notInstalled:
        return HomeBoardNotice(
          icon: Icons.extension_off_outlined,
          title: 'Herdr is not installed',
          message: state.message ?? 'Install Herdr to see its workspaces here.',
          actionLabel: 'Open a shell',
          action: HomeBoardNoticeAction.openShell,
        );
      case HomeBoardPhase.notRunning:
        return const HomeBoardNotice(
          icon: Icons.pause_circle_outline_rounded,
          title: 'Herdr is not running',
          message: 'Start Herdr to run agents on this machine.',
          actionLabel: 'Start Herdr',
          action: HomeBoardNoticeAction.startHerdr,
        );
      case HomeBoardPhase.failed:
        final reason = state.message ?? 'The machine did not answer.';
        return state.workspaces.isEmpty
            ? HomeBoardNotice(
                icon: Icons.cloud_off_rounded,
                title: 'Could not list Herdr workspaces',
                message: reason,
                actionLabel: 'Retry',
                action: HomeBoardNoticeAction.retry,
              )
            : HomeBoardNotice(
                icon: Icons.history_rounded,
                title: 'Showing the last list',
                message: reason,
                actionLabel: 'Retry',
                action: HomeBoardNoticeAction.retry,
              );
      case HomeBoardPhase.ready:
        if (state.workspaces.isNotEmpty || hasOpenHerdrSession) return null;
        return const HomeBoardNotice(
          icon: Icons.space_dashboard_outlined,
          title: 'No Herdr workspaces',
          message: 'Herdr is running but has no workspaces yet.',
          actionLabel: 'Open Herdr',
          action: HomeBoardNoticeAction.startHerdr,
        );
    }
  }
}

/// Full-width compact card for a [HomeBoardNotice].
class HomeBoardNoticeTile extends StatelessWidget {
  const HomeBoardNoticeTile({
    required this.notice,
    required this.palette,
    required this.brightness,
    this.onAction,
    super.key,
  });

  final HomeBoardNotice notice;
  final AppPalette palette;
  final Brightness brightness;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final foreground = palette.foregroundFor(brightness);
    final muted = palette.mutedForegroundFor(brightness);
    final label = notice.actionLabel;
    return Container(
      key: const ValueKey('home-board-notice'),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: palette.panelFor(brightness),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.hairlineFor(brightness)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: notice.busy
                ? const Padding(
                    padding: EdgeInsets.all(3),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(notice.icon, size: 20, color: herdrGreen),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notice.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  notice.message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: muted, fontSize: 12, height: 1.25),
                ),
              ],
            ),
          ),
          if (label != null && onAction != null) ...[
            const SizedBox(width: 6),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onPressed: onAction,
              child: Text(label),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small pill with an agent state (and a dot in its colour).
class AgentStateChip extends StatelessWidget {
  const AgentStateChip({
    required this.state,
    this.label,
    this.dense = false,
    super.key,
  });

  final AgentAttentionState state;

  /// Overrides the state's label.
  final String? label;

  /// Tighter padding and text for tiles.
  final bool dense;

  static String labelFor(AgentAttentionState state) => switch (state) {
    AgentAttentionState.working => 'Working',
    AgentAttentionState.needsInput => 'Needs input',
    AgentAttentionState.blocked => 'Blocked',
    AgentAttentionState.finished => 'Done',
    AgentAttentionState.idle => 'Idle',
    AgentAttentionState.unknown => 'Unknown',
  };

  @override
  Widget build(BuildContext context) {
    final color = agentStateColor(context, state);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: dense ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            label ?? labelFor(state),
            style: TextStyle(
              color: color,
              fontSize: dense ? 10.5 : 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Colour of an agent state across the home page.
Color agentStateColor(BuildContext context, AgentAttentionState? state) {
  final colorScheme = Theme.of(context).colorScheme;
  return switch (state) {
    AgentAttentionState.needsInput ||
    AgentAttentionState.blocked => const Color(0xFFF59E0B),
    AgentAttentionState.working => colorScheme.primary,
    AgentAttentionState.finished => const Color(0xFF22C55E),
    AgentAttentionState.idle ||
    AgentAttentionState.unknown ||
    null => colorScheme.onSurfaceVariant,
  };
}
