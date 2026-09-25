import 'dart:convert';

import 'package:conduit/features/usage/domain/usage_alert.dart';
import 'package:conduit/features/usage/domain/usage_report.dart';
import 'package:conduit/features/usage/domain/usage_summary.dart';
import 'package:flutter_test/flutter_test.dart';

import 'usage_fakes.dart';

void main() {
  final resets = DateTime.utc(2026, 9, 25, 15, 30);

  group('parseUsageReport', () {
    test('reads the companion reply', () {
      final report = parseUsageReport(
        jsonEncode(
          usageReplyJson(
            limits: [
              {
                'label': '5h',
                'usedPct': 42.5,
                'resetsAt': resets.millisecondsSinceEpoch,
                'expired': false,
              },
              {'label': '7d', 'usedPct': 18, 'expired': true},
            ],
            rows: [
              usageRow('2026-09-25', costUsd: 2.5, cacheRead: 5000),
              usageRow('2026-09-24', project: 'web', costUsd: null),
            ],
            codex: {
              'present': true,
              'limits': [
                {'label': '5h', 'usedPct': 10},
              ],
              'today': {'input': 5, 'output': 5, 'costUsd': 0.01},
              'range': {'input': 5, 'output': 5, 'costUsd': 0.01},
              'rows': [
                {
                  'date': '2026-09-25',
                  'project': 'cli',
                  'model': 'gpt-5-codex',
                  'input': 5,
                  'output': 5,
                  'costUsd': 0.01,
                },
              ],
            },
            partial: true,
          ),
        ),
      )!;
      expect(report.machine, 'devbox');
      expect(report.today, '2026-09-25');
      expect(report.companionVersion, '0.6.0');
      expect(report.partial, isTrue);
      expect(report.pricingAsOf, '2026-09-25');
      expect(report.claude.present, isTrue);
      expect(report.claude.limits.first.usedPct, 42.5);
      expect(report.claude.limits.first.resetsAt, resets);
      expect(report.claude.limits.last.expired, isTrue);
      expect(report.claude.sessions.single.contextUsedPct, 41);
      expect(report.claude.today.cacheRead, 5000);
      expect(report.claude.today.tokens, 100 + 1000 + 5000);
      expect(report.claude.today.costUsd, 2.5);
      expect(report.claude.rows, hasLength(2));
      expect(report.claude.rows.last.totals.costUsd, isNull);
      expect(report.codex.present, isTrue);
      expect(report.codex.rows.single.agent, UsageAgent.codex);
      expect(report.codex.limits.single.label, '5h');
    });

    test('rejects anything that is not a usage report', () {
      expect(parseUsageReport(''), isNull);
      expect(parseUsageReport('not json'), isNull);
      expect(
        parseUsageReport('{"error":"unknown command usage\\nusage: …"}'),
        isNull,
      );
      expect(parseUsageReport('{"version":"0.5.0","protocol":1}'), isNull);
      expect(parseUsageReport('[1,2]'), isNull);
    });

    test('tolerates missing sections', () {
      final report = parseUsageReport('{"schema":1,"machine":"m"}')!;
      expect(report.claude.present, isFalse);
      expect(report.codex.present, isFalse);
      expect(report.claude.today, UsageTotals.zero);
    });
  });

  group('limits', () {
    test('an expired or past window shows 0', () {
      final now = DateTime.utc(2026, 9, 25, 12);
      expect(
        UsageLimit(
          label: '5h',
          usedPct: 70,
          resetsAt: resets,
        ).effectivePct(now),
        70,
      );
      expect(
        UsageLimit(
          label: '5h',
          usedPct: 70,
          resetsAt: resets,
        ).effectivePct(resets.add(const Duration(minutes: 1))),
        0,
      );
      expect(
        const UsageLimit(
          label: '5h',
          usedPct: 70,
          expired: true,
        ).effectivePct(now),
        0,
      );
    });

    test('the later window wins, then the higher use', () {
      final merged = mergeUsageLimits([
        [
          UsageLimit(label: '7d', usedPct: 30, resetsAt: resets),
          UsageLimit(
            label: '5h',
            usedPct: 90,
            resetsAt: resets.subtract(const Duration(hours: 5)),
          ),
        ],
        [
          UsageLimit(label: '5h', usedPct: 5, resetsAt: resets),
          UsageLimit(
            label: '7d',
            usedPct: 31,
            resetsAt: resets.add(const Duration(seconds: 20)),
          ),
        ],
      ]);
      expect(merged.map((l) => (l.label, l.usedPct)), [('5h', 5), ('7d', 31)]);
    });
  });

  group('thresholds', () {
    test('warning from 80 %, critical from 95 %', () {
      expect(usageLevelFor(0), UsageLevel.normal);
      expect(usageLevelFor(79.9), UsageLevel.normal);
      expect(usageLevelFor(80), UsageLevel.warning);
      expect(usageLevelFor(94.9), UsageLevel.warning);
      expect(usageLevelFor(95), UsageLevel.critical);
      expect(usageLevelFor(100), UsageLevel.critical);
    });
  });

  group('UsageSummary', () {
    UsageReport report(String machine, List<Map<String, Object?>> rows) =>
        parseUsageReport(
          jsonEncode(usageReplyJson(machine: machine, rows: rows)),
        )!;

    final summary = UsageSummary([
      MachineUsage(
        hostId: 'a',
        hostName: 'Laptop',
        report: report('a', [
          usageRow('2026-09-25', costUsd: 3),
          usageRow('2026-09-23', project: 'web', model: 'claude-sonnet-5'),
        ]),
        liveLimits: [UsageLimit(label: '5h', usedPct: 81, resetsAt: resets)],
      ),
      MachineUsage(
        hostId: 'b',
        hostName: 'Server',
        report: report('b', [usageRow('2026-09-25', costUsd: 0.5)]),
      ),
      const MachineUsage(hostId: 'c', hostName: 'Old', needsUpdate: true),
    ]);

    test('sums today and the range across machines', () {
      expect(summary.today.costUsd, 3.5);
      expect(summary.today.messages, 2);
      expect(summary.range.costUsd, 4.5);
      expect(summary.fiveHour!.usedPct, 81);
      expect(summary.weekly, isNull);
      expect(summary.hasData, isTrue);
    });

    test('groups by machine, project, model and agent', () {
      expect(summary.groupBy(UsageGrouping.machine).map((g) => g.label), [
        'Laptop',
        'Server',
      ]);
      expect(
        summary
            .groupBy(UsageGrouping.project)
            .map((g) => (g.label, g.totals.costUsd)),
        [('api', 3.5), ('web', 1.0)],
      );
      expect(summary.groupBy(UsageGrouping.model).map((g) => g.label), [
        'claude-opus-5',
        'claude-sonnet-5',
      ]);
      expect(summary.groupBy(UsageGrouping.agent).single.label, 'Claude');
    });

    test('lists every day of the range, empty ones too', () {
      final days = summary.days();
      expect(days, hasLength(7));
      expect(days.first.date, '2026-09-19');
      expect(days.last.date, '2026-09-25');
      expect(days.last.totals.costUsd, 3.5);
      expect(days[4].totals.tokens, 1100);
      expect(days[5].totals, UsageTotals.zero);
    });

    test('formats tokens and cost', () {
      expect(formatUsageTokens(12), '12');
      expect(formatUsageTokens(85300), '85k');
      expect(formatUsageTokens(1250000), '1.3M');
      expect(formatUsageTokens(10305046237), '10.3B');
      expect(formatUsageCost(null), '—');
      expect(formatUsageCost(0.004), r'<$0.01');
      expect(formatUsageCost(4.2), r'$4.20');
      expect(formatUsageCost(6841.2), r'$6841');
    });
  });

  group('UsageAlertPolicy', () {
    const policy = UsageAlertPolicy();
    final now = DateTime.utc(2026, 9, 25, 12);

    test('fires at 80 % with the reset time, not below', () {
      expect(
        policy.evaluate(
          fiveHour: UsageLimit(label: '5h', usedPct: 79.9, resetsAt: resets),
          now: now,
          alerted: null,
        ),
        isNull,
      );
      final alert = policy.evaluate(
        fiveHour: UsageLimit(label: '5h', usedPct: 80, resetsAt: resets),
        now: now,
        alerted: null,
      )!;
      expect(alert.window, resets);
      expect(
        alert.body,
        '80% of your 5-hour window used, resets at '
        '${formatClockTime(resets)}.',
      );
      expect(formatClockTime(resets), matches(RegExp(r'^\d\d:\d\d$')));
    });

    test('once per window: same window (even with jitter) stays quiet, '
        'the next window alerts again', () {
      expect(
        policy.evaluate(
          fiveHour: UsageLimit(
            label: '5h',
            usedPct: 97,
            resetsAt: resets.add(const Duration(seconds: 30)),
          ),
          now: now,
          alerted: resets,
        ),
        isNull,
      );
      final next = resets.add(const Duration(hours: 5));
      expect(
        policy
            .evaluate(
              fiveHour: UsageLimit(label: '5h', usedPct: 85, resetsAt: next),
              now: resets.add(const Duration(hours: 3)),
              alerted: resets,
            )!
            .window,
        next,
      );
    });

    test('a window that already reset does not alert', () {
      expect(
        policy.evaluate(
          fiveHour: UsageLimit(label: '5h', usedPct: 99, resetsAt: resets),
          now: resets.add(const Duration(minutes: 1)),
          alerted: null,
        ),
        isNull,
      );
    });
  });
}
