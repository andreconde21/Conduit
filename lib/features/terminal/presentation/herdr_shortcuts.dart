import 'package:conduit/features/hosts/domain/multiplexer_prefix_key.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/terminal/domain/herdr_keymap.dart';
import 'package:conduit/features/terminal/domain/herdr_remote_control.dart';
import 'package:conduit/features/terminal/presentation/terminal_session_controller.dart';
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

/// Herdr actions the app offers, with Herdr's documented default bindings
/// (https://herdr.dev/docs/keyboard/; uppercase text means shift+key). The
/// keys sent and shown come from the machine's own Herdr config when it
/// could be read (see [HerdrKeymap]).
enum HerdrShortcut {
  newTab(
    'New tab',
    Icons.add_box_rounded,
    'c',
    HerdrShortcutGroup.tabs,
    action: 'new_tab',
  ),
  previousTab(
    'Previous tab',
    Icons.skip_previous_rounded,
    'p',
    HerdrShortcutGroup.tabs,
    action: 'previous_tab',
  ),
  nextTab(
    'Next tab',
    Icons.skip_next_rounded,
    'n',
    HerdrShortcutGroup.tabs,
    action: 'next_tab',
  ),
  renameTab(
    'Rename tab',
    Icons.drive_file_rename_outline_rounded,
    'T',
    HerdrShortcutGroup.tabs,
    action: 'rename_tab',
  ),
  closeTab(
    'Close tab',
    Icons.disabled_by_default_rounded,
    'X',
    HerdrShortcutGroup.tabs,
    action: 'close_tab',
    confirm: true,
  ),
  splitRight(
    'Split right',
    Icons.vertical_split_rounded,
    'v',
    HerdrShortcutGroup.splits,
    action: 'split_vertical',
  ),
  splitDown(
    'Split down',
    Icons.splitscreen_rounded,
    '-',
    HerdrShortcutGroup.splits,
    action: 'split_horizontal',
  ),
  paneLeft(
    'Pane left',
    Icons.keyboard_arrow_left_rounded,
    'h',
    HerdrShortcutGroup.panes,
    action: 'focus_pane_left',
  ),
  paneDown(
    'Pane down',
    Icons.keyboard_arrow_down_rounded,
    'j',
    HerdrShortcutGroup.panes,
    action: 'focus_pane_down',
  ),
  paneUp(
    'Pane up',
    Icons.keyboard_arrow_up_rounded,
    'k',
    HerdrShortcutGroup.panes,
    action: 'focus_pane_up',
  ),
  paneRight(
    'Pane right',
    Icons.keyboard_arrow_right_rounded,
    'l',
    HerdrShortcutGroup.panes,
    action: 'focus_pane_right',
  ),
  zoomPane(
    'Zoom pane',
    Icons.zoom_out_map_rounded,
    'z',
    HerdrShortcutGroup.panes,
    action: 'zoom',
  ),
  closePane(
    'Kill pane',
    Icons.cancel_presentation_rounded,
    'x',
    HerdrShortcutGroup.panes,
    action: 'close_pane',
    confirm: true,
  ),
  newWorkspace(
    'New workspace',
    Icons.create_new_folder_rounded,
    'N',
    HerdrShortcutGroup.workspaces,
    action: 'new_workspace',
  ),
  workspacePicker(
    'Workspaces',
    Icons.view_list_rounded,
    'w',
    HerdrShortcutGroup.workspaces,
    action: 'workspace_picker',
  ),
  renameWorkspace(
    'Rename workspace',
    Icons.edit_note_rounded,
    'W',
    HerdrShortcutGroup.workspaces,
    action: 'rename_workspace',
  ),
  closeWorkspace(
    'Close workspace',
    Icons.folder_delete_rounded,
    'D',
    HerdrShortcutGroup.workspaces,
    action: 'close_workspace',
    confirm: true,
  ),
  gotoPicker(
    'Jump to…',
    Icons.explore_rounded,
    'g',
    HerdrShortcutGroup.workspaces,
    action: 'goto',
  ),
  resizeMode(
    'Resize mode',
    Icons.open_in_full_rounded,
    'r',
    HerdrShortcutGroup.modes,
    action: 'resize_mode',
  ),
  copyMode(
    'Scrollback',
    Icons.swap_vert_rounded,
    '[',
    HerdrShortcutGroup.modes,
    action: 'copy_mode',
    entersScrollMode: true,
  ),
  toggleSidebar(
    'Toggle sidebar',
    Icons.view_sidebar_rounded,
    'b',
    HerdrShortcutGroup.modes,
    action: 'toggle_sidebar',
  ),
  help(
    'Help',
    Icons.help_outline_rounded,
    '?',
    HerdrShortcutGroup.modes,
    action: 'help',
  ),
  detach(
    'Detach',
    Icons.logout_rounded,
    'q',
    HerdrShortcutGroup.modes,
    action: 'detach',
  );

