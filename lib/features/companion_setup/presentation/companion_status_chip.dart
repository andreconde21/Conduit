import 'dart:async';

import 'package:conduit/features/companion_setup/domain/companion_status.dart';
import 'package:conduit/features/companion_setup/presentation/companion_setup_controller.dart';
import 'package:conduit/features/companion_setup/presentation/companion_setup_page.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:flutter/material.dart';

/// Colour and icon for a companion state, shared by the chip, the tile and
/// the Agent hooks screen's badge.
(Color, IconData) companionStateVisual(
  BuildContext context,
  CompanionState? state,
) {
  final scheme = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  final green = dark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
  final amber = dark ? const Color(0xFFFFD54F) : const Color(0xFF9A5B00);
  return switch (state) {
    null => (scheme.onSurfaceVariant, Icons.more_horiz_rounded),
    CompanionState.active => (green, Icons.check_circle_rounded),
    CompanionState.waitingForFirstEvent => (
      scheme.primary,
      Icons.hourglass_top_rounded,
    ),
    CompanionState.notInstalled => (
      scheme.onSurfaceVariant,
      Icons.download_rounded,
    ),
    CompanionState.hooksMissing => (amber, Icons.link_off_rounded),
    CompanionState.outdated => (amber, Icons.upgrade_rounded),
    CompanionState.error => (scheme.error, Icons.error_outline_rounded),
  };
}

/// Starts a (cached) check of [host] once the widget is built.
mixin _EnsureCompanionChecked<T extends StatefulWidget> on State<T> {
  SavedHost get checkedHost;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = CompanionSetupScope.maybeOf(context);
    if (controller == null) return;
    final host = checkedHost;
    scheduleMicrotask(() {
      if (mounted) controller.ensureChecked(host);
    });
  }
}

/// A compact status pill for [host] ("Agent hooks: Active"); tapping it
/// opens the Agent hooks screen. Renders nothing without a
/// [CompanionSetupScope] above it.
class CompanionStatusChip extends StatefulWidget {
  const CompanionStatusChip({
    required this.host,
    this.showLabelPrefix = true,
    this.onTap,
    super.key,
  });

  final SavedHost host;

  /// Prefix the state with "Agent hooks:".
  final bool showLabelPrefix;

  /// Replaces the default "open the Agent hooks screen".
  final VoidCallback? onTap;

  @override
  State<CompanionStatusChip> createState() => _CompanionStatusChipState();
}

class _CompanionStatusChipState extends State<CompanionStatusChip>
    with _EnsureCompanionChecked {
  @override
  SavedHost get checkedHost => widget.host;

  @override
  Widget build(BuildContext context) {
    final controller = CompanionSetupScope.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final status = controller.statusFor(widget.host);
        final checking = controller.isChecking(widget.host);
        final (color, icon) = companionStateVisual(context, status?.state);
        final text = status == null
            ? (checking ? 'Checking…' : 'Unknown')
            : status.state.label;
        return ActionChip(
          key: const ValueKey('companion-status-chip'),
          avatar: Icon(icon, size: 16, color: color),
          label: Text(
            widget.showLabelPrefix ? 'Agent hooks: $text' : text,
            overflow: TextOverflow.ellipsis,
          ),
          side: BorderSide(color: color.withValues(alpha: 0.5)),
          visualDensity: VisualDensity.compact,
          onPressed:
              widget.onTap ?? () => showCompanionSetup(context, widget.host),
        );
      },
    );
  }
}

/// "Install agent hooks to get approvals and chat": shown only while the
/// companion is missing, outdated or unhooked on [host]; tapping opens the
/// Agent hooks screen. Renders nothing otherwise (or without a scope).
class CompanionInstallBanner extends StatefulWidget {
  const CompanionInstallBanner({required this.host, super.key});

  final SavedHost host;

  @override
  State<CompanionInstallBanner> createState() => _CompanionInstallBannerState();
}

class _CompanionInstallBannerState extends State<CompanionInstallBanner>
    with _EnsureCompanionChecked {
  @override
  SavedHost get checkedHost => widget.host;

  @override
  Widget build(BuildContext context) {
    final controller = CompanionSetupScope.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.statusFor(widget.host)?.state;
        if (state == null || !state.needsInstall) {
          return const SizedBox.shrink();
        }
        final scheme = Theme.of(context).colorScheme;
        final (color, icon) = companionStateVisual(context, state);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Material(
            key: const ValueKey('companion-install-banner'),
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => showCompanionSetup(context, widget.host),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  children: [
                    Icon(icon, color: color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        state == CompanionState.outdated
                            ? 'Update agent hooks to keep approvals and chat '
                                  'working'
                            : 'Install agent hooks to get approvals and chat',
                        style: TextStyle(color: scheme.onSecondaryContainer),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: scheme.onSecondaryContainer,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The host form's "Agent hooks: `status` ›" row. [resolveHost] returns
/// the machine as currently edited (null when the form is not valid yet).
class CompanionSetupTile extends StatefulWidget {
  const CompanionSetupTile({
    required this.host,
    required this.resolveHost,
    super.key,
  });

  /// The saved machine being edited, for the cached status; null for a new
  /// machine (its status shows after the first check).
  final SavedHost? host;
  final SavedHost? Function() resolveHost;

  @override
  State<CompanionSetupTile> createState() => _CompanionSetupTileState();
}

class _CompanionSetupTileState extends State<CompanionSetupTile> {
  SavedHost? _checked;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = CompanionSetupScope.maybeOf(context);
    final host = widget.host;
    if (controller != null && host != null && _checked == null) {
      scheduleMicrotask(() {
        if (mounted) controller.ensureChecked(host);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = CompanionSetupScope.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final host = _checked ?? widget.host;
        final status = host == null ? null : controller.statusFor(host);
        final checking = host != null && controller.isChecking(host);
        final (color, icon) = companionStateVisual(context, status?.state);
        final text =
            status?.state.label ?? (checking ? 'Checking…' : 'Tap to check');
        return ListTile(
          key: const ValueKey('companion-setup-tile'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: color),
          title: Text('Agent hooks: $text'),
          subtitle: const Text('Conductore companion for approvals and chat'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () async {
            final resolved = widget.resolveHost();
            if (resolved == null) return;
            setState(() => _checked = resolved);
            await showCompanionSetup(context, resolved);
          },
        );
      },
    );
  }
}
