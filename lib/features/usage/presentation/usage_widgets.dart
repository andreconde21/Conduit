import 'dart:math' as math;

import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/features/usage/domain/usage_report.dart';
import 'package:conduit/features/usage/domain/usage_summary.dart';
import 'package:conduit/features/usage/presentation/usage_controller.dart';
import 'package:flutter/material.dart';

/// Makes the app's [UsageController] reachable from any route (the home
/// bar, the Agents panel, Settings, the desktop shell).
class UsageScope extends InheritedWidget {
  const UsageScope({required this.controller, required super.child, super.key});

  final UsageController controller;

  static UsageController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<UsageScope>()?.controller;

  @override
  bool updateShouldNotify(UsageScope oldWidget) =>
      controller != oldWidget.controller;
}

/// The colour of a limit at [percent]: the theme's accent, its yellow from
/// 80 %, its red from 95 % (flat Omarchy colours).
Color usageColor(double percent, AppPalette palette) =>
    switch (usageLevelFor(percent)) {
      UsageLevel.normal => palette.accent,
      UsageLevel.warning => palette.warning,
      UsageLevel.critical => palette.danger,
    };

/// A limit window as a ring: the share used, coloured by [usageColor],
/// the percentage inside. A null [percent] draws an empty track ("not
/// reported").
class UsageRing extends StatelessWidget {
  const UsageRing({
    required this.percent,
    this.size = 34,
    this.showPercent = true,
    this.semanticLabel,
    super.key,
  });

