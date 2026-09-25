import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/features/terminal/presentation/gestures/terminal_gesture_layer.dart';
import 'package:conduit/features/terminal/presentation/terminal_file_tabs_controller.dart';
import 'package:conduit/features/terminal/presentation/terminal_session_controller.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';
import 'package:conduit/features/terminal/presentation/widgets/session_tabs.dart';
import 'package:flutter/material.dart';

/// Per-session tools that open as tabs beside the session: the git diff of
/// the working directory and a live preview of a web app on the host.
enum SessionTool { gitDiff, livePreview }

/// Actions in the terminal row's overflow menu.
enum TerminalHeaderAction {
  chatView,
  gitDiff,
  livePreview,
  reconnect,
  fullscreen,
  newSession,
  closeSession,
}

/// The terminal's single chrome row (~40 dp): back, the scrollable session
/// and file tabs, then the session grid, the agents badge and ONE overflow
/// menu: chat view and the session tools (git diff, live preview), then
/// reconnect, fullscreen and new session, then close session.
///
/// A downward swipe on the row opens the session grid, like the swipe from
/// the terminal's top strip.
class TerminalHeader extends StatelessWidget {
  const TerminalHeader({
    required this.workspace,
    required this.activeSession,
    required this.palette,
    required this.brightness,
    required this.onBack,
    required this.onTabsChanged,
    required this.fileTabs,
    required this.activeFileTab,
    required this.onFileTabSelected,
    required this.onFileTabClosed,
    this.onReconnect,
    this.onToggleFullscreen,
    this.onNewSession,
    this.onOpenChatView,
    this.attentionCount = 0,
    this.onOpenAgentAttention,
    this.onOpenSessionTool,
    this.onOpenSessionGrid,
    this.swipeDownOpensSessionGrid = true,
    super.key,
  });

  static const height = 40.0;

  final TerminalWorkspaceController workspace;
  final TerminalSessionController? activeSession;
  final AppPalette palette;
  final Brightness brightness;
  final VoidCallback onBack;

  /// Called after a tab switch or close so the page can refocus.
  final VoidCallback onTabsChanged;
  final List<TerminalFileTab> fileTabs;
  final TerminalFileTab? activeFileTab;
  final ValueChanged<TerminalFileTab> onFileTabSelected;
  final ValueChanged<TerminalFileTab> onFileTabClosed;

  /// Reconnects the active session; null hides the menu entry.
  final VoidCallback? onReconnect;

  /// Enters fullscreen (which hides this row); null hides the entry.
  final VoidCallback? onToggleFullscreen;

  /// Opens a new session through the connect flow; null hides the entry.
  final VoidCallback? onNewSession;

  /// Opens the chat view of the active session's Claude agent; null hides
  /// the entry.
  final VoidCallback? onOpenChatView;

  /// Number of monitored agents currently needing attention (badge).
  final int attentionCount;

  /// Opens the Agent Attention dashboard; null hides the button.
  final VoidCallback? onOpenAgentAttention;

  /// Opens a session tool (git diff, live preview) for the active session;
  /// null hides those entries.
  final ValueChanged<SessionTool>? onOpenSessionTool;

  /// Opens the session home grid; null hides the button.
  final VoidCallback? onOpenSessionGrid;

  /// Whether a downward swipe on the row opens the session grid.
  final bool swipeDownOpensSessionGrid;

