import 'package:conduit/core/presentation/adaptive_modal.dart';
import 'package:conduit/core/presentation/system_navigation_insets.dart';
import 'package:conduit/core/theme/app_theme.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/hosts/domain/saved_hosts_repository.dart';
import 'package:conduit/features/hosts/presentation/hosts_controller.dart';
import 'package:conduit/features/hosts/presentation/widgets/host_card.dart';
import 'package:conduit/features/hosts/presentation/widgets/host_search_field.dart';
import 'package:conduit/features/local_shell/domain/local_shell_instance.dart';
import 'package:conduit/features/local_shell/presentation/local_shell_controller.dart';
import 'package:conduit/features/local_shell/presentation/widgets/local_shell_section.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Filter key of the on-device shells (saved machines use their id).
const localMachineFilterKey = 'local';

/// Actions in a machine row's menu inside the machine sheet.
enum MachineMenuChoice {
  connectTo,
  files,
  edit,
  agentHooks,
  duplicate,
  copyAddress,
  delete;

  HostAction? get hostAction => switch (this) {
    MachineMenuChoice.connectTo => HostAction.connectTo,
    MachineMenuChoice.files => HostAction.files,
    MachineMenuChoice.edit => HostAction.edit,
    MachineMenuChoice.duplicate => HostAction.duplicate,
    MachineMenuChoice.copyAddress => HostAction.copyAddress,
    MachineMenuChoice.delete => HostAction.delete,
    MachineMenuChoice.agentHooks => null,
  };

  String get label => switch (this) {
    MachineMenuChoice.connectTo => 'Connect to…',
    MachineMenuChoice.files => 'Files',
    MachineMenuChoice.edit => 'Edit',
    MachineMenuChoice.agentHooks => 'Agent hooks',
    MachineMenuChoice.duplicate => 'Duplicate',
    MachineMenuChoice.copyAddress => 'Copy address',
    MachineMenuChoice.delete => 'Delete',
  };

  IconData get icon => switch (this) {
    MachineMenuChoice.connectTo => Icons.call_split_rounded,
    MachineMenuChoice.files => Icons.folder_open_rounded,
    MachineMenuChoice.edit => Icons.edit_outlined,
    MachineMenuChoice.agentHooks => Icons.webhook_rounded,
    MachineMenuChoice.duplicate => Icons.copy_all_rounded,
    MachineMenuChoice.copyAddress => Icons.content_copy_rounded,
    MachineMenuChoice.delete => Icons.delete_outline_rounded,
  };
}

/// The home page's machine filter: an empty set (or one naming only
/// machines that are gone) shows every machine.
@immutable
class MachineFilter {
  const MachineFilter(this.keys);

  /// Saved host ids and [localMachineFilterKey]; empty for all machines.
  final Set<String> keys;

  bool get isAll => keys.isEmpty;

  /// The filter with keys of deleted machines dropped; all machines when
  /// nothing is left.
  MachineFilter validFor(List<SavedHost> hosts) {
    final ids = {for (final host in hosts) host.id};
    return MachineFilter({
      for (final key in keys)
        if (ids.contains(key) || key == localMachineFilterKey) key,
    });
  }

  /// Whether [key] (a host id or [localMachineFilterKey]) is shown.
  bool includes(String key) => keys.isEmpty || keys.contains(key);

  /// "All machines", one or two names, or the first name and a count.
  String label(List<SavedHost> hosts) {
    if (keys.isEmpty) return 'All machines';
    final names = [
      for (final host in hosts)
        if (keys.contains(host.id)) host.name,
      if (keys.contains(localMachineFilterKey)) 'This device',
    ];
    if (names.isEmpty) return 'All machines';
    if (names.length <= 2) return names.join(', ');
    return '${names.first} +${names.length - 1}';
  }

  @override
  bool operator ==(Object other) =>
      other is MachineFilter && setEquals(other.keys, keys);

  @override
  int get hashCode => Object.hashAllUnordered(keys);
}

/// Compact chip in the top bar naming the machines the home page shows
/// ("All machines" or the selected names). Tapping opens the machine
/// sheet.
class MachineChip extends StatelessWidget {
  const MachineChip({
    required this.label,
    required this.live,
    required this.onTap,
    this.otherAttentionCount = 0,
    super.key,
  });

  final String label;

  /// Some shown machine has an open session.
  final bool live;