  final double? percent;
  final double size;
  final bool showPercent;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final value = percent?.clamp(0, 100).toDouble();
    final stroke = math.max(2.5, size / 9);
    return Semantics(
      label: semanticLabel,
      value: value == null ? 'not reported' : '${value.round()} percent',
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _UsageRingPainter(
            fraction: (value ?? 0) / 100,
            color: usageColor(value ?? 0, palette),
            track: palette.hairline,
            stroke: stroke,
          ),
          child: showPercent && size >= 26
              ? Center(
                  child: Text(
                    value == null ? '–' : '${value.round()}',
                    style: TextStyle(
                      fontSize: size * 0.3,
                      fontWeight: FontWeight.w700,
                      color: palette.foreground,
                      height: 1,
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

class _UsageRingPainter extends CustomPainter {
  const _UsageRingPainter({
    required this.fraction,
    required this.color,
    required this.track,
    required this.stroke,
  });

  final double fraction;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    if (fraction <= 0) {
      return;
    }
    // Flat: square caps, no gradient.
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * fraction.clamp(0, 1),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_UsageRingPainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.track != track ||
      old.stroke != stroke;
}

/// Keeps [controller] polling while this widget is mounted.
mixin UsageViewAttachment<T extends StatefulWidget> on State<T> {
  UsageController get usageController;
  VoidCallback? _detach;

  @override
  void initState() {
    super.initState();
    _detach = usageController.attachView();
  }

  @override
  void dispose() {
    _detach?.call();
    super.dispose();
  }
}

/// How [UsageSummaryView] lays itself out.
enum UsageSummaryLayout {
  /// Rings of 34 px with labels, today's tokens and cost beside them: the
  /// phone home bar, a desktop dashboard card.
  bar,

  /// One line of small rings and today's cost: a sidebar footer.
  compact,
}

/// Claude's 5-hour and weekly limit rings and today's tokens and estimated
/// cost across every machine. Drop-in: give it the app's controller
/// ([UsageScope.maybeOf]); it keeps usage fresh while it is on screen.
class UsageSummaryView extends StatefulWidget {
  const UsageSummaryView({
    required this.controller,
    this.layout = UsageSummaryLayout.bar,
    this.onTap,
    this.now,
    super.key,
  });

  final UsageController controller;
  final UsageSummaryLayout layout;
  final VoidCallback? onTap;

  /// For tests.
  final DateTime? now;

  @override
  State<UsageSummaryView> createState() => _UsageSummaryViewState();
}

class _UsageSummaryViewState extends State<UsageSummaryView>
    with UsageViewAttachment {
  @override
  UsageController get usageController => widget.controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final summary = widget.controller.summary;
        final now = widget.now ?? DateTime.now();
        final content = switch (widget.layout) {
          UsageSummaryLayout.bar => _SummaryBar(
            summary: summary,
            now: now,
            loading: widget.controller.isLoading,
          ),
          UsageSummaryLayout.compact => _SummaryCompact(
            summary: summary,
            now: now,
          ),
        };
        final onTap = widget.onTap;
        if (onTap == null) {
          return content;
        }
        return InkWell(onTap: onTap, child: content);
      },
    );
  }
}

class _LabeledRing extends StatelessWidget {
  const _LabeledRing({
    required this.label,
    required this.limit,
    required this.now,
  });

  final String label;
  final UsageLimit? limit;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final limit = this.limit;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        UsageRing(
          key: ValueKey('usage-ring-$label'),
          percent: limit?.effectivePct(now),
          semanticLabel: '$label limit',
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: palette.mutedForeground,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({
    required this.summary,
    required this.now,
    required this.loading,
  });

  final UsageSummary summary;
  final DateTime now;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final today = summary.today;
    final hasReport = summary.machines.any((m) => m.report != null);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _LabeledRing(label: '5h', limit: summary.fiveHour, now: now),
          const SizedBox(width: 10),
          _LabeledRing(label: 'Week', limit: summary.weekly, now: now),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Today',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: palette.mutedForeground,
                  ),
                ),
                Text(
                  hasReport
                      ? '${formatUsageTokens(today.tokens)} tokens · '
                            '${formatUsageCost(today.costUsd)}'
                      : loading
                      ? 'Counting…'
                      : 'No usage reported',
                  key: const ValueKey('usage-today'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (hasReport)
                  Text(
                    'API-price estimate',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: palette.subtleForeground,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCompact extends StatelessWidget {
  const _SummaryCompact({required this.summary, required this.now});

  final UsageSummary summary;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final five = summary.fiveHour?.effectivePct(now);
    final week = summary.weekly?.effectivePct(now);
    final hasReport = summary.machines.any((m) => m.report != null);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Tooltip(
            message: five == null
                ? '5-hour limit: not reported'
                : '5-hour limit: ${five.round()}%',
            child: UsageRing(
              percent: five,
              size: 20,
              showPercent: false,
              semanticLabel: '5h limit',
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: week == null
                ? 'Weekly limit: not reported'
                : 'Weekly limit: ${week.round()}%',
            child: UsageRing(
              percent: week,
              size: 20,
              showPercent: false,
              semanticLabel: 'Weekly limit',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              [
                if (five != null) '${five.round()}%',
                if (hasReport)
                  '${formatUsageCost(summary.today.costUsd)} today',
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: palette.mutedForeground),
            ),
          ),
        ],
      ),
    );
  }
}

/// The slim bar at the top of the phone's home screen: limit rings and
/// today's tokens and cost, collapsible to one line. Tapping it opens the
/// breakdown. Hidden while no machine is asked for usage.
class UsageHomeBar extends StatelessWidget {
  const UsageHomeBar({required this.controller, this.now, super.key});

  final UsageController controller;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final summary = controller.summary;
        if (summary.machines.isEmpty) {
          return const SizedBox.shrink();
        }
        final palette = AppPalette.of(context);
        final collapsed = controller.preferences.barCollapsed;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
          child: Material(
            key: const ValueKey('usage-home-bar'),
            color: palette.panel,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: palette.hairline),
              borderRadius: BorderRadius.circular(4),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                Expanded(
                  child: collapsed
                      ? _CollapsedBar(controller: controller, now: now)
                      : UsageSummaryView(
                          controller: controller,
                          now: now,
                          onTap: () => showUsageSheet(context, controller),
                        ),
                ),
                IconButton(
                  key: const ValueKey('usage-bar-toggle'),
                  tooltip: collapsed ? 'Show usage' : 'Hide usage details',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    collapsed
                        ? Icons.expand_more_rounded
                        : Icons.expand_less_rounded,
                    color: palette.mutedForeground,
                  ),
                  onPressed: () => controller.setBarCollapsed(!collapsed),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CollapsedBar extends StatefulWidget {
  const _CollapsedBar({required this.controller, this.now});

  final UsageController controller;
  final DateTime? now;

  @override
  State<_CollapsedBar> createState() => _CollapsedBarState();
}

class _CollapsedBarState extends State<_CollapsedBar> with UsageViewAttachment {
  @override
  UsageController get usageController => widget.controller;

  @override
  Widget build(BuildContext context) {
    final summary = widget.controller.summary;
    final now = widget.now ?? DateTime.now();
    final palette = AppPalette.of(context);
    final five = summary.fiveHour?.effectivePct(now);
    final week = summary.weekly?.effectivePct(now);
    final hasReport = summary.machines.any((m) => m.report != null);
    final text = [
      '5h ${five == null ? '–' : '${five.round()}%'}',
      'wk ${week == null ? '–' : '${week.round()}%'}',
      if (hasReport) '${formatUsageCost(summary.today.costUsd)} today',
    ].join(' · ');
    return InkWell(
      onTap: () => showUsageSheet(context, widget.controller),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            UsageRing(percent: five, size: 16, showPercent: false),
            const SizedBox(width: 4),
            UsageRing(percent: week, size: 16, showPercent: false),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                key: const ValueKey('usage-collapsed-text'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: palette.foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The usage breakdown in its own sheet (from the home bar).
Future<void> showUsageSheet(BuildContext context, UsageController controller) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text('Usage', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          UsageBreakdown(controller: controller),
        ],
      ),
    ),
  );
}

/// The Usage tab's numbers: limits per machine, tokens and estimated cost
/// per day (bar chart) and by machine, project, model or agent, Codex
/// included when a machine has it.
class UsageBreakdown extends StatefulWidget {
  const UsageBreakdown({
    required this.controller,
    this.now,
    this.onUpdateCompanion,
    super.key,
  });

  final UsageController controller;
  final DateTime? now;

  /// Opens the agent hooks screen for a machine whose companion is too
  /// old; the note has no button without it.
  final void Function(String hostId)? onUpdateCompanion;

  @override
  State<UsageBreakdown> createState() => _UsageBreakdownState();
}

class _UsageBreakdownState extends State<UsageBreakdown>
    with UsageViewAttachment {
  UsageGrouping _grouping = UsageGrouping.project;

  @override
  UsageController get usageController => widget.controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final controller = widget.controller;
    final summary = controller.summary;
    final now = widget.now ?? DateTime.now();
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: palette.mutedForeground,
    );
    if (summary.machines.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Usage comes from the Conductore companion (0.6 or newer) on '
          'machines monitored through it.',
          style: muted,
        ),
      );
    }
    final range = summary.range;
    final days = summary.days();
    final groups = summary.groupBy(_grouping);
    final hasReport = summary.machines.any((m) => m.report != null);
    final fetching = summary.machines.any(
      (m) => controller.isFetching(m.hostId),
    );
    return Column(
      key: const ValueKey('usage-breakdown'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                hasReport
                    ? 'Last ${days.isEmpty ? 7 : days.length} days: '
                          '${formatUsageTokens(range.tokens)} tokens · '
                          '${formatUsageCost(range.costUsd)}'
                    : controller.isLoading
                    ? 'Counting…'
                    : 'No token counts yet',
                style: theme.textTheme.titleSmall,
              ),
            ),
            if (fetching)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                tooltip: 'Refresh usage',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                onPressed: controller.refresh,
              ),
          ],
        ),
        for (final machine in summary.machines) ...[
          const SizedBox(height: 8),
          _MachineLimits(
            machine: machine,
            now: now,
            showName:
                summary.machines.length > 1 ||
                machine.needsUpdate ||
                machine.error != null,
            onUpdateCompanion: widget.onUpdateCompanion,
          ),
        ],
        if (hasReport) ...[
          const SizedBox(height: 14),
          Text('Per day', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          UsageDayChart(days: days),
          const SizedBox(height: 14),
          SegmentedButton<UsageGrouping>(
            key: const ValueKey('usage-grouping'),
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              for (final grouping in UsageGrouping.values)
                ButtonSegment(value: grouping, label: Text(grouping.label)),
            ],
            selected: {_grouping},
            onSelectionChanged: (value) =>
                setState(() => _grouping = value.first),
          ),
          const SizedBox(height: 8),
          if (groups.isEmpty)
            Text('Nothing in this period.', style: muted)
          else
            for (final group in groups.take(12))
              _GroupRow(group: group, max: groups.first.totals),
          const SizedBox(height: 10),
          Text(
            'Costs are estimates at public API list prices'
            '${summary.pricingAsOf == null ? '' : ' (${summary.pricingAsOf})'}. '
            'On a subscription plan this is the API-equivalent cost, not '
            'what you pay.',
            style: muted,
          ),
        ],
      ],
    );
  }
}