  @override
  Widget build(BuildContext context) {
    final foreground = palette.foregroundFor(brightness);
    final session = activeSession;
    return TerminalHeaderSwipeArea(
      enabled: swipeDownOpensSessionGrid,
      onSwipeDown: onOpenSessionGrid,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: palette.canvasFor(brightness),
          border: Border(
            bottom: BorderSide(color: palette.hairlineFor(brightness)),
          ),
        ),
        child: Row(
          children: [
            _RowButton(
              tooltip: 'Machines',
              color: foreground,
              icon: const Icon(Icons.chevron_left_rounded, size: 26),
              onPressed: onBack,
            ),
            Expanded(
              child: SessionTabs(
                workspace: workspace,
                activeSession: session,
                palette: palette,
                brightness: brightness,
                onChanged: onTabsChanged,
                fileTabs: fileTabs,
                activeFileTab: activeFileTab,
                onFileTabSelected: onFileTabSelected,
                onFileTabClosed: onFileTabClosed,
              ),
            ),
            if (onOpenSessionGrid != null)
              _RowButton(
                tooltip: 'Sessions',
                color: foreground,
                icon: const Icon(Icons.grid_view_rounded, size: 19),
                onPressed: onOpenSessionGrid!,
              ),
            if (onOpenAgentAttention != null)
              _RowButton(
                tooltip: 'Agents',
                color: foreground,
                icon: Badge.count(
                  count: attentionCount,
                  isLabelVisible: attentionCount > 0,
                  child: const Icon(Icons.monitor_heart_outlined, size: 20),
                ),
                onPressed: onOpenAgentAttention!,
              ),
            _OverflowMenu(
              session: session,
              color: foreground,
              onReconnect: onReconnect,
              onToggleFullscreen: onToggleFullscreen,
              onNewSession: onNewSession,
              onOpenChatView: onOpenChatView,
              onOpenSessionTool: onOpenSessionTool,
              onClose: session == null
                  ? null
                  : () async {
                      await workspace.close(session);
                      onTabsChanged();
                      if (!context.mounted) return;
                      if (!workspace.hasSessions && fileTabs.isEmpty) {
                        Navigator.of(context).pop();
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }
}

class _RowButton extends StatelessWidget {
  const _RowButton({
    required this.tooltip,
    required this.color,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final Color color;
  final Widget icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      color: color,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 38, height: 40),
      icon: icon,
      onPressed: onPressed,
    );
  }
}

class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({
    required this.session,
    required this.color,
    required this.onReconnect,
    required this.onToggleFullscreen,
    required this.onNewSession,
    required this.onClose,
    this.onOpenChatView,
    this.onOpenSessionTool,
  });

  final TerminalSessionController? session;
  final Color color;
  final VoidCallback? onReconnect;
  final VoidCallback? onToggleFullscreen;
  final VoidCallback? onNewSession;
  final VoidCallback? onClose;
  final VoidCallback? onOpenChatView;
  final ValueChanged<SessionTool>? onOpenSessionTool;

  @override
  Widget build(BuildContext context) {
    final session = this.session;
    final tools = onOpenSessionTool;
    return PopupMenuButton<TerminalHeaderAction>(
      tooltip: 'More',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 200),
      iconColor: color,
      icon: const Icon(Icons.more_vert_rounded, size: 20),
      style: IconButton.styleFrom(
        minimumSize: const Size(34, 40),
        maximumSize: const Size(34, 40),
        padding: EdgeInsets.zero,
      ),
      onSelected: (action) => switch (action) {
        TerminalHeaderAction.chatView => onOpenChatView?.call(),
        TerminalHeaderAction.gitDiff => tools?.call(SessionTool.gitDiff),
        TerminalHeaderAction.livePreview => tools?.call(
          SessionTool.livePreview,
        ),
        TerminalHeaderAction.reconnect => onReconnect?.call(),
        TerminalHeaderAction.fullscreen => onToggleFullscreen?.call(),
        TerminalHeaderAction.newSession => onNewSession?.call(),
        TerminalHeaderAction.closeSession => onClose?.call(),
      },
      itemBuilder: (context) {
        final theme = Theme.of(context);
        // Grouped: agent and session tools, session control, close.
        final groups = [
          <PopupMenuEntry<TerminalHeaderAction>>[
            if (onOpenChatView != null)
              const PopupMenuItem(
                value: TerminalHeaderAction.chatView,
                child: _MenuRow(Icons.forum_outlined, 'Open chat view'),
              ),
            if (tools != null) ...const [
              PopupMenuItem(
                value: TerminalHeaderAction.gitDiff,
                child: _MenuRow(Icons.difference_outlined, 'Git diff'),
              ),
              PopupMenuItem(
                value: TerminalHeaderAction.livePreview,
                child: _MenuRow(Icons.public_rounded, 'Live preview'),
              ),
            ],
          ],
          <PopupMenuEntry<TerminalHeaderAction>>[
            if (onReconnect != null)
              const PopupMenuItem(
                value: TerminalHeaderAction.reconnect,
                child: _MenuRow(Icons.refresh_rounded, 'Reconnect'),
              ),
            if (onToggleFullscreen != null)
              const PopupMenuItem(
                value: TerminalHeaderAction.fullscreen,
                child: _MenuRow(Icons.fullscreen_rounded, 'Fullscreen'),
              ),
            if (onNewSession != null)
              const PopupMenuItem(
                value: TerminalHeaderAction.newSession,
                child: _MenuRow(Icons.add_rounded, 'New session'),
              ),
          ],
          <PopupMenuEntry<TerminalHeaderAction>>[
            if (onClose != null)
              const PopupMenuItem(
                value: TerminalHeaderAction.closeSession,
                child: _MenuRow(Icons.close_rounded, 'Close session'),
              ),
          ],
        ].where((group) => group.isNotEmpty).toList();
        return [
          if (session != null)
            PopupMenuItem<TerminalHeaderAction>(
              enabled: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    session.host.endpoint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          for (final (index, group) in groups.indexed) ...[
            if (index > 0 || session != null) const PopupMenuDivider(),
            ...group,
          ],
        ];
      },
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [Icon(icon, size: 18), const SizedBox(width: 10), Text(label)],
    );
  }
}
