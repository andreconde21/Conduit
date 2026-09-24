import 'package:flutter/material.dart';

/// Sections of the Herdr shortcut list, in display order.
enum HerdrShortcutGroup {
  tabs('Tabs'),
  splits('Splits'),
  panes('Panes'),
  workspaces('Workspaces'),
  modes('Modes');

  const HerdrShortcutGroup(this.label);

  final String label;
}

/// Herdr's documented default bindings, typed after the host's multiplexer
/// prefix, from https://herdr.dev/docs/keyboard/. Uppercase text means
/// shift+key.
enum HerdrShortcut {
  newTab('New tab', Icons.add_box_rounded, 'c', HerdrShortcutGroup.tabs),
  previousTab(
    'Previous tab',
    Icons.skip_previous_rounded,
    'p',
    HerdrShortcutGroup.tabs,
  ),
  nextTab('Next tab', Icons.skip_next_rounded, 'n', HerdrShortcutGroup.tabs),
  renameTab(
    'Rename tab',
    Icons.drive_file_rename_outline_rounded,
    'T',
    HerdrShortcutGroup.tabs,
  ),
  closeTab(
    'Close tab',
    Icons.disabled_by_default_rounded,
    'X',
    HerdrShortcutGroup.tabs,
  ),
  splitRight(
    'Split right',
    Icons.vertical_split_rounded,
    'v',
    HerdrShortcutGroup.splits,
  ),
  splitDown(
    'Split down',
    Icons.splitscreen_rounded,
    '-',
    HerdrShortcutGroup.splits,
  ),
  paneLeft(
    'Pane left',
    Icons.keyboard_arrow_left_rounded,
    'h',
    HerdrShortcutGroup.panes,
  ),
  paneDown(
    'Pane down',
    Icons.keyboard_arrow_down_rounded,
    'j',
    HerdrShortcutGroup.panes,
  ),
  paneUp(
    'Pane up',
    Icons.keyboard_arrow_up_rounded,
    'k',
    HerdrShortcutGroup.panes,
  ),
  paneRight(
    'Pane right',
    Icons.keyboard_arrow_right_rounded,
    'l',
    HerdrShortcutGroup.panes,
  ),
  zoomPane(
    'Zoom pane',
    Icons.zoom_out_map_rounded,
    'z',
    HerdrShortcutGroup.panes,
  ),
  closePane(
    'Close pane',
    Icons.close_fullscreen_rounded,
    'x',
    HerdrShortcutGroup.panes,
  ),
  newWorkspace(
    'New workspace',
    Icons.create_new_folder_rounded,
    'N',
    HerdrShortcutGroup.workspaces,
  ),
  workspacePicker(
    'Workspaces',
    Icons.view_list_rounded,
    'w',
    HerdrShortcutGroup.workspaces,
  ),
  renameWorkspace(
    'Rename workspace',
    Icons.edit_note_rounded,
    'W',
    HerdrShortcutGroup.workspaces,
  ),
  closeWorkspace(
    'Close workspace',
    Icons.folder_delete_rounded,
    'D',
    HerdrShortcutGroup.workspaces,
  ),
  gotoPicker(
    'Goto picker',
    Icons.explore_rounded,
    'g',
    HerdrShortcutGroup.workspaces,
  ),
  resizeMode(
    'Resize mode',
    Icons.open_in_full_rounded,
    'r',
    HerdrShortcutGroup.modes,
  ),
  copyMode(
    'Scrollback',
    Icons.swap_vert_rounded,
    '[',
    HerdrShortcutGroup.modes,
    entersScrollMode: true,
  ),
  toggleSidebar(
    'Toggle sidebar',
    Icons.view_sidebar_rounded,
    'b',
    HerdrShortcutGroup.modes,
  ),
  help('Help', Icons.help_outline_rounded, '?', HerdrShortcutGroup.modes),
  detach('Detach', Icons.logout_rounded, 'q', HerdrShortcutGroup.modes);

  const HerdrShortcut(
    this.label,
    this.icon,
    this.text,
    this.group, {
    this.entersScrollMode = false,
  });

  final String label;
  final IconData icon;

  /// What is typed after the prefix.
  final String text;
  final HerdrShortcutGroup group;
  final bool entersScrollMode;

  /// Shortcuts of [group], in declaration order.
  static List<HerdrShortcut> inGroup(HerdrShortcutGroup group) => [
    for (final shortcut in values)
      if (shortcut.group == group) shortcut,
  ];
}