class _MachineLimits extends StatelessWidget {
  const _MachineLimits({
    required this.machine,
    required this.now,
    required this.showName,
    this.onUpdateCompanion,
  });

  final MachineUsage machine;
  final DateTime now;
  final bool showName;
  final void Function(String hostId)? onUpdateCompanion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: palette.mutedForeground,
    );
    final report = machine.report;
    final codexPresent = report?.codex.present ?? false;
    return Column(
      key: ValueKey('usage-machine-${machine.hostId}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showName)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(machine.hostName, style: theme.textTheme.labelLarge),
          ),
        if (machine.needsUpdate)
          Row(
            children: [
              Expanded(
                child: Text(
                  'The companion on this machine does not report usage '
                  'yet (it needs 0.6.0).',
                  style: muted,
                ),
              ),
              if (onUpdateCompanion case final update?)
                TextButton(
                  onPressed: () => update(machine.hostId),
                  child: const Text('Update agent hooks'),
                ),
            ],
          )
        else if (machine.error != null && report == null)
          Text('Could not read usage: ${machine.error}', style: muted),
        for (final limit in machine.claudeLimits)
          UsageLimitBar(agent: 'Claude', limit: limit, now: now),
        if (codexPresent)
          if (machine.codexLimits.isEmpty)
            Text('Codex: no rate limits reported yet', style: muted)
          else
            for (final limit in machine.codexLimits)
              UsageLimitBar(agent: 'Codex', limit: limit, now: now),
        if (report != null && report.partial)
          Text('Still counting older transcripts…', style: muted),
      ],
    );
  }
}

