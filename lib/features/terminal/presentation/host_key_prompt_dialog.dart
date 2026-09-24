import 'package:conduit/features/terminal/domain/host_key_prompt.dart';
import 'package:flutter/material.dart';

Future<HostKeyDecision?> showHostKeyPromptDialog({
  required BuildContext context,
  required HostKeyPromptRequest request,
}) {
  final isMismatch = request.kind == HostKeyPromptKind.mismatch;
  return showDialog<HostKeyDecision>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      final colorScheme = Theme.of(context).colorScheme;
      return AlertDialog(
        icon: Icon(
          isMismatch ? Icons.warning_amber_rounded : Icons.shield_outlined,
          color: isMismatch ? colorScheme.error : colorScheme.primary,
        ),
        title: Text(isMismatch ? 'Host key changed' : 'Trust this host?'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isMismatch)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'The server at ${request.host}:${request.port} is presenting '
                    'a different key than the one you previously trusted. This '
                    'can indicate a man-in-the-middle attack, or the server '
                    'may have been legitimately rekeyed.',
                    style: TextStyle(color: colorScheme.error),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Conductore has not connected to ${request.host}:${request.port} '
                    'before. Verify the fingerprint matches the one reported by '
                    'the server (e.g. `ssh-keygen -E md5 -lf <key>`).',
                  ),
                ),
              _PromptField(
                label: 'Host',
                value: '${request.host}:${request.port}',
              ),
              _PromptField(label: 'Algorithm', value: request.type),
              _PromptField(label: 'Fingerprint', value: request.fingerprint),
              if (isMismatch && request.existing != null) ...[
                const Divider(height: 24),
                Text(
                  'Previously trusted:',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                _PromptField(label: 'Algorithm', value: request.existing!.type),
                _PromptField(
                  label: 'Fingerprint',
                  value: request.existing!.fingerprint,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(HostKeyDecision.reject),
            child: const Text('Reject'),
          ),
          FilledButton(
            style: isMismatch
                ? FilledButton.styleFrom(backgroundColor: colorScheme.error)
                : null,
            onPressed: () => Navigator.of(context).pop(HostKeyDecision.trust),
            child: Text(isMismatch ? 'Trust new key' : 'Trust'),
          ),
        ],
      );
    },
  );
}

class _PromptField extends StatelessWidget {
  const _PromptField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurfaceVariant,
              letterSpacing: 0.3,
            ),
          ),
          SelectableText(
            value,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}
