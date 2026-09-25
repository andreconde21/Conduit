import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

class ConduitWordmark extends StatelessWidget {
  const ConduitWordmark({
    super.key,
    this.size = 28,
    this.showSubtitle = false,
    this.subtitle = 'SSH workspaces',
  });

  final double size;
  final bool showSubtitle;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConduitGlyph(size: size * 0.95),
        SizedBox(width: size * 0.4),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Conductore',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontSize: size * 0.72,
                height: 1,
              ),
            ),
            if (showSubtitle) ...[
              SizedBox(height: size * 0.18),
              Text(
                subtitle,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontSize: size * 0.4,
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Conductore's mark: a shell prompt chevron and a conductor's baton.
/// The Android launcher icon draws the same shapes
/// (android/app/src/main/res/drawable/ic_launcher_foreground.xml).
class ConduitGlyph extends StatelessWidget {
  const ConduitGlyph({super.key, this.size = 28, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: ConductoreMarkPainter(tint)),
    );
  }
}

/// Paints [ConduitGlyph] in a unit box; shared with the icon tests.
class ConductoreMarkPainter extends CustomPainter {
  ConductoreMarkPainter(this.color);

  final Color color;

  /// Chevron corner points and baton ends, in the unit square. Keep in
  /// sync with the launcher vector (its 60dp glyph box starts at 24dp).
  static const chevron = [
    Offset(0.14, 0.26),
    Offset(0.42, 0.5),
    Offset(0.14, 0.74),
  ];
  static const batonTip = Offset(0.88, 0.2);
  static const batonHandle = Offset(0.53, 0.78);

  @override
  void paint(Canvas canvas, Size size) {
    Offset at(Offset unit) =>
        Offset(unit.dx * size.width, unit.dy * size.height);
    final w = size.width;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final prompt = Path()
      ..moveTo(at(chevron[0]).dx, at(chevron[0]).dy)
      ..lineTo(at(chevron[1]).dx, at(chevron[1]).dy)
      ..lineTo(at(chevron[2]).dx, at(chevron[2]).dy);
    canvas.drawPath(
      prompt,
      stroke
        ..color = color
        ..strokeWidth = w * 0.11,
    );
    canvas.drawLine(
      at(batonHandle),
      at(batonTip),
      stroke
        ..color = color.withValues(alpha: 0.72)
        ..strokeWidth = w * 0.055,
    );
    canvas.drawCircle(at(batonHandle), w * 0.085, Paint()..color = color);
  }

  @override
  bool shouldRepaint(ConductoreMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// The page background: the theme's flat background. (Conduit drew
/// accent glows here; Omarchy's look is flat.)
class ConduitBackdrop extends StatelessWidget {
  const ConduitBackdrop({
    required this.palette,
    required this.child,
    super.key,
  });

  final AppPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: palette.canvas),
      child: child,
    );
  }
}

class ConduitStatusPill extends StatelessWidget {
  const ConduitStatusPill({
    required this.label,
    required this.color,
    super.key,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: icon == null ? 9 : 7,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppTheme.borderRadius,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 5),
          ] else ...[
            Container(width: 6, height: 6, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontFamily: AppTheme.monoFontFamily,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class ConduitSectionLabel extends StatelessWidget {
  const ConduitSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: colorScheme.onSurfaceVariant,
        fontFamily: AppTheme.monoFontFamily,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
    );
  }
}
