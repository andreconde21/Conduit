import 'dart:async';

import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/core/theme/app_theme.dart';
import 'package:conduit/core/theme/terminal_appearance.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/hosts/presentation/widgets/home_session_grid.dart'
    show agentStateColor;
import 'package:conduit/features/terminal/domain/multiplexer_tabs.dart';
import 'package:conduit/features/terminal/presentation/multiplexer_tabs_controller.dart';
import 'package:flutter/material.dart';

/// Whether the strip shows for [tabs] under [visibility]: always, never,
/// or (auto) on a desktop, and on a phone once there are two tabs.
bool showsMultiplexerTabs(
  MultiplexerTabsVisibility visibility, {
  required int tabCount,
  required bool desktop,
}) => switch (visibility) {
  MultiplexerTabsVisibility.never => false,
  MultiplexerTabsVisibility.always => tabCount > 0,
  MultiplexerTabsVisibility.auto => desktop ? tabCount > 0 : tabCount > 1,
};

/// The multiplexer's own tabs under the terminal's top row: one chip per
/// Herdr tab of the focused workspace or tmux window of the session, the
/// active one highlighted and kept in view, a dot for an agent's state or
/// for news since the tab was last shown, and "+" for a new one.
///
/// Tap switches; long-press offers rename, move and close; on a desktop
/// the chips of a tmux session can be dragged into a new order.
class MultiplexerTabStrip extends StatefulWidget {
  const MultiplexerTabStrip({
    required this.controller,
    required this.palette,
    required this.brightness,
    required this.visibility,
    required this.desktop,
    this.onChanged,
    super.key,
  });

  static const height = 32.0;

  final MultiplexerTabsController controller;
  final AppPalette palette;
  final Brightness brightness;
  final MultiplexerTabsVisibility visibility;
  final bool desktop;

  /// After an action from the strip, so the page can refocus the terminal.
  final VoidCallback? onChanged;

  @override
  State<MultiplexerTabStrip> createState() => _MultiplexerTabStripState();
}

