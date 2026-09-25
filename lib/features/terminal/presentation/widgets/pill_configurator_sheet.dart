import 'package:conduit/core/presentation/adaptive_modal.dart';
import 'package:conduit/core/presentation/system_navigation_insets.dart';
import 'package:conduit/core/theme/terminal_appearance.dart';
import 'package:conduit/core/theme/terminal_pill_items.dart';
import 'package:flutter/material.dart';

/// Opens the toolbar configurator. Resolves to the new button list, or null
/// when dismissed without saving.
///
/// [customKeys] are the custom keys defined in the key rows; any of them can
/// be put on the pill too.
Future<List<TerminalPillItem>?> showPillConfigurator({
  required BuildContext context,
  required List<TerminalPillItem> items,
  required List<TerminalKeyboardItem> customKeys,
}) {
  return showAdaptiveModal<List<TerminalPillItem>>(
    kind: AdaptiveModalKind.dialog,
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) =>
        PillConfiguratorSheet(items: items, customKeys: customKeys),
  );
}

class PillConfiguratorSheet extends StatefulWidget {
  const PillConfiguratorSheet({
    required this.items,
    required this.customKeys,
    super.key,
  });

  final List<TerminalPillItem> items;
  final List<TerminalKeyboardItem> customKeys;

  @override
  State<PillConfiguratorSheet> createState() => _PillConfiguratorSheetState();
}

class _PillConfiguratorSheetState extends State<PillConfiguratorSheet> {
  late final List<TerminalPillItem> _items = List.of(widget.items);

  List<TerminalPillItem> get _catalogue => [
    for (final button in TerminalPillButton.values)
      TerminalPillItem.button(button),
    for (final key in widget.customKeys) TerminalPillItem.custom(key.id),
  ];

  String _label(TerminalPillItem item) {
    final button = item.button;
    if (button != null) {
      return button.label;
    }
    for (final key in widget.customKeys) {
      if (key.id == item.customKeyId) {
        return key.displayLabel;
      }
    }
    return 'Missing key';
  }

  String _description(TerminalPillItem item) {
    return item.button?.description ?? 'Custom key from the key rows.';
  }

  /// [newIndex] is already adjusted for the removed item.
  void _reorder(int oldIndex, int newIndex) {
    setState(() => _items.insert(newIndex, _items.removeAt(oldIndex)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final available = _catalogue
        .where((item) => !_items.contains(item))
        .toList();
    final bottomInset = shouldApplyBottomSafeArea(context)
        ? MediaQuery.viewPaddingOf(context).bottom
        : 0.0;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Toolbar buttons',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  key: const ValueKey('pill-config-reset'),
                  onPressed: () => setState(() {
                    _items
                      ..clear()
                      ..addAll(defaultTerminalPillItems);
                  }),
                  child: const Text('Reset'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
            child: Text(
              'Drag to reorder. The ⋯ button always stays at the end: tap it '
              'for the key rows, long-press it to come back here.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverReorderableList(
                  itemCount: _items.length,
                  onReorderItem: _reorder,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return Material(
                      key: ValueKey('pill-config-item-${item.encode()}'),
                      color: Colors.transparent,
                      child: ListTile(
                        dense: true,
                        leading: ReorderableDragStartListener(
                          index: index,
                          child: const Icon(Icons.drag_indicator_rounded),
                        ),
                        title: Text(_label(item)),
                        subtitle: Text(_description(item)),
                        trailing: IconButton(
                          key: ValueKey('pill-config-remove-${item.encode()}'),
                          tooltip: 'Remove',
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () =>
                              setState(() => _items.removeAt(index)),
                        ),
                      ),
                    );
                  },
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Add', style: theme.textTheme.labelLarge),
                        const SizedBox(height: 8),
                        if (available.isEmpty)
                          Text(
                            'Every button is on the toolbar.',
                            style: theme.textTheme.bodySmall,
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final item in available)
                                ActionChip(
                                  key: ValueKey(
                                    'pill-config-add-${item.encode()}',
                                  ),
                                  avatar: const Icon(Icons.add, size: 16),
                                  label: Text(_label(item)),
                                  onPressed: () =>
                                      setState(() => _items.add(item)),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + bottomInset),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('pill-config-save'),
                    onPressed: () => Navigator.of(context).pop(List.of(_items)),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