/// One limit window as a labelled bar with its reset time.
class UsageLimitBar extends StatelessWidget {
  const UsageLimitBar({
    required this.agent,
    required this.limit,
    required this.now,
    super.key,
  });

  final String agent;
  final UsageLimit limit;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final pct = limit.effectivePct(now);
    final reset = limit.resetsAt;
    final resetText = reset == null
        ? null
        : !reset.isAfter(now)
        ? 'reset'
        : 'resets ${_resetsIn(reset.difference(now))}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$agent · ${limit.title}',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              Text(
                '${pct.round()}%${resetText == null ? '' : ' · $resetText'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.mutedForeground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: pct / 100,
              minHeight: 5,
              color: usageColor(pct, palette),
              backgroundColor: palette.hairline,
            ),
          ),
        ],
      ),
    );
  }

  static String _resetsIn(Duration delta) {
    if (delta.inHours >= 24) {
      return 'in ${delta.inDays}d ${delta.inHours % 24}h';
    }
    if (delta.inMinutes >= 60) {
      return 'in ${delta.inHours}h ${delta.inMinutes % 60}m';
    }
    return 'in ${math.max(1, delta.inMinutes)}m';
  }
}

/// Tokens per day as flat bars, today last; the estimated cost under each.
class UsageDayChart extends StatelessWidget {
  const UsageDayChart({required this.days, this.height = 84, super.key});

  final List<UsageDay> days;

  /// Height of the tallest bar.
  final double height;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final max = days.fold<int>(0, (m, d) => math.max(m, d.totals.tokens));
    final label = TextStyle(
      fontSize: 10,
      height: 1.2,
      color: palette.mutedForeground,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final (index, day) in days.indexed)
          Expanded(
            child: Tooltip(
              message:
                  '${day.date}: ${formatUsageTokens(day.totals.tokens)} '
                  'tokens · ${formatUsageCost(day.totals.costUsd)}',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: height,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          key: ValueKey('usage-day-${day.date}'),
                          height: max == 0 || day.totals.tokens == 0
                              ? 0
                              : math.max(2, height * day.totals.tokens / max),
                          color: index == days.length - 1
                              ? palette.accent
                              : palette.accent.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(_weekday(day.date), style: label, maxLines: 1),
                    Text(
                      day.totals.costUsd == null || day.totals.tokens == 0
                          ? ''
                          : formatUsageCost(day.totals.costUsd),
                      style: label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _weekday(String date) {
    final parsed = DateTime.tryParse(date);
    return parsed == null ? '' : _weekdays[parsed.weekday - 1];
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group, required this.max});

  final UsageGroup group;
  final UsageTotals max;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final share = max.costUsd != null && max.costUsd! > 0
        ? (group.totals.costUsd ?? 0) / max.costUsd!
        : max.tokens == 0
        ? 0.0
        : group.totals.tokens / max.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  group.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              Text(
                '${formatUsageTokens(group.totals.tokens)} · '
                '${formatUsageCost(group.totals.costUsd)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.mutedForeground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: share.clamp(0.0, 1.0),
              child: Container(
                height: 4,
                color: palette.accent.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
