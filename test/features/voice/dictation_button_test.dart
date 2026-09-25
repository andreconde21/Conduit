import 'package:conduit/features/voice/data/platform_speech_recognizer.dart';
import 'package:conduit/features/voice/presentation/dictation_button.dart';
import 'package:conduit/features/voice/presentation/dictation_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('conduit/speech');
  const events = EventChannel('conduit/speech_events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> calls;
  late bool permissionGranted;
  late bool grantOnRequest;
  late bool available;
  MockStreamHandlerEventSink? sink;

  void installFakeChannel() {
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'isAvailable':
          return available;
        case 'hasPermission':
          return permissionGranted;
        case 'requestPermission':
          permissionGranted = grantOnRequest;
          return grantOnRequest;
        case 'start':
          final args = call.arguments as Map;
          calls.add('start:${args['language']}');
          return null;
        default:
          return null;
      }
    });
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (_, eventSink) {
          sink = eventSink;
        },
        onCancel: (_) {
          sink = null;
        },
      ),
    );
  }

  setUp(() {
    calls = [];
    permissionGranted = true;
    grantOnRequest = true;
    available = true;
    sink = null;
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockStreamHandler(events, null);
  });

  Future<
    ({
      DictationController controller,
      TextEditingController text,
      List<String> messages,
    })
  >
  pumpButton(
    WidgetTester tester, {
    String language = '',
    String initialText = '',
  }) async {
    final text = TextEditingController(text: initialText);
    final controller = DictationController(
      PlatformSpeechRecognizer(),
      language: () => language,
    );
    final messages = <String>[];
    addTearDown(controller.dispose);
    addTearDown(text.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              Expanded(child: TextField(controller: text)),
              DictationButton(
                controller: controller,
                textController: text,
                onMessage: messages.add,
              ),
            ],
          ),
        ),
      ),
    );
    await controller.checkAvailability();
    await tester.pump();
    return (controller: controller, text: text, messages: messages);
  }

  Future<void> emit(WidgetTester tester, Map<String, Object?> event) async {
    expect(sink, isNotNull, reason: 'the recognizer is not listening');
    sink!.success(event);
    await tester.pump();
    await tester.pump();
  }

  Future<void> tapMic(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('dictation-button')));
    // Method-channel round trips and the event-channel listen resolve over
    // a few microtask turns.
    for (var i = 0; i < 4; i += 1) {
      await tester.pump();
    }
  }

  testWidgets('asks for the microphone, streams partials into the field and '
      'stops on tap', (tester) async {
    installFakeChannel();
    permissionGranted = false;
    final harness = await pumpButton(
      tester,
      language: 'pt-PT',
      initialText: 'fix the',
    );

    expect(find.byTooltip('Dictate'), findsOneWidget);
    await tapMic(tester);

    expect(calls, containsAllInOrder(['hasPermission', 'requestPermission']));
    expect(calls, contains('start:pt-PT'));
    expect(harness.controller.status, DictationStatus.starting);

    await emit(tester, {'type': 'status', 'value': 'ready'});
    expect(harness.controller.status, DictationStatus.listening);
    expect(find.byTooltip('Stop dictating'), findsOneWidget);

    await emit(tester, {'type': 'partial', 'text': 'login'});
    expect(harness.text.text, 'fix the login');
    await emit(tester, {'type': 'partial', 'text': 'login bug'});
    expect(harness.text.text, 'fix the login bug');

    await tapMic(tester);
    expect(calls.last, 'stop');
    expect(harness.controller.status, DictationStatus.finishing);
    expect(find.byTooltip('Finishing…'), findsOneWidget);

    await emit(tester, {'type': 'status', 'value': 'ended'});
    await emit(tester, {'type': 'result', 'text': 'login bug please'});
    expect(harness.text.text, 'fix the login bug please');
    expect(harness.controller.status, DictationStatus.idle);
    expect(find.byTooltip('Dictate'), findsOneWidget);
    expect(harness.messages, isEmpty);
  });

  testWidgets('a denied permission is reported and remembered', (tester) async {
    installFakeChannel();
    permissionGranted = false;
    grantOnRequest = false;
    final harness = await pumpButton(tester);

    await tapMic(tester);

    expect(calls, isNot(contains(startsWith('start'))));
    expect(harness.controller.status, DictationStatus.idle);
    expect(harness.controller.permissionDenied, isTrue);
    expect(harness.messages, ['Microphone access is needed to dictate.']);
    expect(find.byTooltip('Microphone access denied'), findsOneWidget);
  });

  testWidgets('end of speech without a final match keeps the partial text', (
    tester,
  ) async {
    installFakeChannel();
    final harness = await pumpButton(tester);

    await tapMic(tester);
    await emit(tester, {'type': 'status', 'value': 'listening'});
    await emit(tester, {'type': 'partial', 'text': 'keep this'});
    await emit(tester, {'type': 'status', 'value': 'ended'});
    await emit(tester, {'type': 'error', 'code': 7, 'message': 'No match.'});

    expect(harness.text.text, 'keep this');
    expect(harness.controller.status, DictationStatus.idle);
    expect(harness.messages, isEmpty);
  });

  testWidgets('a failure before any transcript restores the field and '
      'surfaces the message', (tester) async {
    installFakeChannel();
    final harness = await pumpButton(tester, initialText: 'draft');

    await tapMic(tester);
    await emit(tester, {'type': 'partial', 'text': 'noise'});
    await emit(tester, {
      'type': 'error',
      'code': 2,
      'message': 'Speech recognition needs a network connection.',
    });

    expect(harness.text.text, 'draft');
    expect(harness.controller.status, DictationStatus.idle);
    expect(harness.messages, [
      'Speech recognition needs a network connection.',
    ]);
  });

  testWidgets('shows a muted mic when the platform has no recognizer', (
    tester,
  ) async {
    installFakeChannel();
    available = false;
    await pumpButton(tester);

    final mic = find.byKey(const ValueKey('dictation-button'));
    expect(mic, findsOneWidget);
    expect(
      find.descendant(of: mic, matching: find.byIcon(Icons.mic_off_rounded)),
      findsOneWidget,
    );
    expect(find.byTooltip('Voice input unavailable'), findsOneWidget);
  });

  testWidgets(
    'tapping the muted mic explains and opens voice settings',
    (tester) async {
      installFakeChannel();
      available = false;
      await pumpButton(tester);

      await tapMic(tester);
      await tester.pumpAndSettle();
      expect(find.text('No speech recognizer'), findsOneWidget);
      expect(find.textContaining('Google speech services'), findsOneWidget);
      // It re-checked first, and never tried to listen.
      expect(calls.where((c) => c == 'isAvailable'), hasLength(2));
      expect(calls, isNot(contains('start')));

      await tester.tap(find.byKey(const ValueKey('speech-open-settings')));
      await tester.pumpAndSettle();
      expect(calls, contains('openSettings'));
      expect(find.text('No speech recognizer'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'offers no settings button off Android',
    (tester) async {
      installFakeChannel();
      available = false;
      await pumpButton(tester);

      await tapMic(tester);
      await tester.pumpAndSettle();
      expect(find.text('No speech recognizer'), findsOneWidget);
      expect(find.byKey(const ValueKey('speech-open-settings')), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('a recognizer installed since is used on the next tap', (
    tester,
  ) async {
    installFakeChannel();
    available = false;
    final harness = await pumpButton(tester);
    expect(harness.controller.isAvailable, isFalse);

    available = true;
    await tapMic(tester);
    expect(find.text('No speech recognizer'), findsNothing);
    expect(calls, contains('start'));
    await harness.controller.cancel();
    await tester.pump();
  });

  testWidgets('a disabled mic stays visible with its reason', (tester) async {
    installFakeChannel();
    final text = TextEditingController();
    final controller = DictationController(
      PlatformSpeechRecognizer(),
      language: () => '',
    );
    addTearDown(controller.dispose);
    addTearDown(text.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DictationButton(
            controller: controller,
            textController: text,
            enabled: false,
            disabledTooltip: 'No Claude session yet',
          ),
        ),
      ),
    );
    final button = tester.widget<IconButton>(
      find.byKey(const ValueKey('dictation-button')),
    );
    expect(button.onPressed, isNull);
    expect(find.byTooltip('No Claude session yet'), findsOneWidget);
  });

  testWidgets('autoStart starts dictating as the button appears', (
    tester,
  ) async {
    installFakeChannel();
    final text = TextEditingController();
    final controller = DictationController(
      PlatformSpeechRecognizer(),
      language: () => '',
    );
    addTearDown(controller.dispose);
    addTearDown(text.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DictationButton(
            controller: controller,
            textController: text,
            autoStart: true,
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i += 1) {
      await tester.pump();
    }
    expect(calls, contains('start'));
    expect(controller.status, isNot(DictationStatus.idle));
    await controller.cancel();
  });
}
