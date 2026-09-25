import 'package:conduit/core/presentation/conduit_brand.dart';
import 'package:flutter/material.dart';

/// Slim Moshi-style bar of the home page: lock on the left, the machine
/// chip in the middle, the settings gear on the right.
class HomeTopBar extends StatelessWidget {
  const HomeTopBar({
    required this.onLock,
    required this.onSettings,
    this.machine,
    super.key,
  });

  final VoidCallback onLock;
  final VoidCallback onSettings;

  /// The machine chip (absent before any machine is saved).
  final Widget? machine;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Lock',
            iconSize: 26,
            color: colorScheme.onSurface,
            icon: const Icon(Icons.lock_outline_rounded),
            onPressed: onLock,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Center(child: machine ?? const ConduitGlyph(size: 24)),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Settings',
            iconSize: 26,
            color: colorScheme.onSurface,
            icon: const Icon(Icons.settings_outlined),
            onPressed: onSettings,
          ),
        ],
      ),
    );
  }
}

/// Entries of the home settings sheet.
enum HomeSettingsChoice { appearance, sync, trustedKeys, agentHooks, lock }

/// The gear's sheet: appearance and backup, sync, trusted keys, the selected
/// machine's agent hooks, and lock.
Future<HomeSettingsChoice?> showHomeSettingsSheet(
  BuildContext context, {
  String? machineName,
}) {
  return showModalBottomSheet<HomeSettingsChoice>(
    context: context,
    useSafeArea: true,
    builder: (context) {
      void pick(HomeSettingsChoice choice) => Navigator.of(context).pop(choice);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Appearance'),
              subtitle: const Text('Theme, terminal font, backup'),
              onTap: () => pick(HomeSettingsChoice.appearance),
            ),
            ListTile(
              key: const ValueKey('home-settings-sync'),
              leading: const Icon(Icons.sync_rounded),
              title: const Text('Sync'),
              subtitle: const Text('Machines and settings on all devices'),
              onTap: () => pick(HomeSettingsChoice.sync),
            ),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Trusted keys'),
              onTap: () => pick(HomeSettingsChoice.trustedKeys),
            ),
            if (machineName != null)
              ListTile(
                leading: const Icon(Icons.webhook_rounded),
                title: const Text('Agent hooks'),
                subtitle: Text(machineName),
                onTap: () => pick(HomeSettingsChoice.agentHooks),
              ),
            ListTile(
              leading: const Icon(Icons.lock_outline_rounded),
              title: const Text('Lock now'),
              onTap: () => pick(HomeSettingsChoice.lock),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
