import 'package:conduit/core/diagnostics/app_error_log.dart';
import 'package:conduit/core/platform_features.dart';
import 'package:conduit/core/presentation/conduit_brand.dart';
import 'package:conduit/core/presentation/system_navigation_insets.dart';
import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/core/theme/app_theme.dart';
import 'package:conduit/core/theme/omarchy_theme_sync_controller.dart';
import 'package:conduit/core/theme/terminal_appearance.dart';
import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/backup/data/app_backup_service.dart';
import 'package:conduit/features/backup/presentation/backup_sheet.dart';
import 'package:conduit/features/home_widget/data/platform_agent_status_widget_channel.dart';
import 'package:conduit/features/home_widget/presentation/quick_settings_tile_controls.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/session_navigation/presentation/session_view_widgets.dart';
import 'package:conduit/features/snippets/presentation/snippet_editor.dart';
import 'package:conduit/features/terminal/presentation/gestures/terminal_gestures_settings.dart';
import 'package:conduit/features/voice/presentation/speech_settings_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> showThemeSheet({
  required BuildContext context,
  required ThemeController controller,
  AppBackupService? backupService,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemUiOverlayStyle(Theme.of(context).brightness),
      child: _ThemeSheet(controller: controller, backupService: backupService),
    ),
  );
}

class _ThemeSheet extends StatelessWidget {
  const _ThemeSheet({required this.controller, required this.backupService});

  final ThemeController controller;
  final AppBackupService? backupService;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return SafeArea(
              bottom: shouldApplyBottomSafeArea(context),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
                children: [
                  Row(
                    children: [
                      Text('Appearance', style: theme.textTheme.headlineSmall),
                      const Spacer(),
                      const ConduitGlyph(size: 24),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Omarchy themes. The terminal, home screen and dialogs share one look.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const ConduitSectionLabel('Theme'),
                  const SizedBox(height: 10),
                  if (controller.omarchySync case final sync?) ...[
                    OmarchySyncControls(sync: sync),
                    const SizedBox(height: 14),
                  ],
                  _ThemeGrid(controller: controller),
                  const SizedBox(height: 22),
                  const ConduitSectionLabel('Terminal'),
                  const SizedBox(height: 10),
                  _TerminalAppearanceControls(controller: controller),
                  const SizedBox(height: 22),
                  const ConduitSectionLabel('Gestures'),
                  const SizedBox(height: 10),
                  TerminalGesturesSettings(controller: controller),
                  if (PlatformFeatures.homeWidget) ...[
                    const SizedBox(height: 22),
                    const ConduitSectionLabel('Home'),
                    const SizedBox(height: 10),
                    _HomeAppearanceControls(controller: controller),
                    const SizedBox(height: 10),
                    QuickSettingsTileControls(
                      channel: PlatformAgentStatusWidgetChannel.instance,
                    ),
                    const SizedBox(height: 22),
                    const ConduitSectionLabel('Speech'),
                    const SizedBox(height: 10),
                    SpeechSettingsControls(controller: controller),
                  ],
                  if (backupService != null) ...[
                    const SizedBox(height: 22),
                    const ConduitSectionLabel('Backup'),
                    const SizedBox(height: 10),
                    _BackupControls(backupService: backupService!),
                  ],
                  const SizedBox(height: 22),
                  const ConduitSectionLabel('About'),
                  const SizedBox(height: 10),
                  const _AboutControls(),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _HomeAppearanceControls extends StatelessWidget {
  const _HomeAppearanceControls({required this.controller});

  final ThemeController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colorScheme.outlineVariant),
        borderRadius: AppTheme.borderRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile(
        secondary: const Icon(Icons.terminal_rounded),
        title: const Text('Show local shell'),
        subtitle: Text(
          'Show the local terminal shortcut on the home screen.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        value: controller.showLocalShell,
        onChanged: controller.setShowLocalShell,
      ),
    );
  }
}

class _BackupControls extends StatelessWidget {
  const _BackupControls({required this.backupService});

  final AppBackupService backupService;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colorScheme.outlineVariant),
        borderRadius: AppTheme.borderRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.backup_rounded),
        title: const Text('Backup and restore'),
        subtitle: Text(
          'Export settings and machines or import a saved backup.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () =>
            showBackupSheet(context: context, backupService: backupService),
      ),
    );
  }
}

