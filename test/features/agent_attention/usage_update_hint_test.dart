import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/agent_attention/presentation/widgets/usage_update_hint.dart';
import 'package:conduit/features/companion_setup/data/companion_probe.dart';
import 'package:conduit/features/companion_setup/domain/companion_status.dart';
import 'package:conduit/features/companion_setup/presentation/companion_setup_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';
import '../companion_setup/companion_fakes.dart';

/// Reports a fixed installed version without running anything.
class _FixedProbe extends CompanionProbe {
  const _FixedProbe(this.version);

  final String version;

  @override
  Future<CompanionStatus> check(AgentCommandRunner runner) async =>
      CompanionStatus(
        state: CompanionState.active,
        checkedAt: DateTime.now(),
        installedVersion: version,
      );
}

void main() {
  Future<void> pumpHint(WidgetTester tester, String version) async {
    final controller = CompanionSetupController(
      runnerFactory: (_) => ScriptedAgentCommandRunner(const []),
      sftpRepository: FakeSftpRepository(
        FakeSftpSession(home: '/home/a', tree: {}),
      ),
      loadBundle: () async => fakeBundle(),
      probe: _FixedProbe(version),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanionSetupScope(
            controller: controller,
            child: UsageUpdateHint(host: buildHost('h')),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a companion older than 0.3.0 offers the update', (tester) async {
    await pumpHint(tester, '0.2.0');
    expect(find.text('Update agent hooks for usage'), findsOneWidget);
    expect(find.textContaining('Companion 0.2.0'), findsOneWidget);
  });

  testWidgets('0.3.0 and newer show nothing', (tester) async {
    await pumpHint(tester, '0.3.0');
    expect(find.text('Update agent hooks for usage'), findsNothing);
  });

  testWidgets('without the setup scope the hint renders nothing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: UsageUpdateHint(host: buildHost('h'))),
    );
    expect(find.byType(TextButton), findsNothing);
  });

  test('version comparison', () {
    expect(usageNeedsCompanionUpdate('0.2.9'), isTrue);
    expect(usageNeedsCompanionUpdate('0.10.0'), isFalse);
    expect(usageNeedsCompanionUpdate(null), isFalse);
  });
}
