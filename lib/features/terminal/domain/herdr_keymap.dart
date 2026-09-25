import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/hosts/domain/multiplexer_prefix_key.dart';
import 'package:conduit_vt/conduit_vt.dart';
import 'package:flutter/foundation.dart';

/// One key of a Herdr binding: modifiers plus a key name as Herdr writes it
/// (`n`, `x`, `1`, `minus`, `left`, `tab`, ...).
@immutable
class HerdrKeyChord {
  const HerdrKeyChord(
    this.key, {
    this.ctrl = false,
    this.alt = false,
    this.shift = false,
  });

  final String key;
  final bool ctrl;
  final bool alt;
  final bool shift;

  /// Herdr's named punctuation (config reference: "minus, comma, ampersand,
  /// plus, and backtick", plus the common rest).
  static const _named = {
    'minus': '-',
    'comma': ',',
    'ampersand': '&',
    'plus': '+',
    'backtick': '`',
    'period': '.',
    'dot': '.',
    'slash': '/',
    'backslash': r'\',
    'semicolon': ';',
    'colon': ':',
    'equal': '=',
    'equals': '=',
    'quote': "'",
    'question': '?',
    'lbracket': '[',
    'rbracket': ']',
    'space': ' ',
  };

  static const _special = {
    'left': TerminalKey.arrowLeft,
    'right': TerminalKey.arrowRight,
    'up': TerminalKey.arrowUp,
    'down': TerminalKey.arrowDown,
    'tab': TerminalKey.tab,
    'enter': TerminalKey.enter,
    'esc': TerminalKey.escape,
    'escape': TerminalKey.escape,
    'home': TerminalKey.home,
    'end': TerminalKey.end,
    'pageup': TerminalKey.pageUp,
    'pagedown': TerminalKey.pageDown,
    'backspace': TerminalKey.backspace,
    'delete': TerminalKey.delete,
  };

  /// The printable character for [key] (shift applied to letters), or null
  /// for a special key.
  String? get character {
    final named = _named[key];
    if (named != null) {
      return named;
    }
    if (key.length != 1) {
      return null;
    }
    return shift ? key.toUpperCase() : key;
  }

  TerminalKey? get specialKey => _special[key];

  /// Whether the app can type this chord: a printable key, or a special
  /// key, with ctrl/alt/shift at most.
  bool get sendable => character != null || specialKey != null;

  /// `x`, `Shift+X`, `Ctrl+Alt+Left`, `-`, `Space`.
  String get label {
    final named = _named[key];
    final String name;
    if (key == 'space') {
      name = 'Space';
    } else if (named != null) {
      name = named;
    } else if (key.length == 1) {
      name = shift ? key.toUpperCase() : key;
    } else {
      name = key[0].toUpperCase() + key.substring(1);
    }
    return [
      if (ctrl) 'Ctrl',
      if (alt) 'Alt',
      if (shift) 'Shift',
      name,
    ].join('+');
  }

  @override
  bool operator ==(Object other) =>
      other is HerdrKeyChord &&
      other.key == key &&
      other.ctrl == ctrl &&
      other.alt == alt &&
      other.shift == shift;

  @override
  int get hashCode => Object.hash(key, ctrl, alt, shift);

  @override
  String toString() => 'HerdrKeyChord($label)';
}

/// One Herdr binding: `prefix+<chord>` or a direct chord.
@immutable
class HerdrKeyBinding {
  const HerdrKeyBinding(this.chord, {this.prefixed = true});

  final HerdrKeyChord chord;
  final bool prefixed;

  /// Parses one binding string (`prefix+shift+x`, `ctrl+alt+left`); null for
  /// anything this app cannot type (cmd/super, ranges, empty).
  static HerdrKeyBinding? tryParse(String raw) {
    final parts = raw.trim().toLowerCase().split('+');
    if (parts.last.isEmpty) {
      return null;
    }
    var prefixed = false;
    var ctrl = false;
    var alt = false;
    var shift = false;
    for (var index = 0; index < parts.length - 1; index += 1) {
      switch (parts[index]) {
        case 'prefix' when index == 0:
          prefixed = true;
        case 'ctrl' || 'control':
          ctrl = true;
        case 'alt' || 'meta' || 'option':
          alt = true;
        case 'shift':
          shift = true;
        default:
          return null;
      }
    }
    final key = parts.last;
    if (key.contains('..')) {
      return null;
    }
    final chord = HerdrKeyChord(key, ctrl: ctrl, alt: alt, shift: shift);
    return chord.sendable ? HerdrKeyBinding(chord, prefixed: prefixed) : null;
  }

