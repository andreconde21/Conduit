import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/core/theme/terminal_appearance.dart';
import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/core/theme/theme_preferences_repository.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/hosts/presentation/hosts_controller.dart';
import 'package:conduit/features/sessions/domain/connect_preferences.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/sessions/presentation/session_connect_flow.dart';
import 'package:conduit/features/terminal/domain/multiplexer_tabs.dart';
import 'package:conduit/features/terminal/presentation/multiplexer_tabs_controller.dart';
import 'package:conduit/features/terminal/presentation/terminal_page.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';
import 'package:conduit/features/terminal/presentation/widgets/multiplexer_tab_strip.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../../support/test_doubles.dart';
import 'multiplexer_tabs_fakes.dart';

class _NoopWakelock extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}

  @override
  Future<bool> get enabled async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WakelockPlusPlatformInterface.instance = _NoopWakelock();

  final strip = find.byKey(const ValueKey('multiplexer-tab-strip'));
  Finder chip(String id) => find.byKey(ValueKey('mux-tab-$id'));

  test('when the strip shows', () {
    bool shows(
      MultiplexerTabsVisibility v,
      int count, {
      bool desktop = false,
    }) => showsMultiplexerTabs(v, tabCount: count, desktop: desktop);
    expect(shows(MultiplexerTabsVisibility.auto, 1), isFalse);
    expect(shows(MultiplexerTabsVisibility.auto, 2), isTrue);
    expect(shows(MultiplexerTabsVisibility.auto, 1, desktop: true), isTrue);
    expect(shows(MultiplexerTabsVisibility.always, 1), isTrue);
    expect(shows(MultiplexerTabsVisibility.never, 5, desktop: true), isFalse);
    expect(shows(MultiplexerTabsVisibility.always, 0), isFalse);
  });

  test('the setting is kept, auto by default', () async {
    final storage = InMemorySecureStorage();
    final first = ThemeController(ThemePreferencesRepository(storage));
    await first.load();
    expect(first.multiplexerTabs, MultiplexerTabsVisibility.auto);
    await first.setMultiplexerTabs(MultiplexerTabsVisibility.always);
    final again = ThemeController(ThemePreferencesRepository(storage));
    await again.load();
    expect(again.multiplexerTabs, MultiplexerTabsVisibility.always);
  });

  group('the strip', () {
    late FakeTmux tmux;
    late MultiplexerTabsController controller;

    Future<void> pumpStrip(
      WidgetTester tester, {
      List<String> windows = const ['zsh', 'claude', 'logs'],
      MultiplexerTabsVisibility visibility = MultiplexerTabsVisibility.auto,
      bool desktop = false,
    }) async {
      tmux = FakeTmux(windows, active: windows.length > 1 ? 1 : 0);
      controller = MultiplexerTabsController(
        backend: TmuxTabsBackend(
          channel: SerialCommandChannel(runnerFactory: () => tmux),
          sessionName: 'work',
        ),
      );
      final palette = AppPalette.fromStoredId(null);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                MultiplexerTabStrip(
                  controller: controller,
                  palette: palette,
                  brightness: Brightness.dark,
                  visibility: visibility,
                  desktop: desktop,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.runAsync(controller.refresh);
      await tester.pump();
    }

    tearDown(() => controller.dispose());

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.runAsync(controller.refresh);
      await tester.pumpAndSettle();
    }

    testWidgets('one chip per window, the active one marked', (tester) async {
      await pumpStrip(tester);
      expect(strip, findsOneWidget);
      expect(tester.getSize(strip).height, MultiplexerTabStrip.height);
      expect(find.text('zsh'), findsOneWidget);
      expect(find.text('claude'), findsOneWidget);
      expect(find.text('logs'), findsOneWidget);
      expect(
        tester.getSemantics(chip('@1').first),
        isSemantics(isSelected: true, label: 'claude'),
      );
      expect(
        tester.getSemantics(chip('@0').first),
        isSemantics(isSelected: false),
      );
    });

    testWidgets('hidden with one window on a phone in auto, shown when '
        'always', (tester) async {
      await pumpStrip(tester, windows: ['zsh']);
      expect(strip, findsNothing);
      controller.dispose();
      await pumpStrip(
        tester,
        windows: ['zsh'],
        visibility: MultiplexerTabsVisibility.always,
      );
      expect(strip, findsOneWidget);
      controller.dispose();
      await pumpStrip(tester, windows: ['zsh'], desktop: true);
      expect(strip, findsOneWidget);
      controller.dispose();
      await pumpStrip(tester, visibility: MultiplexerTabsVisibility.never);
      expect(strip, findsNothing);
    });

    testWidgets('tap switches, + opens a new window', (tester) async {
      await pumpStrip(tester);
      await tester.tap(find.text('logs'));
      await settle(tester);
      expect(tmux.commands, contains(TmuxWindowCommands.select('@2')));
      expect(controller.active?.id, '@2');

      await tester.tap(find.byKey(const ValueKey('mux-tab-new')));
      await settle(tester);
      expect(
        tmux.commands,
        contains(TmuxWindowCommands.create(afterWindowId: '@2')),
      );
      expect(controller.tabs, hasLength(4));
    });

    testWidgets('long-press renames, moves and closes (after asking)', (
      tester,
    ) async {
      await pumpStrip(tester);
      await tester.longPress(find.text('zsh'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mux-tab-rename')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('mux-tab-name')),
        'shell',
      );
      await tester.tap(find.text('Rename'));
      await settle(tester);
      expect(tmux.commands, contains(TmuxWindowCommands.rename('@0', 'shell')));
      expect(find.text('shell'), findsOneWidget);

      await tester.longPress(find.text('shell'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mux-tab-move-right')));
      await settle(tester);
      expect(
        tmux.commands,
        contains(TmuxWindowCommands.swap('@0', '@1', activeWindowId: '@1')),
      );
      expect([for (final tab in controller.tabs) tab.id], ['@1', '@0', '@2']);

      await tester.longPress(find.text('logs'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mux-tab-close')));
      await tester.pumpAndSettle();
      expect(find.text('Close "logs"?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mux-tab-close-confirm')));
      await settle(tester);
      expect(tmux.commands, contains(TmuxWindowCommands.kill('@2')));
      expect(find.text('logs'), findsNothing);
    });

    testWidgets('dragging a chip reorders on a desktop', (tester) async {
      await pumpStrip(tester, desktop: true);
      expect(
        find.byKey(const ValueKey('mux-tabs-reorderable')),
        findsOneWidget,
      );
      final from = tester.getCenter(find.text('zsh'));
      final to = tester.getCenter(find.text('logs'));
      // A mouse, as on a desktop: a touch drag scrolls the strip.
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      for (var i = 1; i <= 10; i += 1) {
        await gesture.moveTo(
          Offset.lerp(from, to + const Offset(30, 0), i / 10)!,
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      // The drop animation, then the swaps it asked for.
      await tester.pumpAndSettle();
      await settle(tester);
      expect(
        tmux.commands.where((command) => command.contains('swap-window')),
        hasLength(2),
      );
      expect([for (final tab in controller.tabs) tab.id], ['@1', '@2', '@0']);
      await gesture.removePointer();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 3));
    });
  });

  group('on the terminal page', () {
    late ThemeController themeController;

    setUp(() async {
      themeController = ThemeController(InMemoryThemePreferences());
      await themeController.load();
    });

    Future<(TerminalWorkspaceController, SessionConnectFlow)> pumpPage(
      WidgetTester tester,
      ConnectTarget? target, {
      AgentCommandRunner? runner,
    }) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      final workspace = TerminalWorkspaceController(
        ImmediateTerminalRepository(TrackableTerminalSession()),
      );
      addTearDown(workspace.dispose);
      final host = buildHost('a');
      final flow = SessionConnectFlow(
        hostsController: HostsController(FakeHostsRepository()),
        workspace: workspace,
        runnerFactory: (_) => runner ?? FakeTmux(['zsh', 'claude'], active: 1),
        preferences: InMemoryConnectPreferencesRepository(),
      );
      workspace.open(target == null ? host : target.apply(host));
      await tester.pumpWidget(
        MaterialApp(
          home: TerminalPage(
            workspace: workspace,
            themeController: themeController,
            sftpRepository: NoNetworkSftpRepository(),
            connectFlow: flow,
          ),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 4; i += 1) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump(const Duration(milliseconds: 100));
      }
      return (workspace, flow);
    }

    Future<void> finish(WidgetTester tester, SessionConnectFlow flow) async {
      await tester.pumpWidget(const SizedBox());
      await flow.herdr.dispose();
    }

    testWidgets('a plain shell has no strip', (tester) async {
      final (_, flow) = await pumpPage(tester, null);
      expect(strip, findsNothing);
      await finish(tester, flow);
    });

    testWidgets('a tmux session shows its windows; Ctrl+PageDown moves to '
        'the next one', (tester) async {
      final tmux = FakeTmux(['zsh', 'claude', 'logs']);
      final (_, flow) = await pumpPage(
        tester,
        const ConnectTarget.tmux('work'),
        runner: tmux,
      );
      expect(strip, findsOneWidget);
      expect(tmux.commands.first, TmuxWindowCommands.list('work'));
      expect(find.text('claude'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      for (var i = 0; i < 3; i += 1) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(tmux.commands, contains(TmuxWindowCommands.select('@1')));
      await finish(tester, flow);
    });

    testWidgets('a Herdr session shows the focused workspace\'s tabs', (
      tester,
    ) async {
      final herdr = FakeHerdr();
      final (_, flow) = await pumpPage(
        tester,
        const ConnectTarget.herdr(workspaceId: 'w4'),
        runner: herdr,
      );
      expect(strip, findsOneWidget);
      expect(find.text('review'), findsOneWidget);
      expect(find.text('Infrastructure'), findsOneWidget);
      await finish(tester, flow);
    });

    testWidgets('the setting hides it', (tester) async {
      await themeController.setMultiplexerTabs(MultiplexerTabsVisibility.never);
      final (_, flow) = await pumpPage(
        tester,
        const ConnectTarget.tmux('work'),
      );
      expect(strip, findsNothing);
      expect(themeController.multiplexerTabs, MultiplexerTabsVisibility.never);
      await finish(tester, flow);
    });
  });
}
