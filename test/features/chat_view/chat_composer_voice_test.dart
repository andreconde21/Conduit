import 'package:conduit/features/chat_view/presentation/widgets/chat_composer.dart';
import 'package:conduit/features/voice/presentation/dictation_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../voice/fake_speech_recognizer.dart';

/// André could not find the mic: it and Talk hid while the chat could not
/// send, and the mic hid on phones without a recognizer.
void main() {
  late FakeSpeechRecognizer recognizer;
  late DictationController dictation;
  late int talks;

  setUp(() {
    recognizer = FakeSpeechRecognizer();
    dictation = DictationController(recognizer, language: () => '');
    talks = 0;
  });

  tearDown(() => dictation.dispose());

  Future<void> pump(WidgetTester tester, {bool enabled = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatComposer(
            onSend: (_) async {},
            onInterrupt: () async {},
            enabled: enabled,
            disabledHint: 'No Claude session yet',
            dictation: dictation,
            onTalk: () => talks += 1,
          ),
        ),
      ),
    );
    await dictation.checkAvailability();
    await tester.pump();
  }

  IconButton button(WidgetTester tester, String key) =>
      tester.widget<IconButton>(find.byKey(ValueKey(key)));

  testWidgets('a disabled composer keeps Talk and the mic, disabled', (
    tester,
  ) async {
    await pump(tester, enabled: false);

    expect(find.byKey(const ValueKey('chat-talk')), findsOneWidget);
    expect(find.byKey(const ValueKey('dictation-button')), findsOneWidget);
    expect(button(tester, 'chat-talk').onPressed, isNull);
    expect(button(tester, 'dictation-button').onPressed, isNull);
    expect(find.byTooltip('No Claude session yet'), findsNWidgets(2));
  });

  testWidgets('an enabled composer offers Talk and the mic', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const ValueKey('chat-talk')));
    expect(talks, 1);
    expect(button(tester, 'dictation-button').onPressed, isNotNull);
  });

  testWidgets('without a recognizer Talk and the mic explain themselves', (
    tester,
  ) async {
    recognizer.available = false;
    await pump(tester);

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('dictation-button')),
        matching: find.byIcon(Icons.mic_off_rounded),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('chat-talk')));
    await tester.pumpAndSettle();
    expect(talks, 0);
    expect(find.text('No speech recognizer'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('dictation-button')));
    await tester.pumpAndSettle();
    expect(find.text('No speech recognizer'), findsOneWidget);
    expect(recognizer.starts, isEmpty);
  });
}
