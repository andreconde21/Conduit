import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/terminal/domain/terminal_gesture_preferences.dart';
import 'package:flutter/material.dart';

/// The "Gestures" part of Settings › Input: one switch per terminal
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
              'window (tmux) or tab (Herdr).',
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
                        'For plain shells. Sessions opened on a tmux or '
                        'Herdr target always use that one. Keys go through '
                        'the host\'s multiplexer prefix (Ctrl+B unless '
                        'changed on the machine).',
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
              'Pinch to change the terminal font size, in tmux, Herdr and '
              'plain shells. Herdr can zoom the pane instead (see "Pinch in '
              'Herdr" below).',
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
              'Swipe up past the bottom to leave scrollback. In Herdr, when '
              'two-finger up/down switches workspaces, rest two fingers for a '
              'moment and then drag, or start Scrollback from the toolbar.',
              style: captionStyle,
            ),
            value: preferences.twoFingerScroll,
            onChanged: (value) =>
                update(preferences.copyWith(twoFingerScroll: value)),
          ),
          const Divider(height: 1),
          SwitchListTile(
            key: const ValueKey('drag-scrolls-remote'),
            secondary: const Icon(Icons.mouse_rounded),
            title: const Text('Drag scrolls the remote app (mouse wheel)'),
            subtitle: Text(
              'In full-screen programs (Claude Code, Herdr, tmux, vim, htop) '
              'a one-finger drag up or down scrolls the program itself, like '
              'a mouse wheel on a desktop. tmux without mouse support opens '
              'copy mode; tap to leave it. Off: the drag only scrolls the '
              "app's own history.",
              style: captionStyle,
            ),
            value: preferences.dragScrollsRemote,
            onChanged: (value) =>
                update(preferences.copyWith(dragScrollsRemote: value)),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Herdr',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.primary,
                ),
              ),
            ),
          ),
          SwitchListTile(
            key: const ValueKey('herdr-two-finger-panes'),
            secondary: const Icon(Icons.view_column_rounded),
            title: const Text('Two-finger swipe switches pane'),
            subtitle: Text(
              'Swipe left or right with two fingers to focus the pane on the '
              'right or left. Also in tmux sessions.',
              style: captionStyle,
            ),
            value: preferences.herdrTwoFingerPanes,
            onChanged: (value) =>
                update(preferences.copyWith(herdrTwoFingerPanes: value)),
          ),
          _ChoiceRow<HerdrVerticalSwipe>(
            key: const ValueKey('herdr-two-finger-vertical'),
            title: 'Two-finger up/down',
            caption:
                'Workspaces: up for the next workspace, down for the previous '
                'one. Scrollback: like tmux.',
            captionStyle: captionStyle,
            values: HerdrVerticalSwipe.values,
            label: (value) => value.label,
            selected: preferences.herdrTwoFingerVertical,
            onSelected: (value) =>
                update(preferences.copyWith(herdrTwoFingerVertical: value)),
          ),
          _ChoiceRow<HerdrPinchAction>(
            key: const ValueKey('herdr-pinch'),
            title: 'Pinch in Herdr',
            caption:
                'Font size (default): like everywhere else. Zoom pane: spread '
                'to zoom the focused pane full-screen, pinch in to restore it.',
            captionStyle: captionStyle,
            values: HerdrPinchAction.values,
            label: (value) => value.label,
            selected: preferences.herdrPinch,
            onSelected: (value) =>
                update(preferences.copyWith(herdrPinch: value)),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.grid_view_rounded),
            title: const Text('Top-row swipes switch sessions'),
            subtitle: Text(
              'Swipe down from the top to open the quick switcher.',
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

/// A setting row with a title, a caption and a segmented choice.
class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.title,
    required this.caption,
    required this.captionStyle,
    required this.values,
    required this.label,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final String title;
  final String caption;
  final TextStyle? captionStyle;
  final List<T> values;
  final String Function(T value) label;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.bodyLarge),
          Text(caption, style: captionStyle),
          const SizedBox(height: 8),
          SegmentedButton<T>(
            showSelectedIcon: false,
            segments: [
              for (final value in values)
                ButtonSegment(value: value, label: Text(label(value))),
            ],
            selected: {selected},
            onSelectionChanged: (selection) => onSelected(selection.single),
          ),
        ],
      ),
    );
  }
}
