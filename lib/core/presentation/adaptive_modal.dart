import 'dart:math' as math;

import 'package:conduit/core/platform_features.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// How a modal reads on a desktop (or a window at least
/// [adaptiveModalDesktopWidth] wide). Phones always get the bottom sheet.
enum AdaptiveModalKind {
  /// A short action menu (long-press / overflow / tile / tab actions): a
  /// popover anchored at the button or pointer.
  menu,

  /// A picker, form or confirmation: a centred dialog.
  dialog,

  /// A long list or panel (agent inbox, Herdr / tmux navigators): a panel
  /// sliding in from the right edge.
  sidePanel,

  /// A searchable list (quick switcher, snippets): a command-palette overlay
  /// centred near the top.
  palette,
}

/// How [showAdaptiveModal] actually presented a modal.
enum AdaptiveModalPresentation {
  bottomSheet,
  popover,
  dialog,
  sidePanel,
  palette,
}

/// Window width from which even a phone-class platform (a tablet in
/// landscape, a resizable Android window) gets the desktop presentation.
const adaptiveModalDesktopWidth = 900.0;

/// A DraggableScrollableSheet child size: [phone] on phones, the whole
/// modal on desktop (where there is nothing to drag).
double adaptiveSheetFraction(BuildContext context, double phone) =>
    useDesktopModals(context) ? 1.0 : phone;

/// Remembers where the last pointer went down, so a menu opened by a click
/// or long-press anchors there without every caller passing a position.
/// [install] runs from main(); [showAdaptiveModal] also installs it.
abstract final class AdaptiveModalPointer {
  static Offset? _position;
  static DateTime _at = DateTime.fromMillisecondsSinceEpoch(0);
  static bool _installed = false;

  /// How long a pointer-down stays the anchor of the next menu.
  static const freshness = Duration(seconds: 2);

  static void install() {
    if (_installed) return;
    _installed = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_route);
  }

  static void _route(PointerEvent event) {
    if (event is PointerDownEvent) {
      _position = event.position;
      _at = DateTime.now();
    }
  }

  /// The last pointer-down position if it is recent, else null (a menu
  /// opened from the keyboard opens centred).
  static Offset? get recent =>
      DateTime.now().difference(_at) <= freshness ? _position : null;

  @visibleForTesting
  static void reset() {
    _position = null;
    _at = DateTime.fromMillisecondsSinceEpoch(0);
  }
}

/// Whether modals under [context] use the desktop presentations.
bool useDesktopModals(BuildContext context) =>
    PlatformFeatures.isDesktop ||
    MediaQuery.sizeOf(context).width >= adaptiveModalDesktopWidth;

/// The presentation [showAdaptiveModal] picks for [kind] under [context].
AdaptiveModalPresentation adaptiveModalPresentation(
  BuildContext context,
  AdaptiveModalKind kind,
) {
  if (!useDesktopModals(context)) return AdaptiveModalPresentation.bottomSheet;
  return switch (kind) {
    AdaptiveModalKind.menu => AdaptiveModalPresentation.popover,
    AdaptiveModalKind.dialog => AdaptiveModalPresentation.dialog,
    AdaptiveModalKind.sidePanel => AdaptiveModalPresentation.sidePanel,
    AdaptiveModalKind.palette => AdaptiveModalPresentation.palette,
  };
}

