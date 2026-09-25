import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/core/theme/theme_preferences_repository.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/chat_view/presentation/chat_view_controller.dart';
import 'package:conduit/features/chat_view/presentation/chat_view_page.dart';
import 'package:conduit/features/voice/presentation/voice_settings_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';
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
    List<Object> script,
  ) async {
    final controller = ChatViewController(
      runner: ScriptedAgentCommandRunner(script),
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
}
