import 'dart:convert';

import 'package:conduit/features/agent_attention/domain/agent_attention.dart';

/// One agent line as the home-screen widget and quick-settings tile show
/// it: display label, machine name and state only (the same lock-screen
/// safe subset the notifications use).
class AgentStatusEntry {
  const AgentStatusEntry({
    required this.name,
    required this.host,
    required this.state,
  });

  final String name;
  final String host;
  final AgentAttentionState state;

  Map<String, Object?> toJson() => {
    'name': name,
    'host': host,
    'state': state.name,
    'label': state.label,
  };

  static AgentStatusEntry fromJson(Map<String, Object?> json) {
    final stateName = json['state'] as String?;
    return AgentStatusEntry(
      name: json['name'] as String? ?? '',
      host: json['host'] as String? ?? '',
      state:
          AgentAttentionState.values
              .where((state) => state.name == stateName)
              .firstOrNull ??
          AgentAttentionState.unknown,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AgentStatusEntry &&
      other.name == name &&
      other.host == host &&
      other.state == state;

  @override
  int get hashCode => Object.hash(name, host, state);
}

/// What the native widget and tile render, pushed from Dart whenever the
/// agent dashboard changes.
///
/// Serialized as JSON so the Kotlin side can store it verbatim in
/// SharedPreferences and render it without the Flutter engine running.
class AgentStatusSnapshot {
  const AgentStatusSnapshot({
    required this.monitoring,
    required this.attentionCount,
    required this.agents,
    required this.updatedAt,
  });

  /// Payload format version; bump when the shape changes.
  static const version = 1;

  /// Most agents listed; the widget has room for four rows at most.
  static const maxAgents = 4;

  /// Whether at least one host is currently monitored. When false the
  /// widget shows its "open the app" placeholder instead of stale rows.
  final bool monitoring;

  /// Agents needing input or blocked, across all monitored hosts.
  final int attentionCount;

  /// Up to [maxAgents] entries, most urgent first.
  final List<AgentStatusEntry> agents;

  final DateTime updatedAt;

  /// Builds the snapshot for every monitored host, sorting agents so the
  /// ones a human should look at come first.
  factory AgentStatusSnapshot.build({
    required Iterable<({String hostName, List<AgentInfo> agents})> hosts,
    required bool monitoring,
    required DateTime now,
  }) {
    final entries = <AgentStatusEntry>[
      for (final host in hosts)
        for (final agent in host.agents)
          AgentStatusEntry(
            name: agent.name,
            host: host.hostName,
            state: agent.state,
          ),
    ];
    // Stable sort by urgency only, so the provider's own ordering breaks
    // ties (the list does not jump around between polls).
    final ranked = entries.indexed.toList()
      ..sort((a, b) {
        final byUrgency = _urgency(a.$2.state).compareTo(_urgency(b.$2.state));
        return byUrgency != 0 ? byUrgency : a.$1.compareTo(b.$1);
      });
    return AgentStatusSnapshot(
      monitoring: monitoring,
      attentionCount: entries
          .where((entry) => entry.state.needsAttention)
          .length,
      agents: [for (final (_, entry) in ranked.take(maxAgents)) entry],
      updatedAt: now,
    );
  }

  /// The snapshot pushed when nothing is monitored (app start, or after the
  /// last monitored session closes).
  factory AgentStatusSnapshot.empty(DateTime now) => AgentStatusSnapshot(
    monitoring: false,
    attentionCount: 0,
    agents: const [],
    updatedAt: now,
  );

  static int _urgency(AgentAttentionState state) => switch (state) {
    AgentAttentionState.needsInput => 0,
    AgentAttentionState.blocked => 1,
    AgentAttentionState.finished => 2,
    AgentAttentionState.working => 3,
    AgentAttentionState.idle => 4,
    AgentAttentionState.unknown => 5,
  };

  Map<String, Object?> toJson() => {
    'version': version,
    'monitoring': monitoring,
    'attentionCount': attentionCount,
    'updatedAt': updatedAt.toUtc().millisecondsSinceEpoch,
    'agents': [for (final agent in agents) agent.toJson()],
  };

  String encode() => jsonEncode(toJson());

  static AgentStatusSnapshot fromJson(Map<String, Object?> json) {
    final agents = json['agents'];
    return AgentStatusSnapshot(
      monitoring: json['monitoring'] as bool? ?? false,
      attentionCount: json['attentionCount'] as int? ?? 0,
      agents: [
        if (agents is List)
          for (final agent in agents)
            if (agent is Map<String, Object?>) AgentStatusEntry.fromJson(agent),
      ],
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        json['updatedAt'] as int? ?? 0,
        isUtc: true,
      ),
    );
  }

  static AgentStatusSnapshot decode(String source) =>
      fromJson(jsonDecode(source) as Map<String, Object?>);

  @override
  bool operator ==(Object other) =>
      other is AgentStatusSnapshot &&
      other.monitoring == monitoring &&
      other.attentionCount == attentionCount &&
      other.updatedAt == updatedAt &&
      _listEquals(other.agents, agents);

  @override
  int get hashCode => Object.hash(
    monitoring,
    attentionCount,
    updatedAt,
    Object.hashAll(agents),
  );

  static bool _listEquals(List<AgentStatusEntry> a, List<AgentStatusEntry> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