/// Drop-in replacement for [showModalBottomSheet]: the same bottom sheet on
/// phones (every sheet argument is passed through unchanged), and on desktop
/// the presentation [kind] asks for. [builder] is the sheet's content in
/// both cases and pops its result the same way, so callers get identical
/// return values. On desktop, Esc closes and the first text field gets the
/// focus.
///
/// Desktop-only arguments:
/// * [anchorContext] / [anchorPosition]: where a [AdaptiveModalKind.menu]
///   popover opens (the button that opened it, or the pointer's global
///   position). Without either it opens at the last click or long-press
///   ([AdaptiveModalPointer]), and centred when there was none.
/// * [desktopMaxWidth]: the width cap of dialogs and palettes (default 640;
///   menus 320, side panels 440).
/// * [desktopFill]: the content needs a bounded height (an Expanded list, a
///   DraggableScrollableSheet): dialogs and palettes then take their full
///   max height (80% of the window) instead of sizing to the content.
Future<T?> showAdaptiveModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required AdaptiveModalKind kind,
  BuildContext? anchorContext,
  Offset? anchorPosition,
  double? desktopMaxWidth,
  bool desktopFill = false,
  // showModalBottomSheet's arguments, for phones.
  Color? backgroundColor,
  String? barrierLabel,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  Color? barrierColor,
  bool isScrollControlled = false,
  double scrollControlDisabledMaxHeightRatio = 9.0 / 16.0,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  RouteSettings? routeSettings,
  AnimationController? transitionAnimationController,
  Offset? anchorPoint,
  AnimationStyle? sheetAnimationStyle,
}) {
  AdaptiveModalPointer.install();
  final presentation = adaptiveModalPresentation(context, kind);
  if (presentation == AdaptiveModalPresentation.bottomSheet) {
    return showModalBottomSheet<T>(
      context: context,
      builder: builder,
      backgroundColor: backgroundColor,
      barrierLabel: barrierLabel,
      elevation: elevation,
      shape: shape,
      clipBehavior: clipBehavior,
      constraints: constraints,
      barrierColor: barrierColor,
      isScrollControlled: isScrollControlled,
      scrollControlDisabledMaxHeightRatio: scrollControlDisabledMaxHeightRatio,
      useRootNavigator: useRootNavigator,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      showDragHandle: showDragHandle,
      useSafeArea: useSafeArea,
      routeSettings: routeSettings,
      transitionAnimationController: transitionAnimationController,
      anchorPoint: anchorPoint,
      sheetAnimationStyle: sheetAnimationStyle,
    );
  }

  final theme = Theme.of(context);
  final surface =
      backgroundColor ??
      theme.bottomSheetTheme.modalBackgroundColor ??
      theme.bottomSheetTheme.backgroundColor ??
      theme.colorScheme.surfaceContainerHigh;
  final anchor = presentation == AdaptiveModalPresentation.popover
      ? _anchorRect(
          anchorContext,
          anchorPosition ??
              (anchorContext == null ? AdaptiveModalPointer.recent : null),
        )
      : null;

  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    barrierDismissible: isDismissible,
    barrierLabel:
        barrierLabel ??
        MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: presentation == AdaptiveModalPresentation.popover
        ? Colors.transparent
        : (barrierColor ?? Colors.black.withValues(alpha: 0.4)),
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (routeContext, _, _) => _DesktopModal(
      presentation: presentation,
      surface: surface,
      anchor: anchor,
      maxWidth: desktopMaxWidth,
      fill: desktopFill,
      child: Builder(builder: builder),
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      if (presentation == AdaptiveModalPresentation.sidePanel) {
        return SlideTransition(
          position: Tween(
            begin: const Offset(0.15, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      }
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.97, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

Rect? _anchorRect(BuildContext? anchorContext, Offset? anchorPosition) {
  if (anchorPosition != null) {
    return Rect.fromLTWH(anchorPosition.dx, anchorPosition.dy, 0, 0);
  }
  final box = anchorContext?.findRenderObject();
  if (box is RenderBox && box.hasSize && box.attached) {
    return box.localToGlobal(Offset.zero) & box.size;
  }
  return null;
}

class _DesktopModal extends StatelessWidget {
  const _DesktopModal({
    required this.presentation,
    required this.surface,
    required this.anchor,
    required this.maxWidth,
    required this.fill,
    required this.child,
  });

  final AdaptiveModalPresentation presentation;
  final Color surface;
  final Rect? anchor;
  final double? maxWidth;
  final bool fill;
  final Widget child;

  static const _margin = 16.0;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final maxHeight = size.height * 0.8;
    final content = _FocusFirstField(child: child);

    Widget card({
      required double width,
      required double height,
      required bool tight,
      BorderRadius radius = const BorderRadius.all(Radius.circular(14)),
    }) {
      return Material(
        key: ValueKey('adaptive-modal-${presentation.name}'),
        color: surface,
        elevation: 12,
        shadowColor: Colors.black54,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: width,
            minWidth: math.min(width, 280),
            maxHeight: height,
            minHeight: tight ? height : 0,
          ),
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            removeBottom: true,
            child: content,
          ),
        ),
      );
    }

    switch (presentation) {
      case AdaptiveModalPresentation.popover:
        final width = math.min(maxWidth ?? 320, size.width - 2 * _margin);
        final anchor = this.anchor;
        final popover = card(width: width, height: maxHeight, tight: false);
        if (anchor == null) return Center(child: popover);
        return CustomSingleChildLayout(
          delegate: _PopoverLayout(anchor, _margin),
          child: popover,
        );
      case AdaptiveModalPresentation.dialog:
        final width = math.min(maxWidth ?? 640, size.width - 2 * _margin);
        return Center(
          child: card(width: width, height: maxHeight, tight: fill),
        );
      case AdaptiveModalPresentation.palette:
        final width = math.min(maxWidth ?? 640, size.width - 2 * _margin);
        return Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(top: math.min(96, size.height * 0.1)),
            child: card(
              width: width,
              height: math.min(maxHeight, size.height * 0.7),
              tight: fill,
            ),
          ),
        );
      case AdaptiveModalPresentation.sidePanel:
        final width = math.min(maxWidth ?? 440, size.width - 2 * _margin);
        return Align(
          alignment: Alignment.centerRight,
          child: card(
            width: width,
            height: size.height,
            tight: true,
            radius: const BorderRadius.horizontal(left: Radius.circular(14)),
          ),
        );
      case AdaptiveModalPresentation.bottomSheet:
        return content;
    }
  }
}

