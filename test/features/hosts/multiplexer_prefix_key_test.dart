import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/hosts/presentation/widgets/multiplexer_prefix_picker.dart';
import 'package:conduit_vt/conduit_vt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

void main() {
  group('MultiplexerPrefixKey', () {
    test('encodes modifiers in a fixed order and decodes them back', () {
      const combos = [
        MultiplexerPrefixKey.controlB,
        MultiplexerPrefixKey.controlA,
        MultiplexerPrefixKey.controlSpace,
        MultiplexerPrefixKey(key: 'x', alt: true),
        MultiplexerPrefixKey(key: 'x', ctrl: true, alt: true, shift: true),
        MultiplexerPrefixKey(key: '`'),
        MultiplexerPrefixKey(key: '-', ctrl: true),
        MultiplexerPrefixKey(key: '7', alt: true),
      ];
      for (final combo in combos) {
        expect(MultiplexerPrefixKey.decode(combo.encode()), combo);
      }
      expect(MultiplexerPrefixKey.controlSpace.encode(), 'ctrl+space');
      expect(
        const MultiplexerPrefixKey(
          key: 'x',
          ctrl: true,
          alt: true,
          shift: true,
        ).encode(),
        'ctrl+alt+shift+x',
      );
    });

    test('still loads the enum names hosts were saved with', () {
      expect(
        MultiplexerPrefixKey.decode('controlB'),
        MultiplexerPrefixKey.controlB,
      );
      expect(
        MultiplexerPrefixKey.decode('controlA'),
        MultiplexerPrefixKey.controlA,
      );
    });

    test('accepts human spellings and rejects garbage', () {
      expect(
        MultiplexerPrefixKey.decode('Ctrl+Space'),
        MultiplexerPrefixKey.controlSpace,
      );
      expect(
        MultiplexerPrefixKey.decode('control+B'),
        MultiplexerPrefixKey.controlB,
      );
      expect(
        MultiplexerPrefixKey.decode('meta+a'),
        const MultiplexerPrefixKey(key: 'a', alt: true),
      );
      expect(MultiplexerPrefixKey.tryDecode(''), isNull);
      expect(MultiplexerPrefixKey.tryDecode('ctrl+'), isNull);
      expect(MultiplexerPrefixKey.tryDecode('hyper+b'), isNull);
      expect(MultiplexerPrefixKey.tryDecode('ctrl+f12'), isNull);
      expect(MultiplexerPrefixKey.decode(null), MultiplexerPrefixKey.defaultKey);
      expect(
        MultiplexerPrefixKey.decode('nonsense'),
        MultiplexerPrefixKey.defaultKey,
      );
    });

    test('labels read like keyboard shortcuts', () {
      expect(MultiplexerPrefixKey.controlB.label, 'Ctrl+B');
      expect(MultiplexerPrefixKey.controlSpace.label, 'Ctrl+Space');
      expect(
        const MultiplexerPrefixKey(key: 'x', alt: true, shift: true).label,
        'Alt+Shift+X',
      );
      expect(const MultiplexerPrefixKey(key: '`').label, '`');
    });

    test('resolves the terminal key and control-key fast path', () {
      expect(MultiplexerPrefixKey.controlB.terminalKey, TerminalKey.keyB);
      expect(MultiplexerPrefixKey.controlB.controlKey, TerminalKey.keyB);
      expect(MultiplexerPrefixKey.controlSpace.controlKey, TerminalKey.space);
      expect(
        const MultiplexerPrefixKey(key: '[', ctrl: true).terminalKey,
        TerminalKey.bracketLeft,
      );
      expect(
        const MultiplexerPrefixKey(key: '[', ctrl: true).controlKey,
        isNull,
      );
      expect(const MultiplexerPrefixKey(key: 'a', alt: true).controlKey, isNull);
      expect(
        const MultiplexerPrefixKey(key: 'a', ctrl: true, shift: true).controlKey,
        isNull,
      );
    });

    test('computes the raw bytes for transports that bypass the terminal', () {
      expect(MultiplexerPrefixKey.controlB.bytes, [0x02]);
      expect(MultiplexerPrefixKey.controlA.bytes, [0x01]);
      expect(MultiplexerPrefixKey.controlSpace.bytes, [0x00]);
      expect(const MultiplexerPrefixKey(key: 'a', alt: true).bytes, [
        0x1b,
        0x61,
      ]);
      expect(
        const MultiplexerPrefixKey(key: 'a', alt: true, shift: true).bytes,
        [0x1b, 0x41],
      );
      expect(const MultiplexerPrefixKey(key: 'a', ctrl: true, alt: true).bytes, [
        0x1b,
        0x01,
      ]);
      expect(const MultiplexerPrefixKey(key: '[', ctrl: true).bytes, [0x1b]);
      expect(const MultiplexerPrefixKey(key: '`').bytes, [0x60]);
      expect(const MultiplexerPrefixKey(key: ';', ctrl: true).bytes, [0x3b]);
    });
  });

  group('SavedHost multiplexer prefix', () {
    test('round-trips a custom prefix through JSON', () {
      final host = buildHost(
        'p',
      ).copyWith(tmuxPrefixKey: MultiplexerPrefixKey.controlSpace);
      final json = host.toJson();
      expect(json['tmuxPrefixKey'], 'ctrl+space');
      expect(
        SavedHost.fromJson(json).tmuxPrefixKey,
        MultiplexerPrefixKey.controlSpace,
      );
    });

    test('loads hosts saved with the old enum name', () {
      final json = buildHost('p').toJson()..['tmuxPrefixKey'] = 'controlA';
      expect(
        SavedHost.fromJson(json).tmuxPrefixKey,
        MultiplexerPrefixKey.controlA,
      );
    });
  });

  group('MultiplexerPrefixField', () {
    testWidgets('composes a prefix from modifier and key chips', (
      tester,
    ) async {
      final picked = <MultiplexerPrefixKey>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiplexerPrefixField(
              value: MultiplexerPrefixKey.controlB,
              onChanged: picked.add,
            ),
          ),
        ),
      );
      expect(find.text('Ctrl+B'), findsOneWidget);
      expect(find.text('Multiplexer prefix (tmux/Herdr)'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('multiplexer-prefix-field')));
      await tester.pumpAndSettle();
      expect(find.text('Multiplexer prefix'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('prefix-key-space')),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const ValueKey('prefix-key-space')));
      await tester.pumpAndSettle();
      expect(find.text('Use Ctrl+Space'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('prefix-mod-alt')),
        -120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('prefix-mod-alt')));
      await tester.pumpAndSettle();
      expect(find.text('Use Ctrl+Alt+Space'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('prefix-mod-ctrl')));
      await tester.pumpAndSettle();
      expect(find.text('Use Alt+Space'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('prefix-key-x')),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('prefix-key-x')));
      await tester.pumpAndSettle();
      expect(find.text('Use Alt+X'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('prefix-save')));
      await tester.pumpAndSettle();
      expect(picked, [const MultiplexerPrefixKey(key: 'x', alt: true)]);
    });

    testWidgets('presets pick a whole combination and cancel keeps the '
        'old value', (tester) async {
      final picked = <MultiplexerPrefixKey>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiplexerPrefixField(
              value: MultiplexerPrefixKey.controlB,
              onChanged: picked.add,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('multiplexer-prefix-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('prefix-preset-ctrl+space')));
      await tester.pumpAndSettle();
      expect(find.text('Use Ctrl+Space'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(picked, isEmpty);
      expect(find.text('Ctrl+B'), findsOneWidget);
    });
  });
}
