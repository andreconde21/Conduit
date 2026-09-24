import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_controller.dart';
import 'package:conduit/features/sessions/presentation/session_grid_page.dart';
import 'package:conduit/features/terminal/presentation/terminal_session_controller.dart';
import 'package:flutter/material.dart';

/// Horizontal strip of live preview tiles for the app's open sessions on
/// the selected machine.
class HostSessionsStrip extends StatelessWidget {
  const HostSessionsStrip({
    required this.sessions,
    required this.activeSession,
    required this.palette,
    required this.brightness,
    required this.onOpen,
    required this.onActions,
    required this.onNewSession,
    this.agentAttention,
    super.key,
  });

  final List<TerminalSessionController> sessions;
  final TerminalSessionController? activeSession;
  final AppPalette palette;
  final Brightness brightness;
  final AgentAttentionController? agentAttention;
  final ValueChanged<TerminalSessionController> onOpen;
  final ValueChanged<TerminalSessionController> onActions;
  final VoidCallback onNewSession;

  static const tileWidth = 164.0;
  static const tileHeight = 188.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 8, 6),
            child: Row(
              children: [
                Text(
                  'SESSIONS',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  sessions.isEmpty ? 'none open' : '${sessions.length} open',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onNewSession,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New'),
                ),
              ],
            ),
          ),
          if (sessions.isNotEmpty)
            SizedBox(
              height: tileHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                itemCount: sessions.length,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final session = sessions[index];
                  return SizedBox(
                    width: tileWidth,
                    child: SessionTile(
                      key: ValueKey('home-session-${session.host.id}'),
                      session: session,
                      palette: palette,
                      brightness: brightness,
                      selected: session == activeSession,
                      agentStatus: agentAttention?.statusFor(session.host.id),
                      onTap: () => onOpen(session),
                      onLongPress: () => onActions(session),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
