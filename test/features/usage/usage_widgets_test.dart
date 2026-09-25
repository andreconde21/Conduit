import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/features/usage/data/usage_preferences.dart';
import 'package:conduit/features/usage/domain/usage_report.dart';
import 'package:conduit/features/usage/presentation/usage_controller.dart';
import 'package:conduit/features/usage/presentation/usage_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'usage_fakes.dart';

void main() {
  final now = DateTime.utc(2026, 9, 25, 12);
  final resets = DateTime.utc(2026, 9, 25, 15);

  late FakeUsageRunner runner;
  late FakeUsageSource source;
  late MemoryUsagePreferencesStore store;

  setUp(() {
    runner = FakeUsageRunner(
      () => FakeUsageRunner.ok(
        usageReplyJson(
          limits: [
            {
              'label': '5h',
              'usedPct': 83,
              'resetsAt': resets.millisecondsSinceEpoch,
            },
            {
              'label': '7d',
              'usedPct': 20,
              'resetsAt': resets
                  .add(const Duration(days: 3))
                  .millisecondsSinceEpoch,
            },
          ],
          rows: [
            usageRow('2026-09-25', output: 1200000, costUsd: 4.2),
            usageRow('2026-09-24', project: 'web', costUsd: 1),
          ],
        ),
      ),
    );
    source = FakeUsageSource([usageHost('box', name: 'Box')], {'box': runner});
    store = MemoryUsagePreferencesStore();
  });

  UsageController controller(WidgetTester tester) {
    final c = UsageController(
      source: source,
      preferences: store,
      clock: () => now,
      observeLifecycle: false,
    );
    addTearDown(c.dispose);
    return c;
  }

  Widget app(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  test('ring colours: accent, then warning from 80 %, danger from 95 %', () {
    final palette = AppPalette.defaultPalette;
    expect(usageColor(79, palette), palette.accent);
    expect(usageColor(80, palette), palette.warning);
    expect(usageColor(95, palette), palette.danger);
  });

  testWidgets('the home bar shows the rings, today and polls while shown', (
    tester,
  ) async {
    final usage = controller(tester);
    await tester.pumpWidget(app(UsageHomeBar(controller: usage, now: now)));
    await tester.pump();
    expect(runner.commands, hasLength(1));
    expect(find.byKey(const ValueKey('usage-home-bar')), findsOneWidget);
    expect(find.text('83'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);
    expect(find.textContaining(r'$4.20'), findsOneWidget);
    expect(find.textContaining('1.2M tokens'), findsOneWidget);
    final ring = tester.widget<UsageRing>(
      find.byKey(const ValueKey('usage-ring-5h')),
    );
    expect(ring.percent, 83);

    // Collapsed: one line, remembered.
    await tester.tap(find.byKey(const ValueKey('usage-bar-toggle')));
    await tester.pump();
    expect(store.value.barCollapsed, isTrue);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('usage-collapsed-text')))
          .data,
      r'5h 83% · wk 20% · $4.20 today',
    );

    // Gone: polling stops.
    await tester.pumpWidget(app(const SizedBox()));
    expect(usage.isVisible, isFalse);
  });

  testWidgets('the home bar hides while no machine reports usage', (
    tester,
  ) async {
    source.hosts = [];
    final usage = controller(tester);
    await tester.pumpWidget(app(UsageHomeBar(controller: usage, now: now)));
    expect(find.byKey(const ValueKey('usage-home-bar')), findsNothing);
    expect(runner.commands, isEmpty);
  });

  testWidgets('the compact summary fits a sidebar footer', (tester) async {
    final usage = controller(tester);
    await tester.pumpWidget(
      app(
        SizedBox(
          width: 220,
          child: UsageSummaryView(
            controller: usage,
            layout: UsageSummaryLayout.compact,
            now: now,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining(r'83% · $4.20 today'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the breakdown groups by project, machine and model', (
    tester,
  ) async {
    final usage = controller(tester);
    await tester.pumpWidget(app(UsageBreakdown(controller: usage, now: now)));
    await tester.pump();
    expect(find.byKey(const ValueKey('usage-breakdown')), findsOneWidget);
    expect(find.text('Claude · 5-hour'), findsOneWidget);
    expect(find.text('Claude · Weekly'), findsOneWidget);
    expect(find.textContaining('83% · resets in 3h'), findsOneWidget);
    expect(find.text('api'), findsOneWidget);
    expect(find.text('web'), findsOneWidget);
    expect(find.byKey(const ValueKey('usage-day-2026-09-25')), findsOneWidget);
    expect(find.byKey(const ValueKey('usage-day-2026-09-19')), findsOneWidget);

    await tester.tap(find.text('Model'));
    await tester.pump();
    expect(find.text('claude-opus-5'), findsOneWidget);
    await tester.tap(find.text('Machine'));
    await tester.pump();
    expect(find.text('Box'), findsOneWidget);
    expect(find.textContaining('API-equivalent cost'), findsOneWidget);
  });

  testWidgets('the breakdown offers the update for an old companion', (
    tester,
  ) async {
    runner.reply = () => FakeUsageRunner.ok({'error': 'unknown command usage'});
    final usage = controller(tester);
    String? updated;
    await tester.pumpWidget(
      app(
        UsageBreakdown(
          controller: usage,
          now: now,
          onUpdateCompanion: (hostId) => updated = hostId,
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('needs 0.6.0'), findsOneWidget);
    await tester.tap(find.text('Update agent hooks'));
    expect(updated, 'box');
  });

  testWidgets('Codex limits show when a machine has Codex', (tester) async {
    runner.reply = () => FakeUsageRunner.ok(
      usageReplyJson(
        codex: {
          'present': true,
          'limits': [
            {'label': '5h', 'usedPct': 12},
          ],
          'rows': <Object?>[],
        },
      ),
    );
    final usage = controller(tester);
    await tester.pumpWidget(app(UsageBreakdown(controller: usage, now: now)));
    await tester.pump();
    expect(find.text('Codex · 5-hour'), findsOneWidget);
    expect(usage.summary.codexPresent, isTrue);
    expect(
      usage.summary.codexLimits.single,
      const UsageLimit(label: '5h', usedPct: 12),
    );
  });
}
