import 'package:conduit/core/platform_features.dart';
import 'package:conduit_vt/conduit_vt.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Physical keyboard handling for the desktop builds.
///
/// conduit_vt's default input handler was written for phones with an
/// occasional hardware keyboard. On a desktop, where every key comes from a
/// real keyboard, it gets a few common combinations wrong:
///
/// * Alt+letter sends ESC + the UPPERCASE letter (Alt+b arrives as Alt+B, so
///   readline's backward-word does nothing), and Alt+Shift+letter, Alt+digit
///   and Alt+punctuation send nothing at all.
/// * Ctrl+[ ] \ / and Ctrl+digits send nothing.
/// * Alt+arrow is encoded with the Ctrl modifier parameter (5, not 3).
///
/// [DesktopKeyInputHandler] runs before the default handler and fixes those.
/// macOS keeps Option for composing characters (Option+2 is `@` on a
/// Portuguese layout), like Terminal.app does by default, so the Alt rules
/// are skipped there.
class DesktopKeyInputHandler implements TerminalInputHandler {
  const DesktopKeyInputHandler();

  static const _esc = '\x1b';

  static final _ctrlSymbols = <TerminalKey, String>{
    TerminalKey.bracketLeft: '\x1b',
    TerminalKey.backslash: '\x1c',
    TerminalKey.bracketRight: '\x1d',
    TerminalKey.slash: '\x1f',
    // xterm's Ctrl+digit table.
    TerminalKey.digit2: '\x00',
    TerminalKey.digit3: '\x1b',
    TerminalKey.digit4: '\x1c',
    TerminalKey.digit5: '\x1d',
    TerminalKey.digit6: '\x1e',
    TerminalKey.digit7: '\x1f',
    TerminalKey.digit8: '\x7f',
  };

  static final _punctuation = <TerminalKey, String>{
    TerminalKey.minus: '-',
    TerminalKey.equal: '=',
    TerminalKey.bracketLeft: '[',
    TerminalKey.bracketRight: ']',
    TerminalKey.backslash: r'\',
    TerminalKey.semicolon: ';',
    TerminalKey.quote: "'",
    TerminalKey.backquote: '`',
    TerminalKey.comma: ',',
    TerminalKey.period: '.',
    TerminalKey.slash: '/',
  };

  static final _cursorFinals = <TerminalKey, String>{
    TerminalKey.arrowUp: 'A',
    TerminalKey.arrowDown: 'B',
    TerminalKey.arrowRight: 'C',
    TerminalKey.arrowLeft: 'D',
    TerminalKey.home: 'H',
    TerminalKey.end: 'F',
  };

  @override
  String? call(TerminalKeyboardEvent event) {
    final key = event.key;
    final macos = event.platform == TerminalTargetPlatform.macos;

    // Cursor keys with a modifier: CSI 1 ; (1 + shift + 2*alt + 4*ctrl) X.
    final cursor = _cursorFinals[key];
    if (cursor != null && event.alt && !macos) {
      final modifier =
          1 +
          (event.shift ? 1 : 0) +
          (event.alt ? 2 : 0) +
          (event.ctrl ? 4 : 0);
      return '$_esc[1;$modifier$cursor';
    }

    if (event.ctrl && !event.alt && !event.shift) {
      return _ctrlSymbols[key];
    }

    if (event.alt && !event.ctrl && !macos) {
      final char = _plainCharacter(key, shift: event.shift);
      return char == null ? null : '$_esc$char';
    }
    return null;
  }

  /// The character an unmodified key types on a US layout, for Alt (meta)
  /// combinations. Shifted punctuation is layout specific and left out.
  static String? _plainCharacter(TerminalKey key, {required bool shift}) {
    if (key.index >= TerminalKey.keyA.index &&
        key.index <= TerminalKey.keyZ.index) {
      final letter = String.fromCharCode(
        'a'.codeUnitAt(0) + key.index - TerminalKey.keyA.index,
      );
      return shift ? letter.toUpperCase() : letter;
    }
    if (shift) return null;
    if (key.index >= TerminalKey.digit1.index &&
        key.index <= TerminalKey.digit9.index) {
      return '${key.index - TerminalKey.digit1.index + 1}';
    }
    if (key == TerminalKey.digit0) return '0';
    return _punctuation[key];
  }
}

/// The input handler a terminal session starts with: the desktop fixes in
/// front of conduit_vt's default on Linux, Windows and macOS, the default
/// alone on phones (unchanged behaviour there).
TerminalInputHandler terminalInputHandlerForPlatform() {
  if (!PlatformFeatures.isDesktop) return defaultInputHandler;
  return const CascadeInputHandler([
    DesktopKeyInputHandler(),
    defaultInputHandler,
  ]);
}

/// conduit_vt's platform flag (macOS Option handling in the keytab). Phones
/// keep `unknown`, as before.
TerminalTargetPlatform terminalTargetPlatform() =>
    switch (defaultTargetPlatform) {
      TargetPlatform.linux => TerminalTargetPlatform.linux,
      TargetPlatform.windows => TerminalTargetPlatform.windows,
      TargetPlatform.macOS => TerminalTargetPlatform.macos,
      _ => TerminalTargetPlatform.unknown,
    };

/// Copy and paste shortcuts of the terminal view. Linux and Windows use the
/// terminal-emulator convention Ctrl+Shift+C / Ctrl+Shift+V, so Ctrl+A,
/// Ctrl+C and Ctrl+V reach the remote shell (conduit_vt's stock shortcuts
/// take Ctrl+A for select-all and Ctrl+V for paste). macOS uses Cmd, which
/// never collides with the shell. Null on phones keeps conduit_vt's
/// defaults there.
Map<ShortcutActivator, Intent>? desktopTerminalShortcuts() {
  switch (defaultTargetPlatform) {
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      return const {
        SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true):
            CopySelectionTextIntent.copy,
        SingleActivator(LogicalKeyboardKey.keyV, control: true, shift: true):
            PasteTextIntent(SelectionChangedCause.keyboard),
        SingleActivator(LogicalKeyboardKey.insert, shift: true):
            PasteTextIntent(SelectionChangedCause.keyboard),
      };
    case TargetPlatform.macOS:
      return const {
        SingleActivator(LogicalKeyboardKey.keyC, meta: true):
            CopySelectionTextIntent.copy,
        SingleActivator(LogicalKeyboardKey.keyV, meta: true): PasteTextIntent(
          SelectionChangedCause.keyboard,
        ),
        SingleActivator(LogicalKeyboardKey.keyA, meta: true):
            SelectAllTextIntent(SelectionChangedCause.keyboard),
      };
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.fuchsia:
      return null;
  }
}