class _MultiplexerTabStripState extends State<MultiplexerTabStrip>
    with WidgetsBindingObserver {
  final _activeKey = GlobalKey();
  final _scroll = ScrollController();
  String? _lastActive;
  bool _routeVisible = true;
  bool _appResumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_revealActive);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Covered by another route: tickers are off, stop polling.
    _routeVisible = TickerMode.valuesOf(context).enabled;
    _sync();
  }

  @override
  void didUpdateWidget(covariant MultiplexerTabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller
        ..removeListener(_revealActive)
        ..setVisible(false);
      widget.controller.addListener(_revealActive);
      _lastActive = null;
    }
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    widget.controller.setVisible(
      _routeVisible &&
          _appResumed &&
          widget.visibility != MultiplexerTabsVisibility.never,
    );
    _revealActive();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller
      ..removeListener(_revealActive)
      ..setVisible(false);
    _scroll.dispose();
    super.dispose();
  }

  void _revealActive() {
    final active = widget.controller.active?.id;
    if (active == null || active == _lastActive) return;
    _lastActive = active;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _activeKey.currentContext;
      if (!mounted || target == null) return;
      unawaited(
        Scrollable.ensureVisible(
          target,
          alignment: 0.5,
          duration: MediaQuery.maybeDisableAnimationsOf(context) ?? false
              ? Duration.zero
              : const Duration(milliseconds: 180),
        ),
      );
    });
  }

  String get _noun =>
      widget.controller.kind == MultiplexerTabsKind.tmux ? 'window' : 'tab';

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _select(MultiplexerTab tab) async {
    await widget.controller.select(tab);
    widget.onChanged?.call();
  }

  Future<void> _create() async {
    await widget.controller.create();
    widget.onChanged?.call();
  }

  Future<void> _showActions(MultiplexerTab tab) async {
    final controller = widget.controller;
    final index = controller.tabs.indexWhere((other) => other.id == tab.id);
    final last = controller.tabs.length - 1;
    final action = await showModalBottomSheet<_TabAction>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                tab.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                controller.kind == MultiplexerTabsKind.tmux
                    ? 'tmux window ${tab.index}'
                    : 'Herdr tab',
              ),
            ),
            const Divider(height: 1),
            ListTile(
              key: const ValueKey('mux-tab-rename'),
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: Text('Rename $_noun'),
              onTap: () => Navigator.of(context).pop(_TabAction.rename),
            ),
            if (controller.canReorder) ...[
              ListTile(
                key: const ValueKey('mux-tab-move-left'),
                enabled: index > 0,
                leading: const Icon(Icons.arrow_back_rounded),
                title: const Text('Move left'),
                onTap: () => Navigator.of(context).pop(_TabAction.moveLeft),
              ),
              ListTile(
                key: const ValueKey('mux-tab-move-right'),
                enabled: index < last,
                leading: const Icon(Icons.arrow_forward_rounded),
                title: const Text('Move right'),
                onTap: () => Navigator.of(context).pop(_TabAction.moveRight),
              ),
            ],
            ListTile(
              key: const ValueKey('mux-tab-close'),
              leading: const Icon(Icons.close_rounded),
              title: Text('Close $_noun'),
              onTap: () => Navigator.of(context).pop(_TabAction.close),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) {
      widget.onChanged?.call();
      return;
    }
    switch (action) {
      case _TabAction.rename:
        final name = await _askName(tab);
        if (name != null && !await controller.rename(tab, name)) {
          _snack('Could not rename the $_noun.');
        }
      case _TabAction.moveLeft:
        await controller.move(tab, -1);
      case _TabAction.moveRight:
        await controller.move(tab, 1);
      case _TabAction.close:
        if (await _confirmClose(tab) && !await controller.close(tab)) {
          _snack('Could not close the $_noun.');
        }
    }
    widget.onChanged?.call();
  }

  Future<String?> _askName(MultiplexerTab tab) => showDialog<String>(
    context: context,
    builder: (context) =>
        _RenameDialog(title: 'Rename $_noun', initial: tab.label),
  );

  Future<bool> _confirmClose(MultiplexerTab tab) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Close "${tab.label}"?'),
        content: Text(
          'Everything running in this $_noun ends, on the machine too.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('mux-tab-close-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final tabs = controller.tabs;
        if (!controller.loaded ||
            !showsMultiplexerTabs(
              widget.visibility,
              tabCount: tabs.length,
              desktop: widget.desktop,
            )) {
          return const SizedBox.shrink();
        }
        final palette = widget.palette;
        final brightness = widget.brightness;
        final reorderable = controller.canReorder && widget.desktop;

        Widget chip(MultiplexerTab tab) => _TabChip(
          key: tab.active ? _activeKey : null,
          tab: tab,
          showIndex: controller.kind == MultiplexerTabsKind.tmux,
          palette: palette,
          brightness: brightness,
          onTap: () => unawaited(_select(tab)),
          onLongPress: () => unawaited(_showActions(tab)),
        );

        final list = reorderable
            ? ReorderableListView.builder(
                key: const ValueKey('mux-tabs-reorderable'),
                scrollController: _scroll,
                scrollDirection: Axis.horizontal,
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                itemCount: tabs.length,
                onReorderItem: (from, to) =>
                    unawaited(controller.reorder(from, to)),
                itemBuilder: (context, index) => ReorderableDragStartListener(
                  key: ValueKey('mux-tab-${tabs[index].id}'),
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: chip(tabs[index]),
                  ),
                ),
              )
            : ListView.separated(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                itemCount: tabs.length,
                separatorBuilder: (_, _) => const SizedBox(width: 4),
                itemBuilder: (context, index) => KeyedSubtree(
                  key: ValueKey('mux-tab-${tabs[index].id}'),
                  child: chip(tabs[index]),
                ),
              );
        return Container(
          key: const ValueKey('multiplexer-tab-strip'),
          height: MultiplexerTabStrip.height,
          decoration: BoxDecoration(
            color: palette.canvasFor(brightness),
            border: Border(
              bottom: BorderSide(color: palette.hairlineFor(brightness)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Align(alignment: Alignment.centerLeft, child: list),
              ),
              IconButton(
                key: const ValueKey('mux-tab-new'),
                tooltip: 'New $_noun',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 34,
                  height: MultiplexerTabStrip.height,
                ),
                iconSize: 18,
                color: palette.foregroundFor(brightness),
                icon: const Icon(Icons.add_rounded),
                onPressed: () => unawaited(_create()),
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _TabAction { rename, moveLeft, moveRight, close }

/// Owns its text field's controller, so it outlives the closing animation.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _field = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('mux-tab-name'),
        controller: _field,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_field.text),
          child: const Text('Rename'),
        ),
      ],
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.tab,
    required this.showIndex,
    required this.palette,
    required this.brightness,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  final MultiplexerTab tab;
  final bool showIndex;
  final AppPalette palette;
  final Brightness brightness;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final accent = palette.accent;
    final foreground = palette.foregroundFor(brightness);
    final muted = palette.mutedForegroundFor(brightness);
    final status = tab.status;
    final showsStatus =
        status != null &&
        status != AgentAttentionState.idle &&
        status != AgentAttentionState.unknown;
    final Color? dot = showsStatus
        ? agentStateColor(context, status)
        : tab.unread
        ? accent
        : null;
    return Center(
      child: Semantics(
        selected: tab.active,
        button: true,
        label: [
          tab.label,
          if (tab.unread) 'new activity',
          if (showsStatus) status.label,
        ].join(', '),
        excludeSemantics: true,
        child: Material(
          color: tab.active
              ? Color.alphaBlend(
                  accent.withValues(alpha: 0.16),
                  palette.panelFor(brightness),
                )
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            side: BorderSide(
              color: tab.active
                  ? accent.withValues(alpha: 0.55)
                  : palette.hairlineFor(brightness),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Container(
              height: 24,
              constraints: const BoxConstraints(maxWidth: 168),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showIndex) ...[
                    Text(
                      '${tab.index}',
                      style: TextStyle(
                        color: muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Flexible(
                    child: Text(
                      tab.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tab.active || tab.unread ? foreground : muted,
                        fontSize: 12,
                        fontWeight: tab.active
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (dot != null) ...[
                    const SizedBox(width: 5),
                    Container(
                      key: ValueKey(
                        showsStatus ? 'mux-tab-status' : 'mux-tab-unread',
                      ),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: dot,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
