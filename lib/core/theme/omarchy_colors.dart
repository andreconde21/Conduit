import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Whether an Omarchy theme is dark or light (`mode` in colors.toml).
enum OmarchyMode { dark, light }

/// The resolved semantic palette of one Omarchy theme.
///
/// Mirrors the keys Omarchy's `bin/omarchy-theme-color` resolves from a
/// theme's `colors.toml` (https://github.com/basecamp/omarchy, MIT). The
/// terminal colours follow Omarchy's `default/themed/alacritty.toml.tpl`.
@immutable
class OmarchyColors {
  const OmarchyColors({
    required this.mode,
    required this.accent,
    required this.background,
    required this.foreground,
    required this.selection,
    required this.selectionForeground,
    required this.muted,
    required this.darkBackground,
    required this.darkerBackground,
    required this.lighterBackground,
    required this.darkForeground,
    required this.lightForeground,
    required this.brightForeground,
    required this.red,
    required this.green,
    required this.yellow,
    required this.blue,
    required this.magenta,
    required this.cyan,
    required this.orange,
    required this.brightRed,
    required this.brightGreen,
    required this.brightYellow,
    required this.brightBlue,
    required this.brightMagenta,
    required this.brightCyan,
  });

  final OmarchyMode mode;
  final Color accent;
  final Color background;
  final Color foreground;
  final Color selection;
  final Color selectionForeground;
  final Color muted;
  final Color darkBackground;
  final Color darkerBackground;
  final Color lighterBackground;
  final Color darkForeground;
  final Color lightForeground;
  final Color brightForeground;
  final Color red;
  final Color green;
  final Color yellow;
  final Color blue;
  final Color magenta;
  final Color cyan;
  final Color orange;
  final Color brightRed;
  final Color brightGreen;
  final Color brightYellow;
  final Color brightBlue;
  final Color brightMagenta;
  final Color brightCyan;

  bool get isDark => mode == OmarchyMode.dark;

  /// The colours keyed by their colors.toml names, as hex strings.
  Map<String, String> toJson() => {
    'mode': mode.name,
    for (final entry in _fields.entries) entry.key: _hex(entry.value(this)),
  };

  /// Reads [toJson] output (or any fully resolved colors.toml map).
  static OmarchyColors? fromJson(Map<String, Object?> json) {
    final values = <String, Color>{};
    for (final key in _fields.keys) {
      final color = parseOmarchyColor(json[key]?.toString());
      if (color == null) {
        return null;
      }
      values[key] = color;
    }
    return OmarchyColors(
      mode: json['mode'] == 'light' ? OmarchyMode.light : OmarchyMode.dark,
      accent: values['accent']!,
      background: values['background']!,
      foreground: values['foreground']!,
      selection: values['selection']!,
      selectionForeground: values['selection_foreground']!,
      muted: values['muted']!,
      darkBackground: values['dark_background']!,
      darkerBackground: values['darker_background']!,
      lighterBackground: values['lighter_background']!,
      darkForeground: values['dark_foreground']!,
      lightForeground: values['light_foreground']!,
      brightForeground: values['bright_foreground']!,
      red: values['red']!,
      green: values['green']!,
      yellow: values['yellow']!,
      blue: values['blue']!,
      magenta: values['magenta']!,
      cyan: values['cyan']!,
      orange: values['orange']!,
      brightRed: values['bright_red']!,
      brightGreen: values['bright_green']!,
      brightYellow: values['bright_yellow']!,
      brightBlue: values['bright_blue']!,
      brightMagenta: values['bright_magenta']!,
      brightCyan: values['bright_cyan']!,
    );
  }

