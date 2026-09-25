import 'package:conduit/core/presentation/system_navigation_insets.dart';
import 'package:conduit/core/theme/app_theme.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/hosts/domain/saved_hosts_repository.dart';
import 'package:conduit/features/hosts/presentation/hosts_controller.dart';
import 'package:conduit/features/hosts/presentation/widgets/host_card.dart';
import 'package:conduit/features/hosts/presentation/widgets/host_search_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Choices in the machine switcher's menu: the host actions plus adding a
/// new machine.
enum MachineMenuChoice {
  connectTo,
  files,
  edit,
  agentHooks,
  duplicate,
  copyAddress,
  delete,
  add;

  HostAction? get hostAction => switch (this) {
    MachineMenuChoice.connectTo => HostAction.connectTo,
    MachineMenuChoice.files => HostAction.files,
    MachineMenuChoice.edit => HostAction.edit,
    MachineMenuChoice.duplicate => HostAction.duplicate,
    MachineMenuChoice.copyAddress => HostAction.copyAddress,
    MachineMenuChoice.delete => HostAction.delete,
    MachineMenuChoice.agentHooks || MachineMenuChoice.add => null,
  };
}

/// Compact chip for the machine the home page is showing, in the top
/// bar: tap the name to switch machines (or add one), the menu for the
/// machine's actions (connect to…, files, edit, agent hooks, duplicate,
/// copy address, delete, add machine).
class MachineChip extends StatelessWidget {
  const MachineChip({
    required this.host,
    required this.sessionCount,
    required this.hostCount,
    required this.onSwitch,
    required this.onMenu,
    this.otherAttentionCount = 0,
    super.key,
  });

  final SavedHost host;

  /// Open app sessions on this machine.
  final int sessionCount;

  /// Saved machines in total (the switch affordance reads differently for
  /// a single machine).
  final int hostCount;

  /// Agents needing input on other monitored machines.
  final int otherAttentionCount;

  final VoidCallback onSwitch;
  final ValueChanged<MachineMenuChoice> onMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final live = sessionCount > 0;
    return Material(
      color: colorScheme.surface.withValues(alpha: 0.6),
      shape: StadiumBorder(side: BorderSide(color: colorScheme.outlineVariant)),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: InkWell(
              onTap: onSwitch,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 7, 4, 7),
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
                              ? const Color(0xFF22C55E)
                              : colorScheme.onSurfaceVariant,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        host.name,
                        key: const ValueKey('machine-name'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(
                      hostCount > 1
                          ? Icons.unfold_more_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: 36,
            height: 36,
            child: PopupMenuButton<MachineMenuChoice>(
              tooltip: 'Machine actions',
              padding: EdgeInsets.zero,
              iconSize: 20,
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: onMenu,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: MachineMenuChoice.connectTo,
                  child: _MenuRow(Icons.call_split_rounded, 'Connect to…'),
                ),
                PopupMenuItem(
                  value: MachineMenuChoice.files,
                  child: _MenuRow(Icons.folder_open_rounded, 'Files'),
                ),
                PopupMenuItem(
                  value: MachineMenuChoice.edit,
                  child: _MenuRow(Icons.edit_outlined, 'Edit'),
                ),
                PopupMenuItem(
                  value: MachineMenuChoice.agentHooks,
                  child: _MenuRow(Icons.webhook_rounded, 'Agent hooks'),
                ),
                PopupMenuItem(
                  value: MachineMenuChoice.duplicate,
                  child: _MenuRow(Icons.copy_all_rounded, 'Duplicate'),
                ),
                PopupMenuItem(
                  value: MachineMenuChoice.copyAddress,
                  child: _MenuRow(Icons.content_copy_rounded, 'Copy address'),
                ),
                PopupMenuItem(
                  value: MachineMenuChoice.delete,
                  child: _MenuRow(Icons.delete_outline_rounded, 'Delete'),
                ),
                PopupMenuDivider(),
                PopupMenuItem(
                  value: MachineMenuChoice.add,
                  child: _MenuRow(Icons.add_rounded, 'Add machine'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [Icon(icon, size: 18), const SizedBox(width: 10), Text(label)],
    );
  }
}

/// What the machine picker returned.
sealed class MachinePickerResult {
  const MachinePickerResult();
}

class MachinePicked extends MachinePickerResult {
  const MachinePicked(this.host);

  final SavedHost host;
}

class MachineAddRequested extends MachinePickerResult {
  const MachineAddRequested();
}

class MachineActionRequested extends MachinePickerResult {
  const MachineActionRequested(this.host, this.action);

  final SavedHost host;
  final HostAction action;
}

/// Bottom sheet listing every saved machine (search, sort, per-machine
/// actions) with an "Add machine" entry.
Future<MachinePickerResult?> showMachinePicker({
  required BuildContext context,
  required HostsController hostsController,
  required String? selectedHostId,
  required Set<String> liveHostIds,
}) {
  return showModalBottomSheet<MachinePickerResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemUiOverlayStyle(Theme.of(context).brightness),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        builder: (context, scrollController) => MachinePickerSheet(
          hostsController: hostsController,
          selectedHostId: selectedHostId,
          liveHostIds: liveHostIds,
          scrollController: scrollController,
          onResult: (result) => Navigator.of(context).pop(result),
        ),
      ),
    ),
  );
}

