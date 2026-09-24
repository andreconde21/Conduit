import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/hosts/presentation/host_form_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

void main() {
  test('agent monitor defaults to auto and round-trips', () {
    final host = buildHost('h');
    expect(host.agentMonitor, AgentMonitorKind.auto);
    expect(
      SavedHost.fromJson(host.toJson()).agentMonitor,
      AgentMonitorKind.auto,
    );

    final companion = host.copyWith(agentMonitor: AgentMonitorKind.companion);
    final json = companion.toJson();
    expect(json['agentMonitor'], 'companion');
    expect(SavedHost.fromJson(json).agentMonitor, AgentMonitorKind.companion);

    // Older saves and unknown values fall back to auto.
    expect(
      SavedHost.fromJson({...json, 'agentMonitor': 'weird'}).agentMonitor,
      AgentMonitorKind.auto,
    );
    expect(AgentMonitorKind.parse(null), AgentMonitorKind.auto);
  });

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> revealAgentSection(WidgetTester tester) async {
    final toggle = find.text('Monitor coding agents');
    await scrollTo(tester, toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
  }

  testWidgets('the form offers the agent monitor choice and hides the '
      'companion check without a doctor', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HostFormPage(
          host: buildHost('h').copyWith(agentAttentionEnabled: false),
        ),
      ),
    );
    await revealAgentSection(tester);
    await scrollTo(tester, find.text('Agent monitor'));

    expect(find.text('Agent monitor'), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('Set up companion'), findsNothing);
  });

  testWidgets('Set up companion runs doctor on the draft and shows the '
      'report', (tester) async {
    SavedHost? probed;
    await tester.pumpWidget(
      MaterialApp(
        home: HostFormPage(
          host: buildHost('h'),
          companionDoctor: (draft) async {
            probed = draft;
            return 'conductore-hostd doctor: OK\n\nhooks: installed';
          },
        ),
      ),
    );
    await revealAgentSection(tester);
    await scrollTo(tester, find.text('Set up companion'));
    await tester.tap(find.text('Set up companion'));
    await tester.pumpAndSettle();

    expect(probed?.host, '192.168.1.1');
    expect(probed?.agentAttentionEnabled, isTrue);
    expect(find.text('Companion check'), findsOneWidget);
    expect(find.textContaining('hooks: installed'), findsOneWidget);
  });
}
