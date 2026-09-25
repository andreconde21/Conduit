import 'dart:async';

import 'package:conduit/core/presentation/conduit_brand.dart';
import 'package:conduit/core/presentation/system_navigation_insets.dart';
import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/core/theme/terminal_appearance.dart';
import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/agent_attention/data/remote_tool_command.dart';
import 'package:conduit/features/agent_attention/data/ssh_agent_command_runner.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_controller.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_sheet.dart';
import 'package:conduit/features/chat_view/presentation/chat_view_launcher.dart';
import 'package:conduit/features/diff_view/data/ssh_git_diff_source.dart';
import 'package:conduit/features/diff_view/presentation/diff_view.dart';
import 'package:conduit/features/diff_view/presentation/diff_view_controller.dart';
import 'package:conduit/features/diff_view/presentation/diff_view_tab.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/live_preview/data/secure_live_preview_port_store.dart';
import 'package:conduit/features/live_preview/data/ssh_port_forwarder.dart';
import 'package:conduit/features/live_preview/domain/live_preview_port_store.dart';
import 'package:conduit/features/live_preview/presentation/live_preview_controller.dart';
import 'package:conduit/features/live_preview/presentation/live_preview_port_dialog.dart';
import 'package:conduit/features/live_preview/presentation/live_preview_tab.dart';
import 'package:conduit/features/live_preview/presentation/live_preview_view.dart';
import 'package:conduit/features/prompt_menus/presentation/prompt_menu_strip.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/sessions/presentation/session_connect_flow.dart';
import 'package:conduit/features/sessions/presentation/session_grid_page.dart';
import 'package:conduit/features/sftp/domain/sftp_repository.dart';
import 'package:conduit/features/sftp/presentation/file_viewer/discard_changes_dialog.dart';
import 'package:conduit/features/sftp/presentation/file_viewer/sftp_file_viewer.dart';
import 'package:conduit/features/share_target/data/sftp_share_uploader.dart';
import 'package:conduit/features/share_target/domain/share_inbox.dart';
import 'package:conduit/features/share_target/presentation/share_target_controller.dart';
import 'package:conduit/features/share_target/presentation/share_target_scope.dart';
import 'package:conduit/features/terminal/data/platform_prompt_image_source.dart';
import 'package:conduit/features/terminal/data/prompt_image_preparer.dart';
import 'package:conduit/features/terminal/domain/herdr_remote_control.dart';
import 'package:conduit/features/terminal/domain/host_key_verifier.dart';
import 'package:conduit/features/terminal/domain/prompt_image.dart';
import 'package:conduit/features/terminal/domain/recent_directories.dart';
import 'package:conduit/features/terminal/domain/security_key_interaction.dart';
import 'package:conduit/features/terminal/domain/terminal_gesture_preferences.dart';
import 'package:conduit/features/terminal/domain/terminal_link_detector.dart';
import 'package:conduit/features/terminal/presentation/gestures/terminal_gesture_layer.dart';
import 'package:conduit/features/terminal/presentation/security_key_picker_dialog.dart';
import 'package:conduit/features/terminal/presentation/security_key_pin_dialog.dart';
import 'package:conduit/features/terminal/presentation/terminal_file_tabs_controller.dart';
import 'package:conduit/features/terminal/presentation/terminal_keyboard_bar.dart';
import 'package:conduit/features/terminal/presentation/terminal_session_controller.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';
import 'package:conduit/features/terminal/presentation/widgets/empty_terminal_state.dart';
import 'package:conduit/features/terminal/presentation/widgets/floating_toolbar.dart';
import 'package:conduit/features/terminal/presentation/widgets/image_crop_page.dart';
import 'package:conduit/features/terminal/presentation/widgets/prompt_composer_sheet.dart';
import 'package:conduit/features/terminal/presentation/widgets/recent_directories_sheet.dart';
import 'package:conduit/features/terminal/presentation/widgets/session_tools_menu.dart';
import 'package:conduit/features/terminal/presentation/widgets/terminal_header.dart';
import 'package:conduit/features/terminal/presentation/widgets/terminal_link_sheet.dart';
import 'package:conduit/features/terminal/presentation/widgets/terminal_surface.dart';
import 'package:conduit/features/voice/data/platform_speech_recognizer.dart';
import 'package:conduit/features/voice/domain/speech_recognizer.dart';
import 'package:conduit/features/voice/presentation/dictation_button.dart';
import 'package:conduit/features/voice/presentation/dictation_controller.dart';
import 'package:conduit_vt/conduit_vt.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class TerminalPage extends StatefulWidget {
  const TerminalPage({
    required this.workspace,
    required this.themeController,
    required this.sftpRepository,
    this.agentAttention,
    this.hostKeyVerifier,
    this.livePreviewPortStore = const SecureLivePreviewPortStore(
      FlutterSecureStorage(),
    ),
    this.connectFlow,
    this.speechRecognizer,
    this.promptImageSource,
    super.key,
  });

  final TerminalWorkspaceController workspace;
  final ThemeController themeController;
  final SftpRepository sftpRepository;

  /// Optional Agent Attention monitoring; null hides the dashboard.
  final AgentAttentionController? agentAttention;

  /// Opens the extra SSH connections behind the session tools (git diff,
  /// live preview); null hides the tools menu.
  final HostKeyVerifier? hostKeyVerifier;

  /// Remembers the last previewed port per host.
  final LivePreviewPortStore livePreviewPortStore;

  /// Optional connect flow for the session grid's "+" tile.
  final SessionConnectFlow? connectFlow;

  /// Voice input for Chat mode. Null means the platform default (Android's
  /// on-device recognizer; no mic elsewhere).
  final SpeechRecognizer? speechRecognizer;

  /// Where Chat mode's image button takes images from. Null means the
  /// platform picker and clipboard.
  final PromptImageSource? promptImageSource;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final _focusNode = FocusNode();
  late final TerminalFileTabsController _fileTabs;
  TerminalSessionController? _focusedSession;
  bool _fullscreen = false;
  bool _tmuxScrollMode = false;
  bool _composeMode = false;
  // Compose recall: recently SENT lines (deduped, oldest first, capped) so a
  // line sent into a mode that discarded it can be recalled; plus one UNSENT
  // draft per session (keyed by host id), preserved across compose close,
  // tab switches, and backgrounding so composing can't silently lose text.
  // Drafts are deliberately in-memory only: prompts can be sensitive, so
  // they are not persisted across a full app restart.
  static const int _composeHistoryLimit = 20;
  final List<String> _composeHistory = <String>[];
  final Map<String, String> _composeDrafts = <String, String>{};
  // Bumped whenever a draft is edited outside the inline bar (the composer
  // sheet), forcing the bar to rebuild with the updated text.
  int _composeRevision = 0;
  DictationController? _dictation;
  ShareTargetController? _shareTarget;
  final Map<TerminalSessionController, StreamSubscription<String>>
  _clipboardSubscriptions = {};

  @override
  void initState() {
    super.initState();
    _fileTabs = TerminalFileTabsController(widget.sftpRepository);
    final recognizer =
        widget.speechRecognizer ??
        (defaultTargetPlatform == TargetPlatform.android
            ? PlatformSpeechRecognizer()
            : null);
    if (recognizer != null) {
      _dictation = DictationController(
        recognizer,
        language: () => widget.themeController.speechLanguage,
      );
      unawaited(_dictation!.checkAvailability());
    }
    unawaited(WakelockPlus.enable());
    SecurityKeyInteraction.instance.registerPinPrompt(_promptSecurityKeyPin);
    SecurityKeyInteraction.instance.registerSelectionPrompt(
      _promptSecurityKeySelection,
    );
    widget.workspace.addListener(_handleWorkspaceChanged);
    _syncRemoteClipboardSubscriptions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusedSession = widget.workspace.activeSession;
      _focusNode.requestFocus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shareTarget = ShareTargetScope.maybeOf(context);
    if (shareTarget == _shareTarget) {
      return;
    }
    _shareTarget?.removeListener(_consumeSharedDraft);
    _shareTarget?.detachTerminalPage();
    _shareTarget = shareTarget;
    shareTarget?.attachTerminalPage();
    shareTarget?.addListener(_consumeSharedDraft);
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeSharedDraft());
  }

  /// Moves a delivered share (uploaded file paths and/or shared text) into
  /// the active session's Chat draft and opens the composer so the user can
  /// add instructions before sending.
  void _consumeSharedDraft() {
    final shareTarget = _shareTarget;
    final session = widget.workspace.activeSession;
    if (!mounted || shareTarget == null || session == null) {
      return;
    }
    final hostId = session.host.id;
    if (!shareTarget.hasDraft(hostId)) {
      return;
    }
    final draft = shareTarget.takeDraft(hostId)!;
    setState(() {
      _composeDrafts[hostId] = mergeShareDraft(
        _composeDrafts[hostId] ?? '',
        draft,
      );
      _composeMode = true;
      _composeRevision += 1;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.workspace.activeSession == session) {
        unawaited(_openPromptComposer(session));
      }
    });
  }

  @override
  void dispose() {
    unawaited(WakelockPlus.disable());
    _setSystemUiFullscreen(false);
    _shareTarget?.removeListener(_consumeSharedDraft);
    _shareTarget?.detachTerminalPage();
    _dictation?.dispose();
    SecurityKeyInteraction.instance.unregisterPinPrompt(_promptSecurityKeyPin);
    SecurityKeyInteraction.instance.unregisterSelectionPrompt(
      _promptSecurityKeySelection,
    );
    widget.workspace.removeListener(_handleWorkspaceChanged);
    for (final subscription in _clipboardSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    _clipboardSubscriptions.clear();
    _focusNode.dispose();
    _fileTabs.dispose();
    super.dispose();
  }

  Future<String?> _promptSecurityKeyPin(SecurityKeyPinRequest request) {
    if (!mounted) {
      return Future<String?>.value();
    }
    return showSecurityKeyPinDialog(context, request);
  }

  Future<int?> _promptSecurityKeySelection(
    SecurityKeySelectionRequest request,
  ) {
    if (!mounted) {
      return Future<int?>.value();
    }
    return showSecurityKeyPickerDialog(context, request);
  }

  /// Follows every open session's OSC 52 copies, background tabs
  /// included, so a copy made in one tab is not lost while another shows.
  void _syncRemoteClipboardSubscriptions() {
    final sessions = widget.workspace.sessions.toSet();
    _clipboardSubscriptions.removeWhere((session, subscription) {
      if (sessions.contains(session)) {
        return false;
      }
      unawaited(subscription.cancel());
      return true;
    });
    for (final session in sessions) {
      _clipboardSubscriptions[session] ??= session.remoteClipboardWrites.listen(
        (text) => _handleRemoteClipboardWrite(session, text),
      );
    }
  }

  void _handleRemoteClipboardWrite(
    TerminalSessionController session,
    String text,
  ) {
    if (!mounted || !widget.themeController.remoteClipboardEnabled) {
      return;
    }
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Copied from ${session.host.name}'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _handleWorkspaceChanged() {
    _syncRemoteClipboardSubscriptions();
    final active = widget.workspace.activeSession;
    if (active == null || active == _focusedSession) return;
    _focusedSession = active;
    _fileTabs.activate(null);
    if (_tmuxScrollMode) {
      setState(() => _tmuxScrollMode = false);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _maybeShowTouchModeHint() {
    final themeController = widget.themeController;
    if (!mounted ||
        themeController.touchModeHintSeen ||
        themeController.terminalMouseInput) {
      return;
    }
    unawaited(themeController.markTouchModeHintSeen());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'This app supports mouse taps. Use the Touch key to forward taps '
          'as terminal mouse clicks.',
        ),
        duration: Duration(seconds: 6),
      ),
    );
  }

  void _showTerminal() {
    _fileTabs.activate(null);
    _focusNode.requestFocus();
  }

  void _handlePathTap(TerminalSessionController session, String path) {
    if (session.host.isLocal) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => _fileTabs.open(session.host, path),
          ),
        ),
      );
  }

  /// A tapped link: a snackbar to open or copy it. Links to the host's own
  /// ports (localhost:3000) open in the live preview, since the phone's
  /// browser would look for them on the phone.
  void _handleLinkTap(TerminalSessionController session, String url) {
    final previewPort = _previewPortFor(session, url);
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Expanded(
                child: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              TextButton(
                onPressed: () {
                  messenger.hideCurrentSnackBar();
                  _copyToClipboard(url, 'Link copied');
                },
                child: const Text('Copy'),
              ),
            ],
          ),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: previewPort == null ? 'Open' : 'Preview',
            onPressed: () => previewPort == null
                ? unawaited(_openInBrowser(url))
                : unawaited(
                    _openLivePreview(
                      session,
                      port: previewPort,
                      path: previewPathOf(url),
                    ),
                  ),
          ),
        ),
      );
  }

  Future<bool> _handleLinkLongPress(
    TerminalSessionController session,
    String url,
    String line,
  ) async {
    final previewPort = _previewPortFor(session, url);
    final action = await showTerminalLinkSheet(
      context,
      url: url,
      previewPort: previewPort,
    );
    if (!mounted || action == null) {
      return false;
    }
    switch (action) {
      case TerminalLinkAction.openInBrowser:
        unawaited(_openInBrowser(url));
      case TerminalLinkAction.openInPreview:
        unawaited(
          _openLivePreview(
            session,
            port: previewPort,
            path: previewPathOf(url),
          ),
        );
      case TerminalLinkAction.copyLink:
        _copyToClipboard(url, 'Link copied');
      case TerminalLinkAction.copyText:
        _copyToClipboard(line, 'Line copied');
    }
    return true;
  }

  int? _previewPortFor(TerminalSessionController session, String url) {
    if (session.host.isLocal || widget.hostKeyVerifier == null) {
      return null;
    }
    return loopbackPreviewPort(url);
  }

  Future<void> _openInBrowser(String url) async {
    final uri = Uri.tryParse(url);
    var opened = false;
    if (uri != null) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('No app can open it')));
    }
  }

  void _copyToClipboard(String text, String message) {
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  Future<void> _closeFileTab(TerminalFileTab tab) async {
    if (tab.viewerKey.currentState?.isDirty ?? false) {
      final discard = await confirmDiscardChanges(context, fileName: tab.title);
      if (!discard || !mounted) return;
    }
    _fileTabs.close(tab);
  }

  static final Listenable _inertListenable = ChangeNotifier();

  void _toggleFullscreen() {
    setState(() => _fullscreen = !_fullscreen);
    _setSystemUiFullscreen(_fullscreen);
  }

  Future<void> _openPromptComposer(TerminalSessionController session) async {
    final hostId = session.host.id;
    await showPromptComposerSheet(
      context: context,
      initialText: _composeDrafts[hostId] ?? '',
      onDraftChanged: (draft) => _composeDrafts[hostId] = draft,
      onSend: session.sendComposed,
      submitEnter: widget.themeController.composeSubmitEnter,
      onSubmitEnterChanged: (enabled) =>
          unawaited(widget.themeController.setComposeSubmitEnter(enabled)),
      isConnected: () => session.isConnected,
      bracketedPasteSupported: () => session.bracketedPasteSupported,
      dictation: _dictation,
      imageAttacher: _promptImageAttacher(session),
    );
    if (!mounted) {
      return;
    }
    // The sheet may have edited or cleared this session's draft; rebuild the
    // inline bar so it shows the latest text.
    setState(() => _composeRevision += 1);
    _focusNode.requestFocus();
  }

  /// Images go to the same per-host inbox as files shared into the app,
  /// and the composer inserts the uploaded path for the agent to read.
  PromptImageAttacher _promptImageAttacher(TerminalSessionController session) {
    final preparer = PromptImagePreparer();
    return PromptImageAttacher(
      source: widget.promptImageSource ?? PlatformPromptImageSource(),
      crop: (image) => showImageCropPage(context, image),
      prepare: preparer.prepare,
      upload: (image) async {
        final paths = await SftpShareUploader(
          widget.sftpRepository,
        ).upload(session.host, [image]);
        return paths.single;
      },
    );
  }

  /// "cd to…" from the Tmux+ menu or the Herdr navigator: the machine's
  /// recent directories, acted on in the way that fits the session.
  Future<void> _openRecentDirectories(TerminalSessionController session) async {
    final directories = widget.connectFlow?.recentDirectories;
    if (directories == null) {
      return;
    }
    final host = session.host;
    final hostId = baseHostId(host.id);
    final list = await directories.load(hostId);
    if (!mounted) {
      return;
    }
    final runnerFactory = widget.connectFlow?.runnerFactory;
    final inHerdr =
        ConnectTarget.fromSessionHostId(host.id)?.kind ==
        ConnectTargetKind.herdr;
    final canRunCommands =
        runnerFactory != null &&
        !host.isLocal &&
        host.authMethod != SshAuthMethod.hardwareKey;
    final actions = <RecentDirectoryAction>[
      if (inHerdr && canRunCommands) RecentDirectoryAction.herdrTab,
      if (host.startTmuxOnConnect) RecentDirectoryAction.tmuxWindow,
      RecentDirectoryAction.cd,
    ];
    final pick = await showRecentDirectoriesSheet(
      context: context,
      hostName: host.name,
      directories: list,
      actions: actions,
      currentDirectory: session.workingDirectory,
    );
    if (pick == null || !mounted) {
      _focusNode.requestFocus();
      return;
    }
    unawaited(directories.record(hostId, pick.directory));
    switch (pick.action) {
      case RecentDirectoryAction.cd:
        session.sendText(cdCommand(pick.directory));
        _sendEnterSoon(session);
      case RecentDirectoryAction.tmuxWindow:
        session.sendPrefix(host.tmuxPrefixKey);
        session.sendText(':');
        session.sendText(tmuxNewWindowCommand(pick.directory));
        _sendEnterSoon(session);
      case RecentDirectoryAction.herdrTab:
        final runner = runnerFactory!(host);
        try {
          final result = await runner.run(
            remoteToolCommand('herdr', herdrNewTabArguments(pick.directory)),
            timeout: const Duration(seconds: 10),
          );
          if (result.exitCode != 0 && mounted) {
            final detail = result.stderr.trim().split('\n').first;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Herdr could not open a tab there'
                  '${detail.isEmpty ? '' : ': $detail'}',
                ),
              ),
            );
          }
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Herdr could not open a tab: $error')),
            );
          }
        } finally {
          unawaited(runner.close());
        }
    }
    if (mounted) {
      _focusNode.requestFocus();
    }
  }

  /// Enter as its own write, like the compose bar: TUIs treat a line that
  /// arrives with its CR in one read as a paste.
  void _sendEnterSoon(TerminalSessionController session) {
    Future<void>.delayed(TerminalSessionController.composedEnterDelay, () {
      session.sendKey(TerminalKey.enter);
    });
  }

  Future<void> _openAgentAttention(AgentAttentionController attention) async {
    await showAgentAttentionSheet(
      context: context,
      controller: attention,
      onOpenAgent: (host, agent) {
        final flow = widget.connectFlow;
        if (flow != null) {
          // The agent's exact workspace, tab and pane, in the right tab.
          unawaited(flow.openAgent(host, agent));
          Navigator.of(context).pop();
          _focusNode.requestFocus();
          return;
        }
        // Navigate as close as possible: activate the host's terminal tab
        // and ask the provider to focus the agent in the remote UI.
        final session = widget.workspace.sessions
            .where((session) => session.host.id == host.id)
            .firstOrNull;
        if (session != null) {
          widget.workspace.activate(session);
        }
        unawaited(attention.focusAgent(host.id, agent));
        Navigator.of(context).pop();
        _focusNode.requestFocus();
      },
      onOpenChat: (host, agent) {
        Navigator.of(context).pop();
        if (!chatViewAvailable(attention, host)) {
          // Herdr-only machines have no transcript or prompt relay.
          unawaited(
            showChatViewUnavailable(context, attention: attention, host: host),
          );
          return;
        }
        unawaited(
          openChatView(
            context: context,
            attention: attention,
            host: host,
            agent: agent,
            dictation: _dictation,
            onOpenTerminal: () => _showAgentTerminal(attention, host, agent),
          ),
        );
      },
    );
    if (mounted) {
      _focusNode.requestFocus();
    }
  }

  /// After the chat view: show the agent's session and focus its pane.
  void _showAgentTerminal(
    AgentAttentionController attention,
    SavedHost host,
    AgentInfo agent,
  ) {
    if (!mounted) return;
    final flow = widget.connectFlow;
    if (flow != null) {
      // The agent's exact Herdr workspace, tab and pane, in the right tab
      // (a plain tab id match misses tabs opened on a Herdr target).
      unawaited(flow.openAgent(host, agent));
      _showTerminal();
      return;
    }
    final session = widget.workspace.sessions
        .where((session) => session.host.id == host.id)
        .firstOrNull;
    if (session != null) widget.workspace.activate(session);
    unawaited(attention.focusAgent(host.id, agent));
    _showTerminal();
  }

  Future<void> _openSessionGrid() async {
    await showSessionGrid(
      context,
      workspace: widget.workspace,
      themeController: widget.themeController,
      agentAttention: widget.agentAttention,
      connectFlow: widget.connectFlow,
    );
    if (!mounted) return;
    _showTerminal();
  }

  Future<void> _openNewSession(SessionConnectFlow connectFlow) async {
    await connectFlow.pickHostAndConnect(context);
    if (!mounted) return;
    _showTerminal();
  }

  /// The Herdr command channel for [session]'s gestures. For a session
  /// that drives Herdr it also has the machine's Herdr keymap read (once,
  /// read-only), so key-labelled shortcuts and key fallbacks use its own
  /// bindings.
  HerdrRemoteControl? _herdrControlFor(TerminalSessionController session) {
    final herdr = widget.connectFlow?.herdr;
    if (herdr == null) {
      return null;
    }
    final drivesHerdr =
        (_gestureTargetFor(session) ??
            widget.themeController.terminalGestures.windowSwitchTarget) ==
        TerminalWindowSwitchTarget.herdr;
    if (drivesHerdr) {
      herdr.ensureKeymap(session);
    }
    return herdr.controlFor(session);
  }

  /// The multiplexer a session's gestures drive: the one it was opened on,
  /// or null (the Gestures preference) for plain shells.
  static TerminalWindowSwitchTarget? _gestureTargetFor(
    TerminalSessionController session,
  ) {
    return switch (ConnectTarget.fromSessionHostId(session.host.id)?.kind) {
      ConnectTargetKind.herdr => TerminalWindowSwitchTarget.herdr,
      ConnectTargetKind.tmux => TerminalWindowSwitchTarget.tmux,
      ConnectTargetKind.shell || ConnectTargetKind.directory || null => null,
    };
  }

  /// Gesture hook: swipe in from the right edge opens the agent attention
  /// sheet when monitoring is available, otherwise the gesture is off.
  VoidCallback? _agentPanelOpener() {
    final attention = widget.agentAttention;
    if (attention == null) {
      return null;
    }
    return () => _openAgentAttention(attention);
  }

  void _setSystemUiFullscreen(bool fullscreen) {
    SystemChrome.setEnabledSystemUIMode(
      fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  void _openSessionTool(TerminalSessionController session, SessionTool tool) {
    switch (tool) {
      case SessionTool.gitDiff:
        _openGitDiff(session);
      case SessionTool.livePreview:
        unawaited(_openLivePreview(session));
    }
  }

  void _openGitDiff(TerminalSessionController session) {
    final verifier = widget.hostKeyVerifier;
    if (verifier == null) {
      return;
    }
    final host = session.host;
    final tab = _fileTabs.add(
      DiffViewTab(
        host: host,
        controller: DiffViewController(
          SshGitDiffSource(SshAgentCommandRunner(verifier, host), host),
        ),
      ),
    );
    if (tab is DiffViewTab && tab.controller.phase == DiffViewPhase.idle) {
      unawaited(tab.controller.start());
    }
  }

  /// Opens the host's live preview tab. With [port] (a tapped
  /// localhost link) the port dialog is skipped and [path] is loaded.
  Future<void> _openLivePreview(
    TerminalSessionController session, {
    int? port,
    String? path,
  }) async {
    final verifier = widget.hostKeyVerifier;
    if (verifier == null) {
      return;
    }
    final host = session.host;
    final existing = _fileTabs.tabs
        .whereType<LivePreviewTab>()
        .where((tab) => tab.host.id == host.id)
        .firstOrNull;
    if (existing != null) {
      _fileTabs.activate(existing);
      final controller = existing.controller;
      if (port != null &&
          (controller.remotePort != port ||
              controller.path !=
                  LivePreviewController.normalizePath(path ?? '/'))) {
        controller.setPath(path ?? '/');
        // Restarting rebinds the local port, which reloads the WebView on
        // the new path.
        unawaited(controller.start(port));
      }
      return;
    }
    final controller = LivePreviewController(
      SshPortForwarder(verifier, host),
      hostId: host.id,
      portStore: widget.livePreviewPortStore,
      commandRunner: SshAgentCommandRunner(verifier, host),
    );
    final int? chosenPort;
    if (port != null) {
      chosenPort = port;
      controller.setPath(path ?? '/');
    } else {
      final initialPort = await controller.suggestedPort();
      if (!mounted) {
        controller.dispose();
        return;
      }
      chosenPort = await showLivePreviewPortDialog(
        context,
        initialPort: initialPort,
        detectPorts: controller.detectPorts,
        hostName: host.name,
      );
    }
    if (chosenPort == null || !mounted) {
      controller.dispose();
      return;
    }
    controller.attachSession(session, () => session.isConnected);
    _fileTabs.add(LivePreviewTab(host: host, controller: controller));
    unawaited(controller.start(chosenPort));
  }

  Future<void> _changePreviewPort(LivePreviewTab tab) async {
    final controller = tab.controller;
    final initialPort =
        controller.remotePort ?? await controller.suggestedPort();
    if (!mounted) {
      return;
    }
    final port = await showLivePreviewPortDialog(
      context,
      initialPort: initialPort,
      detectPorts: controller.detectPorts,
      hostName: tab.host.name,
    );
    if (port != null && mounted) {
      unawaited(controller.start(port));
    }
  }

  Widget _buildFileTab(
    TerminalFileTab tab,
    AppPalette palette,
    Brightness brightness,
  ) {
    final fontFamily = widget.themeController.terminalFont.fontFamily;
    return switch (tab) {
      DiffViewTab() => DiffView(
        key: ValueKey(tab),
        controller: tab.controller,
        palette: palette,
        brightness: brightness,
        fontFamily: fontFamily,
        onOpenFile: (path) => _fileTabs.open(tab.host, path),
      ),
      LivePreviewTab() => LivePreviewView(
        key: ValueKey(tab),
        controller: tab.controller,
        palette: palette,
        brightness: brightness,
        onChangePort: () => unawaited(_changePreviewPort(tab)),
      ),
      _ => SftpFileViewer(
        key: tab.viewerKey,
        path: tab.path,
        palette: palette,
        brightness: brightness,
        fontFamily: fontFamily,
        read: (onProgress) => _fileTabs.read(tab, onProgress),
        write: (bytes) => _fileTabs.write(tab, bytes),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.themeController,
      builder: (context, _) {
        final palette = widget.themeController.palette;
        return Scaffold(
          body: ListenableBuilder(
            listenable: Listenable.merge([widget.workspace, _fileTabs]),
            builder: (context, _) {
              final activeSession = widget.workspace.activeSession;
              final fileTabs = _fileTabs.tabs;
              final activeFileTab = _fileTabs.active;
              final brightness = Theme.of(context).brightness;
              if (activeSession == null && fileTabs.isEmpty) {
                return ConduitBackdrop(
                  palette: palette,
                  child: SafeArea(
                    bottom: shouldApplyBottomSafeArea(context),
                    child: EmptyTerminalState(
                      onBack: () => Navigator.of(context).pop(),
                    ),
                  ),
                );
              }

              final landscape =
                  MediaQuery.orientationOf(context) == Orientation.landscape;
              final gestureNavigation = usesAndroidGestureNavigation(context);
              return SafeArea(
                top: !_fullscreen,
                bottom: shouldApplyBottomSafeArea(context),
                left: !_fullscreen && (!landscape || !gestureNavigation),
                right: !_fullscreen && (!landscape || !gestureNavigation),
                child: Column(
                  children: [
                    if (!_fullscreen)
                      ListenableBuilder(
                        listenable: widget.agentAttention ?? _inertListenable,
                        builder: (context, _) {
                          final attention = widget.agentAttention;
                          final showAgents =
                              attention != null &&
                              (attention.monitoredHosts.isNotEmpty ||
                                  (activeSession?.host.agentAttentionEnabled ??
                                      false));
                          final connectFlow = widget.connectFlow;
                          return TerminalHeader(
                            workspace: widget.workspace,
                            activeSession: activeSession,
                            palette: palette,
                            brightness: brightness,
                            onBack: () => Navigator.of(context).pop(),
                            onTabsChanged: _showTerminal,
                            fileTabs: fileTabs,
                            activeFileTab: activeFileTab,
                            onFileTabSelected: _fileTabs.activate,
                            onFileTabClosed: _closeFileTab,
                            onReconnect: activeSession == null
                                ? null
                                : () async {
                                    await activeSession.disconnect();
                                    await activeSession.connect();
                                    _focusNode.requestFocus();
                                  },
                            onToggleFullscreen: _toggleFullscreen,
                            onNewSession: connectFlow == null
                                ? null
                                : () => _openNewSession(connectFlow),
                            onOpenChatView:
                                attention == null ||
                                    activeSession == null ||
                                    activeSession.host.isLocal
                                ? null
                                : () => openChatViewForHost(
                                    context: context,
                                    attention: attention,
                                    host: activeSession.host,
                                    dictation: _dictation,
                                    onOpenTerminal: (agent) =>
                                        _showAgentTerminal(
                                          attention,
                                          activeSession.host,
                                          agent,
                                        ),
                                  ),
                            attentionCount: attention?.attentionCount ?? 0,
                            onOpenAgentAttention: showAgents
                                ? () => _openAgentAttention(attention)
                                : null,
                            onOpenSessionGrid: _openSessionGrid,
                            swipeDownOpensSessionGrid: widget
                                .themeController
                                .terminalGestures
                                .headerSwipeOpensSessions,
                            actions: [
                              if (activeSession != null &&
                                  widget.hostKeyVerifier != null &&
                                  !activeSession.host.isLocal)
                                SessionToolsMenu(
                                  color: palette.foregroundFor(brightness),
                                  onSelected: (tool) =>
                                      _openSessionTool(activeSession, tool),
                                ),
                            ],
                          );
                        },
                      ),
                    Expanded(
                      child: Container(
                        color: palette.terminalBackgroundFor(brightness),
                        child: activeFileTab == null && activeSession == null
                            ? EmptyTerminalState(
                                onBack: () => Navigator.of(context).pop(),
                              )
                            : IndexedStack(
                                index: activeFileTab != null
                                    ? widget.workspace.sessions.length +
                                          fileTabs.indexOf(activeFileTab)
                                    : widget.workspace.sessions.indexOf(
                                        activeSession!,
                                      ),
                                children: [
                                  for (final session
                                      in widget.workspace.sessions)
                                    TerminalGestureLayer(
                                      key: ValueKey(session.host.id),
                                      target: _gestureTargetFor(session),
                                      herdrControl: _herdrControlFor(session),
                                      onHerdrWorkspaceFocused: (workspaceId) =>
                                          widget.connectFlow?.herdr
                                              .noteWorkspace(
                                                session,
                                                workspaceId,
                                              ),
                                      preferences: widget
                                          .themeController
                                          .terminalGestures,
                                      session: session,
                                      fontSize: widget
                                          .themeController
                                          .terminalFontSize,
                                      onFontSizeChanged: (fontSize) {
                                        unawaited(
                                          widget.themeController
                                              .setTerminalFontSize(fontSize),
                                        );
                                      },
                                      scrollMode:
                                          session == activeSession &&
                                          _tmuxScrollMode,
                                      onEnterScrollMode: () {
                                        setState(() => _tmuxScrollMode = true);
                                        _focusNode.requestFocus();
                                      },
                                      onExitScrollMode: () {
                                        setState(() => _tmuxScrollMode = false);
                                        _focusNode.requestFocus();
                                      },
                                      onOpenSessionGrid: _openSessionGrid,
                                      onOpenAgentPanel: _agentPanelOpener(),
                                      child: TerminalSurface(
                                        session: session,
                                        palette: palette,
                                        brightness: brightness,
                                        fontFamily: widget
                                            .themeController
                                            .terminalFont
                                            .fontFamily,
                                        fontSize: widget
                                            .themeController
                                            .terminalFontSize,
                                        predictiveEchoEnabled:
                                            session.host.predictiveEchoEnabled,
                                        terminalMouseInput: widget
                                            .themeController
                                            .terminalMouseInput,
                                        focusNode:
                                            session == activeSession &&
                                                activeFileTab == null
                                            ? _focusNode
                                            : null,
                                        tmuxScrollMode:
                                            session == activeSession &&
                                            _tmuxScrollMode,
                                        onExitTmuxScrollMode: () {
                                          setState(
                                            () => _tmuxScrollMode = false,
                                          );
                                          _focusNode.requestFocus();
                                        },
                                        onPathTap: (path) =>
                                            _handlePathTap(session, path),
                                        onLinkTap: (url) =>
                                            _handleLinkTap(session, url),
                                        onLinkLongPress: (url, line) =>
                                            _handleLinkLongPress(
                                              session,
                                              url,
                                              line,
                                            ),
                                      ),
                                    ),
                                  for (final tab in fileTabs)
                                    _buildFileTab(tab, palette, brightness),
                                ],
                              ),
                      ),
                    ),
                    // Menu → buttons: tappable choices for prompts on screen.
                    if (activeFileTab == null &&
                        activeSession != null &&
                        widget.themeController.menuButtonsEnabled)
                      PromptMenuStrip(
                        key: ValueKey('prompt-menu-${activeSession.host.id}'),
                        session: activeSession,
                        palette: palette,
                        brightness: brightness,
                        onSent: _focusNode.requestFocus,
                      ),
                    if (activeFileTab != null || activeSession == null)
                      const SizedBox.shrink()
                    else if (_composeMode)
                      _ComposeInputBar(
                        key: ValueKey(
                          'compose-${activeSession.host.id}-$_composeRevision',
                        ),
                        palette: palette,
                        brightness: brightness,
                        history: _composeHistory,
                        initialText:
                            _composeDrafts[activeSession.host.id] ?? '',
                        dictation: _dictation,
                        onChanged: (draft) {
                          _composeDrafts[activeSession.host.id] = draft;
                        },
                        onExpand: () => _openPromptComposer(activeSession),
                        onSend: (line) {
                          if (!activeSession.isConnected) {
                            // The line would be silently dropped; keep it as
                            // the draft instead of clearing it.
                            setState(() {
                              _composeDrafts[activeSession.host.id] = line;
                              _composeRevision += 1;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Not connected. The line was kept as a '
                                  'draft.',
                                ),
                              ),
                            );
                            return;
                          }
                          // Send the line, then deliver Enter as a SEPARATE write a
                          // short moment later. Some remote TUIs (e.g. Claude Code
                          // and other Ink/readline apps) classify a single terminal
                          // read that contains a long line ending in CR as a *paste*
                          // and insert the trailing CR as a literal newline instead
                          // of submitting — so a wrapping compose line silently fails
                          // to send. Delivering Enter in its own read makes it an
                          // isolated keypress that submits regardless of line length.
                          activeSession.sendText(line);
                          Future.delayed(const Duration(milliseconds: 120), () {
                            activeSession.sendKey(TerminalKey.enter);
                          });
                          setState(() {
                            // De-duplicate: drop any earlier identical entry so the
                            // ring keeps distinct lines (re-sending a recalled line
                            // can't churn duplicates that evict good older ones).
                            _composeHistory.remove(line);
                            _composeHistory.add(line);
                            if (_composeHistory.length > _composeHistoryLimit) {
                              _composeHistory.removeAt(0);
                            }
                            _composeDrafts[activeSession.host.id] = '';
                          });
                        },
                        onClose: (draft) {
                          setState(() {
                            _composeMode = false;
                            // Preserve the unsent draft for this session.
                            _composeDrafts[activeSession.host.id] = draft;
                          });
                          _focusNode.requestFocus();
                        },
                      )
                    else
                      TerminalKeyboardBar(
                        controller: activeSession,
                        focusNode: _focusNode,
                        palette: palette,
                        brightness: brightness,
                        rows: widget.themeController.terminalKeyboardRows,
                        globalSnippets: widget.themeController.terminalSnippets,
                        fullscreen: _fullscreen,
                        onToggleFullscreen: _toggleFullscreen,
                        composeActive: _composeMode,
                        onToggleCompose: () =>
                            setState(() => _composeMode = !_composeMode),
                        tmuxPrefixKey: activeSession.host.tmuxPrefixKey,
                        tmuxScrollMode: _tmuxScrollMode,
                        terminalMouseInput:
                            widget.themeController.terminalMouseInput,
                        onTerminalMouseInputChanged: (enabled) {
                          unawaited(
                            widget.themeController.setTerminalMouseInput(
                              enabled,
                            ),
                          );
                          _focusNode.requestFocus();
                        },
                        onRemoteMouseTrackingActivated: _maybeShowTouchModeHint,
                        onOpenRecentDirectories:
                            widget.connectFlow?.recentDirectories == null
                            ? null
                            : () => unawaited(
                                _openRecentDirectories(activeSession),
                              ),
                        onEnterTmuxScrollMode: () {
                          setState(() => _tmuxScrollMode = true);
                          _focusNode.requestFocus();
                        },
                        onExitTmuxScrollMode: () {
                          setState(() => _tmuxScrollMode = false);
                          _focusNode.requestFocus();
                        },
                      ).withToolbarStyle(
                        widget.themeController.terminalToolbarStyle,
                        onReconnect: () async {
                          await activeSession.disconnect();
                          await activeSession.connect();
                        },
                        pillItems: widget.themeController.terminalPillItems,
                        onPillItemsChanged: (items) => unawaited(
                          widget.themeController.setTerminalPillItems(items),
                        ),
                        runnerFactory: widget.connectFlow?.runnerFactory,
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _ComposeInputBar extends StatefulWidget {
  const _ComposeInputBar({
    required this.palette,
    required this.brightness,
    required this.onSend,
    required this.onClose,
    this.onChanged,
    this.onExpand,
    this.history = const <String>[],
    this.initialText = '',
    this.dictation,
    super.key,
  });

  final AppPalette palette;
  final Brightness brightness;
  final ValueChanged<String> onSend;

  /// Called on every edit with the current field text so the owner can keep
  /// the per-session draft up to date even if the bar is torn down (e.g. on
  /// a tab switch) without a close event.
  final ValueChanged<String>? onChanged;

  /// Opens the full multiline composer seeded with the current draft.
  final VoidCallback? onExpand;

  /// Called on close with the current (unsent) field text so the caller can
  /// preserve it — closing compose must not silently discard a draft.
  final ValueChanged<String> onClose;

  /// Recently sent lines, oldest first; shown most-recent-first in the recall
  /// menu. Deduplicated by the caller.
  final List<String> history;

  /// Draft text to restore into the field when compose reopens.
  final String initialText;

  /// Voice input; null hides the mic.
  final DictationController? dictation;

  @override
  State<_ComposeInputBar> createState() => _ComposeInputBarState();
}

class _ComposeInputBarState extends State<_ComposeInputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.initialText.isNotEmpty) {
      _controller.value = TextEditingValue(
        text: widget.initialText,
        selection: TextSelection.collapsed(offset: widget.initialText.length),
      );
    }
    _controller.addListener(_notifyChanged);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  void _notifyChanged() {
    widget.onChanged?.call(_controller.text);
  }

  @override
  void dispose() {
    _controller.removeListener(_notifyChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.replaceAll(RegExp(r'[\r\n]'), '');
    _controller.clear();
    if (text.isEmpty) {
      return;
    }
    widget.onSend(text);
    _focusNode.requestFocus();
  }

  void _recall(String line) {
    _controller.value = TextEditingValue(
      text: line,
      selection: TextSelection.collapsed(offset: line.length),
    );
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: widget.palette.panelFor(widget.brightness),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 4, 6),
        child: Row(
          children: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.history_rounded),
              tooltip: 'Recall a sent line',
              color: widget.palette.panelFor(widget.brightness),
              enabled: widget.history.isNotEmpty,
              onSelected: _recall,
              // Opening the menu takes focus off the field (hiding the soft
              // keyboard). _recall restores focus on select; do the same on
              // cancel so the keyboard always returns after the menu closes.
              onCanceled: _focusNode.requestFocus,
              itemBuilder: (context) => [
                for (final line in widget.history.reversed)
                  PopupMenuItem<String>(
                    value: line,
                    child: Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                autocorrect: true,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                inputFormatters: [
                  // Gboard's action key is inconsistent: sometimes 'Send' (fires
                  // onSubmitted), sometimes 'Enter' (inserts a newline into the
                  // field). Catch the newline-insert path here so submitting is
                  // deterministic regardless of which the IME chooses.
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    if (newValue.text.contains('\n') ||
                        newValue.text.contains('\r')) {
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _send(),
                      );
                      final clean = newValue.text.replaceAll(
                        RegExp(r'[\r\n]'),
                        '',
                      );
                      return TextEditingValue(
                        text: clean,
                        selection: TextSelection.collapsed(
                          offset: clean.length,
                        ),
                      );
                    }
                    return newValue;
                  }),
                ],
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Chat: type a line, Enter to send …',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
              ),
            ),
            if (widget.dictation != null)
              DictationButton(
                controller: widget.dictation!,
                textController: _controller,
                focusNode: _focusNode,
                onMessage: (message) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text(message)));
                },
              ),
            if (widget.onExpand != null)
              IconButton(
                icon: const Icon(Icons.open_in_full_rounded),
                tooltip: 'Open chat mode',
                onPressed: widget.onExpand,
              ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Close chat mode',
              onPressed: () => widget.onClose(_controller.text),
            ),
          ],
        ),
      ),
    );
  }
}
