import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/features/desktop_shell/domain/sidebar_tree.dart';
import 'package:flutter/material.dart';

/// The colour of a state dot: needs you in the attention colour, working
/// in the accent, done in green, idle muted.
Color shellDotColor(BuildContext context, SidebarDot dot) {
  final palette = AppPalette.of(context);
  return switch (dot) {
    SidebarDot.needsYou => palette.attention,
    SidebarDot.working => Theme.of(context).colorScheme.primary,
    SidebarDot.done => palette.success,
    SidebarDot.idle || SidebarDot.none => palette.inactive,
  };
}

/// A small round state dot (working / needs you / done / idle); nothing for
/// [SidebarDot.none]. Needs you gets a ring so it reads at a glance.
class ShellStateDot extends StatelessWidget {
  const ShellStateDot({required this.dot, this.size = 8, super.key});

  final SidebarDot dot;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (dot == SidebarDot.none) return SizedBox(width: size, height: size);
    final color = shellDotColor(context, dot);
    return Tooltip(
      message: dot.label,
      excludeFromSemantics: true,
      child: Semantics(
        label: dot.label,
        child: Container(
          key: ValueKey('state-dot-${dot.name}'),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: dot == SidebarDot.idle ? Colors.transparent : color,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 1.5),
            boxShadow: dot == SidebarDot.needsYou
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.45),
                      blurRadius: 4,
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
  }
}

/// The unread marker: a small accent dot, with the count when above one.
class ShellUnreadBadge extends StatelessWidget {
  const ShellUnreadBadge({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final palette = AppPalette.of(context);
    if (count == 1) {
      return Container(
        key: const ValueKey('unread-dot'),
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: palette.accent,
          shape: BoxShape.circle,
        ),
      );
    }
    return Container(
      key: const ValueKey('unread-count'),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      constraints: const BoxConstraints(minWidth: 16),
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.accent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TextStyle(
          color: palette.onAccent,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
    );
  }
}
