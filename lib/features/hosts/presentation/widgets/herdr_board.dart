import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/hosts/presentation/home_board_controller.dart';
import 'package:flutter/material.dart';

/// The home page's live board: the selected machine's Herdr workspaces and
/// the agent panes inside them, each with a status chip.
class HerdrBoard extends StatelessWidget {
  const HerdrBoard({
    required this.state,
    required this.onOpenPane,
    required this.onOpenWorkspace,
    required this.onRefresh,
    required this.onRequestLoad,
    required this.onStartHerdr,
    required this.onOpenShell,
    this.attachedWorkspaceIds = const {},
    super.key,
  });

  final HomeBoardState state;
  final void Function(HomeBoardWorkspace workspace, HomeBoardPane pane)
  onOpenPane;
  final ValueChanged<HomeBoardWorkspace> onOpenWorkspace;
  final VoidCallback onRefresh;

  /// Lists a hardware-key machine on request.
  final VoidCallback onRequestLoad;

  /// Opens a session that launches Herdr (server not running).
  final VoidCallback onStartHerdr;

  /// Opens a plain session (Herdr not installed).
  final VoidCallback onOpenShell;

  /// Workspaces this app already has a session attached to.
  final Set<String> attachedWorkspaceIds;

  @override
  Widget build(BuildContext context) {
    if (state.phase == HomeBoardPhase.idle) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BoardHeader(state: state, onRefresh: onRefresh),
          const SizedBox(height: 8),
          ..._body(context),
        ],
      ),
    );
  }

  List<Widget> _body(BuildContext context) {
    switch (state.phase) {
      case HomeBoardPhase.idle:
        return const [];
      case HomeBoardPhase.awaitingRequest:
        return [
          _NoticeCard(
            icon: Icons.usb_rounded,
            title: 'Hardware-key login',
            message:
                'Listing this machine’s Herdr panes opens a connection and '
                'asks for a key touch.',
            actionLabel: 'Show panes',
            onAction: onRequestLoad,
          ),
        ];
      case HomeBoardPhase.loading:
        return const [_LoadingCard()];
      case HomeBoardPhase.notInstalled:
        return [
          _NoticeCard(
            icon: Icons.extension_off_outlined,
            title: 'Herdr is not installed',
            message:
                state.message ??
                'Install Herdr on this machine to see its agents here.',
            actionLabel: 'Open a shell',
            onAction: onOpenShell,
          ),
        ];
      case HomeBoardPhase.notRunning:
        return [
          _NoticeCard(
            icon: Icons.pause_circle_outline_rounded,
            title: 'Herdr is not running',
            message: 'Start Herdr to run agents on this machine.',
            actionLabel: 'Start Herdr',
            onAction: onStartHerdr,
          ),
        ];
      case HomeBoardPhase.failed:
        if (state.workspaces.isEmpty) {
          return [
            _NoticeCard(
              icon: Icons.cloud_off_rounded,
              title: 'Could not list panes',
              message: state.message ?? 'The machine did not answer.',
              actionLabel: 'Retry',
              onAction: onRefresh,
            ),
          ];
        }
        return [
          _StaleBanner(message: state.message ?? 'The last refresh failed.'),
          const SizedBox(height: 8),
          ..._workspaces(),
        ];
      case HomeBoardPhase.ready:
        if (state.workspaces.isEmpty) {
          return [
            _NoticeCard(
              icon: Icons.space_dashboard_outlined,
              title: 'No Herdr workspaces',
              message: 'Herdr is running but has no workspaces yet.',
              actionLabel: 'Open Herdr',
              onAction: onStartHerdr,
            ),
          ];
        }
        return _workspaces();
    }
  }

  List<Widget> _workspaces() {
    return [
      for (final workspace in state.workspaces) ...[
        _WorkspaceCard(
          workspace: workspace,
          attached: attachedWorkspaceIds.contains(workspace.id),
          onOpen: () => onOpenWorkspace(workspace),
          onOpenPane: (pane) => onOpenPane(workspace, pane),
        ),
        const SizedBox(height: 10),
      ],
    ];
  }
}

