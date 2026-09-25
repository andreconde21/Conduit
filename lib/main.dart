import 'dart:async';

import 'package:conduit/core/presentation/multiplexer_icon.dart';
import 'package:conduit/core/presentation/system_navigation_insets.dart';
import 'package:conduit/core/theme/app_theme.dart';
import 'package:conduit/core/theme/omarchy_theme_sync_controller.dart';
import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/core/theme/theme_licenses.dart';
import 'package:conduit/core/theme/theme_preferences_repository.dart';
import 'package:conduit/features/agent_attention/data/conductore_host_attention_provider.dart';
import 'package:conduit/features/agent_attention/data/herdr_attention_provider.dart';
import 'package:conduit/features/agent_attention/data/platform_agent_notifier.dart';
import 'package:conduit/features/agent_attention/data/ssh_agent_command_runner.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_controller.dart';
import 'package:conduit/features/agent_attention/presentation/agent_notification_open_listener.dart';
import 'package:conduit/features/agent_attention/presentation/agent_permission_action_listener.dart';
import 'package:conduit/features/app_lock/data/local_app_authenticator.dart';
import 'package:conduit/features/app_lock/presentation/app_lock_controller.dart';
import 'package:conduit/features/app_lock/presentation/lock_page.dart';
import 'package:conduit/features/backup/data/app_backup_service.dart';
import 'package:conduit/features/companion_setup/presentation/companion_setup_controller.dart';
import 'package:conduit/features/home_widget/data/platform_agent_status_widget_channel.dart';
import 'package:conduit/features/home_widget/presentation/agent_status_launch_listener.dart';
import 'package:conduit/features/home_widget/presentation/agent_status_widget_pusher.dart';
import 'package:conduit/features/hosts/data/secure_saved_hosts_repository.dart';
import 'package:conduit/features/hosts/presentation/hosts_controller.dart';
import 'package:conduit/features/hosts/presentation/hosts_page.dart';
import 'package:conduit/features/local_shell/data/local_terminal_repository.dart';
import 'package:conduit/features/local_shell/local_shell_licenses.dart';
import 'package:conduit/features/local_shell/presentation/local_shell_controller.dart';
import 'package:conduit/features/sessions/data/secure_connect_preferences_repository.dart';
import 'package:conduit/features/sessions/presentation/session_connect_flow.dart';
import 'package:conduit/features/sftp/data/dart_ssh_sftp_repository.dart';
import 'package:conduit/features/sftp/data/file_picker_file_export.dart';
import 'package:conduit/features/sftp/data/secure_sftp_bookmarks_repository.dart';
import 'package:conduit/features/sftp/domain/file_export.dart';
import 'package:conduit/features/sftp/domain/sftp_bookmarks_repository.dart';
import 'package:conduit/features/sftp/domain/sftp_repository.dart';
import 'package:conduit/features/share_target/data/platform_share_target_source.dart';
import 'package:conduit/features/share_target/data/sftp_share_uploader.dart';
import 'package:conduit/features/share_target/presentation/share_target_controller.dart';
import 'package:conduit/features/share_target/presentation/share_target_host.dart';
import 'package:conduit/features/share_target/presentation/share_target_scope.dart';
import 'package:conduit/features/terminal/data/connectivity_plus_network.dart';
import 'package:conduit/features/terminal/data/dart_ssh_terminal_repository.dart';
import 'package:conduit/features/terminal/data/mosh_terminal_repository.dart';
import 'package:conduit/features/terminal/data/routing_terminal_repository.dart';
import 'package:conduit/features/terminal/data/secure_host_key_verifier.dart';
import 'package:conduit/features/terminal/data/secure_recent_directories_store.dart';
import 'package:conduit/features/terminal/domain/host_key_verifier.dart';
import 'package:conduit/features/terminal/domain/ssh_terminal_repository.dart';
import 'package:conduit/features/terminal/presentation/host_key_prompt_coordinator.dart';
import 'package:conduit/features/terminal/presentation/recent_directories_controller.dart';
import 'package:conduit/features/terminal/presentation/recent_directory_tracker.dart';
import 'package:conduit/features/terminal/presentation/terminal_background_keepalive.dart';
import 'package:conduit/features/terminal/presentation/terminal_page.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerLocalShellLicenses();
  registerMultiplexerLogoLicenses();
  registerThemeLicenses();
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));

  const secureStorage = FlutterSecureStorage();
  final themeController = ThemeController(
    const ThemePreferencesRepository(secureStorage),
  );
  final lockController = AppLockController(LocalAppAuthenticator());
  final hostsController = HostsController(
    const SecureSavedHostsRepository(secureStorage),
  );
  final promptCoordinator = HostKeyPromptCoordinator();
  final hostKeyVerifier = SecureHostKeyVerifier(
    secureStorage,
    promptCoordinator,
  );
  final localShellController = LocalShellController();
  final terminalRepository = RoutingTerminalRepository(
    ssh: DartSshTerminalRepository(hostKeyVerifier),
    mosh: MoshTerminalRepository(hostKeyVerifier),
    local: LocalTerminalRepository(
      resolveLaunch: localShellController.requireLaunch,
    ),
  );
  final workspaceController = TerminalWorkspaceController(
    terminalRepository,
    ConnectivityPlusNetwork(),
  );
  final sftpRepository = DartSshSftpRepository(hostKeyVerifier);
  const sftpBookmarksRepository = SecureSftpBookmarksRepository(secureStorage);
  final agentAttention = AgentAttentionController(
    workspace: workspaceController,
    runnerFactory: (host) => SshAgentCommandRunner(hostKeyVerifier, host),
    provider: const HerdrAttentionProvider(),
    companionProvider: const ConductoreHostAttentionProvider(),
    notifier: const PlatformAgentAttentionNotifier(),
    persistMonitoringEnabled: (savedHostId) async {
      final host = hostsController.hosts
          .where((host) => host.id == savedHostId)
          .firstOrNull;
      if (host != null && !host.agentAttentionEnabled) {
        await hostsController.upsert(
          host.copyWith(agentAttentionEnabled: true),
        );
      }
    },
  );
  final recentDirectories = RecentDirectoriesController(
    const SecureRecentDirectoriesStore(secureStorage),
  );
  final connectFlow = SessionConnectFlow(
    hostsController: hostsController,
    workspace: workspaceController,
    runnerFactory: (host) => SshAgentCommandRunner(hostKeyVerifier, host),
    preferences: const SecureConnectPreferencesRepository(secureStorage),
    recentDirectories: recentDirectories,
  );
  // Collects recent directories (OSC 7, tmux on detach, companion agents)
  // for the app's whole lifetime, like the widget pusher below.
  RecentDirectoryTracker(
    workspace: workspaceController,
    directories: recentDirectories,
    runnerFactory: (host) => SshAgentCommandRunner(hostKeyVerifier, host),
    agentAttention: agentAttention,
  );
  // Mirrors the agent dashboard onto the Android home-screen widget and
  // quick-settings tile for the app's whole lifetime.
  AgentStatusWidgetPusher.forController(
    agentAttention,
    channel: PlatformAgentStatusWidgetChannel.instance,
  ).start();
  final backupService = AppBackupService(
    hostsController: hostsController,
    themeController: themeController,
    hostKeyVerifier: hostKeyVerifier,
  );
  const fileExport = FilePickerFileExport();
  final shareTarget = ShareTargetController(
    source: PlatformShareTargetSource(),
    workspace: workspaceController,
    uploader: SftpShareUploader(sftpRepository),
  );

  // Agent hooks screen: companion status per machine, shared by every
  // entry point through the scope around the whole app.
  final companionSetup = CompanionSetupController(
    runnerFactory: (host) => SshAgentCommandRunner(hostKeyVerifier, host),
    sftpRepository: sftpRepository,
  );

  // Follows a machine's Omarchy theme (Appearance settings); syncs once
  // the saved theme is loaded, then on every resume.
  final omarchyThemeSync = OmarchyThemeSyncController(
    theme: themeController,
    hosts: () async {
      await hostsController.firstLoad;
      return hostsController.hosts;
    },
    runnerFactory: (host) => SshAgentCommandRunner(hostKeyVerifier, host),
  );
  themeController.omarchySync = omarchyThemeSync;
  unawaited(themeController.load().then((_) => omarchyThemeSync.start()));
  unawaited(shareTarget.start());

  runApp(
    CompanionSetupScope(
      controller: companionSetup,
      agentAttention: agentAttention,
      child: ConduitApp(
        themeController: themeController,
        lockController: lockController,
        hostsController: hostsController,
        terminalRepository: terminalRepository,
        workspaceController: workspaceController,
        localShellController: localShellController,
        hostKeyVerifier: hostKeyVerifier,
        promptCoordinator: promptCoordinator,
        sftpRepository: sftpRepository,
        sftpBookmarksRepository: sftpBookmarksRepository,
        agentAttention: agentAttention,
        backupService: backupService,
        fileExport: fileExport,
        connectFlow: connectFlow,
        shareTarget: shareTarget,
      ),
    ),
  );
}

