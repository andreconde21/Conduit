import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/companion_setup/data/companion_bundle.dart';
import 'package:conduit/features/companion_setup/presentation/companion_setup_controller.dart';
import 'package:conduit/features/companion_setup/presentation/companion_setup_page.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/hosts/presentation/host_form_page.dart';
import 'package:flutter/foundation.dart';
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

  testWidgets('the form offers the agent monitor choice and hides Agent '
      'hooks without a companion setup scope', (tester) async {
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
    expect(find.textContaining('Agent hooks'), findsNothing);
  });

  testWidgets('iOS hides the notification level, which only Android '
      'can deliver', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(
        MaterialApp(home: HostFormPage(host: buildHost('h'))),
      );
      await revealAgentSection(tester);
      await scrollTo(tester, find.text('Agent monitor'));
      expect(find.byKey(const ValueKey('agent-notify-level')), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  // The Agent hooks row that replaced "Set up companion" is covered in
  // test/features/companion_setup/companion_setup_page_test.dart.

  testWidgets('the notification level picker writes both notify flags', (
    tester,
  ) async {
    final controller = CompanionSetupController(
      runnerFactory: (_) {
        return ScriptedAgentCommandRunner([
          const AgentCommandResult(stdout: '', stderr: '', exitCode: 127),
        ]);
      },
      sftpRepository: NoNetworkSftpRepository(),
      loadBundle: () async => const CompanionBundle(version: '0', files: {}),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      CompanionSetupScope(
        controller: controller,
        child: MaterialApp(home: HostFormPage(host: buildHost('h'))),
      ),
    );
    await revealAgentSection(tester);
    final picker = find.byKey(const ValueKey('agent-notify-level'));
    await scrollTo(tester, picker);
    expect(find.text('All'), findsOneWidget);

    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approvals and errors').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('update the inbox quietly'), findsOneWidget);

    final tile = find.byKey(const ValueKey('companion-setup-tile'));
    await scrollTo(tester, tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    // The Agent hooks row opens its screen with the draft as edited.
    final probed = tester
        .widget<CompanionSetupPage>(find.byType(CompanionSetupPage))
        .host;
    expect(probed.agentNotifyLevel, AgentNotifyLevel.approvalsAndErrors);
    expect(probed.agentNotifyInput, isTrue);
    expect(probed.agentNotifyFinished, isFalse);
  });
}
