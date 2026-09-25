import 'package:conduit/core/platform_features.dart';
import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/core/theme/app_theme.dart';
import 'package:conduit/features/desktop_shell/domain/shell_layout.dart';
import 'package:conduit/features/desktop_shell/domain/sidebar_tree.dart';
import 'package:conduit/features/desktop_shell/presentation/widgets/shell_split_area.dart';
import 'package:conduit/features/desktop_shell/presentation/widgets/shell_state_dot.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// One tab of the shell's tab strip.
@immutable
class ShellTabData {
  const ShellTabData({
    required this.viewId,
    required this.label,
    required this.leading,
    this.tooltip = '',
    this.dot = SidebarDot.none,
    this.unread = false,
    this.dirty = false,
    this.listenable,
    this.isSession = false,
  });

  final String viewId;
  final String label;
  final String tooltip;
  final Widget leading;
  final SidebarDot dot;

  /// New output or an agent change since the tab was last on screen.
  final bool unread;

  /// Unsaved edits (file tabs).
  final bool dirty;

  /// Rebuilds the tab when its title may have changed (tool tabs).
  final Listenable? listenable;
  final bool isSession;
}

/// What the tab's context menu asks for.
enum ShellTabAction { splitRight, splitDown, openInPane, close }

/// The tabs across the top of the main area: every open view (terminal
/// sessions, Chat View, files, diffs, live previews). The focused view is
/// highlighted; views shown in another pane are outlined. Drag a tab onto
/// a pane's edge to split, right-click for the same as a menu.
class ShellTabStrip extends StatelessWidget {
  const ShellTabStrip({
    required this.tabs,
    required this.focusedViewId,
    required this.visibleViews,
    required this.onSelect,
    required this.onClose,
    required this.onAction,
    this.canSplit = true,
    super.key,
  });

  final List<ShellTabData> tabs;
  final String? focusedViewId;
  final Set<String> visibleViews;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;
  final void Function(String viewId, ShellTabAction action) onAction;
  final bool canSplit;

  static const tabHeight = 30.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: tabHeight,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: const {
            PointerDeviceKind.touch,
            PointerDeviceKind.trackpad,
          },
        ),
        child: ListView.separated(
          key: const ValueKey('shell-tab-strip'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          itemCount: tabs.length,
          separatorBuilder: (_, _) => const SizedBox(width: 4),
          itemBuilder: (context, index) {
            final tab = tabs[index];
            final listenable = tab.listenable;
            Widget build(BuildContext context) => _ShellTab(
              tab: tab,
              focused: tab.viewId == focusedViewId,
              visible: visibleViews.contains(tab.viewId),
              canSplit: canSplit,
              onSelect: () => onSelect(tab.viewId),
              onClose: () => onClose(tab.viewId),
              onAction: (action) => onAction(tab.viewId, action),
            );
            return KeyedSubtree(
              key: ValueKey('shell-tab-${tab.viewId}'),
              child: listenable == null
                  ? build(context)
                  : ListenableBuilder(
                      listenable: listenable,
                      builder: (c, _) => build(c),
                    ),
            );
          },
        ),
      ),
    );
  }
}

class _ShellTab extends StatefulWidget {
  const _ShellTab({
    required this.tab,
    required this.focused,
    required this.visible,
    required this.canSplit,
    required this.onSelect,
    required this.onClose,
    required this.onAction,
  });

  final ShellTabData tab;
  final bool focused;
  final bool visible;
  final bool canSplit;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final ValueChanged<ShellTabAction> onAction;

  @override
  State<_ShellTab> createState() => _ShellTabState();
}

class _ShellTabState extends State<_ShellTab> {
  bool _hovered = false;

