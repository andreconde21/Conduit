import 'dart:async';

import 'package:conduit/core/platform_features.dart';
import 'package:conduit/core/presentation/theme_sheet.dart';
import 'package:conduit/core/theme/terminal_appearance.dart';
import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/agent_attention/domain/agent_inbox.dart';
import 'package:conduit/features/agent_attention/presentation/widgets/agent_usage_tab.dart';
import 'package:conduit/features/backup/presentation/backup_sheet.dart';
import 'package:conduit/features/companion_setup/presentation/companion_setup_controller.dart';
import 'package:conduit/features/companion_setup/presentation/companion_setup_page.dart';
import 'package:conduit/features/home_widget/data/platform_agent_status_widget_channel.dart';
import 'package:conduit/features/home_widget/presentation/quick_settings_tile_controls.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/session_navigation/presentation/session_view_widgets.dart';
import 'package:conduit/features/settings/presentation/settings_catalog.dart';
import 'package:conduit/features/settings/presentation/settings_services.dart';
import 'package:conduit/features/snippets/presentation/snippet_editor.dart';
import 'package:conduit/features/sync/domain/sync_category.dart';
import 'package:conduit/features/sync/presentation/sync_scope.dart';
import 'package:conduit/features/terminal/presentation/gestures/terminal_gestures_settings.dart';
import 'package:conduit/features/terminal/presentation/trusted_keys_page.dart';
import 'package:conduit/features/terminal/presentation/widgets/pill_configurator_sheet.dart';
import 'package:conduit/features/voice/presentation/speech_settings_controls.dart';
import 'package:flutter/material.dart';

/// The settings of one [section], as a scrolling column of cards.
class SettingsSectionBody extends StatelessWidget {
  const SettingsSectionBody({
    required this.section,
    required this.services,
    this.padding = const EdgeInsets.fromLTRB(18, 4, 18, 28),
    super.key,
  });

