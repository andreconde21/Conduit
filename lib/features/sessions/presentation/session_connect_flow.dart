import 'dart:async';

import 'package:conduit/core/presentation/system_navigation_insets.dart';
import 'package:conduit/core/theme/app_theme.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_controller.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/hosts/presentation/hosts_controller.dart';
import 'package:conduit/features/sessions/domain/connect_preferences.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/sessions/presentation/connect_picker_sheet.dart';
import 'package:conduit/features/sessions/presentation/herdr_session_focus.dart';
import 'package:conduit/features/terminal/presentation/recent_directories_controller.dart';
import 'package:conduit/features/terminal/presentation/terminal_session_controller.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Connects a saved host through the connect picker.
///
/// Owns everything the picker needs (a command runner factory for listing,
/// the per-host preferences) so pages only hand it a host. The caller is
/// still responsible for navigating to the terminal afterwards.
class SessionConnectFlow {
  SessionConnectFlow({
    required this.hostsController,
    required this.workspace,
    required this.runnerFactory,
    required this.preferences,
    this.recentDirectories,
  }) : herdr = HerdrSessionFocus(
         workspace: workspace,
         runnerFactory: runnerFactory,
       );

  final HostsController hostsController;
  final TerminalWorkspaceController workspace;
  final AgentCommandRunnerFactory runnerFactory;
  final ConnectPreferencesRepository preferences;

  /// Recent working directories per host: the picker's "Recent dirs" and
  /// the terminal's "cd to…". Null hides both.
  final RecentDirectoriesController? recentDirectories;

  /// Herdr focus across the app's sessions: re-focus on tab switch, deep
  /// links, and the command channel behind the Herdr gestures.
  final HerdrSessionFocus herdr;

  /// Opens [host] at an agent's exact place in Herdr (see
  /// [HerdrSessionFocus.openAgentLocation]).
  Future<TerminalSessionController?> openAgentLocation(
    SavedHost host, {
    required String workspaceId,
    String tabId = '',
    String paneId = '',
    String label = '',
  }) async {
    await hostsController.markConnected(host);
    return herdr.openAgentLocation(
      host,
      workspaceId: workspaceId,
      tabId: tabId,
      paneId: paneId,
      label: label,
      open: (target) => open(host, target),
    );
  }

  /// Bumped when a deep link wants the terminal on screen; the home page
  /// listens and opens the terminal workspace if it is not showing.
  final ValueNotifier<int> terminalRequests = ValueNotifier<int>(0);

  /// Deep link to [agent] on [host] (a notification, the agent sheet, the
  /// home-screen widget): with a Herdr location, the exact workspace, tab
  /// and pane; otherwise the host's open session, if any. Asks for the
  /// terminal to be shown when something was opened.
  Future<TerminalSessionController?> openAgent(
    SavedHost host,
    AgentInfo agent,
  ) async {
    final workspaceId = agent.workspace ?? '';
    TerminalSessionController? session;
    if (workspaceId.isNotEmpty && !host.isLocal) {
      session = await openAgentLocation(
        host,
        workspaceId: workspaceId,
        tabId: agent.tab ?? '',
        paneId: agent.pane ?? '',
      );
    } else {
      session = workspace.sessions
          .where((candidate) => baseHostId(candidate.host.id) == host.id)
          .firstOrNull;
      if (session != null) {
        workspace.activate(session);
      }
    }
    if (session != null) {
      terminalRequests.value += 1;
    }
    return session;
  }

  void dispose() {
    unawaited(herdr.dispose());
    terminalRequests.dispose();
  }

  /// Target keys with an open session for [host], for the "Active" badges.
  Set<String> activeTargetKeysFor(SavedHost host) => {
    for (final session in workspace.sessions)
      if (baseHostId(session.host.id) == host.id)
        ConnectTarget.keyFromSessionHostId(session.host.id) ?? 'shell',
  };

  /// Opens a session for [host]: straight away when the host remembers a
  /// choice (unless [forcePicker]), otherwise after the picker. Returns
  /// null when the picker was dismissed.
  Future<TerminalSessionController?> connect(
    BuildContext context,
    SavedHost host, {
    bool forcePicker = false,
  }) async {
    await hostsController.markConnected(host);
    if (host.isLocal) {
      return workspace.open(host);
    }
    final saved = await preferences.load(host.id);
    final directories =
        await recentDirectories?.load(host.id) ?? const <String>[];
    if (!context.mounted) {
      return null;
    }
    ConnectPickerResult? result;
    final remembered = saved.lastTarget;
    if (!forcePicker && saved.rememberChoice && remembered != null) {
      result = ConnectPickerResult(target: remembered, remember: true);
    } else {
      final runner = runnerFactory(host);
      try {
        result = await showConnectPicker(
          context: context,
          host: host,
          runner: runner,
          preferences: saved,
          activeTargetKeys: activeTargetKeysFor(host),
          initialTab: remembered?.kind == ConnectTargetKind.herdr
              ? ConnectPickerTab.herdr
              : ConnectPickerTab.tmux,
          recentDirectories: directories,
        );
      } finally {
        unawaited(runner.close());
      }
    }
    if (result == null) {
      return null;
    }
    unawaited(
      preferences.save(
        host.id,
        saved.withChoice(result.target, remember: result.remember),
      ),
    );
    return open(host, result.target);
  }

  /// Opens (or activates) the session for [target] on [host] without any
  /// UI.
  TerminalSessionController open(SavedHost host, ConnectTarget target) {
    return workspace.open(
      target.apply(host),
      startupCommand: target.startupCommand,
    );
  }

  /// Lets the user choose a saved machine, then runs [connect] for it.
  Future<TerminalSessionController?> pickHostAndConnect(
    BuildContext context,
  ) async {
    final host = await showModalBottomSheet<SavedHost>(
      context: context,
      useSafeArea: true,
      builder: (context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.systemUiOverlayStyle(Theme.of(context).brightness),
        child: _HostChooser(hostsController: hostsController),
      ),
    );
    if (host == null || !context.mounted) {
      return null;
    }
    return connect(context, host);
  }
}

class _HostChooser extends StatelessWidget {
  const _HostChooser({required this.hostsController});

  final HostsController hostsController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = shouldApplyBottomSafeArea(context)
        ? MediaQuery.viewPaddingOf(context).bottom
        : 0.0;
    return ListenableBuilder(
      listenable: hostsController,
      builder: (context, _) {
        final hosts = hostsController.sortedHosts
            .where((host) => !host.isLocal)
            .toList();
        return ListView(
          shrinkWrap: true,
          padding: EdgeInsets.fromLTRB(8, 12, 8, 16 + bottomInset),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text('New session', style: theme.textTheme.titleMedium),
            ),
            if (hosts.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No saved machines yet. Add one on the home page first.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final host in hosts)
                ListTile(
                  leading: const Icon(Icons.dns_rounded),
                  title: Text(
                    host.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    host.endpoint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  onTap: () => Navigator.of(context).pop(host),
                ),
          ],
        );
      },
    );
  }
}
