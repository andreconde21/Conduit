import 'dart:convert';

import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/core/theme/omarchy_colors.dart';
import 'package:conduit/core/theme/terminal_appearance.dart';
import 'package:flutter/foundation.dart';

/// One POSIX-sh exec that reports a machine's current Omarchy theme and
/// monospace font, in marked sections for [parseOmarchyProbe].
///
/// Omarchy keeps the active theme in `~/.local/state/omarchy/current/theme`
/// with its name in `theme.name` (bin/omarchy-theme-set,
/// bin/omarchy-theme-current); releases before that used a
/// `~/.config/omarchy/current/theme` symlink to the theme directory, whose
/// name is the link target's basename. The font comes from fontconfig like
/// bin/omarchy-font-current, falling back to alacritty's configured family.
/// Every read is capped, and nothing is written.
const String omarchyThemeProbeCommand = r'''
for d in "$HOME/.local/state/omarchy/current" "$HOME/.config/omarchy/current"; do
  [ -e "$d/theme" ] || continue
  t="$d/theme"
  printf '@@name\n'
  if [ -f "$d/theme.name" ]; then head -c 200 "$d/theme.name"; else basename "$(readlink -f "$t")"; fi
  printf '\n@@colors\n'
  head -c 32768 "$t/colors.toml" 2>/dev/null
  printf '\n@@alacritty\n'
  head -c 32768 "$t/alacritty.toml" 2>/dev/null
  printf '\n@@lightmode\n'
  [ -f "$t/light.mode" ] && echo yes
  break
done
printf '\n@@font\n'
if command -v fc-match >/dev/null 2>&1; then
  fc-match monospace -f '%{family}\n' 2>/dev/null | head -n 1 | cut -d, -f1
elif [ -f "$HOME/.config/alacritty/alacritty.toml" ]; then
  sed -n 's/^normal *= *{ *family *= *"\([^"]*\)".*/\1/p' "$HOME/.config/alacritty/alacritty.toml" | head -n 1
fi
printf '\n@@end\n'
''';

/// What [omarchyThemeProbeCommand] found on a machine.
@immutable
class OmarchyProbeResult {
  const OmarchyProbeResult({
    required this.themeName,
    this.colorsToml = '',
    this.alacrittyToml = '',
    this.lightModeFile = false,
    this.fontFamily = '',
  });

  /// The theme's directory name, e.g. `tokyo-night`; empty when the
  /// machine has no Omarchy theme.
  final String themeName;
  final String colorsToml;
  final String alacrittyToml;
  final bool lightModeFile;
  final String fontFamily;

  bool get hasOmarchy => themeName.isNotEmpty;
}

/// Parses the probe output. Returns null when the output is incomplete
/// (the exec was cut off), so a partial read never changes the theme.
OmarchyProbeResult? parseOmarchyProbe(String stdout) {
  final sections = <String, StringBuffer>{};
  StringBuffer? current;
  var ended = false;
  for (final line in const LineSplitter().convert(stdout)) {
    final marker = RegExp(r'^@@([a-z]+)$').firstMatch(line.trim());
    if (marker != null) {
      final name = marker.group(1)!;
      if (name == 'end') {
        ended = true;
        break;
      }
      current = sections.putIfAbsent(name, StringBuffer.new);
      continue;
    }
    current?.writeln(line);
  }
  if (!ended) {
    return null;
  }
  String read(String name) => sections[name]?.toString().trim() ?? '';
  return OmarchyProbeResult(
    themeName: read('name').split('\n').first.trim(),
    colorsToml: read('colors'),
    alacrittyToml: read('alacritty'),
    lightModeFile: read('lightmode') == 'yes',
    fontFamily: read('font').split('\n').first.trim(),
  );
}

/// The palette for a probed theme: the bundled theme of that name, else
/// the machine's own colors.toml, else its alacritty.toml (themes older
/// than colors.toml). Null when none of them gives a full palette.
AppPalette? paletteForOmarchyProbe(OmarchyProbeResult probe) {
  if (!probe.hasOmarchy) {
    return null;
  }
  final bundled = AppPalette.forOmarchyThemeName(probe.themeName);
  if (bundled != null) {
    return bundled;
  }
  OmarchyColors? colors;
  if (probe.colorsToml.isNotEmpty) {
    colors = OmarchyColorResolver.resolveToml(
      probe.colorsToml,
      lightModeFile: probe.lightModeFile,
    );
  }
  if (colors == null && probe.alacrittyToml.isNotEmpty) {
    final fromAlacritty = OmarchyColorResolver.colorsFromAlacritty(
      probe.alacrittyToml,
    );
    if (fromAlacritty != null) {
      colors = OmarchyColorResolver.resolve(
        fromAlacritty,
        lightModeFile: probe.lightModeFile,
      );
    }
  }
  if (colors == null) {
    return null;
  }
  return AppPalette.custom(name: probe.themeName, colors: colors);
}

/// The theme last read from the followed machine, cached so the app opens
/// in it before the next sync finishes.
@immutable
class OmarchySyncedTheme {
  const OmarchySyncedTheme({
    required this.hostId,
    required this.palette,
    required this.syncedAt,
    this.fontFamily = '',
  });

  final String hostId;
  final AppPalette palette;
  final DateTime syncedAt;

  /// The machine's monospace font family, as reported.
  final String fontFamily;

  /// The bundled font matching [fontFamily], if any.
  TerminalFontOption? get font => terminalFontForFamily(fontFamily);

  Map<String, Object?> toJson() => {
    'hostId': hostId,
    'syncedAt': syncedAt.toUtc().toIso8601String(),
    'fontFamily': fontFamily,
    if (palette.custom) ...{
      'name': palette.label,
      'colors': palette.colors.toJson(),
    } else
      'palette': palette.id,
  };

  static OmarchySyncedTheme? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final hostId = json['hostId'];
    final syncedAt = DateTime.tryParse(json['syncedAt']?.toString() ?? '');
    if (hostId is! String || syncedAt == null) {
      return null;
    }
    AppPalette? palette;
    final colors = json['colors'];
    if (colors is Map) {
      final resolved = OmarchyColors.fromJson(colors.cast<String, Object?>());
      final name = json['name']?.toString() ?? 'Custom';
      if (resolved != null) {
        palette = AppPalette.custom(name: name, colors: resolved);
      }
    } else {
      palette = AppPalette.byId(json['palette']?.toString());
    }
    if (palette == null) {
      return null;
    }
    return OmarchySyncedTheme(
      hostId: hostId,
      palette: palette,
      syncedAt: syncedAt,
      fontFamily: json['fontFamily']?.toString() ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OmarchySyncedTheme &&
      other.hostId == hostId &&
      other.palette == palette &&
      other.syncedAt == syncedAt &&
      other.fontFamily == fontFamily;

  @override
  int get hashCode => Object.hash(hostId, palette, syncedAt, fontFamily);
}
