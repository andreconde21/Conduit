import 'package:conduit/core/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Renders the Markdown subset agent replies actually use: paragraphs,
/// headings, bullet and numbered lists, block quotes, fenced code blocks,
/// tables (shown monospace, as typed), rules, and inline code, bold,
/// italics and links. Everything else is shown as plain text; no HTML is
/// interpreted. Links open only for http(s) and mailto.
class ChatMarkdown extends StatefulWidget {
  const ChatMarkdown(this.text, {this.style, super.key});

  final String text;
  final TextStyle? style;

  @override
  State<ChatMarkdown> createState() => _ChatMarkdownState();
}

sealed class MarkdownBlock {
  const MarkdownBlock();
}

class MarkdownParagraph extends MarkdownBlock {
  const MarkdownParagraph(this.text);
  final String text;
}

class MarkdownHeading extends MarkdownBlock {
  const MarkdownHeading(this.level, this.text);
  final int level;
  final String text;
}

class MarkdownListItem extends MarkdownBlock {
  const MarkdownListItem(this.marker, this.text, this.indent);

  /// `•` or the number with its dot.
  final String marker;
  final String text;
  final int indent;
}

class MarkdownQuote extends MarkdownBlock {
  const MarkdownQuote(this.text);
  final String text;
}

class MarkdownCode extends MarkdownBlock {
  const MarkdownCode(this.code, {this.language});
  final String code;
  final String? language;
}

class MarkdownRule extends MarkdownBlock {
  const MarkdownRule();
}

/// Splits [text] into blocks. Public for tests.
List<MarkdownBlock> parseMarkdownBlocks(String text) {
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  final blocks = <MarkdownBlock>[];
  final paragraph = <String>[];
  void flush() {
    if (paragraph.isNotEmpty) {
      blocks.add(MarkdownParagraph(paragraph.join('\n')));
      paragraph.clear();
    }
  }

  final fence = RegExp(r'^\s*(```|~~~)\s*([\w+-]*)');
  final heading = RegExp(r'^(#{1,6})\s+(.*)$');
  final bullet = RegExp(r'^(\s*)[-*+]\s+(?:\[( |x|X)\]\s+)?(.*)$');
  final ordered = RegExp(r'^(\s*)(\d+)[.)]\s+(.*)$');
  final rule = RegExp(r'^\s*([-*_])(\s*\1){2,}\s*$');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final fenceMatch = fence.firstMatch(line);
    if (fenceMatch != null) {
      flush();
      final marker = fenceMatch.group(1)!;
      final language = fenceMatch.group(2);
      final code = <String>[];
      i += 1;
      while (i < lines.length && !lines[i].trimLeft().startsWith(marker)) {
        code.add(lines[i]);
        i += 1;
      }
      blocks.add(
        MarkdownCode(
          code.join('\n'),
          language: language == null || language.isEmpty ? null : language,
        ),
      );
      continue;
    }
    if (line.trim().isEmpty) {
      flush();
      continue;
    }
    if (line.trimLeft().startsWith('|')) {
      flush();
      final table = <String>[];
      while (i < lines.length && lines[i].trimLeft().startsWith('|')) {
        table.add(lines[i].trim());
        i += 1;
      }
      i -= 1;
      blocks.add(MarkdownCode(table.join('\n')));
      continue;
    }
    if (rule.hasMatch(line)) {
      flush();
      blocks.add(const MarkdownRule());
      continue;
    }
    if (heading.firstMatch(line) case final match?) {
      flush();
      blocks.add(MarkdownHeading(match.group(1)!.length, match.group(2)!));
      continue;
    }
    if (bullet.firstMatch(line) case final match?) {
      flush();
      final check = match.group(2);
      final marker = check == null
          ? '•'
          : check.trim().isEmpty
          ? '☐'
          : '☑';
      blocks.add(
        MarkdownListItem(marker, match.group(3)!, match.group(1)!.length ~/ 2),
      );
      continue;
    }
    if (ordered.firstMatch(line) case final match?) {
      flush();
      blocks.add(
        MarkdownListItem(
          '${match.group(2)}.',
          match.group(3)!,
          match.group(1)!.length ~/ 2,
        ),
      );
      continue;
    }
    if (line.startsWith('>')) {
      flush();
      final quote = <String>[];
      while (i < lines.length && lines[i].startsWith('>')) {
        quote.add(lines[i].replaceFirst(RegExp(r'^>\s?'), ''));
        i += 1;
      }
      i -= 1;
      blocks.add(MarkdownQuote(quote.join('\n')));
      continue;
    }
    paragraph.add(line);
  }
  flush();
  return blocks;
}