class _TerminalAppearanceControls extends StatelessWidget {
  const _TerminalAppearanceControls({required this.controller});

  final ThemeController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<TerminalFontOption>(
          segments: [
            for (final font in TerminalFontOption.values)
              ButtonSegment(
                value: font,
                label: Text(
                  font.label,
                  style: TextStyle(fontFamily: font.fontFamily),
                ),
              ),
          ],
          selected: {controller.terminalFont},
          onSelectionChanged: (selection) =>
              controller.setTerminalFont(selection.single),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: AppTheme.borderRadius,
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.format_size_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text('Font size', style: theme.textTheme.labelLarge),
                  const Spacer(),
                  Text(
                    controller.terminalFontSize.toStringAsFixed(1),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              Slider(
                min: terminalFontSizeMin,
                max: terminalFontSizeMax,
                divisions: terminalFontSizeDivisions,
                value: clampTerminalFontSize(controller.terminalFontSize),
                label: controller.terminalFontSize.toStringAsFixed(1),
                onChanged: controller.setTerminalFontSize,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          height: 72,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: AppTheme.borderRadius,
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Text(
            controller.terminalFont.hasNerdGlyphs
                ? '\u{F07B} ~/conductore \u{E0A0} main ❯ git status'
                : '~/conductore main > git status',
            style: TextStyle(
              fontFamily: controller.terminalFont.fontFamily,
              fontSize: controller.terminalFontSize,
              color: colorScheme.onSurface,
              letterSpacing: 0,
              height: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: AppTheme.borderRadius,
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              const Icon(Icons.keyboard_command_key_rounded, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Key rows', style: theme.textTheme.labelLarge),
              ),
              Text(
                '${controller.terminalKeyboardRows.length}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 10),
              TextButton.icon(
                onPressed: () => _showKeyboardRowsEditor(context, controller),
                icon: const Icon(Icons.tune_rounded, size: 17),
                label: const Text('Edit'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Material(
          color: colorScheme.surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: colorScheme.outlineVariant),
            borderRadius: AppTheme.borderRadius,
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.space_bar_rounded, size: 20),
                    const SizedBox(width: 10),
                    Text('Toolbar style', style: theme.textTheme.titleSmall),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  controller.terminalToolbarStyle.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<TerminalToolbarStyle>(
                    segments: [
                      for (final style in TerminalToolbarStyle.values)
                        ButtonSegment<TerminalToolbarStyle>(
                          value: style,
                          label: Text(style.label),
                        ),
                    ],
                    selected: {controller.terminalToolbarStyle},
                    onSelectionChanged: (selection) {
                      controller.setTerminalToolbarStyle(selection.single);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Material(
          color: colorScheme.surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: colorScheme.outlineVariant),
            borderRadius: AppTheme.borderRadius,
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.keyboard_return_rounded, size: 20),
                    const SizedBox(width: 10),
                    Text('Enter sends', style: theme.textTheme.titleSmall),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  controller.terminalEnterSequence.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<TerminalEnterSequence>(
                    segments: [
                      for (final sequence in TerminalEnterSequence.values)
                        ButtonSegment<TerminalEnterSequence>(
                          value: sequence,
                          label: Text(sequence.label),
                        ),
                    ],
                    selected: {controller.terminalEnterSequence},
                    onSelectionChanged: (selection) {
                      controller.setTerminalEnterSequence(selection.single);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Material(
          color: colorScheme.surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: colorScheme.outlineVariant),
            borderRadius: AppTheme.borderRadius,
          ),
          clipBehavior: Clip.antiAlias,
          child: SwitchListTile(
            secondary: const Icon(Icons.mouse_rounded),
            title: const Text('Send mouse taps'),
            subtitle: Text(
              'Forward terminal taps as mouse clicks when apps enable mouse tracking.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            value: controller.terminalMouseInput,
            onChanged: controller.setTerminalMouseInput,
          ),
        ),
        const SizedBox(height: 14),
        Material(
          color: colorScheme.surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: colorScheme.outlineVariant),
            borderRadius: AppTheme.borderRadius,
          ),
          clipBehavior: Clip.antiAlias,
          child: SwitchListTile(
            secondary: const Icon(Icons.smart_button_rounded),
            title: const Text('Menu buttons'),
            subtitle: Text(
              'Answer numbered menus and y/n prompts (Claude Code, installers) '
              'with buttons above the keyboard bar.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            value: controller.menuButtonsEnabled,
            onChanged: controller.setMenuButtonsEnabled,
          ),
        ),
        const SizedBox(height: 14),
        Material(
          color: colorScheme.surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: colorScheme.outlineVariant),
            borderRadius: AppTheme.borderRadius,
          ),
          clipBehavior: Clip.antiAlias,
          child: SwitchListTile(
            secondary: const Icon(Icons.content_paste_go_rounded),
            title: const Text('Remote clipboard'),
            subtitle: Text(
              'Let programs on the host copy to this phone (OSC 52: vim, '
              'tmux with set-clipboard on). The host can never read it.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            value: controller.remoteClipboardEnabled,
            onChanged: controller.setRemoteClipboardEnabled,
          ),
        ),
        const SizedBox(height: 14),
        Material(
          color: colorScheme.surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: colorScheme.outlineVariant),
            borderRadius: AppTheme.borderRadius,
          ),
          clipBehavior: Clip.antiAlias,
          child: SwitchListTile(
            key: const ValueKey('paste-images-as-files'),
            secondary: const Icon(Icons.image_outlined),
            title: const Text('Paste images as uploaded files'),
            subtitle: Text(
              'Pasting an image uploads it to the machine\'s share inbox '
              'and pastes its path, which Claude Code reads as an image. '
              'Off: paste text only.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            value: controller.pasteImagesAsFiles,
            onChanged: controller.setPasteImagesAsFiles,
          ),
        ),
        const SizedBox(height: 14),
        Material(
          color: colorScheme.surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: colorScheme.outlineVariant),
            borderRadius: AppTheme.borderRadius,
          ),
          clipBehavior: Clip.antiAlias,
          child: SwitchListTile(
            key: const ValueKey('restore-sessions-switch'),
            secondary: const Icon(Icons.restore_page_rounded),
            title: const Text('Restore sessions on launch'),
            subtitle: Text(
              'Bring back the open sessions after the app restarts. tmux and '
              'Herdr sessions reattach; plain shells start fresh.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            value: controller.restoreSessionsOnLaunch,
            onChanged: controller.setRestoreSessionsOnLaunch,
          ),
        ),
        const SizedBox(height: 14),
        const SessionViewSettingsTile(),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: AppTheme.borderRadius,
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: SnippetListEditor(
            title: 'Global snippets',
            caption: 'Shown from the Snip key-row menu on every machine.',
            snippets: controller.terminalSnippets,
            onChanged: controller.setTerminalSnippets,
          ),
        ),
      ],
    );
  }
}

Future<void> _showKeyboardRowsEditor(
  BuildContext context,
  ThemeController controller,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _KeyboardRowsEditor(controller: controller),
  );
}