class MachinePickerSheet extends StatefulWidget {
  const MachinePickerSheet({
    required this.hostsController,
    required this.selectedHostId,
    required this.liveHostIds,
    required this.onResult,
    this.scrollController,
    super.key,
  });

  final HostsController hostsController;
  final String? selectedHostId;
  final Set<String> liveHostIds;
  final ValueChanged<MachinePickerResult> onResult;
  final ScrollController? scrollController;

  @override
  State<MachinePickerSheet> createState() => _MachinePickerSheetState();
}

class _MachinePickerSheetState extends State<MachinePickerSheet> {
  final _search = TextEditingController();
  String _query = '';
  String? _tag;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<SavedHost> _filter(List<SavedHost> hosts) {
    final query = _query.trim().toLowerCase();
    return hosts.where((host) {
      final tagOk = _tag == null || host.tags.contains(_tag);
      final queryOk =
          query.isEmpty ||
          host.name.toLowerCase().contains(query) ||
          host.host.toLowerCase().contains(query) ||
          host.username.toLowerCase().contains(query) ||
          host.tags.any((tag) => tag.toLowerCase().contains(query));
      return tagOk && queryOk;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = shouldApplyBottomSafeArea(context)
        ? MediaQuery.viewPaddingOf(context).bottom
        : 0.0;
    return ListenableBuilder(
      listenable: widget.hostsController,
      builder: (context, _) {
        final all = widget.hostsController.sortedHosts;
        final hosts = _filter(all);
        return ListView(
          controller: widget.scrollController,
          padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Machines',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                HostSortMenu(
                  value: widget.hostsController.sortMode,
                  onChanged: widget.hostsController.setSortMode,
                ),
              ],
            ),
            if (all.length > 4) ...[
              const SizedBox(height: 8),
              HostSearchField(
                controller: _search,
                onChanged: (value) => setState(() => _query = value),
                hasContent: _query.isNotEmpty || _tag != null,
                onClear: () {
                  _search.clear();
                  setState(() {
                    _query = '';
                    _tag = null;
                  });
                },
              ),
            ],
            const SizedBox(height: 12),
            for (final host in hosts) ...[
              HostCard(
                key: ValueKey('picker-${host.id}'),
                host: host,
                active:
                    widget.liveHostIds.contains(host.id) ||
                    host.id == widget.selectedHostId,
                selectedTag: _tag,
                onConnect: () => widget.onResult(MachinePicked(host)),
                onAction: (action) =>
                    widget.onResult(MachineActionRequested(host, action)),
                onTagTap: (tag) =>
                    setState(() => _tag = _tag == tag ? null : tag),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: () => widget.onResult(const MachineAddRequested()),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add machine'),
            ),
          ],
        );
      },
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