  final SettingsSection section;
  final SettingsServices services;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: services.theme,
      builder: (context, _) => ListView(
        key: ValueKey('settings-body-${section.name}'),
        padding: padding,
        children: _children(context),
      ),
    );
  }

  List<Widget> _children(BuildContext context) {
    final theme = services.theme;
    return switch (section) {
      SettingsSection.appearance => _appearance(theme),
      SettingsSection.terminal => _terminal(theme),
      SettingsSection.input => _input(context, theme),
      SettingsSection.chatVoice => _chatVoice(theme),
      SettingsSection.agents => _agents(context),
      SettingsSection.syncBackup => _syncBackup(context),
      SettingsSection.security => _security(context),
      SettingsSection.about => const [AboutControls()],
    };
  }

  List<Widget> _appearance(ThemeController theme) => [
    if (theme.omarchySync case final sync?) ...[
      SettingsCard(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: OmarchySyncControls(sync: sync),
        ),
      ),
      _gap,
    ],
    const SettingsHeading('Themes'),
    ThemeGrid(controller: theme),
    _gap,
    const SettingsHeading('Terminal font'),
    TerminalFontControls(controller: theme),
    _gap,
    SettingsSwitchCard(
      icon: Icons.terminal_rounded,
      title: 'Show local shell',
      subtitle: 'Show the local terminal shortcut on the home screen.',
      value: theme.showLocalShell,
      onChanged: theme.setShowLocalShell,
    ),
  ];

  List<Widget> _terminal(ThemeController theme) => [
    SettingsSegmentCard<TerminalEnterSequence>(
      icon: Icons.keyboard_return_rounded,
      title: 'Enter sends',
      description: theme.terminalEnterSequence.description,
      values: TerminalEnterSequence.values,
      label: (value) => value.label,
      selected: theme.terminalEnterSequence,
      onChanged: theme.setTerminalEnterSequence,
    ),
    _gap,
    SettingsSwitchCard(
      icon: Icons.mouse_rounded,
      title: 'Send mouse taps',
      subtitle:
          'Forward terminal taps as mouse clicks when apps enable mouse '
          'tracking.',
      value: theme.terminalMouseInput,
      onChanged: theme.setTerminalMouseInput,
    ),
    _gap,
    SettingsSwitchCard(
      icon: Icons.content_paste_go_rounded,
      title: 'Remote clipboard',
      subtitle:
          'Let programs on the host copy to this device (OSC 52: vim, '
          'tmux with set-clipboard on). The host can never read it.',
      value: theme.remoteClipboardEnabled,
      onChanged: theme.setRemoteClipboardEnabled,
    ),
    _gap,
    SettingsSwitchCard(
      icon: Icons.smart_button_rounded,
      title: 'Menu buttons',
      subtitle:
          'Answer numbered menus and y/n prompts (Claude Code, installers) '
          'with buttons above the keyboard bar.',
      value: theme.menuButtonsEnabled,
      onChanged: theme.setMenuButtonsEnabled,
    ),
    _gap,
    SettingsSwitchCard(
      switchKey: const ValueKey('paste-images-as-files'),
      icon: Icons.image_outlined,
      title: 'Paste images as uploaded files',
      subtitle:
          "Pasting an image uploads it to the machine's share inbox and "
          'pastes its path, which Claude Code reads as an image. Off: '
          'paste text only.',
      value: theme.pasteImagesAsFiles,
      onChanged: theme.setPasteImagesAsFiles,
    ),
    _gap,
    SettingsSwitchCard(
      switchKey: const ValueKey('restore-sessions-switch'),
      icon: Icons.restore_page_rounded,
      title: 'Restore sessions on launch',
      subtitle:
          'Bring back the open sessions after the app restarts. tmux and '
          'Herdr sessions reattach; plain shells start fresh.',
      value: theme.restoreSessionsOnLaunch,
      onChanged: theme.setRestoreSessionsOnLaunch,
    ),
    _gap,
    // Brings its own bottom gap (and nothing without a SessionViewScope).
    const SessionViewSettingsTile(),
    SettingsCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: SnippetListEditor(
          title: 'Global snippets',
          caption: 'Shown from the Snip key-row menu on every machine.',
          snippets: theme.terminalSnippets,
          onChanged: theme.setTerminalSnippets,
        ),
      ),
    ),
  ];

  List<Widget> _input(BuildContext context, ThemeController theme) => [
    SettingsSegmentCard<TerminalToolbarStyle>(
      icon: Icons.space_bar_rounded,
      title: 'Toolbar style',
      description: theme.terminalToolbarStyle.description,
      values: TerminalToolbarStyle.values,
      label: (value) => value.label,
      selected: theme.terminalToolbarStyle,
      onChanged: theme.setTerminalToolbarStyle,
    ),
    _gap,
    SettingsCard(
      child: ListTile(
        key: const ValueKey('settings-pill-buttons'),
        leading: const Icon(Icons.view_week_outlined),
        title: const Text('Pill buttons'),
        subtitle: Text(
          '${theme.terminalPillItems.length} buttons on the floating pill. '
          'Long-press the pill in a session to change them there too.',
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _configurePill(context, theme),
      ),
    ),
    _gap,
    KeyRowsTile(controller: theme),
    _gap,
    const SettingsHeading('Gestures'),
    TerminalGesturesSettings(controller: theme),
  ];

  static Future<void> _configurePill(
    BuildContext context,
    ThemeController theme,
  ) async {
    final items = await showPillConfigurator(
      context: context,
      items: theme.terminalPillItems,
      customKeys: [
        for (final row in theme.terminalKeyboardRows)
          for (final item in row.items)
            if (item.kind != TerminalKeyboardItemKind.builtIn) item,
      ],
    );
    if (items != null) await theme.setTerminalPillItems(items);
  }

  List<Widget> _chatVoice(ThemeController theme) => [
    SettingsSwitchCard(
      switchKey: const ValueKey('compose-submit-enter'),
      icon: Icons.keyboard_return_rounded,
      title: 'Press Enter after inserting',
      subtitle:
          'The prompt composer inserts your text and presses Enter, so the '
          'agent gets it right away. Off: the text is only inserted.',
      value: theme.composeSubmitEnter,
      onChanged: theme.setComposeSubmitEnter,
    ),
    _gap,
    if (PlatformFeatures.dictation || PlatformFeatures.textToSpeech) ...[
      const SettingsHeading('Dictation and read aloud'),
      SpeechSettingsControls(controller: theme),
    ] else
      const SettingsNote(
        'Dictation, read aloud and Talk use Android speech services, so '
        'they are not available on this device.',
      ),
  ];

  List<Widget> _agents(BuildContext context) {
    final hosts = services.hostsController;
    final attention = services.agentAttention;
    return [
      if (hosts != null)
        ListenableBuilder(
          listenable: hosts,
          builder: (context, _) {
            final machines = [
              for (final host in hosts.sortedHosts)
                if (!host.isLocal) host,
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SettingsHeading('Agent hooks'),
                const SettingsNote(
                  'The Conductore companion reports Claude Code sessions, '
                  'approvals and usage from each machine. Set it up per '
                  'machine, and pick how loudly each one notifies.',
                ),
                const SizedBox(height: 10),
                if (machines.isEmpty)
                  const SettingsNote('Add a machine to set up agent hooks.'),
                for (final host in machines) ...[
                  _AgentMachineCard(
                    host: host,
                    onNotifyLevel: (level) =>
                        hosts.upsert(host.copyWith(agentNotifyLevel: level)),
                  ),
                  const SizedBox(height: 10),
                ],
                const SettingsHeading('Notifications'),
                SettingsNote(
                  [
                    for (final level in AgentNotifyLevel.values)
                      '${level.label}: ${level.description}',
                  ].join('\n'),
                ),
              ],
            );
          },
        ),
      if (attention != null) ...[
        _gap,
        const SettingsHeading('Usage'),
        ListenableBuilder(
          listenable: attention,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: buildAgentUsageChildren(context, <AgentInboxHostInput>[
              for (final host in attention.monitoredHosts)
                (
                  hostId: host.id,
                  hostName: host.name,
                  agents: attention.statusFor(host.id)?.agents ?? const [],
                ),
            ]),
          ),
        ),
      ],
      if (PlatformFeatures.homeWidget) ...[
        _gap,
        QuickSettingsTileControls(
          channel: PlatformAgentStatusWidgetChannel.instance,
        ),
      ],
    ];
  }

  List<Widget> _syncBackup(BuildContext context) {
    final backup = services.backupService;
    return [
      if (services.hasSync) ...[
        SettingsCard(
          child: ListTile(
            key: const ValueKey('settings-device-sync'),
            leading: const Icon(Icons.devices_rounded),
            title: const Text('Device sync'),
            subtitle: const Text(
              'Keep machines and settings the same on every device, end-to-'
              'end encrypted through one of your machines. Devices and '
              'pairing live here.',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showSyncPage(context),
          ),
        ),
        _gap,
      ],
      const SettingsHeading('What syncs'),
      SettingsCard(
        child: Column(
          children: [
            for (final category in SyncCategory.values)
              ListTile(
                dense: true,
                title: Text(category.label),
                subtitle: Text(category.description),
              ),
          ],
        ),
      ),
      if (backup != null) ...[
        _gap,
        const SettingsHeading('Backup file'),
        const SettingsNote(backupCoverage),
        const SizedBox(height: 10),
        BackupActions(backupService: backup),
      ],
    ];
  }

  List<Widget> _security(BuildContext context) {
    final verifier = services.hostKeyVerifier;
    final lockNow = services.onLockNow;
    return [
      SettingsCard(
        child: ListTile(
          leading: const Icon(Icons.fingerprint_rounded),
          title: const Text('App lock'),
          subtitle: Text(
            PlatformFeatures.appLock
                ? 'On. Conductore asks for your fingerprint, face or device '
                      'PIN when it opens, and closes sessions while locked.'
                : 'Not available on this platform.',
          ),
        ),
      ),
      if (lockNow != null) ...[
        _gap,
        SettingsCard(
          child: ListTile(
            key: const ValueKey('settings-lock-now'),
            leading: const Icon(Icons.lock_outline_rounded),
            title: const Text('Lock now'),
            subtitle: const Text('Closes every session until you unlock.'),
            onTap: () async {
              Navigator.of(context).popUntil((route) => route.isFirst);
              await lockNow();
            },
          ),
        ),
      ],
      if (verifier != null) ...[
        _gap,
        SettingsCard(
          child: ListTile(
            key: const ValueKey('settings-trusted-keys'),
            leading: const Icon(Icons.key_rounded),
            title: const Text('Trusted host keys'),
            subtitle: const Text('Servers Conductore has connected to before.'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => TrustedKeysPage(
                  verifier: verifier,
                  themeController: services.theme,
                ),
              ),
            ),
          ),
        ),
      ],
    ];
  }

  static const _gap = SizedBox(height: 14);
}

