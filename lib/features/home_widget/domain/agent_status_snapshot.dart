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

/// One account limit window as the widget's ring shows it: `5h` or `7d`,
/// the share used (0 once the window reset) and whether it is at the
/// warning level (80 % and up).
class AgentStatusLimit {
  const AgentStatusLimit({
    required this.label,
    required this.usedPct,
    this.resetsAt,
  });

  final String label;

  /// 0 to 100, rounded.
  final int usedPct;
  final DateTime? resetsAt;

  /// Mirrors `kUsageWarningPct` / `kUsageCriticalPct` of the app.
  String get level => usedPct >= 95
      ? 'critical'
      : usedPct >= 80
      ? 'warning'
      : 'normal';

  Map<String, Object?> toJson() => {
    'label': label,
    'usedPct': usedPct,
    'level': level,
    if (resetsAt case final at?) 'resetsAt': at.toUtc().millisecondsSinceEpoch,
  };

  static AgentStatusLimit? fromJson(Object? json) {
    if (json is! Map || json['label'] is! String || json['usedPct'] is! num) {
      return null;
    }
    final resets = json['resetsAt'];
    return AgentStatusLimit(
      label: json['label'] as String,
      usedPct: (json['usedPct'] as num).round(),
      resetsAt: resets is int
          ? DateTime.fromMillisecondsSinceEpoch(resets, isUtc: true)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AgentStatusLimit &&
      other.label == label &&
      other.usedPct == usedPct &&
      other.resetsAt == resetsAt;

  @override
  int get hashCode => Object.hash(label, usedPct, resetsAt);
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
    this.limits = const [],
  });

  /// Payload format version; bump when the shape changes. 2: [limits].
  static const version = 2;

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

  /// Claude's 5-hour and weekly windows (the widget's rings), when known.
  final List<AgentStatusLimit> limits;

  /// Builds the snapshot for every monitored host, sorting agents so the
  /// ones a human should look at come first.
  factory AgentStatusSnapshot.build({
    required Iterable<({String hostName, List<AgentInfo> agents})> hosts,
    required bool monitoring,
    required DateTime now,
    List<AgentStatusLimit> limits = const [],
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
      limits: limits,
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
    'limits': [for (final limit in limits) limit.toJson()],
  };

  String encode() => jsonEncode(toJson());

  static AgentStatusSnapshot fromJson(Map<String, Object?> json) {
    final agents = json['agents'];
    final limits = json['limits'];
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
      limits: [
        if (limits is List)
          for (final limit in limits) ?AgentStatusLimit.fromJson(limit),
      ],
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
      _listEquals(other.agents, agents) &&
      _listEquals(other.limits, limits);

  @override
  int get hashCode => Object.hash(
    monitoring,
    attentionCount,
    updatedAt,
    Object.hashAll(agents),
    Object.hashAll(limits),
  );

  static bool _listEquals<T>(List<T> a, List<T> b) {
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