  /// `Ctrl+B Shift+X` for a prefix binding, `Ctrl+Alt+Left` for a direct one.
  String label(String prefixLabel) =>
      prefixed ? '$prefixLabel ${chord.label}' : chord.label;

  @override
  bool operator ==(Object other) =>
      other is HerdrKeyBinding &&
      other.chord == chord &&
      other.prefixed == prefixed;

  @override
  int get hashCode => Object.hash(chord, prefixed);

  @override
  String toString() => 'HerdrKeyBinding(${label('prefix')})';
}

/// Herdr's key bindings on one machine, read from its `config.toml`.
///
/// Herdr 0.9.1 has no command that prints the effective keymap (`herdr
/// config check` only validates, `herdr api snapshot` has no keys), so the
/// `[keys]` table of `~/.config/herdr/config.toml` is read and laid over
/// the documented defaults (https://herdr.dev/docs/config-reference/).
/// Anything unreadable falls back to the default binding.
@immutable
class HerdrKeymap {
  const HerdrKeymap._(
    this._bindings, {
    this.switchTabWithPrefix = true,
    this.prefix,
    this.fromHost = false,
  });

  /// Herdr's documented default keymap.
  static final defaults = HerdrKeymap._(_parseBindings(_defaultKeys));

  /// Whether `switch_tab` includes `prefix+1..9`, so tab N is the prefix
  /// then the digit (the default).
  final bool switchTabWithPrefix;

  /// The config's `keys.prefix`, when it names a key the app can send.
  final MultiplexerPrefixKey? prefix;

  /// Whether this came from the machine (config read, or no config there)
  /// rather than being the offline fallback.
  final bool fromHost;

  final Map<String, List<HerdrKeyBinding>> _bindings;

  /// Every binding of a config action (`detach`, `goto`, ...); empty when
  /// unbound or when none can be typed from the phone.
  List<HerdrKeyBinding> bindingsFor(String action) =>
      _bindings[action] ?? const [];

  /// The binding the app sends for [action]: the first `prefix+` one (it
  /// survives any terminal), else the first direct chord; null when unbound.
  HerdrKeyBinding? bindingFor(String action) {
    final all = bindingsFor(action);
    for (final binding in all) {
      if (binding.prefixed) {
        return binding;
      }
    }
    return all.firstOrNull;
  }

  /// Reads [config] (a whole `config.toml`) over the defaults.
  static HerdrKeymap parseConfig(String config) {
    final keys = _readKeysTable(config);
    final bindings = Map.of(defaults._bindings);
    for (final entry in _parseBindings(keys).entries) {
      bindings[entry.key] = entry.value;
    }
    final switchTab = keys['switch_tab'];
    final prefixValue = keys['prefix'];
    final prefix = prefixValue == null || prefixValue.isEmpty
        ? MultiplexerPrefixKey.defaultKey
        : MultiplexerPrefixKey.tryDecode(prefixValue.first);
    return HerdrKeymap._(
      bindings,
      switchTabWithPrefix: switchTab == null || _hasPrefixedRange(switchTab),
      prefix: prefix,
      fromHost: true,
    );
  }

  /// The keymap of a machine with no `config.toml`: the defaults, known to
  /// be current.
  static final hostDefaults = HerdrKeymap._(
    defaults._bindings,
    prefix: MultiplexerPrefixKey.controlB,
    fromHost: true,
  );

  static bool _hasPrefixedRange(List<String> values) => values.any(
    (value) => value.trim().toLowerCase().replaceAll(' ', '') == 'prefix+1..9',
  );

  static Map<String, List<HerdrKeyBinding>> _parseBindings(
    Map<String, List<String>> keys,
  ) {
    final bindings = <String, List<HerdrKeyBinding>>{};
    for (final entry in keys.entries) {
      if (entry.key == 'prefix' || entry.key == 'switch_tab') {
        continue;
      }
      bindings[entry.key] = [
        for (final value in entry.value) ?HerdrKeyBinding.tryParse(value),
      ];
    }
    return bindings;
  }

