import 'dart:async';

import 'package:conduit/core/app_failure.dart';
import 'package:conduit/core/platform_features.dart';
import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/chat_view/data/conductore_chat_client.dart';
import 'package:conduit/features/chat_view/domain/chat_items.dart';
import 'package:conduit/features/chat_view/domain/chat_working.dart';
import 'package:conduit/features/chat_view/presentation/chat_view_controller.dart';
import 'package:conduit/features/chat_view/presentation/widgets/chat_composer.dart';
import 'package:conduit/features/chat_view/presentation/widgets/chat_thread_items.dart';
import 'package:conduit/features/chat_view/presentation/widgets/chat_working_indicator.dart';
import 'package:conduit/features/terminal/presentation/widgets/prompt_composer_sheet.dart';
import 'package:conduit/features/voice/data/platform_text_to_speech.dart';
import 'package:conduit/features/voice/domain/text_to_speech.dart';
import 'package:conduit/features/voice/domain/voice_preferences.dart';
import 'package:conduit/features/voice/presentation/dictation_controller.dart';
import 'package:conduit/features/voice/presentation/read_aloud_controller.dart';
import 'package:conduit/features/voice/presentation/voice_settings_scope.dart';
import 'package:flutter/material.dart';

/// A native chat over one live Claude Code session: the transcript as
/// bubbles and tool cards, permission prompts answered in the thread, and a
/// composer that types into the same session the terminal shows.
class ChatViewPage extends StatefulWidget {
  const ChatViewPage({
    required this.controller,
    required this.onOpenTerminal,
    this.hostName,
    this.dictation,
    this.ownsController = true,
    this.onSetUpCompanion,
    this.onEnableMonitoring,
    this.textToSpeech,
    super.key,
  });

  final ChatViewController controller;

  /// Leaves the chat for the full TUI of the same session.
  final VoidCallback onOpenTerminal;
  final String? hostName;
  final DictationController? dictation;

  /// Disposes [controller] with the page.
  final bool ownsController;

  /// Opens the Agent hooks screen from the "not installed / too old"
  /// state; null hides the button.
  final VoidCallback? onSetUpCompanion;

  /// Turns agent monitoring on for this machine (approval notifications,
  /// the Agents panel and live updates need it). Non-null only while it is
  /// off; the banner offering it hides once tapped.
  final Future<void> Function()? onEnableMonitoring;

  /// Speaks replies when "Read replies aloud" is on; defaults to the
  /// on-device engine on Android and to none elsewhere (tests inject one).
  final TextToSpeech? textToSpeech;

  @override
  State<ChatViewPage> createState() => _ChatViewPageState();
}

