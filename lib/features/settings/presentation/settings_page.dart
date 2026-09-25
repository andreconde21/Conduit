import 'package:conduit/core/presentation/conduit_brand.dart';
import 'package:conduit/core/presentation/system_navigation_insets.dart';
import 'package:conduit/features/session_navigation/presentation/session_view_controller.dart';
import 'package:conduit/features/settings/presentation/settings_catalog.dart';
import 'package:conduit/features/settings/presentation/settings_sections.dart';
import 'package:conduit/features/settings/presentation/settings_services.dart';
import 'package:conduit/features/sync/presentation/sync_scope.dart';
import 'package:flutter/material.dart';

/// Width from which Settings shows the section list and the open section
/// side by side.
const settingsTwoPaneMinWidth = 900.0;

/// Opens Settings full screen, optionally at [section]. [services] default
/// to the app-wide [SettingsScope]; without either nothing opens.
Future<void> showSettings(
  BuildContext context, {
  SettingsServices? services,
  SettingsSection? section,
}) async {
  final base = services ?? SettingsScope.maybeOf(context);
  if (base == null) return;
  final resolved = base.copyWith(
    hasSync: base.hasSync || SyncScope.maybeOf(context) != null,
    hasSessionViews:
        base.hasSessionViews || SessionViewScope.maybeOf(context) != null,
  );
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SettingsPage(services: resolved, initialSection: section),
    ),
  );
}

/// Settings: a searchable list of sections (Appearance, Terminal, Input,
/// Chat & Voice, Agents, Sync & Backup, Security, About). On a phone a
/// section opens as its own page; from [settingsTwoPaneMinWidth] the list
/// stays on the left and the section shows beside it.
class SettingsPage extends StatefulWidget {
  const SettingsPage({required this.services, this.initialSection, super.key});

  final SettingsServices services;
  final SettingsSection? initialSection;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _search = TextEditingController();
  late SettingsSection _selected =
      widget.initialSection ?? SettingsSection.appearance;
  bool _pushedInitial = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<SettingsEntry> get _matches {
    final query = _search.text.trim();
    if (query.isEmpty) return const [];
    return [
      for (final entry in settingsCatalog)
        if (entry.isAvailable(widget.services) && entry.matches(query)) entry,
    ];
  }

  void _open(SettingsSection section, {required bool wide}) {
    if (wide) {
      setState(() => _selected = section);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SettingsSectionPage(section: section, services: widget.services),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.services.theme.palette;
    return Scaffold(
      body: ConduitBackdrop(
        palette: palette,
        // The backdrop paints; tiles need a Material above it for ink.
        child: Material(
          type: MaterialType.transparency,
          child: SafeArea(
            bottom: shouldApplyBottomSafeArea(context),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= settingsTwoPaneMinWidth;
                final initial = widget.initialSection;
                if (!wide && initial != null && !_pushedInitial) {
                  _pushedInitial = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _open(initial, wide: false);
                  });
                }
                final list = _SectionList(
                  search: _search,
                  matches: _matches,
                  selected: wide ? _selected : null,
                  onOpen: (section) => _open(section, wide: wide),
                );
                if (!wide) return list;
                return Row(
                  key: const ValueKey('settings-two-pane'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 320, child: list),
                    VerticalDivider(
                      width: 1,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _PaneTitle(section: _selected),
                          Expanded(
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 760,
                                ),
                                child: SettingsSectionBody(
                                  key: ValueKey(_selected),
                                  section: _selected,
                                  services: widget.services,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionList extends StatelessWidget {
  const _SectionList({
    required this.search,
    required this.matches,
    required this.selected,
    required this.onOpen,
  });

  final TextEditingController search;
  final List<SettingsEntry> matches;
  final SettingsSection? selected;
  final ValueChanged<SettingsSection> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final searching = search.text.trim().isNotEmpty;
    return ListView(
      key: const ValueKey('settings-sections'),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Settings', style: theme.textTheme.headlineSmall),
            ),
            const ConduitGlyph(size: 24),
            const SizedBox(width: 8),
          ],
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: TextField(
            key: const ValueKey('settings-search'),
            controller: search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search settings',
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              suffixIcon: searching
                  ? IconButton(
                      tooltip: 'Clear search',
                      onPressed: search.clear,
                      icon: const Icon(Icons.close_rounded),
                    )
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (searching) ...[
          if (matches.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No setting matches "${search.text.trim()}".',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final entry in matches)
            ListTile(
              key: ValueKey('settings-result-${entry.title}'),
              leading: Icon(entry.section.icon),
              title: Text(entry.title),
              subtitle: Text(entry.section.title),
              onTap: () => onOpen(entry.section),
            ),
        ] else
          for (final section in SettingsSection.values)
            ListTile(
              key: ValueKey('settings-section-${section.name}'),
              selected: section == selected,
              selectedTileColor: colorScheme.primary.withValues(alpha: 0.10),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
              leading: Icon(section.icon),
              title: Text(section.title),
              subtitle: Text(
                section.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: selected == null
                  ? const Icon(Icons.chevron_right_rounded)
                  : null,
              onTap: () => onOpen(section),
            ),
      ],
    );
  }
}

class _PaneTitle extends StatelessWidget {
  const _PaneTitle({required this.section});

  final SettingsSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      child: Row(
        children: [
          Icon(section.icon, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Text(section.title, style: theme.textTheme.headlineSmall),
        ],
      ),
    );
  }
}

/// One section on a phone: a flat header with back, then its settings.
class SettingsSectionPage extends StatelessWidget {
  const SettingsSectionPage({
    required this.section,
    required this.services,
    super.key,
  });

  final SettingsSection section;
  final SettingsServices services;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: ConduitBackdrop(
        palette: services.theme.palette,
        child: Material(
          type: MaterialType.transparency,
          child: SafeArea(
            bottom: shouldApplyBottomSafeArea(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          section.title,
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SettingsSectionBody(
                    section: section,
                    services: services,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
