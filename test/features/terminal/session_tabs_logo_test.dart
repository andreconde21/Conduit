import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';
import 'package:conduit/features/terminal/presentation/widgets/session_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

void main() {
  testWidgets('session tabs carry the tmux and Herdr logos', (tester) async {
    final workspace = TerminalWorkspaceController(
      ImmediateTerminalRepository(TrackableTerminalSession()),
    );
    addTearDown(workspace.dispose);
    workspace
      ..open(buildHost('plain'))
      ..open(const ConnectTarget.tmux('main').apply(buildHost('t')))
      ..open(
        buildHost(
          'auto',
        ).copyWith(startTmuxOnConnect: true, tmuxSessionName: 'work'),
      )
      ..open(
        const ConnectTarget.herdr(
          workspaceId: 'w1',
          label: 'Infra',
        ).apply(buildHost('h')),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionTabs(
            workspace: workspace,
            activeSession: workspace.activeSession,
            palette: AppPalette.values.first,
            brightness: Brightness.dark,
            onChanged: () {},
            fileTabs: const [],
            activeFileTab: null,
            onFileTabSelected: (_) {},
            onFileTabClosed: (_) {},
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('multiplexer-icon-tmux')),
      findsNWidgets(2),
    );
    expect(
      find.byKey(const ValueKey('multiplexer-icon-herdr')),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 400));
  });
}
