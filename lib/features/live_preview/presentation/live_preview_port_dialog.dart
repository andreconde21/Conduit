import 'package:conduit/features/live_preview/domain/listening_ports.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Asks which port on the host to preview. Returns null when cancelled.
///
/// [detectPorts] runs while the dialog is open; its results appear as
/// chips the user can tap instead of typing.
Future<int?> showLivePreviewPortDialog(
  BuildContext context, {
  required int initialPort,
  required Future<List<ListeningPort>> Function() detectPorts,
  required String hostName,
}) {
  return showDialog<int>(
    context: context,
    builder: (context) => _LivePreviewPortDialog(
      initialPort: initialPort,
      detectPorts: detectPorts(),
      hostName: hostName,
    ),
  );
}

class _LivePreviewPortDialog extends StatefulWidget {
  const _LivePreviewPortDialog({
    required this.initialPort,
    required this.detectPorts,
    required this.hostName,
  });

  final int initialPort;
  final Future<List<ListeningPort>> detectPorts;
  final String hostName;

  @override
  State<_LivePreviewPortDialog> createState() => _LivePreviewPortDialogState();
}

class _LivePreviewPortDialogState extends State<_LivePreviewPortDialog> {
  late final TextEditingController _port = TextEditingController(
    text: '${widget.initialPort}',
  );

  @override
  void dispose() {
    _port.dispose();
    super.dispose();
  }

  int? get _parsedPort {
    final value = int.tryParse(_port.text.trim());
    if (value == null || value < 1 || value > 65535) {
      return null;
    }
    return value;
  }

  void _submit() {
    final port = _parsedPort;
    if (port != null) {
      Navigator.of(context).pop(port);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Live preview'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Port of the web app running on ${widget.hostName}. It is '
            'reached through the SSH connection, so it only needs to '
            'listen on localhost there.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _port,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textInputAction: TextInputAction.go,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'Remote port',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<ListeningPort>>(
            future: widget.detectPorts,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Looking for listening ports…',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                );
              }
              final ports = snapshot.data ?? const <ListeningPort>[];
              if (ports.isEmpty) {
                return Text(
                  'No listening ports detected.',
                  style: theme.textTheme.bodySmall,
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Listening now', style: theme.textTheme.labelMedium),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final port in ports)
                        ActionChip(
                          label: Text(port.label),
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            setState(() => _port.text = '${port.port}');
                          },
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _parsedPort == null ? null : _submit,
          child: const Text('Open'),
        ),
      ],
    );
  }
}