  static final Map<String, Color Function(OmarchyColors)> _fields = {
    'accent': (c) => c.accent,
    'background': (c) => c.background,
    'foreground': (c) => c.foreground,
    'selection': (c) => c.selection,
    'selection_foreground': (c) => c.selectionForeground,
    'muted': (c) => c.muted,
    'dark_background': (c) => c.darkBackground,
    'darker_background': (c) => c.darkerBackground,
    'lighter_background': (c) => c.lighterBackground,
    'dark_foreground': (c) => c.darkForeground,
    'light_foreground': (c) => c.lightForeground,
    'bright_foreground': (c) => c.brightForeground,
    'red': (c) => c.red,
    'green': (c) => c.green,
    'yellow': (c) => c.yellow,
    'blue': (c) => c.blue,
    'magenta': (c) => c.magenta,
    'cyan': (c) => c.cyan,
    'orange': (c) => c.orange,
    'bright_red': (c) => c.brightRed,
    'bright_green': (c) => c.brightGreen,
    'bright_yellow': (c) => c.brightYellow,
    'bright_blue': (c) => c.brightBlue,
    'bright_magenta': (c) => c.brightMagenta,
    'bright_cyan': (c) => c.brightCyan,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! OmarchyColors || other.mode != mode) {
      return false;
    }
    for (final read in _fields.values) {
      if (read(this) != read(other)) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hashAll([mode, for (final read in _fields.values) read(this)]);
}

String _hex(Color color) {
  final argb = color.toARGB32() & 0xFFFFFF;
  return '#${argb.toRadixString(16).padLeft(6, '0')}';
}

/// Parses the colour notations Omarchy themes use for the palette keys:
/// `#rrggbb`, `#rrggbbaa` (alpha dropped), `0xrrggbb` and `rgb(r,g,b)`.
Color? parseOmarchyColor(String? raw) {
  if (raw == null) {
    return null;
  }
  final value = raw.trim();
  final hex = RegExp(
    r'^(?:#|0x)([0-9a-fA-F]{6})(?:[0-9a-fA-F]{2})?$',
  ).firstMatch(value);
  if (hex != null) {
    return Color(0xFF000000 | int.parse(hex.group(1)!, radix: 16));
  }
  final rgb = RegExp(
    r'^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,[\d.\s]+)?\)$',
    caseSensitive: false,
  ).firstMatch(value);
  if (rgb != null) {
    int channel(int group) => int.parse(rgb.group(group)!).clamp(0, 255);
    return Color.fromARGB(255, channel(1), channel(2), channel(3));
  }
  return null;
}

/// A Dart port of Omarchy's colors.toml parser and resolver
/// (`bin/omarchy-theme-color`, MIT): the alias and fallback cascade that
/// turns a partial or legacy colors.toml into the full semantic palette.
class OmarchyColorResolver {
  const OmarchyColorResolver._();

  static final _keyPattern = RegExp(r'^[A-Za-z0-9_-]+$');
  static final _valuePattern = RegExp(r'^[A-Za-z0-9#(),._+/% -]*$');

  /// The raw `key = value` pairs of a colors.toml, as Omarchy reads them.
  static Map<String, String> parseColorsToml(String source) {
    final values = <String, String>{};
    for (final line in const LineSplitter().convert(source)) {
      final split = line.indexOf('=');
      final rawKey = split < 0 ? line : line.substring(0, split);
      var value = split < 0 ? '' : line.substring(split + 1);
      final key = rawKey.replaceAll(RegExp('["\' ]'), '').trim();
      if (key.isEmpty || key.startsWith('#')) {
        continue;
      }
      final quote = RegExp('["\']').firstMatch(value);
      if (quote != null) {
        value = value.substring(quote.end);
        final close = RegExp('["\']').firstMatch(value);
        if (close != null) {
          value = value.substring(0, close.start);
        }
      } else {
        value = value.trim();
      }
      if (!_keyPattern.hasMatch(key) || !_valuePattern.hasMatch(value)) {
        continue;
      }
      values[key] = value;
    }
    return values;
  }

  /// Resolves a colors.toml source into a palette, or null when the theme
  /// lacks colours the app needs (or uses notations it cannot read).
  static OmarchyColors? resolveToml(
    String source, {
    bool lightModeFile = false,
  }) {
    return resolve(parseColorsToml(source), lightModeFile: lightModeFile);
  }