class _BoardHeader extends StatelessWidget {
  const _BoardHeader({required this.state, required this.onRefresh});

  final HomeBoardState state;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final attention = state.attentionCount;
    final subtitle = switch (state.phase) {
      HomeBoardPhase.ready || HomeBoardPhase.failed =>
        state.paneCount == 1
            ? '1 agent pane'
            : '${state.paneCount} agent panes',
      _ => null,
    };
    return Row(
      children: [
        Text(
          'HERDR',
          style: theme.textTheme.labelLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            subtitle ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (attention > 0) ...[
          const SizedBox(width: 8),
          AgentStateChip(
            state: AgentAttentionState.needsInput,
            label: '$attention waiting',
          ),
        ],
        SizedBox(
          width: 36,
          height: 36,
          child: state.refreshing || state.phase == HomeBoardPhase.loading
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  tooltip: 'Refresh panes',
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
        ),
      ],
    );
  }
}

class _WorkspaceCard extends StatelessWidget {
  const _WorkspaceCard({
    required this.workspace,
    required this.attached,
    required this.onOpen,
    required this.onOpenPane,
  });

  final HomeBoardWorkspace workspace;
  final bool attached;
  final VoidCallback onOpen;
  final ValueChanged<HomeBoardPane> onOpenPane;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final summary = workspace.summary;
    final focused = workspace.workspace.focused;
    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: summary?.needsAttention ?? false
              ? _stateColor(context, summary!).withValues(alpha: 0.6)
              : colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              child: Row(
                children: [
                  Icon(
                    Icons.space_dashboard_rounded,
                    size: 16,
                    color: focused
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      workspace.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (attached) ...[
                    const _Tag(label: 'Open'),
                    const SizedBox(width: 6),
                  ],
                  if (workspace.panes.isEmpty && summary != null)
                    AgentStateChip(state: summary),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          for (final pane in workspace.panes) ...[
            Divider(height: 1, color: colorScheme.outlineVariant),
            _PaneRow(pane: pane, onTap: () => onOpenPane(pane)),
          ],
        ],
      ),
    );
  }
}

class _PaneRow extends StatelessWidget {
  const _PaneRow({required this.pane, required this.onTap});

  final HomeBoardPane pane;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final agent = pane.agent;
    final path = [
      if (pane.tabLabel.isNotEmpty) pane.tabLabel,
      if (agent.kind.isNotEmpty) agent.kind,
    ].join(' › ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 9, 12, 9),
        child: Row(
          children: [
            _KindAvatar(kind: agent.kind, state: agent.state),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pane.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (path.isNotEmpty)
                    Text(
                      path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AgentStateChip(state: agent.state),
          ],
        ),
      ),
    );
  }
}

class _KindAvatar extends StatelessWidget {
  const _KindAvatar({required this.kind, required this.state});

  final String kind;
  final AgentAttentionState state;

  @override
  Widget build(BuildContext context) {
    final color = _stateColor(context, state);
    final letter = kind.isEmpty ? '?' : kind.characters.first.toUpperCase();
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// Status chip for one agent: working, needs input, done, idle.
class AgentStateChip extends StatelessWidget {
  const AgentStateChip({required this.state, this.label, super.key});

  final AgentAttentionState state;

  /// Overrides the state's label.
  final String? label;

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
    final color = _stateColor(context, state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
          const SizedBox(width: 5),
          Text(
            label ?? labelFor(state),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

Color _stateColor(BuildContext context, AgentAttentionState state) {
  final colorScheme = Theme.of(context).colorScheme;
  return switch (state) {
    AgentAttentionState.needsInput ||
    AgentAttentionState.blocked => const Color(0xFFF59E0B),
    AgentAttentionState.working => colorScheme.primary,
    AgentAttentionState.finished => const Color(0xFF22C55E),
    AgentAttentionState.idle ||
    AgentAttentionState.unknown => colorScheme.onSurfaceVariant,
  };
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colorScheme.primary,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(
            'Looking for Herdr panes…',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.cloud_off_rounded, size: 14, color: colorScheme.error),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Showing the last known state. $message',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colorScheme.error),
          ),
        ),
      ],
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
