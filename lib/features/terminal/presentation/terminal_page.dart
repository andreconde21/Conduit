import 'dart:async';

import 'package:conduit/core/presentation/conduit_brand.dart';
import 'package:conduit/core/presentation/system_navigation_insets.dart';
import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/core/theme/terminal_appearance.dart';
import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_controller.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_sheet.dart';
import 'package:conduit/features/sftp/domain/sftp_repository.dart';
import 'package:conduit/features/sftp/presentation/file_viewer/discard_changes_dialog.dart';
import 'package:conduit/features/sftp/presentation/file_viewer/sftp_file_viewer.dart';
import 'package:conduit/features/terminal/domain/security_key_interaction.dart';
import 'package:conduit/features/terminal/presentation/security_key_picker_dialog.dart';
import 'package:conduit/features/terminal/presentation/security_key_pin_dialog.dart';
import 'package:conduit/features/terminal/presentation/terminal_file_tabs_controller.dart';
import 'package:conduit/features/terminal/presentation/terminal_keyboard_bar.dart';
import 'package:conduit/features/terminal/presentation/terminal_session_controller.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';
import 'package:conduit/features/terminal/presentation/widgets/empty_terminal_state.dart';
import 'package:conduit/features/terminal/presentation/widgets/prompt_composer_sheet.dart';
import 'package:conduit/features/terminal/presentation/widgets/session_tabs.dart';
import 'package:conduit/features/terminal/presentation/widgets/terminal_header.dart';
import 'package:conduit/features/terminal/presentation/widgets/terminal_surface.dart';
import 'package:conduit_vt/conduit_vt.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class TerminalPage extends StatefulWidget {
  const TerminalPage({
    required this.workspace,
    required this.themeController,
    required this.sftpRepository,
    this.agentAttention,
    super.key,
  });

  final TerminalWorkspaceController workspace;
  final ThemeController themeController;
  final SftpRepository sftpRepository;

  /// Optional Agent Attention monitoring; null hides the dashboard.
  final AgentAttentionController? agentAttention;

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

  @override
  void initState() {
    super.initState();
    _fileTabs = TerminalFileTabsController(widget.sftpRepository);
    unawaited(WakelockPlus.enable());
    SecurityKeyInteraction.instance.registerPinPrompt(_promptSecurityKeyPin);
    SecurityKeyInteraction.instance.registerSelectionPrompt(
      _promptSecurityKeySelection,
    );
    widget.workspace.addListener(_handleWorkspaceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusedSession = widget.workspace.activeSession;
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    unawaited(WakelockPlus.disable());
    _setSystemUiFullscreen(false);
    SecurityKeyInteraction.instance.unregisterPinPrompt(_promptSecurityKeyPin);
    SecurityKeyInteraction.instance.unregisterSelectionPrompt(
      _promptSecurityKeySelection,
    );
    widget.workspace.removeListener(_handleWorkspaceChanged);
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

  void _handleWorkspaceChanged() {
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
    );
    if (!mounted) {
      return;
    }
    // The sheet may have edited or cleared this session's draft; rebuild the
    // inline bar so it shows the latest text.
    setState(() => _composeRevision += 1);
    _focusNode.requestFocus();
  }

  Future<void> _openAgentAttention(AgentAttentionController attention) async {
    await showAgentAttentionSheet(
      context: context,
      controller: attention,
      onOpenAgent: (host, agent) {
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
    );
    if (mounted) {
      _focusNode.requestFocus();
    }
  }

  void _setSystemUiFullscreen(bool fullscreen) {
    SystemChrome.setEnabledSystemUIMode(
      fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
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
                    if (!_fullscreen) ...[
                      if (activeSession != null)
                        ListenableBuilder(
                          listenable: widget.agentAttention ?? _inertListenable,
                          builder: (context, _) {
                            final attention = widget.agentAttention;
                            final showAgents =
                                attention != null &&
                                (attention.monitoredHosts.isNotEmpty ||
                                    activeSession.host.agentAttentionEnabled);
                            return TerminalHeader(
                              session: activeSession,
                              palette: palette,
                              brightness: brightness,
                              onBack: () => Navigator.of(context).pop(),
                              onReconnect: () async {
                                await activeSession.disconnect();
                                await activeSession.connect();
                                _focusNode.requestFocus();
                              },
                              attentionCount: attention?.attentionCount ?? 0,
                              onOpenAgentAttention: showAgents
                                  ? () => _openAgentAttention(attention)
                                  : null,
                            );
                          },
                        ),
                      SessionTabs(
                        workspace: widget.workspace,
                        activeSession: activeSession,
                        palette: palette,
                        brightness: brightness,
                        onChanged: _showTerminal,
                        fileTabs: fileTabs,
                        activeFileTab: activeFileTab,
                        onFileTabSelected: _fileTabs.activate,
                        onFileTabClosed: _closeFileTab,
                      ),
                    ],
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
                                    TerminalSurface(
                                      key: ValueKey(session.host.id),
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
                                      onFontSizeChanged: (fontSize) {
                                        unawaited(
                                          widget.themeController
                                              .setTerminalFontSize(fontSize),
                                        );
                                      },
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
                                        setState(() => _tmuxScrollMode = false);
                                        _focusNode.requestFocus();
                                      },
                                      onPathTap: (path) =>
                                          _handlePathTap(session, path),
                                    ),
                                  for (final tab in fileTabs)
                                    SftpFileViewer(
                                      key: tab.viewerKey,
                                      path: tab.path,
                                      palette: palette,
                                      brightness: brightness,
                                      fontFamily: widget
                                          .themeController
                                          .terminalFont
                                          .fontFamily,
                                      read: (onProgress) =>
                                          _fileTabs.read(tab, onProgress),
                                      write: (bytes) =>
                                          _fileTabs.write(tab, bytes),
                                    ),
                                ],
                              ),
                      ),
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
                        onEnterTmuxScrollMode: () {
                          setState(() => _tmuxScrollMode = true);
                          _focusNode.requestFocus();
                        },
                        onExitTmuxScrollMode: () {
                          setState(() => _tmuxScrollMode = false);
                          _focusNode.requestFocus();
                        },
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