class _ChatMarkdownState extends State<ChatMarkdown> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  static final _inline = RegExp(
    r'`([^`\n]+)`' // 1 inline code
    r'|\*\*([^*\n]+?)\*\*' // 2 bold
    r'|__([^_\n]+?)__' // 3 bold
    r'|(?<![\w*])\*([^*\n]+?)\*(?!\w)' // 4 italic
    r'|(?<!\w)_([^_\n]+?)_(?!\w)' // 5 italic
    r'|\[([^\]\n]+)\]\(([^)\s]+)\)' // 6, 7 link
    r'|(https?://[^\s<>()]+[^\s<>().,;:!?])', // 8 bare URL
  );

  List<InlineSpan> _spans(String text, TextStyle base) {
    final theme = Theme.of(context);
    final spans = <InlineSpan>[];
    var index = 0;
    for (final match in _inline.allMatches(text)) {
      if (match.start > index) {
        spans.add(TextSpan(text: text.substring(index, match.start)));
      }
      index = match.end;
      if (match.group(1) case final code?) {
        spans.add(
          TextSpan(
            text: code,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: (base.fontSize ?? 14) * 0.92,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        );
      } else if (match.group(2) ?? match.group(3) case final bold?) {
        spans.add(
          TextSpan(
            style: const TextStyle(fontWeight: FontWeight.w700),
            children: _spans(bold, base),
          ),
        );
      } else if (match.group(4) ?? match.group(5) case final italic?) {
        spans.add(
          TextSpan(
            text: italic,
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      } else {
        final label = match.group(6) ?? match.group(8)!;
        final url = match.group(7) ?? match.group(8)!;
        spans.add(_link(label, url, theme));
      }
    }
    if (index < text.length) {
      spans.add(TextSpan(text: text.substring(index)));
    }
    return spans;
  }

  InlineSpan _link(String label, String url, ThemeData theme) {
    final uri = Uri.tryParse(url);
    final safe =
        uri != null &&
        (uri.scheme == 'https' ||
            uri.scheme == 'http' ||
            uri.scheme == 'mailto');
    if (!safe) {
      return TextSpan(text: label == url ? url : '$label ($url)');
    }
    final recognizer = TapGestureRecognizer()
      ..onTap = () => launchUrl(uri, mode: LaunchMode.externalApplication);
    _recognizers.add(recognizer);
    return TextSpan(
      text: label,
      recognizer: recognizer,
      style: TextStyle(
        color: theme.colorScheme.primary,
        decoration: TextDecoration.underline,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final theme = Theme.of(context);
    final base = widget.style ?? theme.textTheme.bodyMedium!;
    final blocks = parseMarkdownBlocks(widget.text);
    final children = <Widget>[];
    for (final block in blocks) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 6));
      }
      children.add(switch (block) {
        MarkdownParagraph(:final text) => Text.rich(
          TextSpan(children: _spans(text, base)),
          style: base,
        ),
        MarkdownHeading(:final level, :final text) => Text.rich(
          TextSpan(children: _spans(text, base)),
          style: base.copyWith(
            fontWeight: FontWeight.w800,
            fontSize:
                (base.fontSize ?? 14) *
                (level <= 1
                    ? 1.3
                    : level == 2
                    ? 1.18
                    : 1.06),
          ),
        ),
        MarkdownListItem(:final marker, :final text, :final indent) => Padding(
          padding: EdgeInsets.only(left: 4.0 + indent * 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: marker.length > 2 ? 28 : 18,
                child: Text(marker, style: base),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(children: _spans(text, base)),
                  style: base,
                ),
              ),
            ],
          ),
        ),
        MarkdownQuote(:final text) => Container(
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: theme.colorScheme.outline, width: 3),
            ),
          ),
          child: Text.rich(
            TextSpan(children: _spans(text, base)),
            style: base.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        MarkdownCode(:final code) => Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppTheme.radius),
          ),
          padding: const EdgeInsets.all(10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              code,
              style: base.copyWith(
                fontFamily: 'monospace',
                fontSize: (base.fontSize ?? 14) * 0.88,
              ),
            ),
          ),
        ),
        MarkdownRule() => Divider(color: theme.colorScheme.outlineVariant),
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}
