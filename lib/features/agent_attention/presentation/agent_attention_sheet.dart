import 'dart:async';

import 'package:conduit/core/presentation/system_navigation_insets.dart';
import 'package:conduit/core/theme/app_theme.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_controller.dart';
import 'package:conduit/features/companion_setup/presentation/companion_status_chip.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Called when the user taps an agent: navigate to the host's terminal tab
/// (and optionally send the provider's focus command first).
typedef AgentAttentionNavigate = void Function(SavedHost host, AgentInfo agent);

/// Shows the Agent Attention dashboard: every monitored host with its
/// agents, their states, and useful empty/error/unavailable states.
Future<void> showAgentAttentionSheet({
  required BuildContext context,
  required AgentAttentionController controller,
  required AgentAttentionNavigate onOpenAgent,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemUiOverlayStyle(Theme.of(context).brightness),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        builder: (context, scrollController) => AgentAttentionSheet(
          controller: controller,
          scrollController: scrollController,
          onOpenAgent: onOpenAgent,
        ),
      ),
    ),
  );
}

class AgentAttentionSheet extends StatelessWidget {
  const AgentAttentionSheet({
    required this.controller,
    required this.onOpenAgent,
    this.scrollController,
    super.key,
  });

  final AgentAttentionController controller;
  final AgentAttentionNavigate onOpenAgent;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The sheet itself extends under the system navigation bar; keep the
    // last row above three-button navigation (Samsung One UI reports
    // gesture insets there too, see shouldApplyBottomSafeArea).
    final bottomInset = shouldApplyBottomSafeArea(context)
        ? MediaQuery.viewPaddingOf(context).bottom
        : 0.0;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final hosts = controller.monitoredHosts;
        return ListView(
          controller: scrollController,
          padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + bottomInset),
          children: [
            Text('Agents', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (hosts.isEmpty)
              const _EmptyState(
                icon: Icons.monitor_heart_outlined,
                message:
                    'No machines are being monitored. Enable agent '
                    "monitoring in a machine's settings, then connect "
                    'to it.',
              )
            else
              for (final host in hosts)
                _HostSection(
                  host: host,
                  providerLabel: controller.providerFor(host.id).label,
                  status:
                      controller.statusFor(host.id) ??
                      const AgentHostStatus(loading: true),
                  onRefresh: () => controller.refresh(host.id),
                  onOpenAgent: (agent) => onOpenAgent(host, agent),
                  isDeciding: controller.isDeciding,
                  onDecide: (request, verdict) =>
                      _decide(context, host, request, verdict),
                ),
          ],
        );
      },
    );
  }

  Future<void> _decide(
    BuildContext context,
    SavedHost host,
    PendingPermissionRequest request,
    PermissionVerdict verdict,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await controller.decide(host.id, request, verdict);
    } catch (error) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            'Could not ${verdict.label.toLowerCase()} ${request.toolName}: '
            '$error',
          ),
        ),
      );
    }
  }
}

typedef _DecideCallback =
    void Function(PendingPermissionRequest request, PermissionVerdict verdict);

class _HostSection extends StatelessWidget {
  const _HostSection({
    required this.host,
    required this.providerLabel,
    required this.status,
    required this.onRefresh,
    required this.onOpenAgent,
    required this.isDeciding,
    required this.onDecide,
  });

  final SavedHost host;
  final String providerLabel;
  final AgentHostStatus status;
  final VoidCallback onRefresh;
  final ValueChanged<AgentInfo> onOpenAgent;
  final bool Function(String requestId) isDeciding;
  final _DecideCallback onDecide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  host.name,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(providerLabel, style: theme.textTheme.bodySmall),
              IconButton(
                tooltip: 'Refresh',
                iconSize: 18,
                icon: const Icon(Icons.refresh_rounded),
                onPressed: onRefresh,
              ),
            ],
          ),
        ),
        // Offers the Agent hooks screen while the companion is missing
        // (renders nothing once it is installed, or without a scope).
        if (status.unavailableReason != null ||
            (!status.loading && status.error == null && status.agents.isEmpty))
          CompanionInstallBanner(host: host),
        if (status.unavailableReason != null)
          _EmptyState(
            icon: Icons.extension_off_outlined,
            message: status.unavailableReason!,
          )
        else if (status.error != null)
          _EmptyState(
            icon: Icons.error_outline_rounded,
            message:
                'Could not read agent state. ${status.error!} '
                'Monitoring keeps retrying while connected.',
          )
        else if (status.loading && status.agents.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (status.agents.isEmpty)
          const _EmptyState(
            icon: Icons.check_circle_outline_rounded,
            message: 'No agents are running on this machine.',
          )
        else
          for (final agent in status.agents)
            _AgentTile(
              agent: agent,
              onTap: () => onOpenAgent(agent),
              isDeciding: isDeciding,
              onDecide: onDecide,
            ),
      ],
    );
  }
}

