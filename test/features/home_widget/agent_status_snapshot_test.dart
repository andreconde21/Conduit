import 'dart:convert';

import 'package:conduit/features/agent_attention/data/conductore_host_attention_provider.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/home_widget/domain/agent_status_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 24, 10, 30);

  AgentInfo agent(String name, AgentAttentionState state) =>
      AgentInfo(id: name, name: name, state: state);

  test('orders agents most urgent first and keeps provider order for ties', () {
    final snapshot = AgentStatusSnapshot.build(
      hosts: [
        (
          hostName: 'dev',
          agents: [
            agent('idle-1', AgentAttentionState.idle),
            agent('worker-a', AgentAttentionState.working),
            agent('done', AgentAttentionState.finished),
          ],
        ),
        (
          hostName: 'prod',
          agents: [
            agent('worker-b', AgentAttentionState.working),
            agent('stuck', AgentAttentionState.blocked),
            agent('asks', AgentAttentionState.needsInput),
          ],
        ),
      ],
      monitoring: true,
      now: now,
    );

    expect(snapshot.monitoring, isTrue);
    expect(snapshot.attentionCount, 2);
    expect(snapshot.updatedAt, now);
    expect(snapshot.agents.map((entry) => entry.name), [
      'asks',
      'stuck',
      'done',
      'worker-a',
    ]);
    expect(snapshot.agents.first.host, 'prod');
    expect(snapshot.agents, hasLength(AgentStatusSnapshot.maxAgents));
  });

  test('a companion permission prompt counts as attention', () {
    final parsed = ConductoreHostAttentionProvider.parseSnapshot(
      '{"version":1,"seq":1,"agents":[{"sessionId":"s","name":"api",'
      '"state":"needs_permission","pending":[{"id":"r","toolName":"Bash",'
      '"summary":"ls"}]},{"sessionId":"t","name":"web","state":"working"}]}',
    );
    final snapshot = AgentStatusSnapshot.build(
      hosts: [(hostName: 'dev', agents: parsed.agents)],
      monitoring: true,
      now: now,
    );
    expect(snapshot.attentionCount, 1);
    expect(snapshot.agents.first.name, 'api');
    expect(snapshot.agents.first.state, AgentAttentionState.needsInput);
  });

  test('counts every agent needing attention even beyond the row limit', () {
    final snapshot = AgentStatusSnapshot.build(
      hosts: [
        (
          hostName: 'dev',
          agents: [
            for (var i = 0; i < 6; i++)
              agent('a$i', AgentAttentionState.needsInput),
          ],
        ),
      ],
      monitoring: true,
      now: now,
    );
    expect(snapshot.attentionCount, 6);
    expect(snapshot.agents, hasLength(4));
  });

  test('empty snapshot is not monitoring', () {
    final snapshot = AgentStatusSnapshot.empty(now);
    expect(snapshot.monitoring, isFalse);
    expect(snapshot.attentionCount, 0);
    expect(snapshot.agents, isEmpty);
  });

  test('encodes the shape the native side reads', () {
    final snapshot = AgentStatusSnapshot.build(
      hosts: [
        (
          hostName: 'dev box',
          agents: [agent('builder', AgentAttentionState.needsInput)],
        ),
      ],
      monitoring: true,
      now: now,
    );

    final json = jsonDecode(snapshot.encode()) as Map<String, Object?>;
    expect(json, {
      'version': 2,
      'monitoring': true,
      'attentionCount': 1,
      'updatedAt': now.millisecondsSinceEpoch,
      'agents': [
        {
          'name': 'builder',
          'host': 'dev box',
          'state': 'needsInput',
          'label': 'Needs input',
        },
      ],
      'limits': <Object?>[],
    });
  });

  test('carries the limit rings with their warning level', () {
    final resets = DateTime.utc(2026, 9, 25, 15);
    final snapshot = AgentStatusSnapshot.build(
      hosts: const [],
      monitoring: true,
      now: now,
      limits: [
        AgentStatusLimit(label: '5h', usedPct: 83, resetsAt: resets),
        const AgentStatusLimit(label: '7d', usedPct: 12),
      ],
    );
    final json = jsonDecode(snapshot.encode()) as Map<String, Object?>;
    expect(json['limits'], [
      {
        'label': '5h',
        'usedPct': 83,
        'level': 'warning',
        'resetsAt': resets.millisecondsSinceEpoch,
      },
      {'label': '7d', 'usedPct': 12, 'level': 'normal'},
    ]);
    expect(AgentStatusSnapshot.decode(snapshot.encode()), snapshot);
    expect(const AgentStatusLimit(label: '5h', usedPct: 95).level, 'critical');
    expect(const AgentStatusLimit(label: '5h', usedPct: 79).level, 'normal');
  });

  test('round-trips through JSON', () {
    final snapshot = AgentStatusSnapshot.build(
      hosts: [
        (
          hostName: 'dev',
          agents: [
            agent('a', AgentAttentionState.working),
            agent('b', AgentAttentionState.blocked),
          ],
        ),
      ],
      monitoring: true,
      now: now,
    );
    expect(AgentStatusSnapshot.decode(snapshot.encode()), snapshot);
  });

  test('tolerates missing and unknown fields', () {
    final snapshot = AgentStatusSnapshot.decode(
      '{"agents":[{"name":"x","host":"h","state":"dancing"}]}',
    );
    expect(snapshot.monitoring, isFalse);
    expect(snapshot.attentionCount, 0);
    expect(snapshot.agents.single.state, AgentAttentionState.unknown);
    expect(
      snapshot.updatedAt,
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  });
}
