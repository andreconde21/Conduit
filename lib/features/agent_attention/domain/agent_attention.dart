/// The attention-relevant state of one remote agent, normalized across
/// providers.
enum AgentAttentionState {
  /// Actively producing output or running tools.
  working,

  /// Waiting on a human answer or approval.
  needsInput,

  /// Blocked for another reason a provider distinguishes from input.
  blocked,

  /// Completed background work that has not been reviewed yet.
  finished,

  /// Ready for input with nothing pending.
  idle,

  /// Present, but the provider cannot classify it confidently.
  unknown,
}

extension AgentAttentionStateDetails on AgentAttentionState {
  String get label => switch (this) {
    AgentAttentionState.working => 'Working',
    AgentAttentionState.needsInput => 'Needs input',
    AgentAttentionState.blocked => 'Blocked',
    AgentAttentionState.finished => 'Finished',
    AgentAttentionState.idle => 'Idle',
    AgentAttentionState.unknown => 'Unknown',
  };

  /// Whether this state means a human should look at the agent now.
  bool get needsAttention =>
      this == AgentAttentionState.needsInput ||
      this == AgentAttentionState.blocked;
}

/// What a human answers to a pending permission request.
enum PermissionVerdict { allow, deny, always }

extension PermissionVerdictDetails on PermissionVerdict {
  /// The verdict as the host companion's `decide` command spells it.
  String get wireName => name;

  String get label => switch (this) {
    PermissionVerdict.allow => 'Allow',
    PermissionVerdict.deny => 'Deny',
    PermissionVerdict.always => 'Always',
  };
}

/// One tool call an agent is waiting to have approved, as reported by a
/// provider that can relay permission prompts (the Conductore host
/// companion). Herdr agents never carry these.
class PendingPermissionRequest {
  const PendingPermissionRequest({
    required this.id,
    required this.toolName,
    required this.summary,
    this.toolInput = '',
    this.createdAt,
  });

  /// Provider-issued request id, passed back verbatim with the decision.
  final String id;

  final String toolName;

  /// One-line human description of the call (e.g. the shell command).
  final String summary;

  /// The full tool input, pretty-printed, capped at [maxToolInputLength].
  final String toolInput;

  final DateTime? createdAt;

  /// Longest tool input kept on the phone; anything beyond is truncated
  /// with a marker so a huge file write cannot bloat the dashboard.
  static const maxToolInputLength = 4000;

  @override
  bool operator ==(Object other) {
    return other is PendingPermissionRequest &&
        other.id == id &&
        other.toolName == toolName &&
        other.summary == summary &&
        other.toolInput == toolInput &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(id, toolName, summary, toolInput, createdAt);
}

/// One remote agent as reported by a provider.
class AgentInfo {
  const AgentInfo({
    required this.id,
    required this.name,
    required this.state,
    this.kind = '',
    this.workspace,
    this.tab,
    this.pane,
    this.stateChangedAt,
    this.stateSequence,
    this.pendingRequests = const [],
    this.lastMessage,
  });

  /// Stable identity across polls (provider-specific; e.g. pane id or a
  /// unique live agent name). Used to deduplicate notifications.
  final String id;

  /// Safe display label.
  final String name;

  final AgentAttentionState state;

  /// Provider-reported agent kind (e.g. which CLI runs in the pane).
  final String kind;

  final String? workspace;
  final String? tab;
  final String? pane;

  /// When the agent entered [state], if the provider reports it.
  final DateTime? stateChangedAt;

  /// Monotonic state-transition sequence, if the provider reports one.
  final int? stateSequence;

  /// Permission prompts waiting on a human, oldest first. Empty for
  /// providers that cannot relay them.
  final List<PendingPermissionRequest> pendingRequests;

  /// The agent's latest message, when the provider reports one (the last
  /// assistant text, a notification, or a question it asked). Capped by
  /// the provider; shown in the dashboard and notification bodies.
  final String? lastMessage;

  /// A copy with [pendingRequests] and optionally [state] replaced.
  AgentInfo copyWith({
    AgentAttentionState? state,
    List<PendingPermissionRequest>? pendingRequests,
  }) {
    return AgentInfo(
      id: id,
      name: name,
      state: state ?? this.state,
      kind: kind,
      workspace: workspace,
      tab: tab,
      pane: pane,
      stateChangedAt: stateChangedAt,
      stateSequence: stateSequence,
      pendingRequests: pendingRequests ?? this.pendingRequests,
      lastMessage: lastMessage,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AgentInfo &&
        other.id == id &&
        other.name == name &&
        other.state == state &&
        other.kind == kind &&
        other.workspace == workspace &&
        other.tab == tab &&
        other.pane == pane &&
        other.stateChangedAt == stateChangedAt &&
        other.stateSequence == stateSequence &&
        other.lastMessage == lastMessage &&
        _sameRequests(other.pendingRequests, pendingRequests);
  }

  static bool _sameRequests(
    List<PendingPermissionRequest> a,
    List<PendingPermissionRequest> b,
  ) {
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

  @override
  int get hashCode => Object.hash(
    id,
    name,
    state,
    kind,
    workspace,
    tab,
    pane,
    stateChangedAt,
    stateSequence,
    lastMessage,
    Object.hashAll(pendingRequests),
  );
}

/// One poll's worth of agent information for a host.
class AgentAttentionSnapshot {
  const AgentAttentionSnapshot({required this.agents, this.sequence});

  final List<AgentInfo> agents;

  /// Monotonic snapshot sequence, when the provider numbers its snapshots
  /// (used to resume a change stream and to drop stale results).
  final int? sequence;
}

/// One change reported by a provider's change stream.
class AgentChange {
  const AgentChange({
    required this.sequence,
    required this.agentId,
    required this.agent,
  });

  /// The provider's sequence number for this change.
  final int sequence;

  final String agentId;

  /// The agent's complete new record, or null when it was removed.
  final AgentInfo? agent;
}

/// What one long-poll returned: either a full [snapshot] (the provider
/// could not serve the changes since the requested sequence) followed by
/// any [changes], or just [changes] to apply on top of the known state.
class AgentChangeBatch {
  const AgentChangeBatch({this.snapshot, this.changes = const []});

  final AgentAttentionSnapshot? snapshot;

  /// In sequence order.
  final List<AgentChange> changes;

  bool get isEmpty => snapshot == null && changes.isEmpty;
}
