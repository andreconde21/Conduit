import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/prompt_menus/presentation/prompt_menu_strip.dart';
import 'package:conduit/features/terminal/presentation/terminal_page.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../../support/test_doubles.dart';

class _NoopWakelock extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}

  @override
  Future<bool> get enabled async => false;
}

const _permissionPrompt =
    ' Do you want to proceed?\r\n'
    ' ❯ 1. Yes\r\n'
    '   2. No, and tell Claude what to do differently (esc)';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WakelockPlusPlatformInterface.instance = _NoopWakelock();

  testWidgets('the terminal page shows menu buttons above the key bar and '
      'the setting hides them', (tester) async {
    final workspace = TerminalWorkspaceController(
      ImmediateTerminalRepository(TrackableTerminalSession()),
    );
    addTearDown(workspace.dispose);
    final themeController = ThemeController(InMemoryThemePreferences());
    final session = workspace.open(buildHost('a'));
    // connect() must run outside the fake-async test zone.
    await tester.runAsync(session.connect);
    workspace.activate(session);

    await tester.pumpWidget(
      MaterialApp(
        home: TerminalPage(
          workspace: workspace,
          themeController: themeController,
          sftpRepository: NoNetworkSftpRepository(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(PromptMenuStrip), findsOneWidget);
    expect(find.text('1  Yes'), findsNothing);

    session.terminal.write(_permissionPrompt);
    await tester.pump(PromptMenuStrip.defaultDebounce);
    await tester.pump();

    expect(find.text('1  Yes'), findsOneWidget);
    // The key bar has an Esc key of its own; the strip adds a second one.
    expect(
      find.descendant(
        of: find.byType(PromptMenuStrip),
        matching: find.text('Esc'),
      ),
      findsOneWidget,
    );

    await themeController.setMenuButtonsEnabled(false);
    await tester.pump();

    expect(find.byType(PromptMenuStrip), findsNothing);
    expect(find.text('1  Yes'), findsNothing);
    // Let the terminal's debounced resize timer fire before teardown.
    await tester.pump(const Duration(milliseconds: 300));
  });
}
