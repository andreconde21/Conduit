import 'package:conduit_vt/conduit_vt.dart';

/// The key combination tmux and Herdr wait for before a binding (`prefix n`
/// for the next window, and so on).
///
/// Both multiplexers default to Ctrl+B, but the prefix is the first thing
/// people change (`set -g prefix C-a`, Ctrl+Space, a backtick), so the app
/// stores it per host and sends it wherever a binding is driven from the
/// phone: the Tmux and Herdr keys, the Herdr navigator, the swipe window
/// switching and the tmux detach before a Mosh session closes.
///
/// A combination is any of [ctrl], [alt] and [shift] plus one [key]: a
/// letter, a digit, [spaceKey] or one of [symbolKeys]. It is persisted as
/// `ctrl+alt+shift+key` (see [encode]); the enum names the app used before
/// prefixes became configurable (`controlB`, `controlA`) still decode.
class MultiplexerPrefixKey {
  const MultiplexerPrefixKey({
    required this.key,
    this.ctrl = false,
    this.alt = false,
    this.shift = false,
  });

  static const controlB = MultiplexerPrefixKey(key: 'b', ctrl: true);
  static const controlA = MultiplexerPrefixKey(key: 'a', ctrl: true);
  static const controlSpace = MultiplexerPrefixKey(key: spaceKey, ctrl: true);

  /// What tmux and Herdr use out of the box.
  static const defaultKey = controlB;

  /// Common choices the picker offers as one-tap presets.
  static const presets = [controlB, controlA, controlSpace];

