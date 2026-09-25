import 'package:conduit/core/platform_features.dart';
import 'package:flutter/widgets.dart';

/// Widest the home screen's content grows on a desktop window; beyond it the
/// content stays centred instead of stretching cards across a 27" screen.
const desktopContentMaxWidth = 960.0;

/// Horizontal inset that centres [desktopContentMaxWidth] of content in
/// [width]. Zero on phones and tablets, whose layout is unchanged.
double desktopSideInset(double width) {
  if (!PlatformFeatures.isDesktop || width <= desktopContentMaxWidth) {
    return 0;
  }
  return (width - desktopContentMaxWidth) / 2;
}

/// Wraps a scroll view's slivers so that, on desktop, they are centred at
/// [desktopContentMaxWidth]. The scroll view itself stays full width, so the
/// mouse wheel and the scrollbar work anywhere in the window.
List<Widget> centerSliversOnDesktop(List<Widget> slivers) {
  if (!PlatformFeatures.isDesktop) return slivers;
  return [
    SliverLayoutBuilder(
      builder: (context, constraints) => SliverPadding(
        padding: EdgeInsets.symmetric(
          horizontal: desktopSideInset(constraints.crossAxisExtent),
        ),
        sliver: SliverMainAxisGroup(slivers: slivers),
      ),
    ),
  ];
}
