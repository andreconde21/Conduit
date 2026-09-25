import 'package:conduit/features/desktop_shell/domain/sidebar_tree.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_harness.dart';

final _linux = TargetPlatformVariant.only(TargetPlatform.linux);

void main() {
  testWidgets('smoke: the desktop shell shows sidebar and dashboard', (
    tester,
  ) async {
    await pumpShell(tester);
    expect(find.byKey(const ValueKey('shell-sidebar')), findsOneWidget);
    expect(find.byKey(const ValueKey('shell-dashboard')), findsOneWidget);
    expect(
      find.byKey(
        ValueKey('sidebar-row-machines-${SidebarKeys.machine('workstation')}'),
      ),
      findsOneWidget,
    );
    await tearDownShell(tester);
  }, variant: _linux);
}
