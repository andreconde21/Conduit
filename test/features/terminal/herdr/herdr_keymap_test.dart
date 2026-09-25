import 'dart:io';

import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/hosts/domain/multiplexer_prefix_key.dart';
import 'package:conduit/features/terminal/domain/herdr_keymap.dart';
import 'package:conduit_vt/conduit_vt.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_herdr_runner.dart';

String _fixture(String name) =>
    File('test/features/terminal/herdr/fixtures/$name').readAsStringSync();

/// Records what [HerdrKeySender] types, like the terminal tests do.
List<String> _typed(HerdrKeyBinding binding, {MultiplexerPrefixKey? prefix}) {
  final log = <String>[];
  HerdrKeySender.send(
    binding,
    prefix: prefix ?? MultiplexerPrefixKey.controlB,
    sendPrefix: (prefix) => log.add('prefix:${prefix.encode()}'),
    sendText: (text) => log.add('text:$text'),
    sendKey: (key) => log.add('key:${key.name}'),
    sendControl: (key) => log.add('ctrl:${key.name}'),
  );
  return log;
}

void main() {
  group('HerdrKeymap', () {
    test('the defaults are Herdr 0.9.1\'s documented keymap', () {
      final keymap = HerdrKeymap.defaults;
      expect(keymap.bindingFor('detach')!.label('Ctrl+B'), 'Ctrl+B q');
      expect(
        keymap.bindingFor('workspace_picker')!.label('Ctrl+B'),
        'Ctrl+B w',
      );
      expect(keymap.bindingFor('close_tab')!.label('Ctrl+B'), 'Ctrl+B Shift+X');
      expect(
        keymap.bindingFor('split_horizontal')!.label('Ctrl+B'),
        'Ctrl+B -',
      );
      expect(keymap.bindingFor('focus_pane_left')!.label('Ctrl+B'), 'Ctrl+B h');
      expect(keymap.switchTabWithPrefix, isTrue);
      expect(keymap.fromHost, isFalse);
    });

    test('reads the dev-central config over the defaults', () {
      final keymap = HerdrKeymap.parseConfig(
        _fixture('herdr_config_dev_central.toml'),
      );
      expect(keymap.fromHost, isTrue);
      expect(keymap.prefix, MultiplexerPrefixKey.controlSpace);
      String label(String action) =>
          keymap.bindingFor(action)!.label('Ctrl+Space');
      expect(label('detach'), 'Ctrl+Space d');
      expect(label('workspace_picker'), 'Ctrl+Space f');
      expect(label('goto'), 'Ctrl+Space g');
      expect(label('zoom'), 'Ctrl+Space z');
      expect(label('close_pane'), 'Ctrl+Space x');
      expect(label('close_tab'), 'Ctrl+Space k');
      expect(label('new_workspace'), 'Ctrl+Space Shift+C');
      // prefix+h splits here; pane focus is a direct chord.
      expect(label('split_horizontal'), 'Ctrl+Space h');
      expect(label('focus_pane_left'), 'Ctrl+Alt+Left');
      expect(keymap.bindingFor('focus_pane_left')!.prefixed, isFalse);
      // Array values: the prefix binding is the one sent.
      expect(label('next_tab'), 'Ctrl+Space n');
      expect(keymap.bindingsFor('next_tab'), hasLength(2));
      expect(keymap.switchTabWithPrefix, isTrue);
      // Untouched actions keep their defaults.
      expect(label('toggle_sidebar'), 'Ctrl+Space b');
      // The [[keys.command]] table after [keys] is not read as bindings.
      expect(keymap.bindingsFor('key'), isEmpty);
    });

    test('handles comments, multi-line arrays, unset and odd values', () {
      final keymap = HerdrKeymap.parseConfig('''
[theme]
detach = "prefix+t"   # not in [keys]

[keys]
prefix = "f12"        # not a key the app can send: host prefix is used
detach = "prefix+shift+q" # trailing comment with "quotes"
goto = [
  "cmd+g",
  "prefix+j",
]
zoom = ""
switch_tab = ""
help = 'prefix+?'
''');
      expect(keymap.prefix, isNull);
      expect(keymap.bindingFor('detach')!.label('P'), 'P Shift+Q');
      expect(keymap.bindingFor('goto')!.label('P'), 'P j');
      expect(keymap.bindingFor('zoom'), isNull);
      expect(keymap.switchTabWithPrefix, isFalse);
      expect(keymap.bindingFor('help')!.label('P'), 'P ?');
    });
  });

  group('HerdrKeySender', () {
    test('prefix bindings send the prefix, then the key', () {
      expect(
        _typed(
          HerdrKeyBinding.tryParse('prefix+d')!,
          prefix: MultiplexerPrefixKey.controlSpace,
        ),
        ['prefix:ctrl+space', 'text:d'],
      );
      expect(_typed(HerdrKeyBinding.tryParse('prefix+shift+x')!), [
        'prefix:ctrl+b',
        'text:X',
      ]);
      expect(_typed(HerdrKeyBinding.tryParse('prefix+minus')!), [
        'prefix:ctrl+b',
        'text:-',
      ]);
      expect(_typed(HerdrKeyBinding.tryParse('prefix+tab')!), [
        'prefix:ctrl+b',
        'key:tab',
      ]);
    });

    test('direct chords are encoded like a keyboard would', () {
      expect(_typed(HerdrKeyBinding.tryParse('ctrl+alt+left')!), [
        'text:\x1b[1;7D',
      ]);
      expect(_typed(HerdrKeyBinding.tryParse('alt+right')!), [
        'text:\x1b[1;3C',
      ]);
      expect(_typed(HerdrKeyBinding.tryParse('alt+n')!), ['text:\x1bn']);
      expect(_typed(HerdrKeyBinding.tryParse('ctrl+j')!), [
        'ctrl:${TerminalKey.keyJ.name}',
      ]);
      expect(_typed(HerdrKeyBinding.tryParse('ctrl+alt+z')!), [
        'text:\x1b\x1a',
      ]);
    });

    test('unsendable bindings are dropped', () {
      expect(HerdrKeyBinding.tryParse('cmd+k'), isNull);
      expect(HerdrKeyBinding.tryParse('prefix+1..9'), isNull);
      expect(HerdrKeyBinding.tryParse('prefix+f12'), isNull);
      expect(HerdrKeyBinding.tryParse(''), isNull);
    });
  });

  group('HerdrKeymapReader and cache', () {
    setUp(HerdrKeymapCache.instance.clear);

    test('reads the config read-only and caches it per machine', () async {
      final runner = FakeHerdrRunner(
        (_) => AgentCommandResult(
          stdout: _fixture('herdr_config_dev_central.toml'),
          stderr: '',
          exitCode: 0,
        ),
      );
      final cache = HerdrKeymapCache.instance;
      expect(cache.of('dev').bindingFor('detach')!.label('P'), 'P q');

      await cache.load('dev', runner);
      await cache.load('dev', runner);

      expect(runner.commands, hasLength(1));
      expect(runner.commands.single, contains('herdr/config.toml'));
      expect(runner.commands.single, isNot(contains('>')));
      expect(cache.of('dev').bindingFor('detach')!.label('P'), 'P d');
      expect(cache.of('other').bindingFor('detach')!.label('P'), 'P q');
    });

    test('no config file means the defaults, known to be current', () async {
      final runner = FakeHerdrRunner(
        (_) => const AgentCommandResult(
          stdout: '#conductore:no-herdr-config\n',
          stderr: '',
          exitCode: 0,
        ),
      );
      final keymap = await HerdrKeymapReader.read(runner);
      expect(keymap!.fromHost, isTrue);
      expect(keymap.bindingFor('detach')!.label('P'), 'P q');
    });

    test('a failed read keeps the defaults and is retried', () async {
      var calls = 0;
      final runner = FakeHerdrRunner((_) {
        calls += 1;
        throw StateError('offline');
      });
      final cache = HerdrKeymapCache.instance;
      await cache.load('dev', runner);
      await cache.load('dev', runner);
      expect(calls, 2);
      expect(cache.has('dev'), isFalse);
    });
  });
}
