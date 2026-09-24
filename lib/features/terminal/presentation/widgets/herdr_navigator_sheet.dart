import 'dart:async';

import 'package:conduit/core/presentation/system_navigation_insets.dart';
import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/terminal/domain/herdr_navigator.dart';
import 'package:conduit/features/terminal/presentation/herdr_shortcuts.dart';
import 'package:flutter/material.dart';

/// What the user picked in the Herdr navigator.
sealed class HerdrNavigatorPick {
  const HerdrNavigatorPick();
}

class HerdrPanePick extends HerdrNavigatorPick {
  const HerdrPanePick(this.entry);

  final HerdrPaneEntry entry;
}

class HerdrShortcutPick extends HerdrNavigatorPick {
  const HerdrShortcutPick(this.shortcut);

  final HerdrShortcut shortcut;
}

/// Opens the Herdr navigator: the host's panes first (switch with a tap),
/// then Herdr's shortcuts grouped by what they act on.
///
/// [cached] is shown straight away; [load], when given, refreshes it as the
/// sheet opens. Without [load] the pane section explains why
/// ([paneListUnavailableReason]) and only the shortcuts are offered.
Future<HerdrNavigatorPick?> showHerdrNavigatorSheet({
  required BuildContext context,
  required AppPalette palette,
  required Brightness brightness,
  required String prefixLabel,
  HerdrPaneListing? cached,
  Future<HerdrPaneListing> Function()? load,
  String? paneListUnavailableReason,
}) {
  return showModalBottomSheet<HerdrNavigatorPick>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: palette.panelFor(brightness),
    builder: (context) => HerdrNavigatorSheet(
      palette: palette,
      brightness: brightness,
      prefixLabel: prefixLabel,
      cached: cached,
      load: load,
      paneListUnavailableReason: paneListUnavailableReason,
    ),
  );
}

class HerdrNavigatorSheet extends StatefulWidget {
  const HerdrNavigatorSheet({
    required this.palette,
    required this.brightness,
    required this.prefixLabel,
    this.cached,
    this.load,
    this.paneListUnavailableReason,
    super.key,
  });

  final AppPalette palette;
  final Brightness brightness;
  final String prefixLabel;
  final HerdrPaneListing? cached;
  final Future<HerdrPaneListing> Function()? load;
  final String? paneListUnavailableReason;

  @override
  State<HerdrNavigatorSheet> createState() => _HerdrNavigatorSheetState();
}

