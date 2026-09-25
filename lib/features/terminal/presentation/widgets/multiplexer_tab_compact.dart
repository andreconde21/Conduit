import 'dart:async';

import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/core/theme/app_theme.dart';
import 'package:conduit/features/terminal/domain/multiplexer_tabs.dart';
import 'package:conduit/features/terminal/presentation/multiplexer_tabs_controller.dart';
import 'package:conduit/features/terminal/presentation/widgets/multiplexer_tab_actions.dart';
import 'package:flutter/material.dart';

/// "2/4": the active tab's place among [tabs] (1-based), or "?/4".
String multiplexerTabPosition(List<MultiplexerTab> tabs) {
  final index = tabs.indexWhere((tab) => tab.active);
  return '${index == -1 ? '?' : index + 1}/${tabs.length}';
}

/// Tabs with news that are not on screen.
int multiplexerUnreadCount(List<MultiplexerTab> tabs) =>
    tabs.where((tab) => tab.unread && !tab.active).length;

/// The compact mode's part of the session tab in the top row:
/// "› tests 2/4", the tab's dot and a badge counting the other tabs with
/// news. Tapping it opens the list of tabs ([onTap]). Takes no room until
/// the tabs are known.
class MultiplexerTabInlineLabel extends StatelessWidget {
  const MultiplexerTabInlineLabel({
    required this.controller,
    required this.onTap,
    required this.color,
    required this.mutedColor,
    super.key,
  });

  final MultiplexerTabsController controller;
  final VoidCallback onTap;
  final Color color;
  final Color mutedColor;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final tabs = controller.tabs;
        if (!controller.loaded || tabs.isEmpty) {
          return const SizedBox.shrink();
        }
        final active = controller.active;
        final unread = multiplexerUnreadCount(tabs);
        final palette = AppPalette.of(context);
        final position = multiplexerTabPosition(tabs);
        return Semantics(
          button: true,
          label:
              '${multiplexerTabNoun(controller)} ${active?.label ?? ''}, '
              '$position${unread == 0 ? '' : ', $unread with news'}',
          excludeSemantics: true,
          child: InkWell(
            key: const ValueKey('mux-inline-label'),
            borderRadius: BorderRadius.circular(AppTheme.radius),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('›', style: TextStyle(color: mutedColor, fontSize: 12)),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      active?.label ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    position,
                    style: TextStyle(
                      color: mutedColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (active != null &&
                      multiplexerTabDot(context, active) != null) ...[
                    const SizedBox(width: 4),
                    MultiplexerTabDot(tab: active),
                  ],
                  if (unread > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      key: const ValueKey('mux-inline-unread'),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: palette.accent,
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                      ),
                      child: Text(
                        '$unread',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                  Icon(Icons.expand_more_rounded, size: 14, color: mutedColor),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A pill at the top of the terminal after the multiplexer switched tabs
/// (a swipe, keys, the list): "tests · 2/4" and a dot per tab, fading out
/// after [holdFor]. It never takes a touch and costs no layout space.
class MultiplexerTabOverlay extends StatefulWidget {
  const MultiplexerTabOverlay({
    required this.controller,
    this.holdFor = const Duration(milliseconds: 1100),
    super.key,
  });

  final MultiplexerTabsController controller;
  final Duration holdFor;

  @override
  State<MultiplexerTabOverlay> createState() => _MultiplexerTabOverlayState();
}

class _MultiplexerTabOverlayState extends State<MultiplexerTabOverlay> {
  String? _lastActive;
  bool _shown = false;

  /// Built at all: while shown and while fading out.
  bool _present = false;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _lastActive = widget.controller.active?.id;
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant MultiplexerTabOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _lastActive = widget.controller.active?.id;
      _hide?.cancel();
      _shown = _present = false;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _hide?.cancel();
    super.dispose();
  }

  void _changed() {
    final active = widget.controller.active?.id;
    if (active == null || active == _lastActive) return;
    final first = _lastActive == null;
    _lastActive = active;
    // The first listing is where the session already was, not a switch.
    if (first || !mounted) return;
    setState(() => _shown = _present = true);
    _hide?.cancel();
    _hide = Timer(widget.holdFor, () {
      if (!mounted) return;
      final reduceMotion =
          MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      setState(() {
        _shown = false;
        if (reduceMotion) _present = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final tabs = widget.controller.tabs;
    final active = widget.controller.active;
    final palette = AppPalette.of(context);
    final brightness = Theme.of(context).brightness;
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: AnimatedOpacity(
            opacity: _shown ? 1 : 0,
            onEnd: () {
              if (!_shown && mounted) setState(() => _present = false);
            },
            duration: reduceMotion
                ? Duration.zero
                : Duration(milliseconds: _shown ? 120 : 260),
            child: !_present || active == null
                ? const SizedBox.shrink()
                : Container(
                    key: const ValueKey('mux-tab-overlay'),
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 7),
                    decoration: BoxDecoration(
                      color: palette
                          .panelFor(brightness)
                          .withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(AppTheme.radius),
                      border: Border.all(
                        color: palette.hairlineFor(brightness),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${active.label} · ${multiplexerTabPosition(tabs)}',
                          style: TextStyle(
                            color: palette.foregroundFor(brightness),
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final tab in tabs)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2.5,
                                ),
                                child: Container(
                                  width: tab.active ? 8 : 6,
                                  height: tab.active ? 8 : 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: tab.active
                                        ? palette.accent
                                        : multiplexerTabDot(context, tab) ??
                                              palette
                                                  .mutedForegroundFor(
                                                    brightness,
                                                  )
                                                  .withValues(alpha: 0.5),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
