import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/core/theme/theme_preferences_repository.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/chat_view/presentation/chat_view_controller.dart';
import 'package:conduit/features/chat_view/presentation/chat_view_page.dart';
import 'package:conduit/features/voice/domain/speech_event.dart';
import 'package:conduit/features/voice/presentation/dictation_controller.dart';
import 'package:conduit/features/voice/presentation/voice_settings_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';
import '../voice/fake_speech_recognizer.dart';
import '../voice/fake_tts.dart';
import 'chat_fixtures.dart';

AgentCommandResult ok(String stdout) =>
    AgentCommandResult(stdout: stdout, stderr: '', exitCode: 0);

void main() {
  late FakeTts tts;
  late ThemeController settings;

  setUp(() async {
    tts = FakeTts();
    settings = ThemeController(
      ThemePreferencesRepository(InMemorySecureStorage()),
    );
    await settings.load();
  });

  Future<ChatViewController> pumpPage(
    WidgetTester tester,
    List<Object> script, {
    DictationController? dictation,
    ScriptedAgentCommandRunner? runner,
  }) async {
    final controller = ChatViewController(
      runner: runner ?? ScriptedAgentCommandRunner(script),
      sessionId: 's-1',
      pollInterval: const Duration(days: 1),
    );
    await tester.pumpWidget(
      VoiceSettingsScope(
        settings: settings,
        child: MaterialApp(
          home: ChatViewPage(
            controller: controller,
            onOpenTerminal: () {},
            textToSpeech: tts,
            dictation: dictation,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    return controller;
  }

  final history = [
    userLine('u1', 'hello'),
    assistantLine('a1', [text('An old answer.')]),
  ];

  testWidgets('the speaker toggle reads only new replies and is remembered '
      'per session', (tester) async {
    final chat = await pumpPage(tester, [
      ok(page(history)),
      ok(
        page([
          assistantLine('a2', [
            toolUse('t1', 'Bash', {'command': 'ls'}),
            toolUse('t2', 'Bash', {'command': 'pwd'}),
            text('All **done**, see `todos.ts`.'),
          ]),
        ], offset: 200),
      ),
    ]);
    final toggle = find.byKey(const ValueKey('chat-read-aloud'));
    expect(toggle, findsOneWidget);
    expect(find.byTooltip('Read replies aloud'), findsOneWidget);

    await tester.tap(toggle);
    await tester.pump();
    expect(find.byTooltip('Stop reading replies aloud'), findsOneWidget);
    expect(settings.voice.readAloudFor('s-1'), isTrue);
    expect(settings.voice.readAloudFor('other'), isFalse);
    expect(tts.spoken, isEmpty, reason: 'history is never read');

    await chat.refresh();
    await tester.pump();
    // Only the turn's final answer; the commands are never read.
    expect(tts.spoken, ['All done, see todos.ts.']);

    await tester.tap(toggle);
    await tester.pump();
    expect(tts.stops, 1, reason: 'turning it off stops at once');
    expect(settings.voice.readAloudFor('s-1'), isFalse);
  });

  testWidgets('the default setting turns it on and sending stops speech', (
    tester,
  ) async {
    await settings.setVoice(settings.voice.copyWith(readAloudByDefault: true));
    final chat = await pumpPage(tester, [
      ok(page(history)),
      ok(
        page([
          assistantLine('a2', [text('First reply.'), text('Second reply.')]),
        ], offset: 200),
      ),
      ok('{"ok":true}'),
      ok(page([], offset: 200)),
    ]);
    expect(find.byTooltip('Stop reading replies aloud'), findsOneWidget);

    await chat.refresh();
    await tester.pump();
    expect(tts.spoken, ['First reply. Second reply.']);

    await tester.enterText(
      find.byKey(const ValueKey('chat-composer-field')),
      'go on',
    );
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(tts.stops, 1);
    tts.done();
    await tester.pump();
    expect(tts.spoken, ['First reply. Second reply.']);
  });

  testWidgets('announces approvals', (tester) async {
    await settings.setVoice(settings.voice.copyWith(readAloudByDefault: true));
    final chat = await pumpPage(tester, [
      ok(page(history)),
      ok(
        page(
          [],
          offset: 200,
          state: 'needs_permission',
          pending: [
            {'id': 'req-1', 'toolName': 'Bash', 'summary': 'npm test'},
          ],
        ),
      ),
    ]);
    await chat.refresh();
    await tester.pump();
    expect(tts.spoken, ['Claude needs your approval to run npm test.']);
  });

  testWidgets('screen off keeps reading; leaving the app stops', (
    tester,
  ) async {
    await settings.setVoice(settings.voice.copyWith(readAloudByDefault: true));
    final chat = await pumpPage(tester, [
      ok(page(history)),
      ok(
        page([
          assistantLine('a2', [text('Hi.')]),
        ], offset: 200),
      ),
    ]);
    await chat.refresh();
    await tester.pump();
    expect(tts.spoken, ['Hi.']);

    tts.interactive = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(tts.stops, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    tts.interactive = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(tts.stops, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });

  testWidgets('Talk: speak, auto-send, stay quiet, hear the answer, touch '
      'to stop', (tester) async {
    await settings.setVoice(settings.voice.copyWith(talkSendSilenceSeconds: 2));
    final mic = FakeSpeechRecognizer();
    final dictation = DictationController(mic, language: () => 'en-US');
    addTearDown(dictation.dispose);
    final runner = ScriptedAgentCommandRunner([
      ok(page(history)),
      ok('{"ok":true}'), // send
      ok(
        page([userLine('u2', 'run the tests')], offset: 200, state: 'working'),
      ),
      ok(
        page([
          assistantLine('a2', [text('All green.')]),
        ], offset: 300),
      ),
    ]);
    final chat = await pumpPage(
      tester,
      const [],
      dictation: dictation,
      runner: runner,
    );

    await tester.tap(find.byKey(const ValueKey('chat-talk')));
    await tester.pump();
    expect(find.byKey(const ValueKey('talk-panel')), findsOneWidget);
    expect(find.text('Listening…'), findsOneWidget);

    mic.say('run the tests');
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const ValueKey('talk-countdown')), findsOneWidget);
    expect(find.text('run the tests'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(runner.commands.any((c) => c.contains('send s-1')), isTrue);
    await tester.pump();
    expect(find.text('Claude is working…'), findsOneWidget);

    // Sending polled at once: Claude works, nothing is read.
    expect(tts.spoken, isEmpty);
    await chat.refresh(); // Turn over: the final answer is read.
    await tester.pump();
    expect(tts.spoken, ['All green.']);
    tts.done();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Listening…'), findsOneWidget);

    // Speaking, then touching the thread: the loop ends and what was
    // said goes to the composer.
    mic.emit(const SpeechPartial('and deploy'));
    await tester.pump();
    await tester.tapAt(const Offset(200, 200));
    await tester.pump();
    expect(find.byKey(const ValueKey('talk-panel')), findsNothing);
    final field = find.byKey(const ValueKey('chat-composer-field'));
    expect(tester.widget<TextField>(field).controller!.text, 'and deploy');
    await tester.pump(const Duration(seconds: 5));
  });
}
