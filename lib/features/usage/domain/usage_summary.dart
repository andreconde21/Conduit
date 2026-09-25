import 'package:conduit/features/usage/domain/usage_report.dart';

/// Use of a limit at or above this is shown in the warning colour.
const kUsageWarningPct = 80.0;

/// At or above this, in the danger colour.
const kUsageCriticalPct = 95.0;

enum UsageLevel { normal, warning, critical }

/// How close [percent] is to a limit.
UsageLevel usageLevelFor(double percent) {
  if (percent >= kUsageCriticalPct) {
    return UsageLevel.critical;
  }
  if (percent >= kUsageWarningPct) {
    return UsageLevel.warning;
  }
  return UsageLevel.normal;
}

/// What the app knows about one machine's usage.
class MachineUsage {
  const MachineUsage({
    required this.hostId,
    required this.hostName,
    this.report,
    this.liveLimits = const [],
    this.error,
    this.needsUpdate = false,
    this.fetchedAt,
  });

  final String hostId;
  final String hostName;

  /// The last `usage` reply, kept while a newer one is fetched.
  final UsageReport? report;

  /// Claude limits from the agent monitor's statusline reports, often
  /// newer than [report] (it polls every 15 s, in the background too).
  final List<UsageLimit> liveLimits;

  /// The last fetch failed (the report, if any, is older).
  final String? error;

  /// The companion is missing or older than 0.6.0 (no `usage` command).
  final bool needsUpdate;
  final DateTime? fetchedAt;

  List<UsageLimit> get claudeLimits =>
      mergeUsageLimits([report?.claude.limits ?? const [], liveLimits]);

  List<UsageLimit> get codexLimits => report?.codex.limits ?? const [];

  MachineUsage copyWith({
    String? hostName,
    UsageReport? report,
    List<UsageLimit>? liveLimits,
    String? error,
    bool clearError = false,
    bool? needsUpdate,
    DateTime? fetchedAt,
  }) => MachineUsage(
    hostId: hostId,
    hostName: hostName ?? this.hostName,
    report: report ?? this.report,
    liveLimits: liveLimits ?? this.liveLimits,
    error: clearError ? null : (error ?? this.error),
    needsUpdate: needsUpdate ?? this.needsUpdate,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
}

/// How the Usage tab groups rows.
enum UsageGrouping {
  machine('Machine'),
  project('Project'),
  model('Model'),
  agent('Agent');

  const UsageGrouping(this.label);

  final String label;
}

/// One line of a grouped breakdown.
class UsageGroup {
  const UsageGroup(this.label, this.totals);

  final String label;
  final UsageTotals totals;
}

/// Totals of one day, for the bar chart.
class UsageDay {
  const UsageDay(this.date, this.totals);

  /// `YYYY-MM-DD`.
  final String date;
  final UsageTotals totals;
}

/// Usage across every machine: what the bar, the tab and the widget show.
class UsageSummary {
  const UsageSummary(this.machines);

  static const empty = UsageSummary([]);

  final List<MachineUsage> machines;

  Iterable<UsageReport> get _reports => [
    for (final machine in machines) ?machine.report,
  ];

  /// Whether any machine has answered `usage` or reported limits.
  bool get hasData =>
      machines.any((m) => m.report != null || m.liveLimits.isNotEmpty);

  /// The freshest Claude limit windows across machines.
  List<UsageLimit> get claudeLimits =>
      mergeUsageLimits([for (final m in machines) m.claudeLimits]);

  List<UsageLimit> get codexLimits =>
      mergeUsageLimits([for (final m in machines) m.codexLimits]);

  UsageLimit? get fiveHour =>
      claudeLimits.where((limit) => limit.isFiveHour).firstOrNull;

  UsageLimit? get weekly =>
      claudeLimits.where((limit) => limit.isWeekly).firstOrNull;

  bool get codexPresent => _reports.any((report) => report.codex.present);

  /// Today on each machine, every agent.
  UsageTotals get today {
    var total = UsageTotals.zero;
    for (final report in _reports) {
      total = total + report.claude.today + report.codex.today;
    }
    return total;
  }

