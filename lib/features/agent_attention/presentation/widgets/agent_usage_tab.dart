import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/agent_attention/domain/agent_inbox.dart';
import 'package:conduit/features/agent_attention/presentation/widgets/agent_inbox_widgets.dart';
import 'package:flutter/material.dart';

/// The panel's Usage tab, as a list of children for the panel's scroll
/// view: per host, the account rate-limit windows the newest report
/// carries, then every agent's context window as a ring, or
/// "Not reported" when the provider has no usage for it. [hostNotice]
/// adds a line under a host's name (the update-for-usage hint).
List<Widget> buildAgentUsageChildren(
  BuildContext context,
  List<AgentInboxHostInput> hosts, {
  DateTime? now,
  Widget Function(String hostId)? hostNotice,
}) {
  final theme = Theme.of(context);
  final anyAgents = hosts.any((host) => host.agents.isNotEmpty);
  if (!anyAgents) {
    return [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(
          'No agents are running on the monitored machines.',
          style: theme.textTheme.bodyMedium,
        ),
      ),
    ];
  }
  final anyReported = hosts.any(
    (host) => host.agents.any((agent) => agent.usage != null),
  );
  return [
    if (!anyReported)
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          'Context and rate-limit usage comes from the Conductore companion '
          "when it reads Claude Code's status line. This machine does not "
          'report it yet.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    for (final host in hosts)
      if (host.agents.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Text(host.hostName, style: theme.textTheme.titleSmall),
        ),
        ?hostNotice?.call(host.hostId),
        if (_newestLimits(host.agents) case final limits?)
          for (final limit in limits) _RateLimitBar(limit: limit, now: now),
        for (final agent in host.agents)
          _AgentUsageTile(
            key: ValueKey('usage-${host.hostId}/${agent.id}'),
            agent: agent,
          ),
      ],
  ];
}

/// Rate limits are per account, so show the newest report on the host
/// rather than one copy per agent.
List<AgentRateLimit>? _newestLimits(List<AgentInfo> agents) {
  AgentInfo? newest;
  for (final agent in agents) {
    if (agent.usage?.limits.isNotEmpty != true) {
      continue;
    }
    final at = agent.stateChangedAt;
    final best = newest?.stateChangedAt;
    if (newest == null || (at != null && (best == null || at.isAfter(best)))) {
      newest = agent;
    }
  }
  return newest?.usage?.limits;
}

class _RateLimitBar extends StatelessWidget {
  const _RateLimitBar({required this.limit, this.now});

  final AgentRateLimit limit;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final resetsAt = limit.resetsAt;
    final resets = resetsAt == null ? null : _resetsIn(resetsAt);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${limit.label} limit',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              Text(
                '${limit.usedPct.round()}%'
                '${resets == null ? '' : ' · $resets'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (limit.usedPct / 100).clamp(0, 1).toDouble(),
              minHeight: 6,
              color: ContextRing.colorFor(limit.usedPct, scheme),
              backgroundColor: scheme.outlineVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _resetsIn(DateTime resetsAt) {
    final delta = resetsAt.toUtc().difference((now ?? DateTime.now()).toUtc());
    if (delta.isNegative) {
      return 'reset';
    }
    if (delta.inHours >= 24) {
      return 'resets in ${delta.inDays}d';
    }
    if (delta.inMinutes >= 60) {
      return 'resets in ${delta.inHours}h';
    }
    return 'resets in ${delta.inMinutes}m';
  }
}

class _AgentUsageTile extends StatelessWidget {
  const _AgentUsageTile({required this.agent, super.key});

  final AgentInfo agent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final usage = agent.usage;
    final pct = usage?.contextUsedPct;
    final tokens = usage?.contextTokens;
    final window = usage?.windowLabel;
    final detail = pct == null && tokens == null
        ? 'Not reported'
        : [
            if (tokens != null) '${compactTokens(tokens)} tokens',
            if (window != null) 'of $window',
          ].join(' ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          AgentKindBadge(kind: agent.kind, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  agent.projectLabel ?? agent.name,
                  style: theme.textTheme.bodyLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (pct != null)
            ContextRing(percent: pct, size: 40, showLabel: true)
          else
            SizedBox.square(
              dimension: 40,
              child: Icon(
                Icons.data_usage_rounded,
                color: scheme.outlineVariant,
              ),
            ),
        ],
      ),
    );
  }
}
