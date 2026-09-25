import 'dart:async';

import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_controller.dart';
import 'package:conduit/features/chat_view/presentation/chat_view_launcher.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/session_navigation/domain/session_view_preferences.dart';
import 'package:conduit/features/session_navigation/presentation/session_view_controller.dart';
import 'package:conduit/features/voice/presentation/dictation_controller.dart';
import 'package:flutter/widgets.dart';

/// The Claude session to show in Chat View when the session of [host] (a
/// session host, possibly derived) is opened: its agent as the companion
/// already reports it, when that session's effective view is Chat View.
///
/// Null means the terminal: no controller, a local shell, a pane that runs
/// no Claude (or nothing the companion knows), several candidates, or a
/// session set to Terminal. No SSH round trip is made, so opening a
/// session never waits on the network.
AgentInfo? preferredChatAgent({
  required SessionViewController? views,
  required AgentAttentionController? attention,
  required SavedHost host,
}) {
  if (views == null || attention == null || host.isLocal) return null;
  // Cheap test first: a session that would open in the terminal anyway
  // needs no agent lookup.
  if (views.viewFor(host.id, runsClaude: true) != SessionView.chat) {
    return null;
  }
  final agent = chatAgentForSession(attention, host);
  if (agent == null || !isClaudeAgent(agent)) return null;
  return agent;
}

/// Whether [agent] (opened from a list of agents, at its pane) should show
/// in Chat View: a Claude session on a machine the companion monitors, and
/// the effective view of [sessionHostId] (the session it opens in) is Chat
/// View.
bool agentOpensInChat({
  required SessionViewController? views,
  required AgentAttentionController? attention,
  required SavedHost monitoredHost,
  required AgentInfo agent,
  String? sessionHostId,
}) {
  if (views == null || attention == null) return false;
  final runsClaude =
      isClaudeAgent(agent) &&
      agent.state != AgentAttentionState.finished &&
      chatViewAvailable(attention, monitoredHost);
  return views.viewFor(
        sessionHostId ?? monitoredHost.id,
        runsClaude: runsClaude,
      ) ==
      SessionView.chat;
}

/// Opens Chat View for [host]'s session when [preferredChatAgent] finds
/// one; [onOpenTerminal] runs when its Terminal button is used. Returns
/// whether Chat View opened.
bool openPreferredChatView(
  BuildContext context, {
  required AgentAttentionController? attention,
  required SavedHost host,
  required void Function(AgentInfo agent) onOpenTerminal,
  DictationController? dictation,
}) {
  final agent = preferredChatAgent(
    views: SessionViewScope.maybeOf(context),
    attention: attention,
    host: host,
  );
  if (agent == null || attention == null) return false;
  // Not awaited: the route stays up until the user leaves it.
  unawaited(
    openChatView(
      context: context,
      attention: attention,
      host: host,
      agent: agent,
      dictation: dictation,
      onOpenTerminal: () => onOpenTerminal(agent),
    ),
  );
  return true;
}