class _KeyboardRowsEditor extends StatefulWidget {
  const _KeyboardRowsEditor({required this.controller});

  final ThemeController controller;

  @override
  State<_KeyboardRowsEditor> createState() => _KeyboardRowsEditorState();
}

class _KeyboardRowsEditorState extends State<_KeyboardRowsEditor> {
  late List<TerminalKeyboardRow> _rows;
  final List<int> _rowIds = [];
  var _nextRowId = 0;

  @override
  void initState() {
    super.initState();
    _rows = List.of(widget.controller.terminalKeyboardRows);
    for (var index = 0; index < _rows.length; index += 1) {
      _rowIds.add(_nextRowId++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SafeArea(
      bottom: shouldApplyBottomSafeArea(context),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 8),
              child: Row(
                children: [
                  Text(
                    'Key Rows (${_rows.length})',
                    style: theme.textTheme.titleLarge,
                  ),
                  const Spacer(),
                  TextButton(onPressed: _reset, child: const Text('Reset')),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                itemCount: _rows.length,
                proxyDecorator: _reorderProxyDecorator,
                onReorderItem: _reorder,
                itemBuilder: _buildRow,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _addRow,
                      icon: const Icon(Icons.add_rounded, size: 17),
                      label: const Text('Add row'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: colorScheme.outlineVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, int index) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final row = _rows[index];
    return Card(
      key: ValueKey(_rowIds[index]),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 4),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Row ${index + 1}',
                        style: theme.textTheme.labelLarge,
                      ),
                      Text(
                        row.items.length == 1
                            ? '1 key'
                            : '${row.items.length} keys',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Edit keys',
                  onPressed: () => _editRowKeys(index),
                  icon: const Icon(Icons.tune_rounded),
                ),
                IconButton(
                  tooltip: 'Remove row',
                  onPressed: _rows.length == 1 ? null : () => _removeRow(index),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.drag_handle_rounded),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Icon(
                  Icons.height_rounded,
                  size: 17,
                  color: colorScheme.onSurfaceVariant,
                ),
                Expanded(
                  child: Slider(
                    value: row.height,
                    min: terminalKeyboardRowHeightMin,
                    max: terminalKeyboardRowHeightMax,
                    divisions: 8,
                    label: '${row.height.round()}',
                    onChanged: (value) => setState(
                      () => _rows[index] = row.copyWith(height: value),
                    ),
                    onChangeEnd: (_) => _persist(),
                  ),
                ),
                SizedBox(
                  width: 30,
                  child: Text(
                    '${row.height.round()}',
                    style: theme.textTheme.labelMedium,
                    textAlign: TextAlign.end,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editRowKeys(int index) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _KeyboardActionsEditor(
        title: 'Row ${index + 1} Keys',
        initialItems: _rows[index].items,
        onChanged: (items) {
          setState(() => _rows[index] = _rows[index].copyWith(items: items));
          _persist();
        },
      ),
    );
    if (!mounted) {
      return;
    }
    if (_rows.length > 1 && _rows[index].items.isEmpty) {
      setState(() {
        _rows.removeAt(index);
        _rowIds.removeAt(index);
      });
      _persist();
    }
  }

  Future<void> _addRow() {
    setState(() {
      _rows.add(const TerminalKeyboardRow(items: []));
      _rowIds.add(_nextRowId++);
    });
    return _editRowKeys(_rows.length - 1);
  }

  void _removeRow(int index) {
    setState(() {
      _rows.removeAt(index);
      _rowIds.removeAt(index);
    });
    _persist();
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      _rows.insert(newIndex, _rows.removeAt(oldIndex));
      _rowIds.insert(newIndex, _rowIds.removeAt(oldIndex));
    });
    _persist();
  }

  void _reset() {
    setState(() {
      _rows = List.of(defaultTerminalKeyboardRows);
      _rowIds
        ..clear()
        ..addAll([for (final _ in _rows) _nextRowId++]);
    });
    _persist();
  }

  void _persist() {
    widget.controller.setTerminalKeyboardRows(List.of(_rows));
  }
}

class _KeyboardActionsEditor extends StatefulWidget {
  const _KeyboardActionsEditor({
    required this.title,
    required this.initialItems,
    required this.onChanged,
  });

  final String title;
  final List<TerminalKeyboardItem> initialItems;
  final ValueChanged<List<TerminalKeyboardItem>> onChanged;

  @override
  State<_KeyboardActionsEditor> createState() => _KeyboardActionsEditorState();
}

class _KeyboardActionsEditorState extends State<_KeyboardActionsEditor> {
  late List<TerminalKeyboardItem> _selected;
  final _listController = ScrollController();

  @override
  void initState() {
    super.initState();
    _selected = List<TerminalKeyboardItem>.of(widget.initialItems);
  }

  @override
  void dispose() {
    _listController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedActions = _selected
        .map((item) => item.action)
        .whereType<TerminalKeyboardAction>()
        .toSet();
    final available = TerminalKeyboardAction.values
        .where((action) => !selectedActions.contains(action))
        .toList(growable: false);

    return SafeArea(
      bottom: shouldApplyBottomSafeArea(context),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 8),
              child: Row(
                children: [
                  Text(
                    '${widget.title} (${_selected.length})',
                    style: theme.textTheme.titleLarge,
                  ),
                  const Spacer(),
                  TextButton(onPressed: _addTmux, child: const Text('Tmux')),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                scrollController: _listController,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                itemCount: _selected.length,
                proxyDecorator: _reorderProxyDecorator,
                onReorderItem: _reorder,
                itemBuilder: _buildItem,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
              child: Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final action in available)
                    ActionChip(
                      avatar: Icon(_keyboardActionIcon(action), size: 16),
                      label: Text(action.label),
                      onPressed: () => _addBuiltIn(action),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Custom'),
                    onPressed: _addCustom,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Done'),
              ),
            ),
            Container(height: 1, color: colorScheme.outlineVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, int index) {
    final item = _selected[index];
    return Card(
      key: ValueKey(item.stableId),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(_keyboardItemIcon(item)),
        title: Text(item.displayLabel),
        subtitle: _keyboardItemSubtitle(item),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Remove',
              onPressed: _selected.length == 1 ? null : () => _remove(index),
              icon: const Icon(Icons.remove_circle_outline),
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.drag_handle_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _setSelected(List<TerminalKeyboardItem> next) {
    setState(() {
      _selected = next;
    });
    widget.onChanged(next);
  }

  void _addTmux() {
    final selectedActions = _selected
        .map((item) => item.action)
        .whereType<TerminalKeyboardAction>()
        .toSet();
    _setSelected([
      ..._selected,
      ...tmuxTerminalKeyboardItems.where(
        (item) => !selectedActions.contains(item.action),
      ),
    ]);
  }

  void _addBuiltIn(TerminalKeyboardAction action) {
    _setSelected([..._selected, TerminalKeyboardItem.builtIn(action)]);
  }

  Future<void> _addCustom() async {
    final item = await _showCustomKeyboardItemDialog(context);
    if (item == null || !mounted) {
      return;
    }
    _setSelected([item, ..._selected]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_listController.hasClients) {
        _listController.jumpTo(0);
      }
    });
  }

  void _remove(int index) {
    _setSelected([..._selected.take(index), ..._selected.skip(index + 1)]);
  }

  void _reorder(int oldIndex, int newIndex) {
    final next = List<TerminalKeyboardItem>.of(_selected);
    final item = next.removeAt(oldIndex);
    next.insert(newIndex, item);
    _setSelected(next);
  }
}

Widget _reorderProxyDecorator(
  Widget child,
  int index,
  Animation<double> animation,
) {
  return AnimatedBuilder(
    animation: animation,
    builder: (context, child) {
      final elevation = Curves.easeOut.transform(animation.value);
      return Transform.scale(
        scale: 1 + (0.015 * elevation),
        child: Material(
          color: Colors.transparent,
          elevation: 8 * elevation,
          shadowColor: Colors.black.withValues(alpha: 0.22),
          borderRadius: AppTheme.borderRadius,
          child: child,
        ),
      );
    },
    child: child,
  );
}

Future<TerminalKeyboardItem?> _showCustomKeyboardItemDialog(
  BuildContext context,
) {
  return showDialog<TerminalKeyboardItem>(
    context: context,
    builder: (context) => const _CustomKeyboardItemDialog(),
  );
}

class _CustomKeyboardItemDialog extends StatefulWidget {
  const _CustomKeyboardItemDialog();

  @override
  State<_CustomKeyboardItemDialog> createState() =>
      _CustomKeyboardItemDialogState();
}

class _CustomKeyboardItemDialogState extends State<_CustomKeyboardItemDialog> {
  final _labelController = TextEditingController();
  final _textController = TextEditingController();
  var _kind = TerminalKeyboardItemKind.customText;
  var _controlKey = terminalKeyboardControlKeys.first;
  var _submit = false;

  @override
  void dispose() {
    _labelController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textMode = _kind == TerminalKeyboardItemKind.customText;
    final controlMode = _kind == TerminalKeyboardItemKind.customControl;
    return AlertDialog(
      title: const Text('Custom key'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<TerminalKeyboardItemKind>(
              segments: const [
                ButtonSegment(
                  value: TerminalKeyboardItemKind.customText,
                  label: Text('Text'),
                ),
                ButtonSegment(
                  value: TerminalKeyboardItemKind.customControl,
                  label: Text('Ctrl'),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (value) {
                setState(() => _kind = value.single);
              },
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _labelController,
              decoration: const InputDecoration(
                labelText: 'Label',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            if (textMode) ...[
              TextField(
                controller: _textController,
                decoration: const InputDecoration(
                  labelText: 'Text',
                  border: OutlineInputBorder(),
                ),
                minLines: 1,
                maxLines: 3,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _submit,
                onChanged: (value) {
                  setState(() => _submit = value ?? false);
                },
                title: const Text('Send Enter after text'),
              ),
            ] else if (controlMode)
              DropdownButtonFormField<String>(
                initialValue: _controlKey,
                decoration: const InputDecoration(
                  labelText: 'Control key',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final key in terminalKeyboardControlKeys)
                    DropdownMenuItem(value: key, child: Text('Ctrl+$key')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _controlKey = value);
                  }
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submitItem, child: const Text('Add')),
      ],
    );
  }

  void _submitItem() {
    final label = _labelController.text.trim();
    final text = _textController.text;
    final textMode = _kind == TerminalKeyboardItemKind.customText;
    final controlMode = _kind == TerminalKeyboardItemKind.customControl;
    if (label.isEmpty || (textMode && text.isEmpty)) {
      return;
    }
    Navigator.of(context).pop(
      TerminalKeyboardItem(
        id: _newCustomKeyboardItemId(),
        kind: _kind,
        label: label,
        text: textMode ? text : null,
        controlKey: controlMode ? _controlKey : null,
        submit: textMode && _submit,
      ),
    );
  }
}

String _newCustomKeyboardItemId() {
  return 'custom:${DateTime.now().microsecondsSinceEpoch}';
}

Widget? _keyboardItemSubtitle(TerminalKeyboardItem item) {
  final text = switch (item.kind) {
    TerminalKeyboardItemKind.builtIn => null,
    TerminalKeyboardItemKind.customText =>
      item.submit ? '${item.text ?? ''} + Enter' : item.text,
    TerminalKeyboardItemKind.customControl => 'Ctrl+${item.controlKey}',
  };
  return text == null ? null : Text(text, maxLines: 1);
}

IconData _keyboardItemIcon(TerminalKeyboardItem item) {
  return switch (item.kind) {
    TerminalKeyboardItemKind.builtIn => _keyboardActionIcon(item.action!),
    TerminalKeyboardItemKind.customText => Icons.text_fields_rounded,
    TerminalKeyboardItemKind.customControl =>
      Icons.keyboard_command_key_rounded,
  };
}

IconData _keyboardActionIcon(TerminalKeyboardAction action) {
  return switch (action) {
    TerminalKeyboardAction.escape => Icons.keyboard_rounded,
    TerminalKeyboardAction.control => Icons.keyboard_control_key_rounded,
    TerminalKeyboardAction.alt => Icons.keyboard_option_key_rounded,
    TerminalKeyboardAction.tab => Icons.keyboard_tab_rounded,
    TerminalKeyboardAction.fullscreen => Icons.fullscreen_rounded,
    TerminalKeyboardAction.arrowUp => Icons.keyboard_arrow_up_rounded,
    TerminalKeyboardAction.arrowDown => Icons.keyboard_arrow_down_rounded,
    TerminalKeyboardAction.arrowLeft => Icons.keyboard_arrow_left_rounded,
    TerminalKeyboardAction.arrowRight => Icons.keyboard_arrow_right_rounded,
    TerminalKeyboardAction.home => Icons.first_page_rounded,
    TerminalKeyboardAction.end => Icons.last_page_rounded,
    TerminalKeyboardAction.pageUp => Icons.vertical_align_top_rounded,
    TerminalKeyboardAction.pageDown => Icons.vertical_align_bottom_rounded,
    TerminalKeyboardAction.controlC ||
    TerminalKeyboardAction.controlD ||
    TerminalKeyboardAction.controlZ ||
    TerminalKeyboardAction.controlL => Icons.keyboard_command_key_rounded,
    TerminalKeyboardAction.colon ||
    TerminalKeyboardAction.slash ||
    TerminalKeyboardAction.pipe ||
    TerminalKeyboardAction.dash => Icons.text_fields_rounded,
    TerminalKeyboardAction.paste => Icons.content_paste_rounded,
    TerminalKeyboardAction.functionKeys => Icons.keyboard_rounded,
    TerminalKeyboardAction.tmuxPrefix => Icons.keyboard_command_key_rounded,
    TerminalKeyboardAction.tmuxScrollback => Icons.swap_vert_rounded,
    TerminalKeyboardAction.tmuxMenu => Icons.view_quilt_rounded,
    TerminalKeyboardAction.herdrMenu => Icons.hub_rounded,
    TerminalKeyboardAction.snippets => Icons.snippet_folder_rounded,
    TerminalKeyboardAction.compose => Icons.edit_note_rounded,
    TerminalKeyboardAction.touchMode => Icons.touch_app_rounded,
  };
}

/// The bundled Omarchy themes, dark first, as tappable previews.
class _ThemeGrid extends StatelessWidget {
  const _ThemeGrid({required this.controller});

  final ThemeController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final following = controller.omarchySyncedTheme != null;
    final active = controller.palette;
    // Two per row, in plain rows: the sheet is the only scrollable.
    Widget grid(List<AppPalette> palettes) => Column(
      children: [
        for (var i = 0; i < palettes.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          Row(
            children: [
              for (var j = i; j < i + 2; j++) ...[
                if (j > i) const SizedBox(width: 10),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1.55,
                    child: j < palettes.length
                        ? PaletteCard(
                            palette: palettes[j],
                            selected: palettes[j].id == active.id,
                            onTap: () => controller.setPalette(palettes[j]),
                          )
                        : null,
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
    final dark = [
      for (final palette in AppPalette.values)
        if (palette.isDark) palette,
    ];
    final light = [
      for (final palette in AppPalette.values)
        if (!palette.isDark) palette,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (following) ...[
          Text(
            'Picking a theme below stops following the machine.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
        ],
        if (active.custom) ...[
          SizedBox(
            height: 92,
            child: PaletteCard(palette: active, selected: true, onTap: () {}),
          ),
          const SizedBox(height: 14),
        ],
        Text('Dark', style: theme.textTheme.labelMedium),
        const SizedBox(height: 8),
        grid(dark),
        const SizedBox(height: 14),
        Text('Light', style: theme.textTheme.labelMedium),
        const SizedBox(height: 8),
        grid(light),
      ],
    );
  }
}

/// A theme preview in the theme's own colours: a prompt line and its
/// ANSI colours on the theme background, like a tiny terminal.
class PaletteCard extends StatelessWidget {
  const PaletteCard({
    required this.palette,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final terminal = palette.terminalTheme;
    final mono = AppTheme.monoFontFamily;
    final ansi = [
      terminal.red,
      terminal.green,
      terminal.yellow,
      terminal.blue,
      terminal.magenta,
      terminal.cyan,
      palette.colors.orange,
      terminal.white,
    ];
    return Semantics(
      button: true,
      selected: selected,
      label: '${palette.label} theme',
      child: Material(
        color: palette.canvas,
        shape: RoundedRectangleBorder(
          borderRadius: AppTheme.borderRadius,
          side: BorderSide(
            color: selected ? palette.accent : palette.hairline,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        palette.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.foreground,
                          fontFamily: mono,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    if (selected)
                      Icon(
                        Icons.check_rounded,
                        color: palette.accent,
                        size: 16,
                      ),
                  ],
                ),
                const Spacer(),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '❯ ',
                        style: TextStyle(color: palette.accent),
                      ),
                      TextSpan(
                        text: 'claude ',
                        style: TextStyle(color: palette.foreground),
                      ),
                      TextSpan(
                        text: '--resume',
                        style: TextStyle(color: palette.mutedForeground),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(fontFamily: mono, fontSize: 11),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    for (final color in ansi)
                      Expanded(child: Container(height: 6, color: color)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Follow Omarchy theme from machine": none or one saved machine, its
/// sync status and a Sync now button.
class OmarchySyncControls extends StatefulWidget {
  const OmarchySyncControls({required this.sync, super.key});

  final OmarchyThemeSyncController sync;

  @override
  State<OmarchySyncControls> createState() => _OmarchySyncControlsState();
}

class _OmarchySyncControlsState extends State<OmarchySyncControls> {
  late Future<List<SavedHost>> _machines = widget.sync.machines();

  @override
  void didUpdateWidget(OmarchySyncControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sync != widget.sync) {
      _machines = widget.sync.machines();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.sync, widget.sync.theme]),
      builder: (context, _) {
        final sync = widget.sync;
        final hostId = sync.theme.omarchySyncHostId;
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: AppTheme.borderRadius,
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: FutureBuilder<List<SavedHost>>(
            future: _machines,
            builder: (context, snapshot) {
              final machines = snapshot.data ?? const <SavedHost>[];
              final known = machines.any((host) => host.id == hostId);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Follow Omarchy theme from machine',
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    key: ValueKey('omarchy-sync-machine-$hostId-$known'),
                    initialValue: known ? hostId : null,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<String?>(child: Text('None')),
                      for (final host in machines)
                        DropdownMenuItem<String?>(
                          value: host.id,
                          child: Text(
                            host.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: sync.follow,
                  ),
                  if (hostId != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _status(sync),
                            key: const ValueKey('omarchy-sync-status'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: sync.state == OmarchySyncState.failed
                                  ? colorScheme.error
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: sync.state == OmarchySyncState.syncing
                              ? null
                              : () => sync.refresh(explicit: true),
                          icon: const Icon(Icons.sync_rounded, size: 18),
                          label: const Text('Sync now'),
                        ),
                      ],
                    ),
                  ] else ...[
                    const SizedBox(height: 6),
                    Text(
                      'Reads the theme and font of an Omarchy PC over SSH '
                      'when the app starts or comes back.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              );
            },
          ),
        );
      },
    );
  }

  String _status(OmarchyThemeSyncController sync) {
    if (sync.message.isNotEmpty) {
      return sync.message;
    }
    final synced = sync.theme.omarchySyncedTheme;
    if (synced != null) {
      final time = synced.syncedAt.toLocal();
      return '${synced.palette.label}, synced at '
          '${time.hour.toString().padLeft(2, '0')}:'
          '${time.minute.toString().padLeft(2, '0')}';
    }
    return 'Not synced yet.';
  }
}

/// App identity and the upstream credit Conductore keeps under Apache-2.0.
class _AboutControls extends StatelessWidget {
  const _AboutControls();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Conductore', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Based on Conduit by gwitko (Apache-2.0)',
          key: const ValueKey('about-upstream-credit'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'Conductore',
              applicationLegalese: 'Based on Conduit by gwitko (Apache-2.0)',
            ),
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('Open-source licenses'),
          ),
        ),
        const _ErrorLogButton(),
      ],
    );
  }
}

/// Settings › About › Recent errors: the errors the app caught this run,
/// to read and copy into a bug report.
class _ErrorLogButton extends StatelessWidget {
  const _ErrorLogButton();

  @override
  Widget build(BuildContext context) {
    final log = AppErrorLog.instance;
    return ListenableBuilder(
      listenable: log,
      builder: (context, _) {
        final count = log.entries.length;
        return Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('about-recent-errors'),
            onPressed: () => showRecentErrors(context, log),
            icon: const Icon(Icons.bug_report_outlined, size: 18),
            label: Text(
              count == 0 ? 'Recent errors' : 'Recent errors ($count)',
            ),
          ),
        );
      },
    );
  }
}

/// Lists [log]'s errors, newest first, each expandable to its details,
/// with a button that copies them all.
Future<void> showRecentErrors(BuildContext context, AppErrorLog log) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final entries = log.entries.reversed.toList();
      return AlertDialog(
        key: const ValueKey('recent-errors'),
        title: const Text('Recent errors'),
        content: SizedBox(
          width: double.maxFinite,
          child: entries.isEmpty
              ? const Text('No errors since the app started.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final entry in entries)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(
                          entry.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          TimeOfDay.fromDateTime(
                            entry.time,
                          ).format(dialogContext),
                          style: const TextStyle(fontSize: 11),
                        ),
                        children: [
                          SelectableText(
                            entry.details,
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          if (entries.isNotEmpty)
            FilledButton(
              key: const ValueKey('recent-errors-copy'),
              onPressed: () async {
                await log.copyReport();
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.maybeOf(
                  dialogContext,
                )?.showSnackBar(const SnackBar(content: Text('Errors copied')));
              },
              child: const Text('Copy all'),
            ),
        ],
      );
    },
  );
}
