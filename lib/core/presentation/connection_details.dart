import 'package:flutter/material.dart';

/// A small "Details" link that reveals the technical reason behind a
/// connection problem, so the headline stays plain.
class ConnectionDetails extends StatefulWidget {
  const ConnectionDetails({
    required this.detail,
    this.textAlign = TextAlign.start,
    super.key,
  });

  final String detail;
  final TextAlign textAlign;

  @override
  State<ConnectionDetails> createState() => _ConnectionDetailsState();
}

class _ConnectionDetailsState extends State<ConnectionDetails> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final center = widget.textAlign == TextAlign.center;
    return Column(
      crossAxisAlignment: center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          key: const ValueKey('connection-details-toggle'),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: const Size(0, 32),
            textStyle: theme.textTheme.labelMedium,
          ),
          onPressed: () => setState(() => _open = !_open),
          child: Text(_open ? 'Hide details' : 'Details'),
        ),
        if (_open)
          SelectableText(
            widget.detail,
            key: const ValueKey('connection-details-text'),
            textAlign: widget.textAlign,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          ),
      ],
    );
  }
}
