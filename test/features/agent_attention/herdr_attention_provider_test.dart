import 'package:conduit/core/app_failure.dart';
import 'package:conduit/features/agent_attention/data/herdr_attention_provider.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention_provider.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

void main() {
  const provider = HerdrAttentionProvider();

  AgentCommandResult ok(String stdout) =>
      AgentCommandResult(stdout: stdout, stderr: '', exitCode: 0);

  group('HerdrAttentionProvider.parseAgentList', () {
    test('parses a bare array with documented field names', () {
      final agents = HerdrAttentionProvider.parseAgentList('''
        [
          {"name": "builder", "kind": "claude-code", "agent_status": "working",
           "pane_id": "w1:p2", "workspace_id": "w1", "tab_id": "w1:t1"},
          {"name": "reviewer", "agent_status": "blocked"},
          {"name": "researcher", "agent_status": "done"},
          {"name": "helper", "agent_status": "idle"},
          {"name": "mystery", "agent_status": "someday-new-state"}
        ]
      ''');

      expect(agents, hasLength(5));
      expect(agents[0].id, 'w1:p2');
      expect(agents[0].name, 'builder');
      expect(agents[0].kind, 'claude-code');
      expect(agents[0].state, AgentAttentionState.working);
      expect(agents[0].workspace, 'w1');
      expect(agents[0].tab, 'w1:t1');
      expect(agents[1].state, AgentAttentionState.needsInput);
      expect(agents[2].state, AgentAttentionState.finished);
      expect(agents[3].state, AgentAttentionState.idle);
      expect(agents[4].state, AgentAttentionState.unknown);
    });

    test('parses result and agents envelopes', () {
      const item = '{"name": "a", "state": "working"}';
      for (final raw in [
        '{"agents": [$item]}',
        '{"result": {"agents": [$item]}}',
        '{"result": [$item]}',
      ]) {
        final agents = HerdrAttentionProvider.parseAgentList(raw);
        expect(agents, hasLength(1), reason: raw);
        expect(agents.single.state, AgentAttentionState.working, reason: raw);
      }
    });

    test('treats empty output and empty lists as no agents', () {
      expect(HerdrAttentionProvider.parseAgentList(''), isEmpty);
      expect(HerdrAttentionProvider.parseAgentList('[]'), isEmpty);
      expect(HerdrAttentionProvider.parseAgentList('{"agents": []}'), isEmpty);
    });

    test('skips malformed entries but keeps valid ones', () {
      final agents = HerdrAttentionProvider.parseAgentList(
        '[{"name": "ok", "state": "idle"}, {"state": "working"}, 42, "x"]',
      );
      expect(agents, hasLength(1));
      expect(agents.single.name, 'ok');
    });

    test('drops absurd timestamps instead of failing the snapshot', () {
      final agents = HerdrAttentionProvider.parseAgentList(
        '[{"name": "a", "state": "working", '
        '"state_changed_at": 99999999999999999999999}]',
      );
      expect(agents, hasLength(1));
      expect(agents.single.stateChangedAt, isNull);
    });

    test('parses timestamps and sequence numbers when present', () {
      final agents = HerdrAttentionProvider.parseAgentList(
        '[{"name": "a", "state": "working", '
        '"state_changed_at": 1767225600000, "state_seq": 7}]',
      );
      expect(
        agents.single.stateChangedAt,
        DateTime.fromMillisecondsSinceEpoch(1767225600000, isUtc: true),
      );
      expect(agents.single.stateSequence, 7);
    });

    test('parses real Herdr 0.9.1 output', () {
      // Captured from `herdr agent list` on Herdr 0.9.1: an unnamed agent
      // and a named one, inside the CLI envelope.
      final agents = HerdrAttentionProvider.parseAgentList('''
        {"id":"cli:agent:list","result":{"agents":[
          {"agent":"claude","agent_session":{"agent":"claude","kind":"id",
           "source":"herdr:claude","value":"fedc75e1"},"agent_status":"idle",
           "cwd":"/root","focused":false,"foreground_cwd":"/root",
           "pane_id":"w4:p4","revision":1,"state_change_seq":101,
           "tab_id":"w4:t4","terminal_id":"term_65c2cc308a9ca2",
           "terminal_title":"\\u2733 Tailscale audit",
           "terminal_title_stripped":"Tailscale audit","workspace_id":"w4"},
          {"agent":"claude","agent_status":"working","cwd":"/root/Projects",
           "focused":true,"interactive_ready":true,"name":"conductore",
           "pane_id":"wX:p1","revision":2,"state_change_seq":154,
           "tab_id":"wX:t1","terminal_id":"term_65c3e513abe0ae",
           "terminal_title":"\\u25d1 Conductore handoff",
           "terminal_title_stripped":"Conductore handoff","workspace_id":"wX"}
        ],"type":"agent_list"}}
      ''');

      expect(agents, hasLength(2));
      final unnamed = agents[0];
      expect(unnamed.id, 'w4:p4');
      // `agent` is the kind, not the name; the title labels unnamed agents.
      expect(unnamed.kind, 'claude');
      expect(unnamed.name, 'Tailscale audit');
      expect(unnamed.state, AgentAttentionState.idle);
      expect(unnamed.stateSequence, 101);
      expect(unnamed.workspace, 'w4');
      expect(unnamed.tab, 'w4:t4');
      final named = agents[1];
      expect(named.name, 'conductore');
      expect(named.kind, 'claude');
      expect(named.state, AgentAttentionState.working);
      expect(named.stateSequence, 154);
    });

    test('surfaces a JSON error envelope on stdout as a failure', () {
      expect(
        () => HerdrAttentionProvider.parseAgentList(
          '{"id":"cli:agent:list","error":{"code":"internal",'
          '"message":"socket gone"}}',
        ),
        throwsA(
          isA<AppFailure>().having(
            (failure) => failure.toString(),
            'message',
            contains('socket gone'),
          ),
        ),
      );
    });

    test('throws AppFailure on non-JSON output', () {
      expect(
        () => HerdrAttentionProvider.parseAgentList('herdr: segfault'),
        throwsA(isA<AppFailure>()),
      );
    });

    test('throws AppFailure on an unexpected JSON shape', () {
      expect(
        () => HerdrAttentionProvider.parseAgentList('"just a string"'),
        throwsA(isA<AppFailure>()),
      );
    });
  });

  group('HerdrAttentionProvider.fetchAgents', () {
    test('reports Herdr missing on exit 127', () async {
      final runner = ScriptedAgentCommandRunner([
        const AgentCommandResult(
          stdout: '',
          stderr: 'sh: herdr: command not found',
          exitCode: 127,
        ),
      ]);
      expect(
        () => provider.fetchAgents(runner),
        throwsA(isA<AgentProviderUnavailable>()),
      );
    });

    test('reports an older Herdr on CLI usage errors (exit 2)', () async {
      final runner = ScriptedAgentCommandRunner([
        const AgentCommandResult(
          stdout: '',
          stderr: 'unknown subcommand: agent',
          exitCode: 2,
        ),
      ]);
      expect(
        () => provider.fetchAgents(runner),
        throwsA(isA<AgentProviderUnavailable>()),
      );
    });

    test('surfaces server errors with the JSON message', () async {
      final runner = ScriptedAgentCommandRunner([
        const AgentCommandResult(
          stdout: '',
          stderr: '{"error": {"code": "internal", "message": "socket gone"}}',
          exitCode: 1,
        ),
      ]);
      await expectLater(
        () => provider.fetchAgents(runner),
        throwsA(
          isA<AppFailure>().having(
            (failure) => failure.toString(),
            'message',
            contains('socket gone'),
          ),
        ),
      );
    });

    test('explains a stopped Herdr server without a socket path', () async {
      final runner = ScriptedAgentCommandRunner([
        const AgentCommandResult(
          stdout: '',
          stderr:
              '{"id":"cli:agent:list","error":{"code":"server_not_running",'
              '"message":"no herdr server is running at /root/.config/herdr/'
              'herdr.sock; run `herdr` to start or attach it"}}',
          exitCode: 1,
        ),
      ]);
      await expectLater(
        () => provider.fetchAgents(runner),
        throwsA(
          isA<AppFailure>()
              .having(
                (failure) => failure.toString(),
                'message',
                contains('Herdr is not running'),
              )
              .having(
                (failure) => failure.toString(),
                'no socket path',
                isNot(contains('.sock')),
              ),
        ),
      );
    });

    test('runs the documented list command and parses agents', () async {
      final runner = ScriptedAgentCommandRunner([
        ok('[{"name": "builder", "state": "working"}]'),
      ]);
      final snapshot = await provider.fetchAgents(runner);
      expect(runner.commands, [
        HerdrAttentionProvider.remoteCommand('agent list'),
      ]);
      expect(snapshot.agents.single.name, 'builder');
    });
  });

  group('HerdrAttentionProvider.remoteCommand', () {
    test('runs herdr under sh with user-local install dirs on PATH', () {
      final command = HerdrAttentionProvider.remoteCommand('agent list');
      expect(command, startsWith("sh -c 'PATH=\""));
      expect(command, contains(r'$HOME/.local/bin'));
      expect(command, contains(r'$HOME/.local/share/mise/shims'));
      expect(command, contains('/opt/homebrew/bin'));
      expect(command, contains(r':$PATH" exec herdr agent list'));
      expect(command, endsWith("'"));
    });

    test('escapes single quotes inside the wrapped command', () {
      final command = HerdrAttentionProvider.remoteCommand("agent focus 'a b'");
      expect(command, endsWith(r"exec herdr agent focus '\''a b'\'''"));
    });
  });

  group('HerdrAttentionProvider.focusCommand', () {
    test('prefers the pane id over any name', () {
      // Unnamed agents are labelled by their terminal title, which is not a
      // valid focus target; the pane id always is.
      expect(
        provider.focusCommand(
          const AgentInfo(
            id: 'w1:p9',
            name: 'Tailscale audit for coolify URLs',
            pane: 'w1:p9',
            state: AgentAttentionState.idle,
          ),
        ),
        HerdrAttentionProvider.remoteCommand('agent focus w1:p9'),
      );
    });

    test('falls back to a live agent name only when it is one', () {
      expect(
        provider.focusCommand(
          const AgentInfo(
            id: 'builder',
            name: 'builder',
            state: AgentAttentionState.idle,
          ),
        ),
        HerdrAttentionProvider.remoteCommand('agent focus builder'),
      );
      for (final name in ['', 'Needs Review', r"my agent's \$run", 'claude ']) {
        expect(
          provider.focusCommand(
            AgentInfo(id: 'x', name: name, state: AgentAttentionState.idle),
          ),
          isNull,
          reason: name,
        );
      }
    });
  });
}
