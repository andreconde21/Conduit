import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/chat_view/presentation/chat_view_controller.dart';
import 'package:conduit/features/chat_view/presentation/chat_view_page.dart';
import 'package:conduit/features/share_target/domain/shared_payload.dart';
import 'package:conduit/features/terminal/domain/prompt_image.dart';
import 'package:conduit/features/terminal/presentation/widgets/prompt_composer_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

class _Source implements PromptImageSource {
  _Source(this.image);

  final SharedFile? image;

  @override
  Future<SharedFile?> pick(PromptImageOrigin origin) async => image;
}

PromptImageAttacher _attacher(SharedFile? image, List<String> uploads) =>
    PromptImageAttacher(
      source: _Source(image),
      crop: (image) async => fullImageCrop,
      prepare: (image, crop) async => image,
      upload: (image) async {
        uploads.add(image.name);
        return '/home/u/conductore-inbox/image-20260925-143005.png';
      },
    );

const _image = SharedFile(path: '/c/clipboard.png', name: 'clipboard.png');

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') return {'text': 'hello'};
          if (call.method == 'Clipboard.hasStrings') return {'value': true};
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('Chat View: "Paste image" in the field menu inserts the '
      'uploaded path', (tester) async {
    final uploads = <String>[];
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
          initialDraft: 'Look at',
          imageAttacher: _attacher(_image, uploads),
          clipboardHasImage: () async => true,
        ),
      ),
    );
    await tester.pump();
    final field = find.byKey(const ValueKey('chat-composer-field'));
    await tester.tap(field);
    await tester.pump();
    await tester.longPress(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste image'));
    await tester.pumpAndSettle();
    expect(uploads, ['clipboard.png']);
    expect(
      tester.widget<TextField>(field).controller!.text,
      'Look at /home/u/conductore-inbox/image-20260925-143005.png ',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Chat View: no "Paste image" without an image', (tester) async {
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
          initialDraft: 'x',
          imageAttacher: _attacher(_image, []),
          clipboardHasImage: () async => false,
        ),
      ),
    );
    await tester.pump();
    final field = find.byKey(const ValueKey('chat-composer-field'));
    await tester.tap(field);
    await tester.pump();
    await tester.longPress(field);
    await tester.pumpAndSettle();
    expect(find.text('Paste image'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  Future<TextEditingController> openSheet(
    WidgetTester tester,
    PromptImageAttacher attacher, {
    bool pasteImages = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showPromptComposerSheet(
              context: context,
              initialText: '',
              onDraftChanged: (_) {},
              onSend: (text, {required submit}) async {},
              submitEnter: false,
              onSubmitEnterChanged: (_) {},
              isConnected: () => true,
              imageAttacher: attacher,
              pasteImages: pasteImages,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Paste clipboard'));
    await tester.pumpAndSettle();
    return tester
        .widget<TextField>(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(TextField),
          ),
        )
        .controller!;
  }

  testWidgets('Chat mode composer: Paste puts an image in as its path', (
    tester,
  ) async {
    final uploads = <String>[];
    final text = await openSheet(tester, _attacher(_image, uploads));
    expect(uploads, ['clipboard.png']);
    expect(text.text, '/home/u/conductore-inbox/image-20260925-143005.png ');
  });

  testWidgets('Chat mode composer: Paste without an image pastes text', (
    tester,
  ) async {
    final uploads = <String>[];
    final text = await openSheet(tester, _attacher(null, uploads));
    expect(uploads, isEmpty);
    expect(text.text, 'hello');
  });

  testWidgets('Chat mode composer: the setting off keeps Paste text-only', (
    tester,
  ) async {
    final uploads = <String>[];
    final text = await openSheet(
      tester,
      _attacher(_image, uploads),
      pasteImages: false,
    );
    expect(uploads, isEmpty);
    expect(text.text, 'hello');
  });
}