class ConduitApp extends StatefulWidget {
  const ConduitApp({
    required this.themeController,
    required this.lockController,
    required this.hostsController,
    required this.terminalRepository,
    required this.workspaceController,
    required this.localShellController,
    required this.hostKeyVerifier,
    required this.promptCoordinator,
    required this.sftpRepository,
    required this.sftpBookmarksRepository,
    required this.agentAttention,
    required this.backupService,
    required this.fileExport,
    this.connectFlow,
    this.shareTarget,
    super.key,
  });

  final ThemeController themeController;
  final AppLockController lockController;
  final HostsController hostsController;
  final SshTerminalRepository terminalRepository;
  final TerminalWorkspaceController workspaceController;
  final LocalShellController localShellController;
  final HostKeyVerifier hostKeyVerifier;
  final HostKeyPromptCoordinator promptCoordinator;
  final SftpRepository sftpRepository;
  final SftpBookmarksRepository sftpBookmarksRepository;
  final AgentAttentionController agentAttention;
  final AppBackupService backupService;
  final FileExport fileExport;
  final SessionConnectFlow? connectFlow;

  /// Share-to-agent flow; null disables the Android share target.
  final ShareTargetController? shareTarget;

  @override
  State<ConduitApp> createState() => _ConduitAppState();
}

