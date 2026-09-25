import 'package:conduit/core/app_failure.dart';
import 'package:conduit/features/voice/presentation/dictation_button.dart';
import 'package:conduit/features/voice/presentation/dictation_controller.dart';
import 'package:flutter/material.dart';

/// The chat view's input row: a field where Enter sends, voice dictation,
/// the full composer for multiline prompts, and Esc to interrupt.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    required this.onSend,
    required this.onInterrupt,
    this.enabled = true,
    this.disabledHint,
    this.sending = false,
    this.showInterrupt = false,
    this.onExpand,
    this.dictation,
    super.key,
  });

  /// Sends one prompt; throws to keep the text in the field.
  final Future<void> Function(String text) onSend;
  final Future<void> Function() onInterrupt;
  final bool enabled;

  /// Shown as the hint while [enabled] is false.
  final String? disabledHint;
  final bool sending;

  /// Emphasizes the Esc button (the agent is working).
  final bool showInterrupt;

  /// Opens the full-screen composer seeded with the field's text; it gets
  /// the current text and a setter for the draft.
  final void Function(String text, ValueChanged<String> setDraft)? onExpand;
  final DictationController? dictation;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled || widget.sending) {
      return;
    }
    _controller.clear();
    try {
      await widget.onSend(text);
    } catch (error) {
      if (!mounted) return;
      // Keep the prompt so nothing typed is lost.
      if (_controller.text.isEmpty) {
        _controller.text = text;
      }
      _showError(error);
    }
  }

  Future<void> _interrupt() async {
    try {
      await widget.onInterrupt();
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(error is AppFailure ? error.userMessage : '$error'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Interrupt (Esc)',
              onPressed: _interrupt,
              icon: Icon(
                Icons.stop_circle_outlined,
                color: widget.showInterrupt ? theme.colorScheme.error : null,
              ),
            ),
            Expanded(
              child: TextField(
                key: const ValueKey('chat-composer-field'),
                controller: _controller,
                focusNode: _focusNode,
                enabled: widget.enabled,
                minLines: 1,
                maxLines: 4,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: widget.enabled
                      ? 'Message Claude…'
                      : widget.disabledHint,
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(20)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            if (widget.dictation != null && widget.enabled)
              DictationButton(
                controller: widget.dictation!,
                textController: _controller,
                focusNode: _focusNode,
                onMessage: (message) => ScaffoldMessenger.maybeOf(context)
                  ?..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(content: Text(message))),
              ),
            if (widget.onExpand != null && widget.enabled)
              IconButton(
                tooltip: 'Open composer',
                icon: const Icon(Icons.open_in_full_rounded),
                onPressed: () => widget.onExpand!(
                  _controller.text,
                  (draft) => _controller.text = draft,
                ),
              ),
            widget.sending
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: 'Send',
                    onPressed: widget.enabled ? _send : null,
                    icon: const Icon(Icons.send_rounded),
                  ),
          ],
        ),
      ),
    );
  }
}
