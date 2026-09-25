import 'package:flutter/material.dart';

enum TerminalLinkAction { openInBrowser, openInPreview, copyLink, copyText }

/// The long-press menu for a link in terminal output. Resolves to the
/// chosen action, or null when dismissed.
///
/// [previewPort] is the remote port when the link points at the host
/// itself (localhost and friends); only then is the in-app preview offered.
Future<TerminalLinkAction?> showTerminalLinkSheet(
  BuildContext context, {
  required String url,
  int? previewPort,
}) {
  return showModalBottomSheet<TerminalLinkAction>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                url,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.open_in_browser_rounded),
              title: const Text('Open in browser'),
              onTap: () =>
                  Navigator.of(context).pop(TerminalLinkAction.openInBrowser),
            ),
            if (previewPort != null)
              ListTile(
                leading: const Icon(Icons.preview_rounded),
                title: const Text('Open in in-app preview'),
                subtitle: Text('Forward port $previewPort from the host'),
                onTap: () =>
                    Navigator.of(context).pop(TerminalLinkAction.openInPreview),
              ),
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('Copy link'),
              onTap: () =>
                  Navigator.of(context).pop(TerminalLinkAction.copyLink),
            ),
            ListTile(
              leading: const Icon(Icons.content_copy_rounded),
              title: const Text('Copy text'),
              subtitle: const Text('The whole line the link is on'),
              onTap: () =>
                  Navigator.of(context).pop(TerminalLinkAction.copyText),
            ),
          ],
        ),
      );
    },
  );
}
