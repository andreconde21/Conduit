import 'package:conduit/core/presentation/adaptive_modal.dart';
import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/features/snippets/domain/terminal_snippet.dart';
import 'package:flutter/material.dart';

/// Built-in quick prompts for driving Claude Code from the toolbar palette.
enum ToolbarQuickPrompt {
  clear('/clear', 'Start a fresh conversation', text: '/clear'),
  compact('/compact', 'Summarize the context', text: '/compact'),
  help('/help', 'Show Claude Code help', text: '/help'),
  continuePrompt('continue', 'Tell the agent to keep going', text: 'continue'),
  yes('yes', 'Confirm the current question', text: 'yes'),
  escapeTwice('Esc Esc', 'Rewind or clear the input'),
  interrupt('Ctrl+C', 'Interrupt the running command');

  const ToolbarQuickPrompt(this.label, this.description, {this.text});

  final String label;
  final String description;

  /// The line to type and submit with Enter; null for key sequences.
  final String? text;
}

/// Opens the swipe-up palette: quick prompts first, then the host's and the
/// global saved snippets (the same lists the Snip key-row menu shows).
///
/// Selecting an entry pops the sheet and reports it through the callbacks.
Future<void> showToolbarSnippetPalette({
  required BuildContext context,
  required AppPalette palette,
  required Brightness brightness,
  required List<TerminalSnippet> hostSnippets,
  required List<TerminalSnippet> globalSnippets,
  required ValueChanged<ToolbarQuickPrompt> onQuickPrompt,
  required ValueChanged<TerminalSnippet> onSnippet,
  String hostPassword = '',
  ValueChanged<String>? onPassword,
}) {
  return showAdaptiveModal<void>(
    kind: AdaptiveModalKind.palette,
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: palette.panelFor(brightness),
    builder: (context) => ToolbarSnippetPalette(
      palette: palette,
      brightness: brightness,
      hostSnippets: hostSnippets,
      globalSnippets: globalSnippets,
      hostPassword: hostPassword,
      onQuickPrompt: (prompt) {
        Navigator.of(context).pop();
        onQuickPrompt(prompt);
      },
      onSnippet: (snippet) {
        Navigator.of(context).pop();
        onSnippet(snippet);
      },
      onPassword: onPassword == null
          ? null
          : (password) {
              Navigator.of(context).pop();
              onPassword(password);
            },
    ),
  );
}

class ToolbarSnippetPalette extends StatelessWidget {
  const ToolbarSnippetPalette({
    required this.palette,
    required this.brightness,
    required this.hostSnippets,
    required this.globalSnippets,
    required this.onQuickPrompt,
    required this.onSnippet,
    this.hostPassword = '',
    this.onPassword,
    super.key,
  });

  final AppPalette palette;
  final Brightness brightness;
  final List<TerminalSnippet> hostSnippets;
  final List<TerminalSnippet> globalSnippets;
  final ValueChanged<ToolbarQuickPrompt> onQuickPrompt;
  final ValueChanged<TerminalSnippet> onSnippet;
  final String hostPassword;
  final ValueChanged<String>? onPassword;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = palette.foregroundFor(brightness);
    final muted = palette.mutedForegroundFor(brightness);
    final host = hostSnippets.where((snippet) => snippet.isValid).toList();
    final global = globalSnippets.where((snippet) => snippet.isValid).toList();
    final hasPassword = hostPassword.isNotEmpty && onPassword != null;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        children: [
          Text(
            'Quick prompts',
            style: theme.textTheme.titleSmall?.copyWith(color: foreground),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final prompt in ToolbarQuickPrompt.values)
                Tooltip(
                  message: prompt.description,
                  child: ActionChip(
                    label: Text(prompt.label),
                    labelStyle: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                    backgroundColor: palette.panelElevatedFor(brightness),
                    side: BorderSide(color: palette.hairlineFor(brightness)),
                    onPressed: () => onQuickPrompt(prompt),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Snippets',
            style: theme.textTheme.titleSmall?.copyWith(color: foreground),
          ),
          const SizedBox(height: 4),
          if (host.isEmpty && global.isEmpty && !hasPassword)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No snippets saved. Add global snippets in Settings › Terminal, or '
                'per-machine snippets when editing a machine.',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
          if (host.isNotEmpty) ...[
            _SectionLabel('Host', color: muted),
            for (final snippet in host)
              _SnippetTile(
                snippet: snippet,
                foreground: foreground,
                muted: muted,
                onTap: () => onSnippet(snippet),
              ),
          ],
          if (global.isNotEmpty) ...[
            _SectionLabel('Global', color: muted),
            for (final snippet in global)
              _SnippetTile(
                snippet: snippet,
                foreground: foreground,
                muted: muted,
                onTap: () => onSnippet(snippet),
              ),
          ],
          if (hasPassword)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.visibility_off_rounded, color: muted),
              title: Text('Password', style: TextStyle(color: foreground)),
              subtitle: Text(
                'Types the saved host password',
                style: TextStyle(color: muted),
              ),
              onTap: () => onPassword!(hostPassword),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: color, letterSpacing: 0.6),
      ),
    );
  }
}

class _SnippetTile extends StatelessWidget {
  const _SnippetTile({
    required this.snippet,
    required this.foreground,
    required this.muted,
    required this.onTap,
  });

  final TerminalSnippet snippet;
  final Color foreground;
  final Color muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = snippet.hidden || snippet.text.isEmpty
        ? null
        : snippet.submit
        ? '${snippet.text} + Enter'
        : snippet.text;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        snippet.hidden ? Icons.visibility_off_rounded : Icons.code_rounded,
        color: muted,
      ),
      title: Text(
        snippet.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: foreground),
      ),
      subtitle: preview == null
          ? null
          : Text(
              preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: muted),
            ),
      onTap: onTap,
    );
  }
}
