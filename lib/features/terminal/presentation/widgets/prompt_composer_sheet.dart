import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Upper bound on a single composed prompt, in characters. Large pastes are
/// fine over SSH, but remote line editors and TUIs degrade badly past this
/// point; oversized prompts are kept as drafts instead of silently truncated.
const promptComposerMaxChars = 100000;

/// Sends a composed prompt into the terminal. Implementations deliver the
/// text atomically (bracketed paste when the remote app supports it) and,
/// when [submit] is set, follow up with an isolated Enter keypress.
typedef PromptComposerSend =
    Future<void> Function(String text, {required bool submit});

/// Shows the full-screen prompt composer for the active terminal session.
///
/// The composer edits a per-session draft: [onDraftChanged] fires on every
/// edit so the caller always holds the latest text, no matter how the sheet
/// closes. Sending clears the draft; Cancel and dismissal keep it.
///
/// [bracketedPasteSupported] is polled at build time so the sheet can warn
/// when a multiline prompt would be delivered line by line (each newline
/// acting as Enter) because the remote application has not switched
/// bracketed paste on.
Future<void> showPromptComposerSheet({
  required BuildContext context,
  required String initialText,
  required ValueChanged<String> onDraftChanged,
  required PromptComposerSend onSend,
  required bool submitEnter,
  required ValueChanged<bool> onSubmitEnterChanged,
  required bool Function() isConnected,
  bool Function()? bracketedPasteSupported,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => PromptComposerSheet(
      initialText: initialText,
      onDraftChanged: onDraftChanged,
      onSend: onSend,
      submitEnter: submitEnter,
      onSubmitEnterChanged: onSubmitEnterChanged,
      isConnected: isConnected,
      bracketedPasteSupported: bracketedPasteSupported,
    ),
  );
}

class PromptComposerSheet extends StatefulWidget {
  const PromptComposerSheet({
    required this.initialText,
    required this.onDraftChanged,
    required this.onSend,
    required this.submitEnter,
    required this.onSubmitEnterChanged,
    required this.isConnected,
    this.bracketedPasteSupported,
    super.key,
  });

  final String initialText;
  final ValueChanged<String> onDraftChanged;
  final PromptComposerSend onSend;
  final bool submitEnter;
  final ValueChanged<bool> onSubmitEnterChanged;
  final bool Function() isConnected;
  final bool Function()? bracketedPasteSupported;

  @override
  State<PromptComposerSheet> createState() => _PromptComposerSheetState();
}

class _PromptComposerSheetState extends State<PromptComposerSheet> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();
  late bool _submitEnter;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _controller.addListener(_handleTextChanged);
    _submitEnter = widget.submitEnter;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    widget.onDraftChanged(_controller.text);
    // Rebuild for the character count, the oversize/empty send guard, and to
    // clear a stale send error once the user edits again.
    setState(() => _error = null);
  }

  bool get _oversized => _controller.text.length > promptComposerMaxChars;

  bool get _multiline => _controller.text.contains('\n');

  Future<void> _send() async {
    final text = _controller.text;
    if (_sending || text.isEmpty || _oversized) {
      return;
    }
    if (!widget.isConnected()) {
      _showError('Not connected. The prompt was kept as a draft.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.onSend(text, submit: _submitEnter);
    } catch (error) {
      if (mounted) {
        setState(() => _sending = false);
        _showError('Sending failed. The prompt was kept as a draft.');
      }
      return;
    }
    widget.onDraftChanged('');
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  // Errors are shown inside the sheet: a SnackBar would be drawn on the
  // Scaffold underneath and hidden behind the modal.
  void _showError(String message) {
    setState(() => _error = message);
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) {
      return;
    }
    final text = data?.text;
    if (text == null || text.isEmpty) {
      return;
    }
    final value = _controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final updated = value.text.replaceRange(start, end, text);
    _controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    _focusNode.requestFocus();
  }

  void _selectAll() {
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    _focusNode.requestFocus();
  }

  void _clear() {
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final length = _controller.text.length;
    final canSend = !_sending && length > 0 && !_oversized;
    final bracketedPaste = widget.bracketedPasteSupported?.call() ?? true;
    final String? notice;
    if (_oversized) {
      notice =
          'Too large to send safely. Trim or split the prompt; '
          'it stays saved as a draft.';
    } else if (_error != null) {
      notice = _error;
    } else if (_multiline && !bracketedPaste) {
      notice =
          'The remote app has not enabled bracketed paste, so each line '
          'will be sent as if you pressed Enter after it.';
    } else {
      notice = null;
    }
    final noticeColor = _oversized || _error != null
        ? colorScheme.error
        : colorScheme.onSurfaceVariant;
    // The keyboard inset comes first so the sheet rises above the IME; the
    // SafeArea then keeps the button row clear of the Android navigation bar
    // whenever the keyboard is hidden (MediaQuery.padding is already zero
    // while the keyboard covers the bar). The column scrolls so a short
    // landscape viewport cannot overflow.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('Compose prompt', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Paste clipboard',
                    icon: const Icon(Icons.content_paste_rounded),
                    onPressed: _sending ? null : _pasteFromClipboard,
                  ),
                  IconButton(
                    tooltip: 'Select all',
                    icon: const Icon(Icons.select_all_rounded),
                    onPressed: _sending || length == 0 ? null : _selectAll,
                  ),
                  IconButton(
                    tooltip: 'Clear draft',
                    icon: const Icon(Icons.backspace_outlined),
                    onPressed: _sending || length == 0 ? null : _clear,
                  ),
                ],
              ),
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                // readOnly (not enabled: false) keeps focus and the keyboard
                // through a send, so a failed send leaves the user editing.
                readOnly: _sending,
                minLines: 4,
                maxLines: 8,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: 'Type, dictate, or paste a prompt…',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (notice != null)
                    Expanded(
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          notice,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: noticeColor,
                          ),
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  const SizedBox(width: 8),
                  Text(
                    '$length / $promptComposerMaxChars',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Press Enter after inserting'),
                subtitle: Text(
                  _submitEnter
                      ? 'The prompt is submitted immediately.'
                      : 'The prompt is left in the terminal for review.',
                  style: theme.textTheme.bodySmall,
                ),
                value: _submitEnter,
                onChanged: _sending
                    ? null
                    : (value) {
                        setState(() => _submitEnter = value);
                        widget.onSubmitEnterChanged(value);
                      },
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: _sending
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: canSend ? _send : null,
                    icon: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _submitEnter
                                ? Icons.send_rounded
                                : Icons.keyboard_return_rounded,
                          ),
                    label: Text(_submitEnter ? 'Insert & Send' : 'Insert'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
