import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/terminal/domain/terminal_gesture_preferences.dart';
import 'package:flutter/material.dart';

/// The "Gestures" section of the Appearance sheet: one switch per terminal
/// gesture plus the multiplexer the window swipe talks to.
class TerminalGesturesSettings extends StatelessWidget {
  const TerminalGesturesSettings({required this.controller, super.key});

  final ThemeController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final preferences = controller.terminalGestures;
    final captionStyle = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );

    Future<void> update(TerminalGesturePreferences next) =>
        controller.setTerminalGestures(next);

    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.swipe_rounded),
            title: const Text('Swipe switches window'),
            subtitle: Text(
              'Swipe left or right with one finger for the next or previous '
              'window.',
              style: captionStyle,
            ),
            value: preferences.swipeSwitchesWindow,
            onChanged: (value) =>
                update(preferences.copyWith(swipeSwitchesWindow: value)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Swipe target', style: theme.textTheme.bodyLarge),
                      Text(
                        'tmux uses the host prefix; Herdr always uses Ctrl-B. '
                        'Scrollback swipes use the same prefix.',
                        style: captionStyle,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SegmentedButton<TerminalWindowSwitchTarget>(
                  showSelectedIcon: false,
                  segments: [
                    for (final target in TerminalWindowSwitchTarget.values)
                      ButtonSegment(value: target, label: Text(target.label)),
                  ],
                  selected: {preferences.windowSwitchTarget},
                  onSelectionChanged: (selection) => update(
                    preferences.copyWith(windowSwitchTarget: selection.single),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.pinch_rounded),
            title: const Text('Pinch to zoom'),
            subtitle: Text(
              'Pinch to change the terminal font size.',
              style: captionStyle,
            ),
            value: preferences.pinchZoom,
            onChanged: (value) =>
                update(preferences.copyWith(pinchZoom: value)),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.swap_vert_rounded),
            title: const Text('Two-finger scrollback'),
            subtitle: Text(
              'Swipe down with two fingers to scroll back through history. '
              'Swipe up past the bottom to leave scrollback.',
              style: captionStyle,
            ),
            value: preferences.twoFingerScroll,
            onChanged: (value) =>
                update(preferences.copyWith(twoFingerScroll: value)),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.grid_view_rounded),
            title: const Text('Swipe down opens sessions'),
            subtitle: Text(
              'Swipe down from the top of the terminal to open the session '
              'grid.',
              style: captionStyle,
            ),
            value: preferences.headerSwipeOpensSessions,
            onChanged: (value) =>
                update(preferences.copyWith(headerSwipeOpensSessions: value)),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.smart_toy_outlined),
            title: const Text('Edge swipe opens agents'),
            subtitle: Text(
              'Swipe in from the right edge to open the agent panel.',
              style: captionStyle,
            ),
            value: preferences.edgeSwipeOpensAgents,
            onChanged: (value) =>
                update(preferences.copyWith(edgeSwipeOpensAgents: value)),
          ),
        ],
      ),
    );
  }
}
