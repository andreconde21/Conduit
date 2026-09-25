import 'package:conduit/features/terminal/presentation/desktop_shortcuts.dart';
import 'package:flutter/material.dart';

/// The "Keyboard shortcuts" help sheet (Ctrl+Shift+/ or Cmd+/, and the
/// terminal menu), listing the running OS's keys.
Future<void> showDesktopShortcutsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) => const DesktopShortcutsSheet(),
  );
}

class DesktopShortcutsSheet extends StatelessWidget {
  const DesktopShortcutsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = desktopShortcutHelp();
    return ListView(
      key: const ValueKey('desktop-shortcuts-sheet'),
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text('Keyboard shortcuts', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(child: Text(row.label)),
                const SizedBox(width: 12),
                Text(
                  row.keys,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
