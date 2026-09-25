import 'dart:ui' as ui;

import 'package:conduit/core/theme/app_palette.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The terminal multiplexers the app attaches sessions to.
enum MultiplexerKind {
  tmux,
  herdr;

  String get label => switch (this) {
    MultiplexerKind.tmux => 'tmux',
    MultiplexerKind.herdr => 'Herdr',
  };
}

/// The official logo of a terminal multiplexer, drawn from the path data of
/// its upstream SVG (see `third_party/brand/README.md`):
///
/// * tmux: the logomark from `tmux/tmux` `logo/tmux-logomark.svg` (ISC,
///   Copyright (c) 2015 Jason Long): a dark screen split into panes above
///   the green status bar.
/// * Herdr: `herdrdev/herdr` `assets/logo.svg` (Apache-2.0): the dark
///   herding-dog mark with a `>_` prompt on its light grey square.
///
/// Brand colours are the logos' own, with one exception: on a dark theme
/// the tmux screen is drawn in the theme's foreground, because the official
/// dark grey all but disappears on a dark background. The shape and the
/// green status bar stay exactly as upstream. Herdr's square is rounded to
/// sit with the app's other badges.
class MultiplexerIcon extends StatelessWidget {
  const MultiplexerIcon(
    this.kind, {
    this.size = 18,
    this.semanticLabel,
    super.key,
  });

  final MultiplexerKind kind;
  final double size;

  /// Read by screen readers; defaults to the multiplexer's name. Pass an
  /// empty string when a neighbouring label already names it.
  final String? semanticLabel;

  /// The colour of the tmux logomark's screen: the official grey on light
  /// themes, the theme foreground on dark ones.
  static Color tmuxScreenColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? AppPalette.of(context).foreground
      : _TmuxLogoPainter.officialScreenGrey;

  @override
  Widget build(BuildContext context) {
    final label = semanticLabel ?? kind.label;
    final icon = SizedBox.square(
      key: ValueKey('multiplexer-icon-${kind.name}'),
      dimension: size,
      child: CustomPaint(
        painter: switch (kind) {
          MultiplexerKind.tmux => _TmuxLogoPainter(tmuxScreenColor(context)),
          MultiplexerKind.herdr => const _HerdrLogoPainter(),
        },
      ),
    );
    if (label.isEmpty) return ExcludeSemantics(child: icon);
    return Semantics(label: label, image: true, child: icon);
  }
}

/// tmux logomark, 160 × 160 viewBox.
class _TmuxLogoPainter extends CustomPainter {
  const _TmuxLogoPainter(this.screenColor);

  static const _statusBarGreen = Color(0xFF1BB91F);

  /// The logomark's own screen colour, used on light themes.
  static const officialScreenGrey = Color(0xFF3C3C3C);

  final Color screenColor;

  // The logo's group is `fill-rule="evenodd"`: the bar's two overlapping
  // subpaths leave only the rounded strip under the screen.
  static final ui.Path _statusBar = parseSvgPathData(
    _tmuxStatusBarData,
  ).shift(const Offset(0, 116))..fillType = PathFillType.evenOdd;
  static final ui.Path _screen = parseSvgPathData(_tmuxScreenData)
    ..fillType = PathFillType.evenOdd;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / 160, size.height / 160)
      ..drawPath(_statusBar, Paint()..color = _statusBarGreen)
      ..drawPath(_screen, Paint()..color = screenColor)
      ..restore();
  }

  @override
  bool shouldRepaint(_TmuxLogoPainter oldDelegate) =>
      oldDelegate.screenColor != screenColor;
}

/// Herdr logo, 512 × 512 viewBox; the mark is potrace output in a
/// `translate(0 512) scale(.1 -.1)` group.
class _HerdrLogoPainter extends CustomPainter {
  const _HerdrLogoPainter();

  static const _background = Color(0xFFD9DAD8);
  static const _mark = Color(0xFF303438);

