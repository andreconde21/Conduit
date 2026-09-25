import 'package:conduit/core/theme/omarchy_colors.dart';
import 'package:conduit/core/theme/omarchy_themes.dart';
import 'package:conduit_vt/conduit_vt.dart';
import 'package:flutter/material.dart';

/// One app theme: an Omarchy theme's colours mapped onto the app chrome and
/// the terminal.
///
/// The bundled palettes are Omarchy's built-in themes
/// (https://github.com/basecamp/omarchy themes/, MIT); [AppPalette.custom]
/// wraps a theme read from a machine at runtime (Omarchy theme sync). Each
/// theme is either dark or light, and the theme decides the app brightness,
/// like Omarchy itself. The `*For(Brightness)` helpers keep their signature
/// for the widgets that call them but always answer with this theme's
/// colours.
@immutable
class AppPalette {
  const AppPalette._(this.id, this.label, this.colors) : custom = false;

  /// A theme that is not bundled, e.g. a user's own Omarchy theme.
  AppPalette.custom({required String name, required this.colors})
    : id = '$customIdPrefix${omarchyThemeSlug(name)}',
      label = omarchyThemeLabel(name),
      custom = true;

  static const customIdPrefix = 'omarchy-custom:';

  /// Stable id: the Omarchy theme directory name (`tokyo-night`).
  final String id;
  final String label;
  final OmarchyColors colors;

  /// Whether this theme came from a machine rather than the bundle.
  final bool custom;

  static const catppuccin = AppPalette._(
    'catppuccin',
    'Catppuccin',
    omarchyCatppuccin,
  );
  static const catppuccinLatte = AppPalette._(
    'catppuccin-latte',
    'Catppuccin Latte',
    omarchyCatppuccinLatte,
  );
  static const ethereal = AppPalette._('ethereal', 'Ethereal', omarchyEthereal);
  static const everforest = AppPalette._(
    'everforest',
    'Everforest',
    omarchyEverforest,
  );
  static const flexokiLight = AppPalette._(
    'flexoki-light',
    'Flexoki Light',
    omarchyFlexokiLight,
  );
  static const gruvbox = AppPalette._('gruvbox', 'Gruvbox', omarchyGruvbox);
  static const hackerman = AppPalette._(
    'hackerman',
    'Hackerman',
    omarchyHackerman,
  );
  static const kanagawa = AppPalette._('kanagawa', 'Kanagawa', omarchyKanagawa);
  static const lastHorizon = AppPalette._(
    'last-horizon',
    'Last Horizon',
    omarchyLastHorizon,
  );
  static const lumon = AppPalette._('lumon', 'Lumon', omarchyLumon);
  static const lupine = AppPalette._('lupine', 'Lupine', omarchyLupine);
  static const matteBlack = AppPalette._(
    'matte-black',
    'Matte Black',
    omarchyMatteBlack,
  );
  static const miasma = AppPalette._('miasma', 'Miasma', omarchyMiasma);
  static const nord = AppPalette._('nord', 'Nord', omarchyNord);
  static const osakaJade = AppPalette._(
    'osaka-jade',
    'Osaka Jade',
    omarchyOsakaJade,
  );
  static const retro82 = AppPalette._('retro-82', 'Retro 82', omarchyRetro82);
  static const ristretto = AppPalette._(
    'ristretto',
    'Ristretto',
    omarchyRistretto,
  );
  static const rosePine = AppPalette._(
    'rose-pine',
    'Rose Pine',
    omarchyRosePine,
  );
  static const solitude = AppPalette._('solitude', 'Solitude', omarchySolitude);
  static const tokyoNight = AppPalette._(
    'tokyo-night',
    'Tokyo Night',
    omarchyTokyoNight,
  );
  static const vantablack = AppPalette._(
    'vantablack',
    'Vantablack',
    omarchyVantablack,
  );
  static const white = AppPalette._('white', 'White', omarchyWhite);

  /// The theme for new installs and for the retired Conduit palettes.
  static const AppPalette defaultPalette = everforest;

  /// Every bundled theme, in Omarchy's (alphabetical) order.
  static const List<AppPalette> values = [
    catppuccin,
    catppuccinLatte,
    ethereal,
    everforest,
    flexokiLight,
    gruvbox,
    hackerman,
    kanagawa,
    lastHorizon,
    lumon,
    lupine,
    matteBlack,
    miasma,
    nord,
    osakaJade,
    retro82,
    ristretto,
    rosePine,
    solitude,
    tokyoNight,
    vantablack,
    white,
  ];

  /// Conduit's old palette ids that have an Omarchy theme of the same
  /// name and brightness. Every other old id (and the old default,
  /// `synthwave`) migrates to [defaultPalette].
  static const Map<String, String> legacyIds = {
    'catppuccin': 'catppuccin',
    'tokyoNight': 'tokyo-night',
    'nord': 'nord',
    'gruvbox': 'gruvbox',
    'kanagawa': 'kanagawa',
    'everforest': 'everforest',
  };

  /// The bundled theme with this [id], or null.
  static AppPalette? byId(String? id) {
    for (final palette in values) {
      if (palette.id == id) {
        return palette;
      }
    }
    return null;
  }

  /// A saved palette id, migrating Conduit's retired palettes.
  static AppPalette fromStoredId(String? id) {
    return byId(id) ?? byId(legacyIds[id]) ?? defaultPalette;
  }