/// Opens below the anchor (or above when there is no room), aligned to its
/// left edge and kept inside the window.
class _PopoverLayout extends SingleChildLayoutDelegate {
  _PopoverLayout(this.anchor, this.margin);

  final Rect anchor;
  final double margin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest).deflate(EdgeInsets.all(margin));

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final below = anchor.bottom + 4;
    final y = below + childSize.height <= size.height - margin
        ? below
        : math.max(margin, anchor.top - 4 - childSize.height);
    final x = anchor.left
        .clamp(margin, math.max(margin, size.width - margin - childSize.width))
        .toDouble();
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_PopoverLayout oldDelegate) =>
      anchor != oldDelegate.anchor || margin != oldDelegate.margin;
}

/// Moves the focus to the first text field of the modal (a search box, a
/// form's first field) once it is shown, unless something inside already
/// took it (an autofocus field).
class _FocusFirstField extends StatefulWidget {
  const _FocusFirstField({required this.child});

  final Widget child;

  @override
  State<_FocusFirstField> createState() => _FocusFirstFieldState();
}

class _FocusFirstFieldState extends State<_FocusFirstField> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusFirstField());
  }

  void _focusFirstField() {
    if (!mounted) return;
    final primary = FocusManager.instance.primaryFocus?.context;
    if (primary != null && _isInside(primary)) {
      if (primary.widget is EditableText ||
          primary.findAncestorWidgetOfExactType<EditableText>() != null) {
        return;
      }
    }
    EditableText? first;
    void visit(Element element) {
      if (first != null) return;
      final widget = element.widget;
      if (widget is EditableText && !widget.readOnly) {
        first = widget;
        return;
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    first?.focusNode.requestFocus();
  }

  bool _isInside(BuildContext other) {
    var inside = false;
    other.visitAncestorElements((element) {
      if (element == context) {
        inside = true;
        return false;
      }
      return true;
    });
    return inside;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