  Future<void> _showMenu(Offset position) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<ShellTabAction>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          enabled: widget.canSplit,
          value: ShellTabAction.splitRight,
          child: const _MenuRow(Icons.vertical_split_outlined, 'Split right'),
        ),
        PopupMenuItem(
          enabled: widget.canSplit,
          value: ShellTabAction.splitDown,
          child: const _MenuRow(Icons.horizontal_split_outlined, 'Split down'),
        ),
        const PopupMenuItem(
          value: ShellTabAction.openInPane,
          child: _MenuRow(Icons.open_in_full_rounded, 'Show in this pane'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: ShellTabAction.close,
          child: _MenuRow(Icons.close_rounded, 'Close'),
        ),
      ],
    );
    if (action != null) widget.onAction(action);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final tab = widget.tab;
    final focused = widget.focused;
    final foreground = palette.foreground;
    final muted = palette.mutedForeground;
    final background = focused
        ? Color.alphaBlend(
            palette.accent.withValues(alpha: 0.16),
            palette.panel,
          )
        : _hovered
        ? palette.panel
        : Colors.transparent;
    final label = Text(
      tab.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: focused || tab.unread ? foreground : muted,
        fontSize: 12.5,
        fontWeight: focused || tab.unread ? FontWeight.w800 : FontWeight.w600,
      ),
    );
    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      constraints: const BoxConstraints(maxWidth: 200),
      height: ShellTabStrip.tabHeight,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(
          color: focused
              ? palette.accent.withValues(alpha: 0.6)
              : widget.visible
              ? palette.accent.withValues(alpha: 0.3)
              : palette.hairline,
        ),
      ),
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          tab.leading,
          const SizedBox(width: 6),
          Flexible(child: label),
          if (tab.unread && !focused) ...[
            const SizedBox(width: 5),
            const ShellUnreadBadge(count: 1),
          ],
          if (tab.dot != SidebarDot.none) ...[
            const SizedBox(width: 6),
            ShellStateDot(dot: tab.dot, size: 7),
          ],
          if (tab.dirty) ...[
            const SizedBox(width: 4),
            Container(
              key: const ValueKey('dirty-dot'),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: palette.accent,
                shape: BoxShape.circle,
              ),
            ),
          ],
          SizedBox(
            width: 26,
            height: 26,
            child: focused || _hovered
                ? IconButton(
                    key: ValueKey('shell-tab-close-${tab.viewId}'),
                    tooltip: 'Close',
                    iconSize: 14,
                    padding: EdgeInsets.zero,
                    color: muted,
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded),
                  )
                : null,
          ),
        ],
      ),
    );
    final tappable = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Listener(
        // Middle click closes, like a browser tab.
        onPointerDown: (event) {
          if (event.buttons == kMiddleMouseButton) widget.onClose();
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onSelect,
          onSecondaryTapUp: (details) => _showMenu(details.globalPosition),
          onLongPressStart: (details) => _showMenu(details.globalPosition),
          child: chip,
        ),
      ),
    );
    return Tooltip(
      message: tab.tooltip.isEmpty ? tab.label : tab.tooltip,
      waitDuration: const Duration(milliseconds: 700),
      child: Draggable<ShellViewDrag>(
        data: ShellViewDrag(tab.viewId, tab.label),
        // With touch (tablets) a sideways drag scrolls the strip: tabs
        // are pulled down into the panes.
        affinity: PlatformFeatures.isDesktop ? null : Axis.vertical,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: _DragFeedback(label: tab.label, leading: tab.leading),
        childWhenDragging: Opacity(opacity: 0.45, child: chip),
        child: tappable,
      ),
    );
  }
}

class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.label, required this.leading});

  final String label;
  final Widget leading;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: palette.panelElevated,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: palette.accent),
          boxShadow: const [
            BoxShadow(color: Color(0x40000000), blurRadius: 10),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            leading,
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: palette.foreground,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18),
      const SizedBox(width: 10),
      Flexible(
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    ],
  );
}

/// The split a tab action asks for.
ShellEdge? edgeForTabAction(ShellTabAction action) => switch (action) {
  ShellTabAction.splitRight => ShellEdge.right,
  ShellTabAction.splitDown => ShellEdge.bottom,
  ShellTabAction.openInPane => ShellEdge.center,
  ShellTabAction.close => null,
};
