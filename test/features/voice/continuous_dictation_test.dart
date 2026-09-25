import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/core/theme/theme_preferences_repository.dart';
import 'package:conduit/features/voice/data/platform_speech_recognizer.dart';
import 'package:conduit/features/voice/presentation/dictation_button.dart';
import 'package:conduit/features/voice/presentation/dictation_controller.dart';
import 'package:conduit/features/voice/presentation/voice_settings_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('conduit/speech');
  const events = EventChannel('conduit/speech_events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> calls;
  late List<Map<Object?, Object?>> starts;
  MockStreamHandlerEventSink? sink;

  // Installed inside each test body: handlers registered in setUp run
  // outside the test's fake-async zone and deliver events too late.
  void installFakeChannel() {
    calls = [];
    starts = [];
    sink = null;
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'isAvailable':
        case 'hasPermission':
          return true;
        case 'start':
          starts.add(call.arguments as Map<Object?, Object?>);
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

  tearDown(() {
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockStreamHandler(events, null);
  });

  test('joinDictation spaces phrases and keeps punctuation attached', () {
    expect(joinDictation('', 'hello'), 'hello');
    expect(joinDictation('hello', 'world'), 'hello world');
    expect(joinDictation('hello ', '  world '), 'hello world');
    expect(joinDictation('hello', ', world'), 'hello, world');
    expect(joinDictation('done', '.'), 'done.');
    expect(joinDictation('keep', ''), 'keep');
  });

  group('continuous session', () {
    late DictationController controller;
    late List<String> partials;
    late List<String> finished;
    late int cancelled;
    late DictationSink dictationSink;

    Future<void> emit(WidgetTester tester, Map<String, Object?> event) async {
      expect(sink, isNotNull);
      sink!.success(event);
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
    }

    Future<void> begin(
      WidgetTester tester, {
      Duration silence = const Duration(seconds: 8),
      Duration maxSession = const Duration(minutes: 5),
    }) async {
      installFakeChannel();
      await tester.pumpWidget(const SizedBox());
      partials = [];
      finished = [];
      cancelled = 0;
      controller = DictationController(
        PlatformSpeechRecognizer(),
        language: () => 'pt-PT',
        options: () => DictationOptions(
          continuous: true,
          silenceTimeout: silence,
          maxSession: maxSession,
        ),
      );
      addTearDown(controller.dispose);
      dictationSink = DictationSink(
        onBegin: () {},
        onPartial: partials.add,
        onFinish: finished.add,
        onCancel: () => cancelled += 1,
      );
      await controller.start(dictationSink);
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      await emit(tester, {'type': 'status', 'value': 'ready'});
    }

    testWidgets('restarts after each phrase and stitches the text', (
      tester,
    ) async {
      await begin(tester);
      expect(starts.single['continuous'], isTrue);
      expect(starts.single['restart'], isFalse);
      expect(starts.single['completeSilenceMillis'], 4000);
      expect(starts.single['minimumLengthMillis'], 10000);
      expect(controller.status, DictationStatus.listening);

      await emit(tester, {'type': 'status', 'value': 'listening'});
      await emit(tester, {'type': 'partial', 'text': 'fix the'});
      expect(partials.last, 'fix the');
      await emit(tester, {'type': 'status', 'value': 'ended'});
      expect(controller.status, DictationStatus.listening);
      await emit(tester, {'type': 'result', 'text': 'fix the login'});
      expect(partials.last, 'fix the login');
      expect(starts, hasLength(2));
      expect(starts.last['restart'], isTrue);
      expect(finished, isEmpty);

      // Silence ends a phrase with "no match": keep going.
      await emit(tester, {'type': 'error', 'code': 7, 'message': 'No match'});
      expect(starts, hasLength(3));
      await emit(tester, {'type': 'status', 'value': 'ready'});

      await emit(tester, {'type': 'partial', 'text': 'bug'});
      expect(partials.last, 'fix the login bug');
      // A speech timeout after a partial keeps the partial.
      await emit(tester, {'type': 'error', 'code': 6, 'message': 'Timeout'});
      expect(partials.last, 'fix the login bug');
      expect(starts, hasLength(4));

      await emit(tester, {'type': 'partial', 'text': ', please'});
      await controller.stop();
      await tester.pump();
      expect(calls.last, 'stop');
      expect(controller.status, DictationStatus.finishing);
      await emit(tester, {'type': 'result', 'text': ', please'});
      expect(finished, ['fix the login bug, please']);
      expect(controller.status, DictationStatus.idle);
      expect(calls.last, 'cancel', reason: 'releases the kept recognizer');
      expect(starts, hasLength(4), reason: 'no restart after a stop');
      expect(controller.pause, isNull);
    });

    testWidgets('pauses itself after the configured silence', (tester) async {
      await begin(tester, silence: const Duration(seconds: 3));
      await emit(tester, {'type': 'partial', 'text': 'hello'});
      await tester.pump(const Duration(seconds: 2));
      await emit(tester, {'type': 'partial', 'text': 'hello there'});
      await tester.pump(const Duration(seconds: 2));
      expect(controller.status, DictationStatus.listening);
      await tester.pump(const Duration(seconds: 2));
      expect(controller.status, DictationStatus.finishing);
      expect(controller.pause, DictationPause.silence);
      expect(controller.message, contains('Tap the mic to continue'));
      await emit(tester, {'type': 'result', 'text': 'hello there'});
      expect(finished, ['hello there']);
      expect(controller.status, DictationStatus.idle);
    });

    testWidgets('stops at the maximum session length', (tester) async {
      await begin(
        tester,
        silence: const Duration(seconds: 60),
        maxSession: const Duration(minutes: 1),
      );
      for (var i = 0; i < 12; i++) {
        await emit(tester, {'type': 'partial', 'text': 'word $i'});
        await tester.pump(const Duration(seconds: 5));
      }
      expect(controller.pause, DictationPause.maxSession);
      // No result arrives: the stop does not wait forever.
      await tester.pump(const Duration(seconds: 4));
      expect(controller.status, DictationStatus.idle);
      expect(finished.single, 'word 11');
    });

    testWidgets('a busy recognizer on restart is retried', (tester) async {
      await begin(tester);
      await emit(tester, {'type': 'result', 'text': 'one'});
      expect(starts, hasLength(2));
      await emit(tester, {'type': 'error', 'code': 8, 'message': 'Busy'});
      await tester.pump(const Duration(milliseconds: 300));
      expect(starts, hasLength(3));
      expect(starts.last['restart'], isFalse, reason: 'a fresh recognizer');
      await emit(tester, {'type': 'status', 'value': 'ready'});
      await emit(tester, {'type': 'result', 'text': 'two'});
      expect(partials.last, 'one two');
      await controller.cancel();
      expect(finished, ['one two']);
    });

    testWidgets('a hard error keeps what was already said', (tester) async {
      await begin(tester);
      await emit(tester, {'type': 'result', 'text': 'keep me'});
      await emit(tester, {'type': 'status', 'value': 'ready'});
      await emit(tester, {
        'type': 'error',
        'code': 2,
        'message': 'Speech recognition needs a network connection.',
      });
      expect(finished, ['keep me']);
      expect(cancelled, 0);
      expect(controller.message, contains('network'));
    });

    testWidgets('stopping between phrases finishes at once', (tester) async {
      await begin(tester);
      await emit(tester, {'type': 'result', 'text': 'quick'});
      await controller.stop();
      await tester.pump(const Duration(milliseconds: 1));
      expect(finished, ['quick']);
      expect(controller.status, DictationStatus.idle);
    });
  });

  testWidgets('the mic follows Settings and shows the paused state', (
    tester,
  ) async {
    installFakeChannel();
    final settings = ThemeController(
      ThemePreferencesRepository(InMemorySecureStorage()),
    );
    await settings.load();
    await settings.setVoice(
      settings.voice.copyWith(dictationSilenceSeconds: 3),
    );
    final text = TextEditingController(text: 'note:');
    addTearDown(text.dispose);
    final controller = DictationController(
      PlatformSpeechRecognizer(),
      language: () => '',
    );
    addTearDown(controller.dispose);
    final messages = <String>[];
    await tester.pumpWidget(
      VoiceSettingsScope(
        settings: settings,
        child: MaterialApp(
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
      ),
    );
    await tester.tap(find.byKey(const ValueKey('dictation-button')));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    expect(starts.single['continuous'], isTrue);
    await tester.pump();
    sink!.success({'type': 'status', 'value': 'ready'});
    await tester.pump();
    await tester.pump();
    sink!.success({'type': 'level', 'value': 0.8});
    await tester.pump();
    expect(find.byKey(const ValueKey('dictation-pulse')), findsOneWidget);
    await tester.pump();
    sink!.success({'type': 'result', 'text': 'first'});
    await tester.pump();
    await tester.pump();
    sink!.success({'type': 'partial', 'text': 'second'});
    await tester.pump();
    expect(text.text, 'note: first second');

    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 4));
    expect(controller.status, DictationStatus.idle);
    expect(text.text, 'note: first second');
    expect(find.byTooltip('Paused, tap to continue'), findsOneWidget);
    expect(messages.single, contains('Paused after 3 s of silence'));
  });
}
