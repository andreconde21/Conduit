import 'dart:async';

import 'package:conduit/core/app_failure.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/chat_view/data/conductore_chat_client.dart';
import 'package:conduit/features/chat_view/domain/chat_items.dart';
import 'package:conduit/features/chat_view/presentation/chat_view_controller.dart';
import 'package:conduit/features/chat_view/presentation/widgets/chat_composer.dart';
import 'package:conduit/features/chat_view/presentation/widgets/chat_thread_items.dart';
import 'package:conduit/features/terminal/presentation/widgets/prompt_composer_sheet.dart';
import 'package:conduit/features/voice/presentation/dictation_controller.dart';
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

  @override
  State<ChatViewPage> createState() => _ChatViewPageState();
}

class _ChatViewPageState extends State<ChatViewPage>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();
  bool _showJump = false;
  Timer? _clock;

  ChatViewController get _chat => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    _chat.setVisible(true);
    // The elapsed time in the header.
    _clock = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _chat.setVisible(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _scroll.dispose();
    _chat.setVisible(false);
    if (widget.ownsController) {
      _chat.dispose();
    }
    super.dispose();
  }

  void _onScroll() {
    // The list is reversed: offset 0 is the newest message.
    final away = _scroll.offset > 240;
    if (away != _showJump) {
      setState(() => _showJump = away);
    }
    final position = _scroll.position;
    if (position.maxScrollExtent - position.pixels < 400) {
      unawaited(_chat.loadOlder());
    }
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
        await _chat.send(value, enter: submit);
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
                Text(
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
              ],
            ),
            actions: [
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
                  onSend: _chat.send,
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
    final pending = _chat.pending;
    final waiting = _chat.agent?.state == 'waiting_input';
    // Newest first: the list is reversed so it opens at the latest message
    // and stays there as messages arrive.
    final rows = <Widget>[
      for (final request in pending.reversed)
        ChatApprovalCard(
          key: ValueKey('approval-${request.id}'),
          request: request,
          busy: _chat.isDeciding(request.id),
          onDecide: (verdict) => _decide(request, verdict),
        ),
      for (var i = items.length - 1; i >= 0; i--)
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
        if (_showJump)
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