class _AgentTile extends StatelessWidget {
  const _AgentTile({
    required this.agent,
    required this.onTap,
    required this.isDeciding,
    required this.onDecide,
  });

  final AgentInfo agent;
  final VoidCallback onTap;
  final bool Function(String requestId) isDeciding;
  final _DecideCallback onDecide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final (icon, color) = switch (agent.state) {
      AgentAttentionState.working => (
        Icons.autorenew_rounded,
        colorScheme.primary,
      ),
      AgentAttentionState.needsInput => (
        Icons.pan_tool_alt_outlined,
        colorScheme.error,
      ),
      AgentAttentionState.blocked => (Icons.block_rounded, colorScheme.error),
      AgentAttentionState.finished => (
        Icons.check_circle_rounded,
        colorScheme.tertiary,
      ),
      AgentAttentionState.idle => (
        Icons.pause_circle_outline_rounded,
        colorScheme.onSurfaceVariant,
      ),
      AgentAttentionState.unknown => (
        Icons.help_outline_rounded,
        colorScheme.onSurfaceVariant,
      ),
    };
    final location = [
      if (agent.kind.isNotEmpty) agent.kind,
      if (agent.workspace != null) 'workspace ${agent.workspace}',
      if (agent.tab != null) 'tab ${agent.tab}',
    ].join(' · ');
    final changed = agent.stateChangedAt;
    final pending = agent.pendingRequests;
    // A permission prompt is reported as "needs input"; say what kind.
    final stateLabel = pending.isNotEmpty && agent.state.needsAttention
        ? 'Needs permission'
        : agent.state.label;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              label:
                  'Agent ${agent.name}, $stateLabel'
                  '${location.isEmpty ? '' : ', $location'}',
              button: true,
              child: ListTile(
                onTap: onTap,
                leading: Icon(icon, color: color),
                title: Text(
                  agent.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: location.isEmpty ? null : Text(location, maxLines: 1),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      stateLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (changed != null)
                      Text(
                        _relativeTime(changed),
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
            if (agent.lastMessage case final message?)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            for (final request in pending)
              _PendingRequestCard(
                request: request,
                busy: isDeciding(request.id),
                onDecide: (verdict) => onDecide(request, verdict),
              ),
          ],
        ),
      ),
    );
  }

  String _relativeTime(DateTime time) {
    final delta = DateTime.now().toUtc().difference(time.toUtc());
    if (delta.inSeconds < 60) {
      return 'just now';
    }
    if (delta.inMinutes < 60) {
      return '${delta.inMinutes}m ago';
    }
    if (delta.inHours < 24) {
      return '${delta.inHours}h ago';
    }
    return '${delta.inDays}d ago';
  }
}

/// One pending permission request: what the agent wants to run, the full
/// tool input on demand, and the three answers.
class _PendingRequestCard extends StatefulWidget {
  const _PendingRequestCard({
    required this.request,
    required this.busy,
    required this.onDecide,
  });

  final PendingPermissionRequest request;
  final bool busy;
  final ValueChanged<PermissionVerdict> onDecide;

  @override
  State<_PendingRequestCard> createState() => _PendingRequestCardState();
}

class _PendingRequestCardState extends State<_PendingRequestCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final request = widget.request;
    final hasInput = request.toolInput.trim().isNotEmpty;
    return Container(
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.25),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.shield_outlined,
                size: 18,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  request.toolName,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasInput)
                TextButton.icon(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                  ),
                  label: Text(_expanded ? 'Hide input' : 'Tool input'),
                ),
            ],
          ),
          SelectableText(
            request.summary,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
            ),
            maxLines: _expanded ? null : 3,
          ),
          if (_expanded && hasInput) ...[
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(10),
              child: SingleChildScrollView(
                child: SelectableText(
                  request.toolInput,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              for (final verdict in const [
                PermissionVerdict.deny,
                PermissionVerdict.always,
                PermissionVerdict.allow,
              ]) ...[
                if (verdict != PermissionVerdict.deny) const SizedBox(width: 8),
                Expanded(
                  child: switch (verdict) {
                    PermissionVerdict.allow => FilledButton(
                      onPressed: widget.busy
                          ? null
                          : () => widget.onDecide(verdict),
                      child: Text(verdict.label),
                    ),
                    PermissionVerdict.always => FilledButton.tonal(
                      onPressed: widget.busy
                          ? null
                          : () => widget.onDecide(verdict),
                      child: Text(verdict.label),
                    ),
                    PermissionVerdict.deny => OutlinedButton(
                      onPressed: widget.busy
                          ? null
                          : () => widget.onDecide(verdict),
                      child: Text(verdict.label),
                    ),
                  },
                ),
              ],
            ],
          ),
          if (widget.busy)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