  /// The `[keys]` table as action -> binding strings. Understands the TOML
  /// Herdr documents for it: `name = "value"`, `name = ["a", "b"]` (also
  /// across lines), comments, and stops at the next table header
  /// (`[[keys.command]]` included).
  static Map<String, List<String>> _readKeysTable(String config) {
    final result = <String, List<String>>{};
    var inKeys = false;
    String? pendingName;
    final pending = StringBuffer();
    for (final rawLine in config.split('\n')) {
      final line = _stripComment(rawLine).trim();
      if (pendingName != null) {
        pending.write(' $line');
        if (line.contains(']')) {
          result[pendingName] = _strings(pending.toString());
          pendingName = null;
          pending.clear();
        }
        continue;
      }
      if (line.isEmpty) {
        continue;
      }
      if (line.startsWith('[')) {
        inKeys = line == '[keys]';
        continue;
      }
      if (!inKeys) {
        continue;
      }
      final equals = line.indexOf('=');
      if (equals <= 0) {
        continue;
      }
      final name = line.substring(0, equals).trim();
      final value = line.substring(equals + 1).trim();
      if (value.startsWith('[') && !value.contains(']')) {
        pendingName = name;
        pending.write(value);
        continue;
      }
      result[name] = _strings(value);
    }
    return result;
  }

  static List<String> _strings(String value) => [
    for (final match in RegExp(
      r'"([^"]*)"|'
      "'([^']*)'",
    ).allMatches(value))
      match.group(1) ?? match.group(2) ?? '',
  ];

  /// Drops a `#` comment that is outside quotes.
  static String _stripComment(String line) {
    var quote = '';
    for (var index = 0; index < line.length; index += 1) {
      final char = line[index];
      if (quote.isNotEmpty) {
        if (char == quote) {
          quote = '';
        }
      } else if (char == '"' || char == "'") {
        quote = char;
      } else if (char == '#') {
        return line.substring(0, index);
      }
    }
    return line;
  }

  /// `herdr --default-config` [keys] entries the app uses (Herdr 0.9.1).
  static const _defaultKeys = {
    'detach': ['prefix+q'],
    'goto': ['prefix+g'],
    'workspace_picker': ['prefix+w'],
    'new_workspace': ['prefix+shift+n'],
    'rename_workspace': ['prefix+shift+w'],
    'close_workspace': ['prefix+shift+d'],
    'new_tab': ['prefix+c'],
    'rename_tab': ['prefix+shift+t'],
    'previous_tab': ['prefix+p'],
    'next_tab': ['prefix+n'],
    'switch_tab': ['prefix+1..9'],
    'close_tab': ['prefix+shift+x'],
    'copy_mode': ['prefix+['],
    'focus_pane_left': ['prefix+h'],
    'focus_pane_down': ['prefix+j'],
    'focus_pane_up': ['prefix+k'],
    'focus_pane_right': ['prefix+l'],
    'split_vertical': ['prefix+v'],
    'split_horizontal': ['prefix+minus'],
    'close_pane': ['prefix+x'],
    'zoom': ['prefix+z'],
    'resize_mode': ['prefix+r'],
    'toggle_sidebar': ['prefix+b'],
    'help': ['prefix+?'],
  };
}