  const HerdrShortcut(
    this.label,
    this.icon,
    this.text,
    this.group, {
    required this.action,
    this.entersScrollMode = false,
    this.confirm = false,
  });

  /// The `[keys]` action in Herdr's config (`detach`, `goto`, ...): the
  /// machine's own binding is looked up by it.
  final String action;

  final String label;
  final IconData icon;

  /// Herdr's documented default key after the prefix. What is actually
  /// sent is the machine's binding for [action] (see [sendHerdrAction]).
  final String text;
  final HerdrShortcutGroup group;
  final bool entersScrollMode;

  /// Destructive: the app asks before sending it.
  final bool confirm;

  /// The one-tap row at the top of the navigator, in order (Moshi's
  /// shortcut panel: new tab, workspaces, jump, zoom, kill pane, detach).
  static const quick = [
    newTab,
    workspacePicker,
    gotoPicker,
    zoomPane,
    closePane,
    detach,
  ];

  /// Shortcuts of [group], in declaration order.
  static List<HerdrShortcut> inGroup(HerdrShortcutGroup group) => [
    for (final shortcut in values)
      if (shortcut.group == group) shortcut,
  ];
}

/// How the navigator's "new" row and the pill's long-press menu show a
/// [HerdrNewPane], and the key binding used when the CLI cannot do it.
extension HerdrNewPaneDetails on HerdrNewPane {
  /// The Herdr action typed as a fallback (the machine's binding for it).
  HerdrShortcut get shortcut => switch (this) {
    HerdrNewPane.splitRight => HerdrShortcut.splitRight,
    HerdrNewPane.splitDown => HerdrShortcut.splitDown,
    HerdrNewPane.newTab => HerdrShortcut.newTab,
    HerdrNewPane.newWorkspace => HerdrShortcut.newWorkspace,
  };

  String get label => shortcut.label;
  IconData get icon => shortcut.icon;
}

/// Herdr keys as a machine has them bound (see [HerdrKeymap]).
extension HerdrShortcutKeys on HerdrShortcut {
  /// The binding the app sends; null when the machine unbound it.
  HerdrKeyBinding? bindingIn(HerdrKeymap keymap) => keymap.bindingFor(action);

  /// `Ctrl+Space d`, or "Not bound".
  String keyHintIn(HerdrKeymap keymap, String prefixLabel) =>
      bindingIn(keymap)?.label(prefixLabel) ?? 'Not bound';
}

/// The Herdr keymap of [session]'s machine (Herdr's defaults until read).
HerdrKeymap herdrKeymapOf(TerminalSessionController session) =>
    HerdrKeymapCache.instance.of(baseHostId(session.host.id));

/// The prefix Herdr listens for: the machine's `keys.prefix` when it was
/// read, else the host's configured multiplexer prefix.
MultiplexerPrefixKey herdrPrefixOf(
  HerdrKeymap keymap,
  MultiplexerPrefixKey hostPrefix,
) => keymap.prefix ?? hostPrefix;

/// Types the machine's binding for a Herdr config [action] into [session].
/// Returns false (and types nothing) when the action is unbound there.
bool sendHerdrAction(
  TerminalSessionController session,
  String action, {
  required MultiplexerPrefixKey hostPrefix,
  HerdrKeymap? keymap,
}) {
  final map = keymap ?? herdrKeymapOf(session);
  final binding = map.bindingFor(action);
  if (binding == null) {
    return false;
  }
  HerdrKeySender.send(
    binding,
    prefix: herdrPrefixOf(map, hostPrefix),
    sendPrefix: session.sendPrefix,
    sendText: session.sendText,
    sendKey: session.sendKey,
    sendControl: session.sendControl,
  );
  return true;
}

/// Tab [number] (1-9) with the machine's `switch_tab = "prefix+1..9"`;
/// false when that range is not bound behind the prefix.
bool sendHerdrTab(
  TerminalSessionController session,
  int number, {
  required MultiplexerPrefixKey hostPrefix,
  HerdrKeymap? keymap,
}) {
  final map = keymap ?? herdrKeymapOf(session);
  if (!map.switchTabWithPrefix) {
    return false;
  }
  session.sendPrefix(herdrPrefixOf(map, hostPrefix));
  session.sendText('$number');
  return true;
}