/// A heading over a group of settings (plain case, unlike the uppercase
/// section labels elsewhere).
class SettingsHeading extends StatelessWidget {
  const SettingsHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 2),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Muted explanatory text under a heading.
class SettingsNote extends StatelessWidget {
  const SettingsNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// One machine in Settings › Agents: its agent hooks screen and its
/// notification level.
class _AgentMachineCard extends StatelessWidget {
  const _AgentMachineCard({required this.host, required this.onNotifyLevel});

  final SavedHost host;
  final ValueChanged<AgentNotifyLevel> onNotifyLevel;

  @override
  Widget build(BuildContext context) {
    final hasCompanion = CompanionSetupScope.maybeOf(context) != null;
    return SettingsCard(
      child: Column(
        children: [
          ListTile(
            key: ValueKey('settings-agent-hooks-${host.id}'),
            leading: const Icon(Icons.webhook_rounded),
            title: Text(
              host.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              host.agentAttentionEnabled
                  ? 'Agent monitoring on'
                  : 'Agent monitoring off (machine settings)',
            ),
            trailing: hasCompanion
                ? const Icon(Icons.chevron_right_rounded)
                : null,
            onTap: hasCompanion
                ? () => unawaited(showCompanionSetup(context, host))
                : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 12, 6),
            child: Row(
              children: [
                const Icon(Icons.notifications_none_rounded, size: 20),
                const SizedBox(width: 16),
                const Text('Notify'),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<AgentNotifyLevel>(
                    key: ValueKey('settings-notify-${host.id}'),
                    value: host.agentNotifyLevel,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final level in AgentNotifyLevel.values)
                        DropdownMenuItem(
                          value: level,
                          child: Text(
                            level.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (level) {
                      if (level != null) onNotifyLevel(level);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