  UsageTotals todayFor(UsageAgent agent) {
    var total = UsageTotals.zero;
    for (final report in _reports) {
      total =
          total +
          (agent == UsageAgent.claude ? report.claude : report.codex).today;
    }
    return total;
  }

  UsageTotals get range {
    var total = UsageTotals.zero;
    for (final report in _reports) {
      total = total + report.claude.range + report.codex.range;
    }
    return total;
  }

  /// Every row, with its machine's name.
  List<UsageRow> get rows => [
    for (final machine in machines)
      if (machine.report case final report?)
        for (final section in report.agents)
          for (final row in section.rows) row.withMachine(machine.hostName),
  ];

  /// Rows of [agent] (all agents when null) summed by [grouping], largest
  /// first (by cost, then tokens).
  List<UsageGroup> groupBy(UsageGrouping grouping, {UsageAgent? agent}) {
    final sums = <String, UsageTotals>{};
    for (final row in rows) {
      if (agent != null && row.agent != agent) {
        continue;
      }
      final key = switch (grouping) {
        UsageGrouping.machine => row.machine,
        UsageGrouping.project => row.project,
        UsageGrouping.model => row.model,
        UsageGrouping.agent => row.agent.label,
      };
      sums[key] = (sums[key] ?? UsageTotals.zero) + row.totals;
    }
    return [for (final e in sums.entries) UsageGroup(e.key, e.value)]..sort((
      a,
      b,
    ) {
      final byCost = (b.totals.costUsd ?? 0).compareTo(a.totals.costUsd ?? 0);
      return byCost != 0 ? byCost : b.totals.tokens.compareTo(a.totals.tokens);
    });
  }

  /// One entry per day from the earliest report's first day to the latest
  /// report's today, empty days included.
  List<UsageDay> days({UsageAgent? agent}) {
    final reports = _reports.toList();
    if (reports.isEmpty) {
      return const [];
    }
    var first = reports.first.from;
    var last = reports.first.today;
    for (final report in reports) {
      if (report.from.isNotEmpty && report.from.compareTo(first) < 0) {
        first = report.from;
      }
      if (report.today.compareTo(last) > 0) {
        last = report.today;
      }
    }
    final sums = <String, UsageTotals>{};
    for (final row in rows) {
      if (agent != null && row.agent != agent) {
        continue;
      }
      sums[row.date] = (sums[row.date] ?? UsageTotals.zero) + row.totals;
    }
    final start = DateTime.tryParse(first);
    final end = DateTime.tryParse(last);
    if (start == null || end == null) {
      return const [];
    }
    return [
      for (
        var day = DateTime.utc(start.year, start.month, start.day);
        !day.isAfter(DateTime.utc(end.year, end.month, end.day));
        day = day.add(const Duration(days: 1))
      )
        UsageDay(_date(day), sums[_date(day)] ?? UsageTotals.zero),
    ];
  }

  static String _date(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  /// The pricing note and date of the newest report.
  String? get pricingAsOf =>
      _reports.map((r) => r.pricingAsOf).nonNulls.firstOrNull;
}

/// `1.2M`, `850k`, `12`.
String formatUsageTokens(int tokens) {
  if (tokens >= 1000000000) {
    return '${_trim(tokens / 1000000000)}B';
  }
  if (tokens >= 1000000) {
    return '${_trim(tokens / 1000000)}M';
  }
  if (tokens >= 1000) {
    return '${(tokens / 1000).round()}k';
  }
  return '$tokens';
}

String _trim(double value) =>
    value >= 100 ? value.round().toString() : value.toStringAsFixed(1);

/// `$12.40`, `$0.03`, `<$0.01`, `—` without a price.
String formatUsageCost(double? usd) {
  if (usd == null) {
    return '—';
  }
  if (usd > 0 && usd < 0.01) {
    return r'<$0.01';
  }
  if (usd >= 1000) {
    return '\$${usd.round()}';
  }
  return '\$${usd.toStringAsFixed(2)}';
}
