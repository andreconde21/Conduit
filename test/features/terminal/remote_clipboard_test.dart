import 'dart:convert';

import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/core/theme/theme_preferences_repository.dart';
import 'package:conduit/features/terminal/domain/osc52_clipboard.dart';
import 'package:conduit/features/terminal/presentation/terminal_page.dart';
import 'package:conduit/features/terminal/presentation/terminal_session_controller.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../../support/test_doubles.dart';

class _NoopWakelock extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}

  @override
  Future<bool> get enabled async => false;
}

String _osc52(String text, {String terminator = '\x07'}) =>
    '\x1b]52;c;${base64.encode(utf8.encode(text))}$terminator';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WakelockPlusPlatformInterface.instance = _NoopWakelock();

  group('decodeOsc52Payload', () {
    test('decodes the clipboard selection', () {
      final data = base64.encode(utf8.encode('héllo\nworld'));
      expect(decodeOsc52Payload(['c', data]), 'héllo\nworld');
    });

    test('tolerates a missing selection and missing padding', () {
      expect(decodeOsc52Payload(['aGk']), 'hi');
      expect(decodeOsc52Payload(['', 'aGk=']), 'hi');
    });

    test('ignores read requests, clears and garbage', () {
      expect(decodeOsc52Payload(['c', '?']), isNull);
      expect(decodeOsc52Payload(['c', '']), isNull);
      expect(decodeOsc52Payload([]), isNull);
      expect(decodeOsc52Payload(['c', '!!not base64!!']), isNull);
    });

    test('caps the decoded size', () {
      final data = base64.encode(List<int>.filled(11, 0x41));
      expect(decodeOsc52Payload(['c', data], maxBytes: 10), isNull);
      expect(decodeOsc52Payload(['c', data], maxBytes: 11), 'A' * 11);
      final big = base64.encode(List<int>.filled(osc52MaxBytes + 1, 0x41));
      expect(decodeOsc52Payload(['c', big]), isNull);
    });
  });

  group('TerminalSessionController OSC 52', () {
    test('emits copies ended by BEL or ST and skips read requests', () async {
      final controller = TerminalSessionController(
        host: buildHost('osc'),
        repository: ImmediateTerminalRepository(TrackableTerminalSession()),
      );
      addTearDown(controller.dispose);
      final copies = <String>[];
      controller.remoteClipboardWrites.listen(copies.add);

      controller.terminal.write('before ${_osc52('one')} after');
      controller.terminal.write(_osc52('two', terminator: '\x1b\\'));
      controller.terminal.write('\x1b]52;c;?\x07');
      await Future<void>.delayed(Duration.zero);

      expect(copies, ['one', 'two']);
      // The sequence itself never shows up as text.
      expect(controller.terminal.buffer.lines[0].getText(), 'before  after');
    });

    test('handles a sequence split across writes', () async {
      final controller = TerminalSessionController(
        host: buildHost('osc-split'),
        repository: ImmediateTerminalRepository(TrackableTerminalSession()),
      );
      addTearDown(controller.dispose);
      final copies = <String>[];
      controller.remoteClipboardWrites.listen(copies.add);

      final sequence = _osc52('split payload');
      controller.terminal.write(sequence.substring(0, 12));
      controller.terminal.write(sequence.substring(12));
      await Future<void>.delayed(Duration.zero);

      expect(copies, ['split payload']);
    });
  });

  test('the remote clipboard setting defaults on and persists', () async {
    final storage = InMemorySecureStorage();
    final repository = ThemePreferencesRepository(storage);
    expect((await repository.load()).remoteClipboardEnabled, isTrue);
    await repository.save(
      const ThemePreferences(
        themeMode: ThemeMode.dark,
        palette: AppPalette.everforest,
        remoteClipboardEnabled: false,
      ),
    );
    expect((await repository.load()).remoteClipboardEnabled, isFalse);
  });

  testWidgets('the terminal page copies OSC 52 text and says from where, '
      'unless the setting is off', (tester) async {
    final clipboard = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final workspace = TerminalWorkspaceController(
      ImmediateTerminalRepository(TrackableTerminalSession()),
    );
    addTearDown(workspace.dispose);
    final themeController = ThemeController(InMemoryThemePreferences());
    final session = workspace.open(buildHost('devbox'));
    await tester.runAsync(session.connect);

    await tester.pumpWidget(
      MaterialApp(
        home: TerminalPage(
          workspace: workspace,
          themeController: themeController,
          sftpRepository: NoNetworkSftpRepository(),
        ),
      ),
    );
    await tester.pump();

    session.terminal.write(_osc52('git log --oneline'));
    await tester.pump();
    await tester.pump();

    expect(clipboard, ['git log --oneline']);
    expect(find.text('Copied from Host devbox'), findsOneWidget);

    await themeController.setRemoteClipboardEnabled(false);
    session.terminal.write(_osc52('secret'));
    await tester.pump();

    expect(clipboard, ['git log --oneline']);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
  });
}