/// Types Herdr bindings into a terminal.
///
/// Prefix bindings send the prefix, then the chord. Chords go out the way a
/// keyboard would send them: printable keys as text (Alt adds ESC), Ctrl
/// with a letter as a control key, and arrows or other special keys with
/// the xterm modifier parameter (`ESC [ 1 ; m X`).
abstract final class HerdrKeySender {
  static void send(
    HerdrKeyBinding binding, {
    required MultiplexerPrefixKey prefix,
    required void Function(MultiplexerPrefixKey prefix) sendPrefix,
    required void Function(String text) sendText,
    required void Function(TerminalKey key) sendKey,
    required void Function(TerminalKey key) sendControl,
  }) {
    if (binding.prefixed) {
      sendPrefix(prefix);
    }
    final chord = binding.chord;
    final special = chord.specialKey;
    if (special != null) {
      final modifier =
          1 +
          (chord.shift ? 1 : 0) +
          (chord.alt ? 2 : 0) +
          (chord.ctrl ? 4 : 0);
      final letter = switch (special) {
        TerminalKey.arrowUp => 'A',
        TerminalKey.arrowDown => 'B',
        TerminalKey.arrowRight => 'C',
        TerminalKey.arrowLeft => 'D',
        TerminalKey.home => 'H',
        TerminalKey.end => 'F',
        _ => null,
      };
      if (modifier == 1) {
        sendKey(special);
      } else if (letter != null) {
        sendText('\x1b[1;$modifier$letter');
      } else if (special == TerminalKey.tab && chord.shift) {
        sendText('\x1b[Z');
      } else {
        sendKey(special);
      }
      return;
    }
    final char = chord.character!;
    if (chord.ctrl) {
      final letter = MultiplexerPrefixKey.letterKeys.contains(chord.key);
      if (letter && !chord.alt) {
        sendControl(
          MultiplexerPrefixKey(key: chord.key, ctrl: true).terminalKey,
        );
        return;
      }
      final bytes = MultiplexerPrefixKey(
        key: MultiplexerPrefixKey.isValidKey(chord.key)
            ? chord.key
            : char == ' '
            ? MultiplexerPrefixKey.spaceKey
            : char,
        ctrl: true,
        alt: chord.alt,
      ).sequence;
      sendText(bytes);
      return;
    }
    sendText(chord.alt ? '\x1b$char' : char);
  }
}

/// Keymaps per machine (saved host id), read once per app run.
class HerdrKeymapCache extends ChangeNotifier {
  HerdrKeymapCache._();

  static final instance = HerdrKeymapCache._();

  final _keymaps = <String, HerdrKeymap>{};
  final _loading = <String>{};

  /// The machine's keymap, or Herdr's defaults until it is read.
  HerdrKeymap of(String hostId) => _keymaps[hostId] ?? HerdrKeymap.defaults;

  bool has(String hostId) => _keymaps.containsKey(hostId);

  void put(String hostId, HerdrKeymap keymap) {
    _keymaps[hostId] = keymap;
    notifyListeners();
  }

  /// Reads [hostId]'s keymap over [runner] unless it is known or being
  /// read. A failed read leaves the defaults in place and is retried next
  /// time.
  Future<HerdrKeymap> load(String hostId, AgentCommandRunner runner) =>
      loadWith(hostId, () => HerdrKeymapReader.read(runner));

  /// [load] with any reader (a queued command channel, say).
  Future<HerdrKeymap> loadWith(
    String hostId,
    Future<HerdrKeymap?> Function() read,
  ) async {
    final known = _keymaps[hostId];
    if (known != null || !_loading.add(hostId)) {
      return known ?? HerdrKeymap.defaults;
    }
    try {
      final keymap = await read();
      if (keymap != null) {
        put(hostId, keymap);
        return keymap;
      }
      return HerdrKeymap.defaults;
    } finally {
      _loading.remove(hostId);
    }
  }

  @visibleForTesting
  void clear() {
    _keymaps.clear();
    _loading.clear();
  }
}

/// Reads a machine's Herdr config, read-only.
abstract final class HerdrKeymapReader {
  /// Where Herdr reads its config on Linux and macOS
  /// (https://herdr.dev/docs/configuration/), honouring XDG_CONFIG_HOME.
  /// Prints a marker instead when there is no config file, so "no file"
  /// (Herdr's defaults apply) is told apart from a failed read.
  static const command =
      r'''sh -c 'f="${XDG_CONFIG_HOME:-$HOME/.config}/herdr/config.toml"; if [ -f "$f" ]; then cat "$f"; else echo "#conductore:no-herdr-config"; fi' ''';

  static const _noConfig = '#conductore:no-herdr-config';

  /// The keymap, or null when the machine could not be asked.
  static Future<HerdrKeymap?> read(AgentCommandRunner runner) async {
    try {
      return interpret(
        await runner.run(command, timeout: const Duration(seconds: 10)),
      );
    } catch (_) {
      return null;
    }
  }

  /// The keymap in [result] of [command]; null for a failed read.
  static HerdrKeymap? interpret(AgentCommandResult? result) {
    if (result == null || (result.exitCode != null && result.exitCode != 0)) {
      return null;
    }
    if (result.stdout.trim() == _noConfig) {
      return HerdrKeymap.hostDefaults;
    }
    return HerdrKeymap.parseConfig(result.stdout);
  }
}
