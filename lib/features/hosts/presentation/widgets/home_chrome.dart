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
enum HomeSettingsChoice { appearance, trustedKeys, agentHooks, lock }

/// The gear's sheet: appearance and backup, trusted keys, the selected
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

/// Saved-machine and live-session counters, shown in the home page's
/// "More" area.
class HomeStats extends StatelessWidget {
  const HomeStats({
    required this.hostCount,
    required this.activeSessionCount,
    required this.onOpenSessions,
    super.key,
  });

  final int hostCount;
  final int activeSessionCount;
  final VoidCallback? onOpenSessions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatsRow(hostCount: hostCount, activeSessionCount: activeSessionCount),
        if (activeSessionCount > 0) ...[
          const SizedBox(height: 12),
          _ResumeBanner(
            activeSessionCount: activeSessionCount,
            onOpenSessions: onOpenSessions,
          ),
        ],
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.hostCount, required this.activeSessionCount});

  final int hostCount;
  final int activeSessionCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            label: 'Saved',
            value: '$hostCount',
            icon: Icons.storage_rounded,
            accent: false,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            label: 'Live sessions',
            value: '$activeSessionCount',
            icon: Icons.bolt_rounded,
            accent: activeSessionCount > 0,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accentColor = colorScheme.primary;
    final background = accent
        ? Color.alphaBlend(
            accentColor.withValues(alpha: 0.12),
            colorScheme.surface,
          )
        : colorScheme.surface;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent
              ? accentColor.withValues(alpha: 0.4)
              : colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: accent ? accentColor : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: accent ? accentColor : colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.displaySmall?.copyWith(
              color: accent ? accentColor : colorScheme.onSurface,
              fontSize: 28,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResumeBanner extends StatelessWidget {
  const _ResumeBanner({
    required this.activeSessionCount,
    required this.onOpenSessions,
  });

  final int activeSessionCount;
  final VoidCallback? onOpenSessions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = colorScheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onOpenSessions,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              accent.withValues(alpha: 0.16),
              colorScheme.surface,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.tab_rounded, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resume sessions',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      '$activeSessionCount active',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 14, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}
