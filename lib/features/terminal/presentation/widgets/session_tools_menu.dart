import 'package:flutter/material.dart';

enum SessionTool { gitDiff, livePreview }

/// Overflow menu in the terminal header for per-session tools that open as
/// tabs beside the session: the git diff of the working directory and a
/// live preview of a web app on the host.
class SessionToolsMenu extends StatelessWidget {
  const SessionToolsMenu({
    required this.color,
    required this.onSelected,
    super.key,
  });

  final Color color;
  final ValueChanged<SessionTool> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<SessionTool>(
      tooltip: 'Session tools',
      icon: Icon(Icons.more_vert_rounded, color: color),
      onSelected: onSelected,
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: SessionTool.gitDiff,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.difference_outlined),
            title: Text('Git diff'),
          ),
        ),
        PopupMenuItem(
          value: SessionTool.livePreview,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.public_rounded),
            title: Text('Live preview'),
          ),
        ),
      ],
    );
  }
}