  static final ui.Path _markPath = parseSvgPathData(_herdrMarkData).transform(
    Float64List.fromList([
      0.1, 0, 0, 0, //
      0, -0.1, 0, 0, //
      0, 0, 1, 0, //
      0, 512, 0, 1, //
    ]),
  );

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 512;
    canvas
      ..save()
      ..scale(scale, size.height / 512)
      ..clipRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, 512, 512),
          const Radius.circular(112),
        ),
      )
      ..drawRect(
        const Rect.fromLTWH(0, 0, 512, 512),
        Paint()..color = _background,
      )
      ..drawPath(_markPath, Paint()..color = _mark)
      ..restore();
  }

  @override
  bool shouldRepaint(_HerdrLogoPainter oldDelegate) => false;
}

/// Registers the logos' notices on Flutter's licence page.
void registerMultiplexerLogoLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(['tmux logo'], _tmuxLogoLicense);
    yield const LicenseEntryWithLineBreaks(['Herdr logo'], _herdrLogoNotice);
  });
}

/// Parses SVG path data (`M L H V C S Q T Z`, absolute and relative, with
/// implicit repeats) into a [ui.Path]. Arcs are not supported: neither logo
/// uses them.
@visibleForTesting
ui.Path parseSvgPathData(String data) {
  final path = ui.Path();
  final tokens = RegExp(
    r'[MmLlHhVvCcSsQqTtZz]|[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?',
  ).allMatches(data).map((match) => match.group(0)!).toList();
  var index = 0;
  var command = '';
  var x = 0.0;
  var y = 0.0;
  var startX = 0.0;
  var startY = 0.0;
  var controlX = 0.0;
  var controlY = 0.0;
  var previous = '';

  bool isCommand(String token) => RegExp(r'^[A-Za-z]$').hasMatch(token);
  double next() => double.parse(tokens[index++]);

  while (index < tokens.length) {
    if (isCommand(tokens[index])) {
      command = tokens[index++];
    } else if (command.isEmpty) {
      throw FormatException('Path data must start with a command: $data');
    }
    final relative = command == command.toLowerCase();
    final dx = relative ? x : 0.0;
    final dy = relative ? y : 0.0;
    switch (command.toUpperCase()) {
      case 'M':
        x = next() + dx;
        y = next() + dy;
        startX = x;
        startY = y;
        path.moveTo(x, y);
        // Further pairs after a moveto are implicit linetos.
        command = relative ? 'l' : 'L';
      case 'L':
        x = next() + dx;
        y = next() + dy;
        path.lineTo(x, y);
      case 'H':
        x = next() + dx;
        path.lineTo(x, y);
      case 'V':
        y = next() + dy;
        path.lineTo(x, y);
      case 'C':
        final x1 = next() + dx;
        final y1 = next() + dy;
        controlX = next() + dx;
        controlY = next() + dy;
        x = next() + dx;
        y = next() + dy;
        path.cubicTo(x1, y1, controlX, controlY, x, y);
      case 'S':
        final reflect = previous == 'C' || previous == 'S';
        final x1 = reflect ? 2 * x - controlX : x;
        final y1 = reflect ? 2 * y - controlY : y;
        controlX = next() + dx;
        controlY = next() + dy;
        x = next() + dx;
        y = next() + dy;
        path.cubicTo(x1, y1, controlX, controlY, x, y);
      case 'Q':
        controlX = next() + dx;
        controlY = next() + dy;
        x = next() + dx;
        y = next() + dy;
        path.quadraticBezierTo(controlX, controlY, x, y);
      case 'T':
        final reflect = previous == 'Q' || previous == 'T';
        controlX = reflect ? 2 * x - controlX : x;
        controlY = reflect ? 2 * y - controlY : y;
        x = next() + dx;
        y = next() + dy;
        path.quadraticBezierTo(controlX, controlY, x, y);
      case 'Z':
        path.close();
        x = startX;
        y = startY;
      default:
        throw FormatException('Unsupported path command "$command".');
    }
    previous = command.toUpperCase();
  }
  return path;
}

// Path data copied verbatim from third_party/brand.

const _tmuxStatusBarData =
    'M0,0 L160,0 L160,28.9961276 C160,37.2825375 153.278035,44 '
    '145.001535,44 L14.9984654,44 C6.71504169,44 0,37.2934149 '
    '0,28.9961276 L0,0 Z M0,0 L160,0 L160,30 L0,30 L0,0 Z';