  /// Applies Omarchy's resolve_theme_colors cascade to raw [input] values.
  static OmarchyColors? resolve(
    Map<String, String> input, {
    bool lightModeFile = false,
  }) {
    final c = Map<String, String>.of(input);
    bool has(String key) => (c[key] ?? '').isNotEmpty;
    void alias(String key, String fallback) {
      if (!has(key)) {
        c[key] = c[fallback] ?? '';
      }
    }

    const legacyPalette = {
      'background': 'bg',
      'dark_background': 'dark_bg',
      'darker_background': 'darker_bg',
      'lighter_background': 'lighter_bg',
      'foreground': 'fg',
      'dark_foreground': 'dark_fg',
      'light_foreground': 'light_fg',
      'bright_foreground': 'bright_fg',
    };
    legacyPalette.forEach(alias);

    if (!has('background')) c['background'] = c['color0'] ?? '';
    if (!has('foreground')) c['foreground'] = c['color7'] ?? '';
    if (has('background')) c['color0'] = c['background']!;
    if (has('foreground')) c['color7'] = c['foreground']!;

    const legacyAnsi = {
      'red': 'color1',
      'green': 'color2',
      'yellow': 'color3',
      'blue': 'color4',
      'magenta': 'color5',
      'cyan': 'color6',
      'bright_red': 'color9',
      'bright_green': 'color10',
      'bright_yellow': 'color11',
      'bright_blue': 'color12',
      'bright_magenta': 'color13',
      'bright_cyan': 'color14',
    };
    legacyAnsi.forEach(alias);
    alias('magenta', 'purple');
    alias('bright_magenta', 'bright_purple');

    String? first(List<String> keys) {
      for (final key in keys) {
        if (has(key)) {
          return c[key];
        }
      }
      return null;
    }

    void fill(String key, List<String> fallbacks) {
      if (!has(key)) {
        c[key] = first(fallbacks) ?? '';
      }
    }

    fill('light_foreground', ['color7', 'foreground']);
    fill('bright_foreground', ['color15', 'foreground']);
    c['cursor'] = c['bright_foreground'] ?? '';
    fill('lighter_background', ['color0', 'background']);
    fill('dark_foreground', ['color8', 'foreground']);
    fill('muted', ['color8', 'dark_foreground']);
    fill('selection', [
      'selection_background',
      'color8',
      'color0',
      'background',
    ]);
    fill('selection_background', ['selection']);
    fill('selection_foreground', ['bright_foreground']);
    fill('orange', ['yellow']);

    String? mix(String key, Color target, double amount) {
      final start = parseOmarchyColor(c[key]);
      if (start == null) {
        return null;
      }
      return _hex(mixOmarchyColor(start, target, amount));
    }

    void derive(String key, String from, Color target, double amount) {
      if (!has(key)) {
        c[key] = mix(from, target, amount) ?? '';
      }
    }

    const black = Color(0xFF000000);
    const white = Color(0xFFFFFFFF);
    derive('brown', 'orange', black, 0.5);
    derive('dark_background', 'background', black, 0.25);
    derive('darker_background', 'background', black, 0.5);
    derive('bright_red', 'red', white, 0.2);
    derive('bright_yellow', 'yellow', white, 0.2);
    derive('bright_green', 'green', white, 0.2);
    derive('bright_cyan', 'cyan', white, 0.2);
    derive('bright_blue', 'blue', white, 0.2);
    derive('bright_magenta', 'magenta', white, 0.2);

    // Omarchy's own mode precedence: mode, theme_type, a light.mode file,
    // then background luminance.
    var mode = c['mode'];
    if (mode == null || mode.isEmpty) mode = c['theme_type'];
    if (mode == null || mode.isEmpty) {
      if (lightModeFile) {
        mode = 'light';
      } else {
        final background = parseOmarchyColor(c['background']);
        if (background != null) {
          final argb = background.toARGB32();
          final sum =
              ((argb >> 16) & 0xFF) + ((argb >> 8) & 0xFF) + (argb & 0xFF);
          mode = sum > 382 ? 'light' : 'dark';
        } else {
          mode = 'dark';
        }
      }
    }
    // Every theme without an accent key gets Omarchy's usual choice: blue.
    fill('accent', ['blue']);
    c['mode'] = mode;
    return OmarchyColors.fromJson(c);
  }

  /// Builds colors.toml values from an alacritty.toml palette, like
  /// Omarchy's `bin/omarchy-theme-colors-from-alacritty` (for themes that
  /// predate colors.toml). Returns null without all eight normal colours.
  static Map<String, String>? colorsFromAlacritty(String source) {
    final values = <String, String>{};
    var section = '';
    for (final rawLine in const LineSplitter().convert(source)) {
      final line = rawLine.trim();
      final header = RegExp(r'^\[([^\]]*)\]$').firstMatch(line);
      if (header != null) {
        section = header.group(1)!.trim();
        continue;
      }
      if (line.startsWith('[')) {
        section = '';
        continue;
      }
      if (section.isEmpty) {
        continue;
      }
      final split = line.indexOf('=');
      if (split <= 0) {
        continue;
      }
      final key = line.substring(0, split).trim();
      if (key.startsWith('#')) {
        continue;
      }
      final hex = RegExp(
        r'''^["']?(?:0[xX]|#)?([0-9a-fA-F]{6})["']?(?:\s*#.*)?$''',
      ).firstMatch(line.substring(split + 1).trim());
      if (hex == null) {
        continue;
      }
      values.putIfAbsent(
        '$section.$key',
        () => '#${hex.group(1)!.toLowerCase()}',
      );
    }
    const names = [
      'black',
      'red',
      'green',
      'yellow',
      'blue',
      'magenta',
      'cyan',
      'white',
    ];
    final colors = <String, String>{};
    for (var i = 0; i < names.length; i++) {
      final normal = values['colors.normal.${names[i]}'];
      if (normal == null) {
        return null;
      }
      colors['color$i'] = normal;
    }
    for (var i = 0; i < names.length; i++) {
      colors['color${i + 8}'] =
          values['colors.bright.${names[i]}'] ?? colors['color$i']!;
    }
    final background = values['colors.primary.background'] ?? colors['color0']!;
    final foreground = values['colors.primary.foreground'] ?? colors['color7']!;
    colors['color0'] = background;
    colors['color7'] = foreground;
    colors['background'] = background;
    colors['foreground'] = foreground;
    colors['selection'] = values['colors.selection.background'] ?? foreground;
    colors['accent'] = colors['color4']!;
    return colors;
  }
}

/// Omarchy's `mix_color`: a per-channel linear mix, rounded half up.
Color mixOmarchyColor(Color start, Color end, double amount) {
  final t = amount.clamp(0.0, 1.0);
  final a = start.toARGB32();
  final b = end.toARGB32();
  int channel(int shift) {
    final from = (a >> shift) & 0xFF;
    final to = (b >> shift) & 0xFF;
    return (from * (1 - t) + to * t + 0.5).floor();
  }

  return Color.fromARGB(255, channel(16), channel(8), channel(0));
}