  static const spaceKey = 'space';
  static const letterKeys = [
    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', //
    'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
  ];
  static const digitKeys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];
  static const symbolKeys = [
    '`', '-', '=', '[', ']', '\\', ';', "'", ',', '.', '/', //
  ];

  /// Every key the picker offers, in display order.
  static const allKeys = [spaceKey, ...letterKeys, ...digitKeys, ...symbolKeys];

  /// The key without modifiers: a lowercase letter, a digit, [spaceKey] or a
  /// symbol from [symbolKeys].
  final String key;
  final bool ctrl;
  final bool alt;
  final bool shift;

  static bool isValidKey(String key) => allKeys.contains(key);

  bool get isLetter => letterKeys.contains(key);
  bool get isSpace => key == spaceKey;
  bool get hasModifier => ctrl || alt || shift;

  MultiplexerPrefixKey copyWith({
    String? key,
    bool? ctrl,
    bool? alt,
    bool? shift,
  }) {
    return MultiplexerPrefixKey(
      key: key ?? this.key,
      ctrl: ctrl ?? this.ctrl,
      alt: alt ?? this.alt,
      shift: shift ?? this.shift,
    );
  }

  /// `ctrl+alt+shift+<key>`, modifiers in that order and only when set,
  /// e.g. `ctrl+b`, `ctrl+space`, `alt+shift+x`, or just `` ` `` for an
  /// unmodified key.
  String encode() {
    return [
      if (ctrl) 'ctrl',
      if (alt) 'alt',
      if (shift) 'shift',
      key,
    ].join('+');
  }

  /// Parses [encode] output, the pre-configurable enum names (`controlB`,
  /// `controlA`), and a few spellings people type (`Ctrl+Space`,
  /// `control+b`). Returns null for anything else.
  static MultiplexerPrefixKey? tryDecode(String? raw) {
    if (raw == null) {
      return null;
    }
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    switch (trimmed) {
      case 'controlB':
        return controlB;
      case 'controlA':
        return controlA;
    }
    final parts = trimmed.split('+');
    var ctrl = false;
    var alt = false;
    var shift = false;
    String? key;
    for (var index = 0; index < parts.length; index += 1) {
      final part = parts[index].trim();
      if (index == parts.length - 1) {
        key = _normalizeKey(part);
        break;
      }
      switch (part.toLowerCase()) {
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
    if (key == null || !isValidKey(key)) {
      return null;
    }
    return MultiplexerPrefixKey(key: key, ctrl: ctrl, alt: alt, shift: shift);
  }

  /// [tryDecode] with [defaultKey] for anything unreadable.
  static MultiplexerPrefixKey decode(String? raw) =>
      tryDecode(raw) ?? defaultKey;

  static String? _normalizeKey(String part) {
    final lower = part.toLowerCase();
    if (lower == 'space' || lower == 'spc' || part == ' ') {
      return spaceKey;
    }
    return lower;
  }

  /// Human label, e.g. `Ctrl+B`, `Ctrl+Space`, `Alt+Shift+X`.
  String get label {
    return [
      if (ctrl) 'Ctrl',
      if (alt) 'Alt',
      if (shift) 'Shift',
      keyLabel,
    ].join('+');
  }

  /// The key alone as shown in the picker: `Space`, `B`, `` ` ``.
  String get keyLabel => isSpace ? 'Space' : key.toUpperCase();

  /// The key as the terminal knows it.
  TerminalKey get terminalKey {
    if (isSpace) {
      return TerminalKey.space;
    }
    if (isLetter) {
      return TerminalKey.values[TerminalKey.keyA.index +
          key.codeUnitAt(0) -
          'a'.codeUnitAt(0)];
    }
    return switch (key) {
      '1' => TerminalKey.digit1,
      '2' => TerminalKey.digit2,
      '3' => TerminalKey.digit3,
      '4' => TerminalKey.digit4,
      '5' => TerminalKey.digit5,
      '6' => TerminalKey.digit6,
      '7' => TerminalKey.digit7,
      '8' => TerminalKey.digit8,
      '9' => TerminalKey.digit9,
      '0' => TerminalKey.digit0,
      '`' => TerminalKey.backquote,
      '-' => TerminalKey.minus,
      '=' => TerminalKey.equal,
      '[' => TerminalKey.bracketLeft,
      ']' => TerminalKey.bracketRight,
      '\\' => TerminalKey.backslash,
      ';' => TerminalKey.semicolon,
      "'" => TerminalKey.quote,
      ',' => TerminalKey.comma,
      '.' => TerminalKey.period,
      '/' => TerminalKey.slash,
      _ => TerminalKey.none,
    };
  }

  /// For a plain Ctrl+letter or Ctrl+Space the terminal's own control-key
  /// path produces the byte, so senders can use it (and tests can observe
  /// it as a control key). Null for every other combination, which goes out
  /// as [sequence].
  TerminalKey? get controlKey {
    if (ctrl && !alt && !shift && (isLetter || isSpace)) {
      return terminalKey;
    }
    return null;
  }

  /// The bytes this combination sends to the remote side, for transports
  /// that bypass the terminal (the tmux detach before a Mosh close).
  ///
  /// Ctrl folds letters, Space and the bracket keys to their control
  /// characters; Alt prepends ESC; Shift uppercases a letter. Ctrl with a
  /// key that has no control character (`;` say) sends the key itself.
  List<int> get bytes {
    final base = isSpace ? ' ' : key;
    var code = base.codeUnitAt(0);
    if (shift && isLetter) {
      code = base.toUpperCase().codeUnitAt(0);
    }
    if (ctrl) {
      code = _controlCodeFor(base) ?? code;
    }
    return [if (alt) 0x1b, code];
  }

  String get sequence => String.fromCharCodes(bytes);

  static int? _controlCodeFor(String key) {
    if (letterKeys.contains(key)) {
      return key.codeUnitAt(0) - 'a'.codeUnitAt(0) + 1;
    }
    return switch (key) {
      ' ' || '`' || '2' => 0x00,
      '[' || '3' => 0x1b,
      '\\' || '4' => 0x1c,
      ']' || '5' => 0x1d,
      '6' => 0x1e,
      '-' || '/' || '7' => 0x1f,
      '8' => 0x7f,
      _ => null,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is MultiplexerPrefixKey &&
        other.key == key &&
        other.ctrl == ctrl &&
        other.alt == alt &&
        other.shift == shift;
  }

  @override
  int get hashCode => Object.hash(key, ctrl, alt, shift);

  @override
  String toString() => 'MultiplexerPrefixKey(${encode()})';
}