class _ConduitAppState extends State<ConduitApp> with WidgetsBindingObserver {
  final _backgroundKeepalive = const TerminalBackgroundKeepalive();
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  bool _keepaliveRunning = false;
  int _keepaliveSessionCount = 0;
  bool _notificationPermissionRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.workspaceController.addListener(_syncBackgroundKeepalive);
    widget.themeController.addListener(_syncTerminalPreferences);
    widget.lockController.addListener(_syncShareTargetGate);
    _syncTerminalPreferences();
    _syncShareTargetGate();
  }

  // Shares wait behind the lock screen instead of opening pickers over it.
  void _syncShareTargetGate() {
    widget.shareTarget?.setGateOpen(widget.lockController.isUnlocked);
  }

  void _syncTerminalPreferences() {
    widget.workspaceController.setEnterSequence(
      widget.themeController.terminalEnterSequence,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _syncBackgroundKeepalive();
    _syncAgentAttention(state);

    if (state == AppLifecycleState.resumed) {
      for (final session in widget.workspaceController.sessions) {
        session.forceResize();
      }
    }
  }

  void _syncAgentAttention(AppLifecycleState state) {
    // On Android the keepalive foreground service holds connections open in
    // the background, which is exactly when attention notifications matter,
    // so polling continues. Elsewhere backgrounded sockets die anyway, so
    // polling pauses until the app returns.
    final active =
        state == AppLifecycleState.resumed ||
        (defaultTargetPlatform == TargetPlatform.android &&
            state != AppLifecycleState.detached);
    widget.agentAttention.setAppActive(active);
    // The companion long-poll only runs while the app is on screen; in the
    // background the periodic poll (and its notifications) is enough.
    widget.agentAttention.setAppForeground(
      state == AppLifecycleState.resumed || state == AppLifecycleState.inactive,
    );
  }

  void _syncBackgroundKeepalive() {
    final sessionCount = widget.workspaceController.liveSessionCount;
    _maybeRequestNotificationPermission(sessionCount);
    final shouldRun =
        sessionCount > 0 &&
        (_lifecycleState == AppLifecycleState.hidden ||
            _lifecycleState == AppLifecycleState.paused);

    if (shouldRun == _keepaliveRunning &&
        (!shouldRun || sessionCount == _keepaliveSessionCount)) {
      return;
    }

    _keepaliveRunning = shouldRun;
    _keepaliveSessionCount = shouldRun ? sessionCount : 0;
    unawaited(
      (shouldRun
              ? _backgroundKeepalive.start(sessionCount: sessionCount)
              : _backgroundKeepalive.stop())
          .catchError((_) {
            _keepaliveRunning = !shouldRun;
            _keepaliveSessionCount = 0;
          }),
    );
  }

  void _maybeRequestNotificationPermission(int sessionCount) {
    if (_notificationPermissionRequested ||
        sessionCount == 0 ||
        _lifecycleState != AppLifecycleState.resumed ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _notificationPermissionRequested = true;
    unawaited(
      _backgroundKeepalive.requestNotificationPermission().catchError((_) {}),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.workspaceController.removeListener(_syncBackgroundKeepalive);
    widget.themeController.removeListener(_syncTerminalPreferences);
    widget.lockController.removeListener(_syncShareTargetGate);
    unawaited(_backgroundKeepalive.stop());
    super.dispose();
  }

  Widget _buildTerminalPage(BuildContext context) {
    return TerminalPage(
      workspace: widget.workspaceController,
      themeController: widget.themeController,
      sftpRepository: widget.sftpRepository,
      agentAttention: widget.agentAttention,
      connectFlow: widget.connectFlow,
    );
  }

  /// Wraps the home page with the share-to-agent UI (banner, pickers).
  Widget _wrapShareTargetHost(Widget home) {
    final shareTarget = widget.shareTarget;
    if (shareTarget == null) {
      return home;
    }
    return ShareTargetHost(
      controller: shareTarget,
      workspace: widget.workspaceController,
      terminalPageBuilder: _buildTerminalPage,
      child: home,
    );
  }

  Widget _wrapShareTargetScope(Widget app) {
    final shareTarget = widget.shareTarget;
    if (shareTarget == null) {
      return app;
    }
    return ShareTargetScope(controller: shareTarget, child: app);
  }

  /// Notification taps open the agent's exact place (Herdr workspace, tab
  /// and pane) through the connect flow.
  Widget _wrapNotificationOpen(Widget home) {
    final flow = widget.connectFlow;
    if (flow == null) {
      return home;
    }
    return AgentNotificationOpenListener(
      source: PlatformAgentOpenRequests.instance,
      findHost: (hostId) async {
        await widget.hostsController.firstLoad;
        return widget.hostsController.hosts
            .where((host) => host.id == hostId)
            .firstOrNull;
      },
      onOpen: (host, agent) async {
        await flow.openAgent(host, agent);
      },
      child: home,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.themeController,
      builder: (context, _) {
        return MaterialApp(
          title: 'Conductore',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(
            brightness: Brightness.light,
            palette: widget.themeController.palette,
          ),
          darkTheme: AppTheme.build(
            brightness: Brightness.dark,
            palette: widget.themeController.palette,
          ),
          themeMode: widget.themeController.effectiveThemeMode,
          builder: (context, child) {
            final overlayStyle = AppTheme.systemUiOverlayStyle(
              Theme.of(context).brightness,
            );
            SystemChrome.setSystemUIOverlayStyle(overlayStyle);
            final content = AnnotatedRegion<SystemUiOverlayStyle>(
              value: overlayStyle,
              child: Stack(
                children: [
                  child ?? const SizedBox.shrink(),
                  AndroidThreeButtonNavigationBackground(
                    color: Theme.of(context).scaffoldBackgroundColor,
                  ),
                ],
              ),
            );
            // The builder sits above the Navigator, so pushed routes (the
            // terminal page) can read the share-target controller.
            return _wrapShareTargetScope(content);
          },
          home: ListenableBuilder(
            listenable: widget.lockController,
            builder: (context, _) {
              if (!widget.lockController.isUnlocked) {
                return LockPage(
                  controller: widget.lockController,
                  themeController: widget.themeController,
                );
              }

              final home = HostsPage(
                hostsController: widget.hostsController,
                lockController: widget.lockController,
                terminalRepository: widget.terminalRepository,
                workspaceController: widget.workspaceController,
                localShellController: widget.localShellController,
                themeController: widget.themeController,
                hostKeyVerifier: widget.hostKeyVerifier,
                promptCoordinator: widget.promptCoordinator,
                sftpRepository: widget.sftpRepository,
                sftpBookmarksRepository: widget.sftpBookmarksRepository,
                agentAttention: widget.agentAttention,
                backupService: widget.backupService,
                fileExport: widget.fileExport,
                connectFlow: widget.connectFlow,
              );
              return _wrapShareTargetHost(
                AgentStatusLaunchListener(
                  channel: PlatformAgentStatusWidgetChannel.instance,
                  agentAttention: widget.agentAttention,
                  workspace: widget.workspaceController,
                  connectFlow: widget.connectFlow,
                  child: AgentPermissionActionListener(
                    source: PlatformAgentPermissionActions.instance,
                    agentAttention: widget.agentAttention,
                    findHost: (hostId) async {
                      await widget.hostsController.firstLoad;
                      return widget.hostsController.hosts
                          .where((host) => host.id == hostId)
                          .firstOrNull;
                    },
                    child: _wrapNotificationOpen(home),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