  /// Agents needing input on machines the filter hides.
  final int otherAttentionCount;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: colorScheme.surface.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('machine-chip'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Badge(
                isLabelVisible: otherAttentionCount > 0,
                label: Text('$otherAttentionCount'),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: live
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  key: const ValueKey('machine-name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.unfold_more_rounded,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the machine sheet asks the home page to do once it has closed.
sealed class MachineSheetResult {
  const MachineSheetResult();
}

class MachineAddRequested extends MachineSheetResult {
  const MachineAddRequested();
}

class MachineMenuRequested extends MachineSheetResult {
  const MachineMenuRequested(this.host, this.choice);

  final SavedHost host;
  final MachineMenuChoice choice;
}

class LocalShellSetupRequested extends MachineSheetResult {
  const LocalShellSetupRequested();
}

class LocalShellOpenRequested extends MachineSheetResult {
  const LocalShellOpenRequested(this.instance);

  final LocalShellInstance instance;
}

class LocalShellManageRequested extends MachineSheetResult {
  const LocalShellManageRequested(this.instance);

  final LocalShellInstance instance;
}

/// The machine sheet: every saved machine with a checkbox (the home page's
/// filter, applied as it changes; "All machines" by default) and its own
/// menu, then "Add machine" and the local shells.
Future<MachineSheetResult?> showMachineSheet({
  required BuildContext context,
  required HostsController hostsController,
  required MachineFilter filter,
  required ValueChanged<MachineFilter> onFilterChanged,
  required Set<String> liveKeys,
  LocalShellController? localShellController,
  Set<String> activeLocalInstanceIds = const {},
}) {
  return showAdaptiveModal<MachineSheetResult>(
    kind: AdaptiveModalKind.dialog,
    desktopFill: true,
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemUiOverlayStyle(Theme.of(context).brightness),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: adaptiveSheetFraction(context, 0.65),
        minChildSize: adaptiveSheetFraction(context, 0.3),
        maxChildSize: adaptiveSheetFraction(context, 0.92),
        builder: (context, scrollController) => MachineSheet(
          hostsController: hostsController,
          filter: filter,
          onFilterChanged: onFilterChanged,
          liveKeys: liveKeys,
          localShellController: localShellController,
          activeLocalInstanceIds: activeLocalInstanceIds,
          scrollController: scrollController,
          onResult: (result) => Navigator.of(context).pop(result),
        ),
      ),
    ),
  );
}

class MachineSheet extends StatefulWidget {
  const MachineSheet({
    required this.hostsController,
    required this.filter,
    required this.onFilterChanged,
    required this.liveKeys,
    required this.onResult,
    this.localShellController,
    this.activeLocalInstanceIds = const {},
    this.scrollController,
    super.key,
  });

  final HostsController hostsController;
  final MachineFilter filter;
  final ValueChanged<MachineFilter> onFilterChanged;

  /// Filter keys with an open session (a dot on their row).
  final Set<String> liveKeys;
  final ValueChanged<MachineSheetResult> onResult;

  /// Local shells, listed at the bottom; null hides them.
  final LocalShellController? localShellController;
  final Set<String> activeLocalInstanceIds;
  final ScrollController? scrollController;

  @override
  State<MachineSheet> createState() => _MachineSheetState();
}

class _MachineSheetState extends State<MachineSheet> {
  final _search = TextEditingController();
  String _query = '';
  late MachineFilter _filter = widget.filter;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<SavedHost> _matching(List<SavedHost> hosts) {
    final query = _query.trim().toLowerCase();
    return hosts.where((host) {
      return query.isEmpty ||
          host.name.toLowerCase().contains(query) ||
          host.host.toLowerCase().contains(query) ||
          host.username.toLowerCase().contains(query) ||
          host.tags.any((tag) => tag.toLowerCase().contains(query));
    }).toList();
  }

  void _set(Set<String> keys) {
    final next = MachineFilter(keys);
    setState(() => _filter = next);
    widget.onFilterChanged(next);
  }

  void _toggle(String key) {
    final keys = Set.of(_filter.keys);
    if (!keys.remove(key)) keys.add(key);
    _set(keys);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final bottomInset = shouldApplyBottomSafeArea(context)
        ? MediaQuery.viewPaddingOf(context).bottom
        : 0.0;
    final local = widget.localShellController;
    return ListenableBuilder(
      listenable: widget.hostsController,
      builder: (context, _) {
        final all = widget.hostsController.sortedHosts;
        final hosts = _matching(all);
        return ListView(
          key: const ValueKey('machine-sheet'),
          controller: widget.scrollController,
          padding: EdgeInsets.fromLTRB(0, 12, 0, 16 + bottomInset),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Machines',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Sessions and workspaces of the checked machines',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  HostSortMenu(
                    value: widget.hostsController.sortMode,
                    onChanged: widget.hostsController.setSortMode,
                  ),
                ],
              ),
            ),
            if (all.length > 4)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: HostSearchField(
                  controller: _search,
                  onChanged: (value) => setState(() => _query = value),
                  hasContent: _query.isNotEmpty,
                  onClear: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                ),
              ),
            const SizedBox(height: 8),
            if (all.isNotEmpty) ...[
              _CheckRow(
                key: const ValueKey('machine-filter-all'),
                checked: _filter.isAll,
                title: 'All machines',
                bold: true,
                onToggle: () => _set(const {}),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
            ],
            for (final host in hosts)
              _CheckRow(
                key: ValueKey('machine-row-${host.id}'),
                checked: _filter.keys.contains(host.id),
                title: host.name,
                subtitle: '${host.endpoint} · ${host.useMosh ? 'Mosh' : 'SSH'}',
                live: widget.liveKeys.contains(host.id),
                onToggle: () => _toggle(host.id),
                onOnly: () => _set({host.id}),
                trailing: PopupMenuButton<MachineMenuChoice>(
                  key: ValueKey('machine-menu-${host.id}'),
                  tooltip: 'Machine actions',
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (choice) =>
                      widget.onResult(MachineMenuRequested(host, choice)),
                  itemBuilder: (context) => [
                    for (final choice in MachineMenuChoice.values)
                      PopupMenuItem(
                        value: choice,
                        child: Row(
                          children: [
                            Icon(choice.icon, size: 18),
                            const SizedBox(width: 10),
                            Text(choice.label),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: OutlinedButton.icon(
                onPressed: () => widget.onResult(const MachineAddRequested()),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add machine'),
              ),
            ),
            if (local != null) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Divider(height: 1),
              ),
              _CheckRow(
                key: const ValueKey('machine-filter-local'),
                checked: _filter.keys.contains(localMachineFilterKey),
                title: 'This device',
                subtitle: 'Local shell sessions',
                live: widget.liveKeys.contains(localMachineFilterKey),
                onToggle: () => _toggle(localMachineFilterKey),
                onOnly: () => _set({localMachineFilterKey}),
              ),
              LocalShellSection(
                controller: local,
                activeInstanceIds: widget.activeLocalInstanceIds,
                onAdd: () => widget.onResult(const LocalShellSetupRequested()),
                onOpenInstance: (instance) async =>
                    widget.onResult(LocalShellOpenRequested(instance)),
                onManageInstance: (instance) =>
                    widget.onResult(LocalShellManageRequested(instance)),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// A checkbox row of the machine sheet: tap toggles, long press shows only
/// this entry.
class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.checked,
    required this.title,
    required this.onToggle,
    this.subtitle,
    this.bold = false,
    this.live = false,
    this.onOnly,
    this.trailing,
    super.key,
  });

  final bool checked;
  final String title;
  final String? subtitle;
  final bool bold;
  final bool live;
  final VoidCallback onToggle;
  final VoidCallback? onOnly;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return InkWell(
      onTap: onToggle,
      onLongPress: onOnly,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: EdgeInsets.fromLTRB(8, 2, trailing == null ? 16 : 4, 2),
          child: Row(
            children: [
              Checkbox(value: checked, onChanged: (_) => onToggle()),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: bold
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                            ),
                          ),
                        ),
                        if (live) ...[
                          const SizedBox(width: 8),
                          Tooltip(
                            message: 'Open sessions',
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// Sort-mode menu for the machine list.
class HostSortMenu extends StatelessWidget {
  const HostSortMenu({required this.value, required this.onChanged, super.key});

  final HostListSortMode value;
  final ValueChanged<HostListSortMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<HostListSortMode>(
      tooltip: 'Sort machines',
      initialValue: value,
      onSelected: onChanged,
      icon: const Icon(Icons.sort_rounded),
      itemBuilder: (context) => [
        for (final mode in HostListSortMode.values)
          PopupMenuItem(
            value: mode,
            child: Row(
              children: [
                Icon(_sortIcon(mode), size: 18),
                const SizedBox(width: 10),
                Text(_sortLabel(mode)),
              ],
            ),
          ),
      ],
    );
  }

  static String _sortLabel(HostListSortMode mode) => switch (mode) {
    HostListSortMode.lastConnected => 'Last connected',
    HostListSortMode.name => 'Name',
    HostListSortMode.added => 'Added',
    HostListSortMode.manual => 'Manual',
  };

  static IconData _sortIcon(HostListSortMode mode) => switch (mode) {
    HostListSortMode.lastConnected => Icons.schedule_rounded,
    HostListSortMode.name => Icons.sort_by_alpha_rounded,
    HostListSortMode.added => Icons.playlist_add_check_rounded,
    HostListSortMode.manual => Icons.drag_indicator_rounded,
  };
}