const _tmuxScreenData =
    'M83,70 L83,0 L77,0 L77,146 L83,146 L83,76 L160,76 L160,70 L83,70 '
    'Z M0,15.0064867 C0,6.71863293 6.72196489,0 14.9984654,0 '
    'L145.001535,0 C153.284958,0 160,6.72491953 160,15.0064867 '
    'L160,146 L0,146 L0,15.0064867 Z';

const _herdrMarkData =
    'M2794 3710 c-129 -33 -299 -135 -359 -214 -21 -28 -26 -42 -21 -63 '
    '9 -38 154 -178 199 -192 32 -11 41 -9 104 23 171 86 354 70 475 -43 '
    '150 -138 150 -379 0 -511 -107 -95 -278 -94 -386 2 l-46 40 -11 -29 '
    'c-16 -40 -14 -122 4 -164 60 -144 264 -222 452 -174 360 92 559 494 '
    '430 868 -36 103 -81 173 -175 267 -71 72 -100 93 -180 132 -52 26 '
    '-127 54 -167 62 -96 21 -230 20 -319 -4z M2183 3695 c-116 -32 -221 '
    '-108 -273 -199 -17 -28 -30 -54 -30 -58 0 -4 20 1 45 12 66 28 220 '
    '68 294 76 64 7 65 7 137 83 40 41 71 77 69 79 -2 2 -21 8 -42 13 '
    '-55 12 -140 10 -200 -6z M2212 3388 c-159 -22 -390 -122 -559 -241 '
    '-299 -210 -585 -600 -609 -828 -12 -118 40 -251 125 -318 96 -76 '
    '178 -98 426 -116 110 -8 224 -21 254 -29 125 -34 230 -115 272 -211 '
    '11 -24 24 -81 30 -127 20 -170 65 -271 166 -374 34 -35 63 -65 63 '
    '-67 0 -1 -10 -27 -22 -57 -29 -76 -37 -259 -14 -350 42 -170 158 '
    '-318 311 -397 44 -23 98 -46 120 -52 22 -6 45 -14 51 -18 5 -5 15 '
    '-48 22 -96 6 -48 14 -92 17 -97 4 -6 415 -10 1131 -10 l1124 0 0 '
    '1584 0 1585 -55 -19 c-84 -29 -143 -68 -232 -154 l-83 -78 -54 49 '
    'c-111 102 -233 151 -391 160 -113 6 -199 -10 -298 -54 l-60 -27 -26 '
    '34 c-37 51 -120 134 -127 128 -3 -4 0 -34 7 -67 17 -89 7 -268 -21 '
    '-356 -103 -328 -377 -545 -688 -545 -161 0 -273 41 -373 137 -37 35 '
    '-66 75 -85 116 -79 173 -8 407 124 407 44 0 68 -14 117 -66 74 -78 '
    '167 -82 238 -9 60 62 72 147 33 231 -42 90 -120 130 -238 122 -50 '
    '-4 -85 -14 -131 -37 -89 -45 -122 -52 -176 -40 -92 20 -262 163 '
    '-302 253 -11 25 -21 45 -22 45 -1 -1 -30 -6 -65 -11z m-256 -505 '
    'c115 -88 129 -102 132 -131 2 -18 -2 -40 -9 -49 -7 -8 -69 -55 -138 '
    '-105 -103 -73 -130 -88 -151 -83 -35 8 -51 34 -48 74 3 31 12 42 83 '
    '92 44 31 80 61 82 66 1 4 -30 31 -69 58 -39 28 -77 56 -85 63 -18 '
    '19 -16 72 4 94 32 35 63 23 199 -79z m528 -88 c23 -24 28 -52 14 '
    '-82 l-13 -28 -141 -3 c-130 -2 -142 -1 -158 17 -23 26 -24 66 -1 91 '
    '16 18 32 20 151 20 105 0 136 -3 148 -15z';

const _tmuxLogoLicense = '''
Copyright (c) 2015, Jason Long <jason@jasonlong.me>

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.''';

const _herdrLogoNotice = '''
The Herdr logo (https://github.com/herdrdev/herdr, assets/logo.svg) is part
of the Herdr repository, licensed under the Apache License, Version 2.0
(https://www.apache.org/licenses/LICENSE-2.0). It is shown only to identify
Herdr sessions. Unless required by applicable law or agreed to in writing,
it is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
ANY KIND, either express or implied.''';
