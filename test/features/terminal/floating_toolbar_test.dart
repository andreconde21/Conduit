import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/core/theme/terminal_appearance.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/snippets/domain/terminal_snippet.dart';
import 'package:conduit/features/terminal/presentation/terminal_keyboard_bar.dart';
import 'package:conduit/features/terminal/presentation/terminal_session_controller.dart';
import 'package:conduit/features/terminal/presentation/widgets/floating_toolbar.dart';
import 'package:conduit/features/terminal/presentation/widgets/toolbar_arrow_pad.dart';
import 'package:conduit_vt/conduit_vt.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

const _pill = ValueKey('floating-toolbar-pill');
const _arrows = ValueKey('toolbar-arrows');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildToolbar({
    required _RecordingTerminalSessionController controller,
    required FocusNode focusNode,
    List<TerminalSnippet> globalSnippets = const [],
    bool composeActive = false,
    VoidCallback? onToggleCompose,
    Future<void> Function()? onReconnect,
    TerminalToolbarStyle style = TerminalToolbarStyle.floatingPill,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: Focus(
                focusNode: focusNode,
                child: const SizedBox.expand(),
              ),
            ),
            TerminalKeyboardBar(
              controller: controller,
              focusNode: focusNode,
              palette: AppPalette.catppuccin,
              brightness: Brightness.dark,
              rows: const [
                TerminalKeyboardRow(
                  items: [
                    TerminalKeyboardItem.builtIn(
                      TerminalKeyboardAction.herdrMenu,
                    ),
                    TerminalKeyboardItem.builtIn(
                      TerminalKeyboardAction.tmuxMenu,
                    ),
                  ],
                ),
              ],
              globalSnippets: globalSnippets,
              fullscreen: false,
              onToggleFullscreen: () {},
              composeActive: composeActive,
              onToggleCompose: onToggleCompose,
              onEnterTmuxScrollMode: () {},
              onExitTmuxScrollMode: () {},
              tmuxPrefixKey: TmuxPrefixKey.controlB,
              tmuxScrollMode: false,
            ).withToolbarStyle(style, onReconnect: onReconnect),
          ],
        ),
      ),
    );
  }

  List<MethodCall> recordPlatformCalls(WidgetTester tester) {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    return calls;
  }

  /// Swipes up starting on the Esc key: any spot on the pill works except the
  /// arrow pad, which claims its own drags.
  Future<void> swipeUp(WidgetTester tester) {
    return tester.dragFrom(
      tester.getCenter(find.text('Esc')),
      const Offset(0, -80),
    );
  }

  group('FloatingTerminalToolbar', () {
    testWidgets('long-press alternates: Esc sends Ctrl+C, Tab sends Shift+Tab, '
        'with haptic feedback', (tester) async {
      final controller = _RecordingTerminalSessionController();
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      addTearDown(controller.dispose);
      final platformCalls = recordPlatformCalls(tester);

      await tester.pumpWidget(
        buildToolbar(controller: controller, focusNode: focusNode),
      );

      await tester.tap(find.text('Esc'));
      await tester.tap(find.text('Tab'));
      expect(controller.sentKeys, [TerminalKey.escape, TerminalKey.tab]);
      expect(controller.sentControlKeys, isEmpty);
      expect(platformCalls.where(_isHaptic), isEmpty);

      await tester.longPress(find.text('Esc'));
      expect(controller.sentControlKeys, [TerminalKey.keyC]);
      expect(platformCalls.where(_isHaptic), hasLength(1));

      await tester.longPress(find.text('Tab'));
      expect(controller.sentKeys, [
        TerminalKey.escape,
        TerminalKey.tab,
        TerminalKey.backtab,
      ]);
      expect(platformCalls.where(_isHaptic), hasLength(2));
    });

    testWidgets('Ctrl tap arms the next key, long-press latches until '
        'released', (tester) async {
      final controller = _RecordingTerminalSessionController();
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      addTearDown(controller.dispose);
      recordPlatformCalls(tester);

      await tester.pumpWidget(
        buildToolbar(controller: controller, focusNode: focusNode),
      );

      // One-shot: armed, consumed by the next key.
      await tester.tap(find.text('Ctrl'));
      await tester.pump();
      expect(controller.keyboard.ctrl, isTrue);
      expect(controller.keyboard.ctrlLatched, isFalse);
      await tester.tap(find.text('Esc'));
      await tester.pump();
      expect(controller.keyboard.ctrl, isFalse);

      // Latched: survives keys, highlighted, released by the next tap.
      await tester.longPress(find.text('Ctrl'));
      await tester.pump();
      expect(controller.keyboard.ctrlLatched, isTrue);
      expect(controller.keyboard.ctrl, isTrue);
      await tester.tap(find.text('Esc'));
      await tester.tap(find.text('Tab'));
      await tester.pump();
      expect(controller.keyboard.ctrl, isTrue);
      expect(controller.keyboard.ctrlLatched, isTrue);
      final latchedStyle = tester.widget<Text>(find.text('Ctrl')).style;
      expect(latchedStyle?.color, AppPalette.catppuccin.canvas);

      await tester.tap(find.text('Ctrl'));
      await tester.pump();
      expect(controller.keyboard.ctrlLatched, isFalse);
      expect(controller.keyboard.ctrl, isFalse);
      final releasedStyle = tester.widget<Text>(find.text('Ctrl')).style;
      expect(releasedStyle?.color, AppPalette.catppuccin.foreground);
    });

    testWidgets('arrow pad drag emits arrows proportional to the distance '
        'and repeats while held far out', (tester) async {
      final controller = _RecordingTerminalSessionController();
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        buildToolbar(controller: controller, focusNode: focusNode),
      );

      final pad = find.byKey(_arrows);
      await tester.drag(pad, const Offset(90, 0));
      await tester.pump();
      expect(
        controller.sentKeys,
        List.filled(
          (90 / toolbarArrowPadStep).truncate(),
          TerminalKey.arrowRight,
        ),
      );

      controller.sentKeys.clear();
      await tester.drag(pad, const Offset(0, -40));
      await tester.pump();
      expect(controller.sentKeys, [TerminalKey.arrowUp, TerminalKey.arrowUp]);

      // Moving back toward the origin mirrors the finger.
      controller.sentKeys.clear();
      final gesture = await tester.startGesture(tester.getCenter(pad));
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump();
      expect(controller.sentKeys, [
        TerminalKey.arrowRight,
        TerminalKey.arrowRight,
        TerminalKey.arrowLeft,
        TerminalKey.arrowLeft,
      ]);

      // Resting past the hold radius auto-repeats the direction.
      controller.sentKeys.clear();
      await gesture.moveBy(const Offset(0, 70));
      await tester.pump();
      final immediate = controller.sentKeys.length;
      expect(immediate, greaterThan(0));
      expect(controller.sentKeys.toSet(), {TerminalKey.arrowDown});
      await tester.pump(toolbarArrowPadRepeatDelay);
      await tester.pump(toolbarArrowPadRepeatInterval);
      await tester.pump(toolbarArrowPadRepeatInterval);
      expect(controller.sentKeys.length, immediate + 2);
      expect(controller.sentKeys.toSet(), {TerminalKey.arrowDown});
      await gesture.up();
      await tester.pump(toolbarArrowPadRepeatInterval * 3);
      expect(controller.sentKeys.length, immediate + 2);
    });

    testWidgets('arrow pad taps: edges send a single arrow, the centre '
        'nothing', (tester) async {
      final controller = _RecordingTerminalSessionController();
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        buildToolbar(controller: controller, focusNode: focusNode),
      );

      final pad = find.byKey(_arrows);
      final rect = tester.getRect(pad);
      await tester.tapAt(Offset(rect.center.dx, rect.top + 3));
      await tester.tapAt(Offset(rect.right - 3, rect.center.dy));
      await tester.tapAt(Offset(rect.center.dx, rect.bottom - 3));
      await tester.tapAt(Offset(rect.left + 3, rect.center.dy));
      await tester.tapAt(rect.center);
      await tester.pump();

      expect(controller.sentKeys, [
        TerminalKey.arrowUp,
        TerminalKey.arrowRight,
        TerminalKey.arrowDown,
        TerminalKey.arrowLeft,
      ]);
    });

    testWidgets('swipe up opens the palette; quick prompts type the line '
        'and press Enter separately', (tester) async {
      final controller = _RecordingTerminalSessionController();
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        buildToolbar(
          controller: controller,
          focusNode: focusNode,
          globalSnippets: const [
            TerminalSnippet(id: 'g1', label: 'Deploy', text: 'make deploy'),
          ],
        ),
      );
      expect(find.text('Quick prompts'), findsNothing);

      await swipeUp(tester);
      await tester.pumpAndSettle();

      expect(find.text('Quick prompts'), findsOneWidget);
      expect(find.text('/clear'), findsOneWidget);
      expect(find.text('/compact'), findsOneWidget);
      expect(find.text('Esc Esc'), findsOneWidget);
      expect(find.text('Ctrl+C'), findsOneWidget);
      expect(find.text('Deploy'), findsOneWidget);
      expect(controller.sentText, isEmpty);

      await tester.tap(find.text('/clear'));
      await tester.pump();
      expect(controller.sentText, ['/clear']);
      expect(controller.sentKeys, isEmpty);
      await tester.pump(floatingToolbarSubmitDelay);
      expect(controller.sentKeys, [TerminalKey.enter]);
      await tester.pumpAndSettle();
      expect(find.text('Quick prompts'), findsNothing);

      await swipeUp(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Esc Esc'));
      await tester.pumpAndSettle();
      expect(controller.sentKeys, [
        TerminalKey.enter,
        TerminalKey.escape,
        TerminalKey.escape,
      ]);

      await swipeUp(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ctrl+C'));
      await tester.pumpAndSettle();
      expect(controller.sentControlKeys, [TerminalKey.keyC]);

      await swipeUp(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deploy'));
      await tester.pump();
      expect(controller.sentText, ['/clear', 'make deploy']);
      expect(controller.sentKeys.last, TerminalKey.escape);
      await tester.pump(floatingToolbarSubmitDelay);
      expect(controller.sentKeys.last, TerminalKey.enter);
      await tester.pumpAndSettle();
    });

    testWidgets('a short or sideways drag does not open the palette', (
      tester,
    ) async {
      final controller = _RecordingTerminalSessionController();
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        buildToolbar(controller: controller, focusNode: focusNode),
      );

      // Within the touch slop this is just a tap on Esc.
      await tester.dragFrom(
        tester.getCenter(find.text('Esc')),
        const Offset(0, -10),
      );
      await tester.pumpAndSettle();
      expect(find.text('Quick prompts'), findsNothing);
      expect(controller.sentKeys, [TerminalKey.escape]);
      controller.sentKeys.clear();

      await tester.dragFrom(
        tester.getCenter(find.text('Esc')),
        const Offset(-80, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('Quick prompts'), findsNothing);
      expect(controller.sentKeys, isEmpty);
      expect(controller.sentControlKeys, isEmpty);
    });

    testWidgets('sits above a three-button navigation bar', (tester) async {
      final controller = _RecordingTerminalSessionController();
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        buildToolbar(controller: controller, focusNode: focusNode),
      );
      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final withoutInset = tester.getBottomRight(find.byKey(_pill)).dy;
      expect(withoutInset, lessThanOrEqualTo(screenHeight));

      // A three-button Android navigation bar with the keyboard hidden is
      // reported as bottom view padding (physical pixels).
      tester.view.viewPadding = const FakeViewPadding(bottom: 96);
      addTearDown(tester.view.resetViewPadding);
      tester.view.padding = const FakeViewPadding(bottom: 96);
      addTearDown(tester.view.resetPadding);
      await tester.pump();

      final inset = 96 / tester.view.devicePixelRatio;
      final withInset = tester.getBottomRight(find.byKey(_pill)).dy;
      expect(withInset, lessThanOrEqualTo(screenHeight - inset));
      expect(withInset, lessThanOrEqualTo(withoutInset - inset));
    });

    testWidgets('the overflow button reveals and hides the key rows', (
      tester,
    ) async {
      final controller = _RecordingTerminalSessionController();
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        buildToolbar(controller: controller, focusNode: focusNode),
      );
      expect(find.text('Herdr'), findsNothing);
      expect(find.byType(TerminalKeyboardBar), findsNothing);

      await tester.tap(find.byKey(const ValueKey('toolbar-more')));
      await tester.pumpAndSettle();
      expect(find.text('Herdr'), findsOneWidget);
      expect(find.text('Tmux+'), findsOneWidget);
      // The rows sit above the pill, not below it.
      expect(
        tester.getBottomLeft(find.text('Herdr')).dy,
        lessThan(tester.getTopLeft(find.byKey(_pill)).dy),
      );

      await tester.tap(find.byKey(const ValueKey('toolbar-more')));
      await tester.pumpAndSettle();
      expect(find.text('Herdr'), findsNothing);
    });

    testWidgets('redraw sends Ctrl+L on tap and reconnects on long-press', (
      tester,
    ) async {
      final controller = _RecordingTerminalSessionController();
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      addTearDown(controller.dispose);
      recordPlatformCalls(tester);
      var reconnects = 0;

      await tester.pumpWidget(
        buildToolbar(
          controller: controller,
          focusNode: focusNode,
          onReconnect: () async => reconnects += 1,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('toolbar-redraw')));
      expect(controller.sentControlKeys, [TerminalKey.keyL]);
      expect(reconnects, 0);

      await tester.longPress(find.byKey(const ValueKey('toolbar-redraw')));
      await tester.pump();
      expect(reconnects, 1);
      expect(controller.sentControlKeys, [TerminalKey.keyL]);
    });

    testWidgets('chat button toggles compose mode and reflects it', (
      tester,
    ) async {
      final controller = _RecordingTerminalSessionController();
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      addTearDown(controller.dispose);
      var toggles = 0;

      await tester.pumpWidget(
        buildToolbar(
          controller: controller,
          focusNode: focusNode,
          onToggleCompose: () => toggles += 1,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('toolbar-chat')));
      expect(toggles, 1);
    });

    testWidgets('keyboard button shows the soft keyboard when hidden and '
        'hides it when shown', (tester) async {
      final controller = _RecordingTerminalSessionController();
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      addTearDown(controller.dispose);
      final textInputCalls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.textInput,
        (call) async {
          textInputCalls.add(call.method);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.textInput,
          null,
        ),
      );

      await tester.pumpWidget(
        buildToolbar(controller: controller, focusNode: focusNode),
      );
      expect(find.byIcon(Icons.keyboard_rounded), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('toolbar-keyboard')));
      await tester.pump();
      expect(textInputCalls, ['TextInput.show']);
      expect(focusNode.hasFocus, isTrue);

      tester.view.viewInsets = const FakeViewPadding(bottom: 600);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      expect(find.byIcon(Icons.keyboard_hide_rounded), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('toolbar-keyboard')));
      await tester.pump();
      expect(textInputCalls, ['TextInput.show', 'TextInput.hide']);
    });

    testWidgets('the key rows style bypasses the pill entirely', (
      tester,
    ) async {
      final controller = _RecordingTerminalSessionController();
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        buildToolbar(
          controller: controller,
          focusNode: focusNode,
          style: TerminalToolbarStyle.keyRows,
        ),
      );

      expect(find.byType(FloatingTerminalToolbar), findsNothing);
      expect(find.byKey(_pill), findsNothing);
      expect(find.text('Herdr'), findsOneWidget);
    });
  });
}

bool _isHaptic(MethodCall call) => call.method == 'HapticFeedback.vibrate';

class _RecordingTerminalSessionController extends TerminalSessionController {
  _RecordingTerminalSessionController({SavedHost? host})
    : super(
        host: host ?? buildHost('toolbar'),
        repository: NoNetworkTerminalRepository(),
      );

  final List<TerminalKey> sentKeys = <TerminalKey>[];
  final List<TerminalKey> sentControlKeys = <TerminalKey>[];
  final List<String> sentText = <String>[];

  @override
  void sendKey(TerminalKey key) {
    sentKeys.add(key);
    keyboard.clearModifiers();
  }

  @override
  void sendControl(TerminalKey key) {
    sentControlKeys.add(key);
    keyboard.clearModifiers();
  }

  @override
  void sendText(String text) {
    sentText.add(text);
    keyboard.clearModifiers();
  }
}
