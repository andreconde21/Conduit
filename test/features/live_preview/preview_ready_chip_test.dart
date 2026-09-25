import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/chat_view/presentation/chat_view_controller.dart';
import 'package:conduit/features/chat_view/presentation/chat_view_page.dart';
import 'package:conduit/features/live_preview/domain/dev_server_detection.dart';
import 'package:conduit/features/live_preview/presentation/preview_ready_chip.dart';
import 'package:conduit/features/live_preview/presentation/preview_ready_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

PreviewReadyController _controller() => PreviewReadyController(
  runnerFactory: () => ScriptedAgentCommandRunner([
    const AgentCommandResult(stdout: '', stderr: '', exitCode: 1),
  ]),
);

void main() {
  testWidgets('hidden without an offer, shows one, opens and dismisses', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    final opened = <DevServerOffer>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PreviewReadyChip(controller: controller, onOpen: opened.add),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('preview-ready-chip')), findsNothing);

    controller.scanScreen([
      '  VITE v5.1.0',
      '  ➜  Local:   http://localhost:5173/',
    ]);
    await tester.pump();
    expect(find.text('Preview ready · :5173 · vite'), findsOneWidget);

    await tester.tap(find.text('Preview ready · :5173 · vite'));
    await tester.pump();
    expect(opened.single.port, 5173);
    expect(opened.single.path, '/');
    expect(find.byKey(const ValueKey('preview-ready-chip')), findsNothing);

    controller.scanScreen(['Local: http://localhost:4321/blog']);
    await tester.pump();
    expect(find.text('Preview ready · :4321'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('preview-ready-dismiss')));
    await tester.pump();
    expect(find.byKey(const ValueKey('preview-ready-chip')), findsNothing);
    expect(opened, hasLength(1));
    expect(controller.handledPorts, {5173, 4321});
  });

  testWidgets('stays hidden while Live preview already shows the port', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    controller.scanScreen(['Local: http://localhost:3000/']);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PreviewReadyChip(
            controller: controller,
            onOpen: (_) {},
            hidden: (offer) => offer.port == 3000,
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('preview-ready-chip')), findsNothing);
  });

  testWidgets('Chat View shows the accessory and starts with the draft', (
    tester,
  ) async {
    final chat = ChatViewController(
      runner: ScriptedAgentCommandRunner([
        const AgentCommandResult(stdout: '{}', stderr: '', exitCode: 0),
      ]),
      sessionId: 's-1',
      pollInterval: const Duration(days: 1),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ChatViewPage(
          controller: chat,
          onOpenTerminal: () {},
          accessory: const Text('chip here'),
          initialDraft: '~/.conductore/inbox/shot.png ',
        ),
      ),
    );
    await tester.pump();
    expect(find.text('chip here'), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('chat-composer-field')),
    );
    expect(field.controller!.text, '~/.conductore/inbox/shot.png ');
    await tester.pumpWidget(const SizedBox());
  });
}
