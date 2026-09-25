import 'package:conduit/features/agent_attention/data/conductore_host_attention_provider.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/chat_view/presentation/chat_view_launcher.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';
import 'live_status_fixture.dart';

/// Which Claude session the Chat button opens, against the companion's
/// real `status` shape.
void main() {
  final agents = ConductoreHostAttentionProvider.parseSnapshot(
    liveHerdrStatusJson(),
  ).agents;

  SavedHost herdr(String workspace, {String tab = ''}) => ConnectTarget.herdr(
    workspaceId: workspace,
    tabId: tab,
  ).apply(buildHost('h'));

  String? matched(ChatAgentMatch match) =>
      match is ChatAgentMatched ? match.agent.id : null;

  List<String> candidates(ChatAgentMatch match) => match is ChatAgentAmbiguous
      ? [for (final agent in match.candidates) agent.id]
      : const [];

  test('the fixture parses into Herdr ids like the companion sends', () {
    final api = agents.singleWhere((agent) => agent.id == 's-api');
    expect(api.workspace, 'w7');
    expect(api.tab, 'w7:t1');
    expect(api.pane, 'w7:p1');
  });

  test('a Herdr workspace session opens the Claude in that workspace, '
      'though the machine runs several', () {
    // The connect target of a workspace has no tab: the old matcher fell
    // back to "the only live agent" and found six.
    expect(matched(resolveChatAgent(herdr('w7'), agents)), 's-api');
    expect(matched(resolveChatAgent(herdr('w4'), agents)), 's-root');
  });

  test('a stale session listed for the same pane gives way to the newest', () {
    expect(matched(resolveChatAgent(herdr('wX'), agents)), 's-mobile');
  });

  test('two Claudes in one workspace: the focused pane decides, else ask', () {
    final host = herdr('w5');
    expect(candidates(resolveChatAgent(host, agents)), ['s-left', 's-right']);
    expect(
      matched(
        resolveChatAgent(
          host,
          agents,
          location: const ChatSessionLocation(
            herdrWorkspaceId: 'w5',
            herdrPaneId: 'w5:p5',
          ),
        ),
      ),
      's-right',
    );
    // A focused pane that runs no Claude narrows nothing.
    expect(
      candidates(
        resolveChatAgent(
          host,
          agents,
          location: const ChatSessionLocation(herdrPaneId: 'w5:p9'),
        ),
      ),
      ['s-left', 's-right'],
    );
  });

  test('the tab in a pane-opened session narrows too', () {
    expect(
      matched(resolveChatAgent(herdr('w4', tab: 'w4:t4'), agents)),
      's-root',
    );
  });

  test('the workspace the session moved to wins over its connect target', () {
    expect(
      matched(
        resolveChatAgent(
          herdr('w7'),
          agents,
          location: const ChatSessionLocation(herdrWorkspaceId: 'w4'),
        ),
      ),
      's-root',
    );
  });

  test('a workspace without Claude asks, flagged as elsewhere', () {
    final match = resolveChatAgent(herdr('w9'), agents);
    expect(match, isA<ChatAgentAmbiguous>());
    expect((match as ChatAgentAmbiguous).elsewhere, isTrue);
    // The stale duplicate is not offered.
    expect(
      match.candidates.map((agent) => agent.id),
      isNot(contains('s-stale')),
    );
  });

  test('a plain shell on a machine with several asks; with one opens it', () {
    final shell = buildHost('h');
    expect(resolveChatAgent(shell, agents), isA<ChatAgentAmbiguous>());
    expect(matched(resolveChatAgent(shell, [agents.first])), agents.first.id);
  });

  test('tmux sessions match on the session name', () {
    const tmuxAgents = [
      AgentInfo(
        id: 'a',
        name: 'a',
        state: AgentAttentionState.working,
        tab: 'other:0',
      ),
      AgentInfo(
        id: 'b',
        name: 'b',
        state: AgentAttentionState.working,
        tab: 'work:1',
      ),
    ];
    final host = const ConnectTarget.tmux('work').apply(buildHost('h'));
    expect(matched(resolveChatAgent(host, tmuxAgents)), 'b');
  });

  test('nothing live is none', () {
    const ended = [
      AgentInfo(id: 'a', name: 'a', state: AgentAttentionState.finished),
    ];
    expect(resolveChatAgent(herdr('w7'), ended), isA<ChatAgentNone>());
  });
}