class _HerdrNavigatorSheetState extends State<HerdrNavigatorSheet> {
  late HerdrPaneListing? _listing = widget.cached;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final load = widget.load;
    if (load == null) {
      return;
    }
    setState(() => _loading = true);
    HerdrPaneListing listing;
    try {
      listing = await load();
    } catch (error) {
      listing = HerdrListingFailed('$error');
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
      // Keep showing the cached panes when a refresh fails outright.
      if (listing is! HerdrListingFailed || _listing is! HerdrPanesAvailable) {
        _listing = listing;
      }
    });
  }

  AppPalette get _palette => widget.palette;
  Brightness get _brightness => widget.brightness;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = shouldApplyBottomSafeArea(context)
        ? MediaQuery.viewPaddingOf(context).bottom
        : 0.0;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.94,
      builder: (context, scrollController) {
        return ListView(
          key: const ValueKey('herdr-navigator'),
          controller: scrollController,
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomInset),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: _palette.mutedForegroundFor(_brightness),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.view_quilt_rounded, color: _palette.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Herdr', style: theme.textTheme.titleLarge),
                ),
                if (_loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (widget.load != null)
                  IconButton(
                    key: const ValueKey('herdr-refresh'),
                    tooltip: 'Refresh panes',
                    visualDensity: VisualDensity.compact,
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _sectionLabel(theme, 'Panes'),
            const SizedBox(height: 6),
            ..._buildPaneSection(theme),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: _sectionLabel(theme, 'Shortcuts')),
                Text(
                  'prefix ${widget.prefixLabel}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _palette.mutedForegroundFor(_brightness),
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
            for (final group in HerdrShortcutGroup.values) ...[
              const SizedBox(height: 10),
              Text(
                group.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: _palette.mutedForegroundFor(_brightness),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final shortcut in HerdrShortcut.inGroup(group))
                    ActionChip(
                      key: ValueKey('herdr-shortcut-${shortcut.name}'),
                      avatar: Icon(shortcut.icon, size: 16),
                      label: Text(shortcut.label),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(HerdrShortcutPick(shortcut)),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _sectionLabel(ThemeData theme, String label) {
    return Text(
      label.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: _palette.mutedForegroundFor(_brightness),
        letterSpacing: 1.1,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  List<Widget> _buildPaneSection(ThemeData theme) {
    final reason = widget.paneListUnavailableReason;
    if (widget.load == null && widget.cached == null) {
      return [_message(theme, reason ?? 'The pane list is not available.')];
    }
    final listing = _listing;
    switch (listing) {
      case null:
        return [_message(theme, 'Looking for Herdr panes…')];
      case HerdrNotFound():
        return [
          _message(
            theme,
            'Herdr not found on this machine. The shortcuts below still '
            'work if Herdr runs inside this session.',
            key: const ValueKey('herdr-not-found'),
          ),
        ];
      case HerdrNotRunning():
        return [_message(theme, 'Herdr is installed but not running.')];
      case HerdrListingFailed(:final message):
        return [_message(theme, 'Could not list Herdr panes. $message')];
      case HerdrPanesAvailable(:final entries):
        if (entries.isEmpty) {
          return [_message(theme, 'Herdr has no panes open.')];
        }
        return [for (final entry in entries) _paneTile(theme, entry)];
    }
  }

  Widget _message(ThemeData theme, String text, {Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: _palette.mutedForegroundFor(_brightness),
        ),
      ),
    );
  }

  Widget _paneTile(ThemeData theme, HerdrPaneEntry entry) {
    final accent = _palette.accent;
    final location = [
      entry.workspaceLabel,
      if (entry.tabLabel.isNotEmpty && entry.tabLabel != entry.title)
        entry.tabLabel,
    ].join(' › ');
    final title = entry.title.isEmpty ? entry.workspaceLabel : entry.title;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        key: ValueKey('herdr-pane-${entry.paneId ?? entry.tabId}'),
        color: entry.focused
            ? Color.alphaBlend(
                accent.withValues(alpha: 0.18),
                _palette.panelElevatedFor(_brightness),
              )
            : _palette.panelElevatedFor(_brightness),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: entry.focused
              ? BorderSide(color: accent.withValues(alpha: 0.7))
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).pop(HerdrPanePick(entry)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(
                  entry.isAgent
                      ? Icons.smart_toy_outlined
                      : Icons.terminal_rounded,
                  size: 20,
                  color: entry.focused
                      ? accent
                      : _palette.mutedForegroundFor(_brightness),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        [
                          location,
                          if (entry.agentKind.isNotEmpty) entry.agentKind,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _palette.mutedForegroundFor(_brightness),
                        ),
                      ),
                    ],
                  ),
                ),
                if (entry.focused) ...[
                  const SizedBox(width: 8),
                  _chip('Current', accent),
                ],
                if (entry.status case final status?) ...[
                  const SizedBox(width: 6),
                  _chip(status.label, _statusColor(status)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _statusColor(AgentAttentionState status) => switch (status) {
    AgentAttentionState.needsInput ||
    AgentAttentionState.blocked => _palette.warning,
    AgentAttentionState.working => _palette.accent,
    AgentAttentionState.finished => _palette.success,
    AgentAttentionState.idle ||
    AgentAttentionState.unknown => _palette.mutedForegroundFor(_brightness),
  };

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
