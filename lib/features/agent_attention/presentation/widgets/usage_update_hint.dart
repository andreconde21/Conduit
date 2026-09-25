import 'dart:async';

import 'package:conduit/features/companion_setup/domain/companion_status.dart';
import 'package:conduit/features/companion_setup/presentation/companion_setup_controller.dart';
import 'package:conduit/features/companion_setup/presentation/companion_setup_page.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:flutter/material.dart';

/// The first companion version that reports usage (the statusline command).
/// Chat and approvals only need [kCompanionMinVersion]; usage is optional.
const kCompanionUsageVersion = '0.3.0';

/// Whether companion [version] predates usage reporting (unknown: no).
bool usageNeedsCompanionUpdate(String? version) =>
    version != null &&
    compareCompanionVersions(version, kCompanionUsageVersion) < 0;

/// In the Usage tab: "Update agent hooks for usage" when [host]'s companion
/// is older than [kCompanionUsageVersion]; nothing otherwise, while the
/// version is unknown, or without a [CompanionSetupScope].
class UsageUpdateHint extends StatefulWidget {
  const UsageUpdateHint({required this.host, super.key});

  final SavedHost host;

  @override
  State<UsageUpdateHint> createState() => _UsageUpdateHintState();
}

class _UsageUpdateHintState extends State<UsageUpdateHint> {
  CompanionSetupController? _checkedWith;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = CompanionSetupScope.maybeOf(context);
    if (controller != null && !identical(controller, _checkedWith)) {
      _checkedWith = controller;
      final host = widget.host;
      // Not during build: the check notifies listeners.
      scheduleMicrotask(() {
        if (mounted) controller.ensureChecked(host);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = CompanionSetupScope.maybeOf(context);
    if (controller == null) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final version = controller.statusFor(widget.host)?.installedVersion;
        if (!usageNeedsCompanionUpdate(version)) {
          return const SizedBox.shrink();
        }
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Companion $version on ${widget.host.name} does not '
                  'report usage.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => showCompanionSetup(context, widget.host),
                icon: const Icon(Icons.system_update_alt_rounded, size: 18),
                label: const Text('Update agent hooks for usage'),
              ),
            ],
          ),
        );
      },
    );
  }
}