  /// The bundled theme for an Omarchy theme name as the machine reports
  /// it (`tokyo-night`, `Tokyo Night`), or null for an unknown theme.
  static AppPalette? forOmarchyThemeName(String name) =>
      byId(omarchyThemeSlug(name));

  String get name => id;

  String get caption => custom
      ? 'Custom Omarchy theme'
      : isDark
      ? 'Dark'
      : 'Light';

  bool get isDark => colors.isDark;

  Brightness get brightness => isDark ? Brightness.dark : Brightness.light;

  ThemeMode get themeMode => isDark ? ThemeMode.dark : ThemeMode.light;

  Color get seed => accent;

  Color get accent => colors.accent;

  /// A second hue for the rare two-tone mark: the theme's blue, or its
  /// cyan when blue is already the accent.
  Color get accentSecondary =>
      colors.blue == colors.accent ? colors.cyan : colors.blue;

  /// The terminal background: every surface starts from it.
  Color get canvas => colors.background;

  /// Cards and bars: the background nudged a few percent toward the text.
  Color get panel => mixOmarchyColor(
    colors.background,
    colors.foreground,
    isDark ? 0.045 : 0.035,
  );

  /// Sheets, dialogs and menus.
  Color get panelElevated => mixOmarchyColor(
    colors.background,
    colors.foreground,
    isDark ? 0.085 : 0.06,
  );

  /// The thin 1px border every card and field draws: Omarchy's muted
  /// colour, softened toward the background.
  Color get hairline => mixOmarchyColor(colors.background, colors.muted, 0.7);

  /// A stronger border (outlined buttons, focused outlines): muted itself.
  Color get border => colors.muted;

  Color get foreground => colors.foreground;
  Color get mutedForeground =>
      mixOmarchyColor(colors.foreground, colors.background, 0.3);
  Color get subtleForeground =>
      mixOmarchyColor(colors.foreground, colors.background, 0.46);
  Color get success => colors.green;
  Color get warning => colors.yellow;
  Color get danger => colors.red;

  Color get accentSoft => accent.withValues(alpha: 0.16);
  Color get accentGlow => accent.withValues(alpha: 0.08);
  Color get accentOnDark => Color.lerp(accent, Colors.black, 0.55)!;

  /// Text drawn on a filled accent surface: the dark background on a
  /// light accent, white on a dark one.
  Color get onAccent {
    if (accent.computeLuminance() > 0.3) {
      return isDark ? canvas : const Color(0xFF111111);
    }
    return Colors.white;
  }

  Color canvasFor(Brightness _) => canvas;
  Color panelFor(Brightness _) => panel;
  Color panelElevatedFor(Brightness _) => panelElevated;
  Color hairlineFor(Brightness _) => hairline;
  Color borderFor(Brightness _) => border;
  Color foregroundFor(Brightness _) => foreground;
  Color mutedForegroundFor(Brightness _) => mutedForeground;
  Color subtleForegroundFor(Brightness _) => subtleForeground;

  Color terminalBackgroundFor(Brightness _) => canvas;
  Color terminalPanelFor(Brightness _) => panel;
  Color terminalForegroundFor(Brightness _) => foreground;
  Color terminalMutedForegroundFor(Brightness _) => mutedForeground;
  Color terminalBorderFor(Brightness _) => hairline;

  TerminalTheme terminalThemeFor(Brightness _) => terminalTheme;
  TerminalTheme get lightTerminalTheme => terminalTheme;

  /// The 16 ANSI colours exactly as Omarchy's alacritty template maps
  /// them (`default/themed/alacritty.toml.tpl`): black is the background,
  /// bright black is muted, white is the foreground, bright white is
  /// bright_foreground; search hits use yellow and red.
  ///
  /// The terminal paints the selection over the text, so it is the accent
  /// at low alpha rather than Omarchy's opaque selection colour.
  TerminalTheme get terminalTheme => _terminalThemes[this] ??= TerminalTheme(
    cursor: colors.brightForeground,
    selection: accent.withValues(alpha: isDark ? 0.32 : 0.26),
    foreground: colors.foreground,
    background: colors.background,
    black: colors.background,
    red: colors.red,
    green: colors.green,
    yellow: colors.yellow,
    blue: colors.blue,
    magenta: colors.magenta,
    cyan: colors.cyan,
    white: colors.foreground,
    brightBlack: colors.muted,
    brightRed: colors.brightRed,
    brightGreen: colors.brightGreen,
    brightYellow: colors.brightYellow,
    brightBlue: colors.brightBlue,
    brightMagenta: colors.brightMagenta,
    brightCyan: colors.brightCyan,
    brightWhite: colors.brightForeground,
    searchHitBackground: colors.yellow,
    searchHitBackgroundCurrent: colors.red,
    searchHitForeground: colors.background,
  );

  static final Expando<TerminalTheme> _terminalThemes = Expando();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppPalette && other.id == id && other.colors == colors;

  @override
  int get hashCode => Object.hash(id, colors);

  @override
  String toString() => 'AppPalette($id)';
}

/// Omarchy's theme directory name for a displayed or raw theme name:
/// `Tokyo Night` and `tokyo-night` both give `tokyo-night`.
String omarchyThemeSlug(String name) => name
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[\s_]+'), '-')
    .replaceAll(RegExp(r'[^a-z0-9.-]'), '');

/// The display name Omarchy's `omarchy-theme-current` prints.
String omarchyThemeLabel(String name) => omarchyThemeSlug(name)
    .split('-')
    .where((part) => part.isNotEmpty)
    .map((part) => part[0].toUpperCase() + part.substring(1))
    .join(' ');
