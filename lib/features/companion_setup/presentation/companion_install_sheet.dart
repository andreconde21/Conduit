import 'package:conduit/core/presentation/system_navigation_insets.dart';
import 'package:conduit/features/companion_setup/data/companion_installer.dart';
import 'package:flutter/material.dart';

/// The Claude Code hook events `conductore-hostd install` registers
/// (host/lib/settings.js `EVENTS`).
const companionHookEvents = [
  'SessionStart',
  'UserPromptSubmit',
  'PreToolUse',
  'PostToolUse',
  'PermissionRequest',
  'Notification',
  'Stop',
  'SubagentStop',
  'SessionEnd',
];

/// What installing changes on the machine, one line per item, in the order
/// the confirmation sheet lists them.
List<String> companionInstallChanges(String version) => [
  'Uploads the companion $version to '
      '~/${CompanionInstaller.uploadDirectory(version)}/.',
  'Copies it to ~/.local/share/conductore and links '
      '~/.local/bin/conductore-hostd and ~/.local/bin/conductore-hook.',
  'Adds ${companionHookEvents.length} hook entries to '
      '~/.claude/settings.json (${companionHookEvents.join(', ')}).',
  'Saves the previous file as ~/.claude/settings.json.bak first.',
  'Leaves your other hooks and settings untouched. Running it again '
      'changes nothing.',
  'Opens no network port. The daemon starts on the first hook event and '
      'exits after 24 hours without requests.',
];

/// Asks before installing; resolves true when the user taps Install.
Future<bool> showCompanionInstallConfirmation(
  BuildContext context, {
  required String hostName,
  required String version,
  bool update = false,
}) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => CompanionInstallSheet(
      hostName: hostName,
      version: version,
      update: update,
    ),
  );
  return confirmed ?? false;
}

class CompanionInstallSheet extends StatelessWidget {
  const CompanionInstallSheet({
    required this.hostName,
    required this.version,
    this.update = false,
    super.key,
  });

  final String hostName;
  final String version;
  final bool update;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = shouldApplyBottomSafeArea(context)
        ? MediaQuery.viewPaddingOf(context).bottom
        : 0.0;
    final action = update ? 'Update' : 'Install';
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$action agent hooks on $hostName?',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            'This runs the bundled install.sh as your SSH user. It needs '
            'Node.js 18 or newer on the machine.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (final line in companionInstallChanges(version))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.check_rounded, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(line)),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('companion-install-confirm'),
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.download_rounded),
                  label: Text(action),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
