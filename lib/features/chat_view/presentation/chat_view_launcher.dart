import 'package:conduit/features/agent_attention/data/conductore_host_attention_provider.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_controller.dart';
import 'package:conduit/features/chat_view/data/conductore_chat_client.dart';
import 'package:conduit/features/chat_view/presentation/chat_view_controller.dart';
import 'package:conduit/features/chat_view/presentation/chat_view_page.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/voice/presentation/dictation_controller.dart';
import 'package:flutter/material.dart';

/// Whether [host]'s agents come from the Conductore companion, which the
/// chat view needs (Herdr alone has no transcript or prompt relay here).
bool chatViewAvailable(AgentAttentionController attention, SavedHost host) =>
    attention.isMonitoring(host.id) &&
    attention.providerFor(host.id).id ==
        const ConductoreHostAttentionProvider().id;

/// Opens the chat view for [agent] on [host] as a full-screen route.
/// [onOpenTerminal] runs after the route is popped by its Terminal button
/// (the caller shows that session's TUI).
Future<void> openChatView({
  required BuildContext context,
  required AgentAttentionController attention,
  required SavedHost host,
  required AgentInfo agent,
  required VoidCallback onOpenTerminal,
  DictationController? dictation,
}) async {
  final (runner, :owned) = attention.runnerFor(host);
  final changes = _AgentChangeSignal(attention, host.id, agent.id);
  Future<void> decide(
    PendingPermissionRequest request,
    PermissionVerdict verdict,
  ) async {
    if (attention.isMonitoring(host.id)) {
      return attention.decide(host.id, request, verdict);
    }
    final command = const ConductoreHostAttentionProvider().decideCommand(
      request,
      verdict,
    );
    final result = await runner.run(
      command!,
      timeout: const Duration(seconds: 15),
    );
    if (result.exitCode != null && result.exitCode != 0) {
      throw ConductoreHostAttentionProvider.failureFrom(
        result.stdout,
        result.stderr,
      );
    }
  }

  final controller = ChatViewController(
    runner: runner,
    ownsRunner: owned,
    sessionId: agent.id,
    fallbackName: agent.name,
    decide: decide,
    agentChanges: changes,
  );
  var toTerminal = false;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (routeContext) => ChatViewPage(
        controller: controller,
        hostName: host.name,
        dictation: dictation,
        onOpenTerminal: () {
          toTerminal = true;
          Navigator.of(routeContext).pop();
        },
      ),
    ),
  );
  changes.dispose();
  if (toTerminal) {
    onOpenTerminal();
  }
}

/// Explains why the chat view cannot open for [host] and how to fix it.
Future<void> showChatViewUnavailable(
  BuildContext context, {
  required AgentAttentionController? attention,
  required SavedHost host,
}) {
  final monitored = attention?.isMonitoring(host.id) ?? false;
  final message = !host.agentAttentionEnabled || !monitored
      ? 'Chat view reads the session through the Conductore companion. '
            'Turn on agent monitoring for ${host.name} (machine settings, '
            'Agent monitor: Companion or Automatic) and connect to it.\n\n'
            '${ConductoreChatClient.installHint}'
      : '${host.name} reports its agents through '
            '${attention!.providerFor(host.id).label}, not the Conductore '
            'companion. ${ConductoreChatClient.installHint} Then refresh '
            'the Agents panel.';
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Chat view needs the companion'),
      content: SelectableText(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Picks which Claude session on [host] to open: the only live one, or
/// the user's choice. Null when there is none (after telling the user) or
/// the picker was dismissed.
Future<AgentInfo?> pickChatAgent(
  BuildContext context, {
  required AgentAttentionController attention,
  required SavedHost host,
}) async {
  final agents = [
    for (final agent
        in attention.statusFor(host.id)?.agents ?? const <AgentInfo>[])
      if (agent.state != AgentAttentionState.finished) agent,
  ];
  if (agents.isEmpty) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          'No Claude session is running on ${host.name}. Start claude in '
          'tmux or Herdr there, then try again.',
        ),
      ),
    );
    return null;
  }
  if (agents.length == 1) {
    return agents.single;
  }
  return showModalBottomSheet<AgentInfo>(
    context: context,
    useSafeArea: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('Open chat for…')),
          for (final agent in agents)
            ListTile(
              leading: const Icon(Icons.forum_outlined),
              title: Text(agent.name),
              subtitle: Text(
                [agent.state.label, ?agent.workspace].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.of(context).pop(agent),
            ),
        ],
      ),
    ),
  );
}

/// Fires when the attention controller's record of one session changes
/// (state, pending requests, message), so the chat polls at once instead of
/// waiting for its next tick.
class _AgentChangeSignal extends ChangeNotifier {
  _AgentChangeSignal(this._attention, this._hostId, this._agentId) {
    _last = _current();
    _attention.addListener(_check);
  }

  final AgentAttentionController _attention;
  final String _hostId;
  final String _agentId;
  AgentInfo? _last;

  AgentInfo? _current() {
    for (final agent
        in _attention.statusFor(_hostId)?.agents ?? const <AgentInfo>[]) {
      if (agent.id == _agentId) {
        return agent;
      }
    }
    return null;
  }

  void _check() {
    final now = _current();
    if (now != _last) {
      _last = now;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _attention.removeListener(_check);
    super.dispose();
  }
}

/// The terminal overflow's "Open chat view": explains the missing
/// companion, else picks the session on [host] and opens its chat.
/// [onOpenTerminal] gets the agent whose TUI to show afterwards.
Future<void> openChatViewForHost({
  required BuildContext context,
  required AgentAttentionController? attention,
  required SavedHost host,
  required ValueChanged<AgentInfo> onOpenTerminal,
  DictationController? dictation,
}) async {
  if (attention == null || !chatViewAvailable(attention, host)) {
    await showChatViewUnavailable(context, attention: attention, host: host);
    return;
  }
  final agent = await pickChatAgent(context, attention: attention, host: host);
  if (agent == null || !context.mounted) {
    return;
  }
  await openChatView(
    context: context,
    attention: attention,
    host: host,
    agent: agent,
    dictation: dictation,
    onOpenTerminal: () => onOpenTerminal(agent),
  );
}