class _ChatViewPageState extends State<ChatViewPage>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();
  bool _monitoringTurnedOn = false;

  Future<void> _enableMonitoring() async {
    setState(() => _monitoringTurnedOn = true);
    try {
      await widget.onEnableMonitoring?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() => _monitoringTurnedOn = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Could not turn on monitoring: $error')),
      );
    }
  }

  bool _showJump = false;
  Timer? _clock;
  ReadAloudController? _readAloud;

  /// When the working indicator appeared, for turns whose prompt has no
  /// timestamp.
  DateTime? _workingShownAt;

  ChatWorking? get _working => _chat.loading || _chat.unsupported != null
      ? null
      : ChatWorking.of(_chat.agent, _chat.items);

  ChatViewController get _chat => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    _chat.setVisible(true);
    _chat.addListener(_stickToBottom);
    final tts =
        widget.textToSpeech ??
        (PlatformFeatures.textToSpeech ? PlatformTextToSpeech() : null);
    if (tts != null) {
      _readAloud = ReadAloudController(
        tts: tts,
        preferences: () => _settings?.voice ?? VoicePreferences.defaults,
        dictationLanguage: () => _settings?.speechLanguage ?? '',
      );
      unawaited(_readAloud!.checkAvailability());
      _chat.addListener(_feedReadAloud);
      widget.dictation?.addListener(_syncDictation);
    }
    // The elapsed time in the header.
    _clock = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  bool _readAloudPrimed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final readAloud = _readAloud;
    if (readAloud != null && !_readAloudPrimed) {
      _readAloudPrimed = true;
      final voice = _settings?.voice ?? VoicePreferences.defaults;
      readAloud.setEnabled(voice.readAloudFor(_chat.sessionId));
      _feedReadAloud();
    }
  }

  ThemeController? get _settings => VoiceSettingsScope.maybeOf(context);

  /// Hands every new poll to the reader; the first loaded thread only
  /// marks what is already there as read.
  void _feedReadAloud() {
    if (!_chat.loading && _chat.unsupported == null) {
      _readAloud?.observe(_chat.items, _chat.pending);
    }
  }

  void _syncDictation() {
    _readAloud?.suppressed = widget.dictation?.isActive ?? false;
  }

  void _toggleReadAloud() {
    final readAloud = _readAloud;
    if (readAloud == null) return;
    final enabled = !readAloud.enabled;
    readAloud.setEnabled(enabled);
    final settings = _settings;
    if (settings != null) {
      unawaited(
        settings.setVoice(
          settings.voice.withSessionReadAloud(_chat.sessionId, enabled),
        ),
      );
    }
  }

  /// The user is acting (sending, answering): stop talking over them.
  void _quiet() => _readAloud?.stop();

  Future<void> _send(String text, {bool enter = true}) {
    _quiet();
    return _chat.send(text, enter: enter);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final readAloud = _readAloud;
    if (state == AppLifecycleState.resumed ||
        readAloud == null ||
        !readAloud.enabled) {
      _chat.setVisible(state == AppLifecycleState.resumed);
      return;
    }
    // Read-aloud is on. Keep polling and reading while only the screen
    // went off with this chat on top; leaving the chat (another app, the
    // home screen) silences it. No background service keeps it alive.
    if (state == AppLifecycleState.inactive) {
      return;
    }
    final onTop = ModalRoute.of(context)?.isCurrent ?? true;
    unawaited(
      readAloud.screenOn().then((screenOn) {
        if (!mounted) return;
        final keep = onTop && !screenOn;
        _chat.setVisible(keep);
        if (!keep) readAloud.stop();
      }),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chat.removeListener(_feedReadAloud);
    _chat.removeListener(_stickToBottom);
    widget.dictation?.removeListener(_syncDictation);
    _readAloud?.dispose();
    _clock?.cancel();
    _scroll.dispose();
    _chat.setVisible(false);
    if (widget.ownsController) {
      _chat.dispose();
    }
    super.dispose();
  }

  /// Within this distance of the newest message the thread follows new
  /// messages; further up it holds still.
  static const _stickDistance = 48.0;

  /// Set while the user reads further up: the thread shows nothing newer
  /// than [_ThreadFreeze.lastItemId], so arriving messages, approvals and
  /// the working row cannot move what is on screen. They are counted on
  /// the "New messages" pill and appear once the user is back at the
  /// bottom.
  _ThreadFreeze? _freeze;

  /// The last working state shown, kept for a frozen working row.
  ChatWorking? _lastWorking;

  void _onScroll() {
    // The list is reversed: offset 0 is the newest message.
    final offset = _scroll.offset;
    final away = offset > 240;
    if (away != _showJump) {
      setState(() => _showJump = away);
    }
    if (offset > _stickDistance && _freeze == null) {
      setState(() {
        _freeze = _ThreadFreeze(
          lastItemId: _chat.items.lastOrNull?.id,
          approvals: {for (final request in _chat.pending) request.id},
          working: _working != null,
        );
      });
    } else if (offset <= _stickDistance && _freeze != null) {
      setState(() => _freeze = null);
      _stickToBottom();
    }
    final position = _scroll.position;
    if (position.maxScrollExtent - position.pixels < 400) {
      unawaited(_chat.loadOlder());
    }
  }

  /// Follows new messages while at the bottom.
  void _stickToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _freeze != null || !_scroll.hasClients) return;
      if (_scroll.offset > 0 && _scroll.offset <= _stickDistance) {
        _scroll.jumpTo(0);
      }
    });
  }

  void _jumpToLatest() {
    unawaited(
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      ),
    );
  }

  Future<void> _decide(
    PendingPermissionRequest request,
    PermissionVerdict verdict,
  ) async {
    _quiet();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await _chat.decide(request, verdict);
    } catch (error) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            'Could not ${verdict.label.toLowerCase()} ${request.toolName}: '
            '${error is AppFailure ? error.userMessage : error}',
          ),
        ),
      );
    }
  }

  Future<void> _pick(int number) async {
    _quiet();
    try {
      await _chat.answerQuestion(number);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(error is AppFailure ? error.userMessage : '$error'),
        ),
      );
    }
  }

  Future<void> _openComposer(String text, ValueChanged<String> setDraft) {
    var draft = text;
    return showPromptComposerSheet(
      context: context,
      initialText: text,
      onDraftChanged: (value) => draft = value,
      onSend: (value, {required submit}) async {
        await _send(value, enter: submit);
        draft = '';
      },
      submitEnter: true,
      onSubmitEnterChanged: (_) {},
      isConnected: () => _chat.canSend,
      // `send` pastes multiline text as one bracketed paste on the host.
      bracketedPasteSupported: () => true,
      dictation: widget.dictation,
    ).whenComplete(() => setDraft(draft));
  }

  static String _elapsed(DateTime? since) {
    if (since == null) return '';
    final d = DateTime.now().toUtc().difference(since.toUtc());
    if (d.isNegative || d.inMinutes < 1) return '<1m';
    if (d.inHours < 1) return '${d.inMinutes}m';
    if (d.inDays < 1) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inDays}d ${d.inHours % 24}h';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _chat,
      builder: (context, _) {
        final activity = _chat.activity;
        final working = _working;
        if (working == null) {
          _workingShownAt = null;
        } else {
          _workingShownAt ??= DateTime.now();
        }
        final elapsed = _elapsed(_chat.startedAt);
        final subtitle = [
          activity?.label ?? 'Connecting…',
          if (elapsed.isNotEmpty) elapsed,
          ?widget.hostName,
        ].join(' · ');
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_chat.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                PulseWhile(
                  key: const ValueKey('chat-header-pulse'),
                  active: working != null,
                  child: Text(
                    subtitle,
                    key: const ValueKey('chat-header-status'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: switch (activity) {
                        ChatActivity.needsApproval ||
                        ChatActivity.waiting => theme.colorScheme.error,
                        ChatActivity.thinking ||
                        ChatActivity.working => theme.colorScheme.primary,
                        _ => theme.colorScheme.onSurfaceVariant,
                      },
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              if (_readAloud case final readAloud?)
                _ReadAloudToggle(
                  controller: readAloud,
                  onPressed: _toggleReadAloud,
                ),
              TextButton.icon(
                onPressed: widget.onOpenTerminal,
                icon: const Icon(Icons.terminal_rounded),
                label: const Text('Terminal'),
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                if (_chat.error case final error?)
                  MaterialBanner(
                    content: Text(error, maxLines: 3),
                    actions: [
                      TextButton(
                        onPressed: _chat.refresh,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                if (widget.onEnableMonitoring != null && !_monitoringTurnedOn)
                  MaterialBanner(
                    key: const ValueKey('chat-enable-monitoring'),
                    leading: const Icon(Icons.monitor_heart_outlined),
                    content: const Text(
                      'Agent monitoring is off for this machine. Turn it on '
                      'for approval alerts and the Agents panel.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: _enableMonitoring,
                        child: const Text('Turn on'),
                      ),
                    ],
                  ),
                Expanded(child: _buildThread(context)),
                ChatComposer(
                  enabled: _chat.canSend,
                  disabledHint: _chat.unsupported != null
                      ? 'Chat unavailable'
                      : _chat.agent?.state == 'ended'
                      ? 'This session has ended'
                      : 'Answer the approval above first',
                  sending: _chat.sending,
                  showInterrupt:
                      activity == ChatActivity.working ||
                      activity == ChatActivity.thinking,
                  onSend: _send,
                  onInterrupt: _chat.interrupt,
                  onExpand: _openComposer,
                  dictation: widget.dictation,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildThread(BuildContext context) {
    final theme = Theme.of(context);
    if (_chat.unsupported case final reason?) {
      final setUp = widget.onSetUpCompanion;
      return _Centered(
        icon: Icons.extension_off_outlined,
        text: reason,
        action: setUp == null
            ? null
            : FilledButton.icon(
                key: const ValueKey('chat-set-up-companion'),
                onPressed: setUp,
                icon: const Icon(Icons.webhook_rounded),
                label: Text(
                  _chat.unsupportedKind == ChatUnsupportedKind.outdated
                      ? 'Update agent hooks'
                      : 'Install agent hooks',
                ),
              ),
      );
    }
    if (_chat.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final items = _chat.items;
    final allPending = _chat.pending;
    final waiting = _chat.agent?.state == 'waiting_input';
    final working = _working;
    if (working != null) _lastWorking = working;
    // While frozen, show only what was there when the user scrolled up.
    final freeze = _freeze;
    var shownCount = items.length;
    var pending = allPending;
    var held = 0;
    if (freeze != null) {
      final last = freeze.lastItemId == null
          ? -1
          : items.lastIndexWhere((item) => item.id == freeze.lastItemId);
      if (last != -1 || freeze.lastItemId == null) {
        shownCount = last + 1;
      }
      for (var i = shownCount; i < items.length; i++) {
        if (items[i] is! ChatThinking) held += 1;
      }
      pending = [
        for (final request in allPending)
          if (freeze.approvals.contains(request.id)) request,
      ];
      held += allPending.length - pending.length;
    }
    final showWorkingRow = freeze == null
        ? working != null
        : freeze.working && (working ?? _lastWorking) != null;
    final shownWorking = working ?? _lastWorking;
    // Newest first: the list is reversed so it opens at the latest message
    // and stays there as messages arrive.
    final rows = <Widget>[
      if (showWorkingRow && shownWorking != null)
        // Frozen and finished: keep the row's space so nothing moves.
        Visibility(
          key: const ValueKey('chat-working-slot'),
          visible: working != null,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: ChatWorkingIndicator(
            key: const ValueKey('chat-working-indicator'),
            working: shownWorking,
            since: shownWorking.since ?? _workingShownAt ?? DateTime.now(),
          ),
        ),
      for (final request in pending.reversed)
        ChatApprovalCard(
          key: ValueKey('approval-${request.id}'),
          request: request,
          busy: _chat.isDeciding(request.id),
          onDecide: (verdict) => _decide(request, verdict),
        ),
      for (var i = shownCount - 1; i >= 0; i--)
        _row(items[i], isLast: i == items.length - 1, waiting: waiting),
      if (_chat.hasOlder)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Center(
            child: _chat.loadingOlder
                ? const CircularProgressIndicator()
                : TextButton(
                    onPressed: _chat.loadOlder,
                    child: const Text('Load earlier messages'),
                  ),
          ),
        )
      else if (_chat.olderOnlyInTerminal)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Center(
            child: Text(
              'Earlier messages are in the terminal.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        )
      else if (items.isEmpty && pending.isEmpty)
        const _Centered(
          icon: Icons.forum_outlined,
          text: 'No messages yet. Send a prompt to start.',
        ),
    ];
    return Stack(
      children: [
        ListView(
          key: const ValueKey('chat-thread'),
          controller: _scroll,
          reverse: true,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          children: rows,
        ),
        if (held > 0)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: FilledButton.tonalIcon(
                key: const ValueKey('chat-new-messages'),
                onPressed: _jumpToLatest,
                icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                label: Text('New messages ($held)'),
              ),
            ),
          )
        else if (_showJump)
          Positioned(
            right: 12,
            bottom: 12,
            child: FloatingActionButton.small(
              heroTag: null,
              tooltip: 'Latest',
              backgroundColor: theme.colorScheme.secondaryContainer,
              onPressed: _jumpToLatest,
              child: const Icon(Icons.keyboard_double_arrow_down_rounded),
            ),
          ),
      ],
    );
  }

  Widget _row(ChatItem item, {required bool isLast, required bool waiting}) {
    final key = ValueKey(item.id);
    return switch (item) {
      ChatUserMessage() => ChatUserBubble(key: key, item: item),
      ChatAssistantText() => ChatAssistantBubble(key: key, item: item),
      ChatThinking() => ChatThinkingRow(key: key, item: item),
      ChatToolCall() => ChatToolCard(key: key, item: item),
      ChatTodoList() => ChatTodoCard(key: key, item: item),
      ChatPlan() => ChatPlanCard(key: key, item: item),
      ChatQuestion() => ChatQuestionCard(
        key: key,
        item: item,
        onPick: !item.answered && isLast && waiting ? _pick : null,
      ),
      ChatNotice() => ChatNoticeRow(key: key, item: item),
    };
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// The header's speaker: on/off for "Read replies aloud"; tinted while
/// speaking. Turning it off stops speech at once.
class _ReadAloudToggle extends StatelessWidget {
  const _ReadAloudToggle({required this.controller, required this.onPressed});

  final ReadAloudController controller;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.isAvailable) {
          return const SizedBox.shrink();
        }
        final on = controller.enabled;
        return IconButton(
          key: const ValueKey('chat-read-aloud'),
          tooltip: on ? 'Stop reading replies aloud' : 'Read replies aloud',
          isSelected: on,
          onPressed: onPressed,
          icon: const Icon(Icons.volume_off_outlined),
          selectedIcon: Icon(
            controller.speaking
                ? Icons.record_voice_over_rounded
                : Icons.volume_up_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
        );
      },
    );
  }
}

/// What the thread showed when the user scrolled away from the bottom.
class _ThreadFreeze {
  const _ThreadFreeze({
    required this.lastItemId,
    required this.approvals,
    required this.working,
  });

  final String? lastItemId;
  final Set<String> approvals;
  final bool working;
}
