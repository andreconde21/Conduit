import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:flutter/foundation.dart';

/// The inbox sections, in display order: approvals are pinned on top.
enum AgentInboxSection {
  needsApproval,
  needsInput,
  working,
  doneIdle;

  String get label => switch (this) {
    AgentInboxSection.needsApproval => 'Needs approval',
    AgentInboxSection.needsInput => 'Needs input',
    AgentInboxSection.working => 'Working',
    AgentInboxSection.doneIdle => 'Done & idle',
  };

  /// Rows in this section can be swiped away (hidden until they change).
  bool get dismissible => this == AgentInboxSection.doneIdle;

  static AgentInboxSection of(AgentInfo agent) {
    if (agent.pendingRequests.isNotEmpty) {
      return AgentInboxSection.needsApproval;
    }
    return switch (agent.state) {
      AgentAttentionState.needsInput ||
      AgentAttentionState.blocked => AgentInboxSection.needsInput,
      AgentAttentionState.working => AgentInboxSection.working,
      AgentAttentionState.finished ||
      AgentAttentionState.idle ||
      AgentAttentionState.unknown => AgentInboxSection.doneIdle,
    };
  }
}

/// One inbox row: the single live record of one agent session on one host.
/// New events replace the agent, never add a second row.
class AgentInboxEntry {
  const AgentInboxEntry({
    required this.hostId,
    required this.hostName,
    required this.agent,
  });

  final String hostId;
  final String hostName;
  final AgentInfo agent;

  /// Stable across updates, so the row keeps its widget state in place.
  String get key => '$hostId/${agent.id}';

  String get project => agent.projectLabel ?? agent.name;

  AgentInboxSection get section => AgentInboxSection.of(agent);
}

/// A run of rows sharing a host and project inside one section. [hostName]
/// and [project] are null when the inbox does not group (a single host).
class AgentInboxGroup {
  const AgentInboxGroup({required this.entries, this.hostName, this.project});

  final String? hostName;
  final String? project;
  final List<AgentInboxEntry> entries;
}

/// One host's agents, in the order the inbox should consider them.
typedef AgentInboxHostInput = ({
  String hostId,
  String hostName,
  List<AgentInfo> agents,
});

/// The whole inbox: non-empty sections in display order, plus how many rows
/// are hidden by local dismissals.
class AgentInbox {
  const AgentInbox({required this.sections, required this.hiddenCount});

  /// Builds the inbox from each host's agents. With more than one host,
  /// every section is grouped by host (in [hosts] order) then project
  /// (alphabetical); with one host the section is a single newest-first
  /// run. Rows [dismissals] hides are left out and counted.
  factory AgentInbox.build(
    List<AgentInboxHostInput> hosts, {
    AgentInboxDismissals? dismissals,
  }) {
    final grouped = hosts.length > 1;
    final bySection = <AgentInboxSection, List<AgentInboxEntry>>{};
    final hostOrder = <String, int>{};
    var hidden = 0;
    for (final host in hosts) {
      hostOrder[host.hostId] = hostOrder.length;
      final seen = <String>{};
      for (final agent in host.agents) {
        // One row per agent session, even if a provider repeats one.
        if (!seen.add(agent.id)) {
          continue;
        }
        if (dismissals?.isHidden(host.hostId, agent) ?? false) {
          hidden += 1;
          continue;
        }
        final entry = AgentInboxEntry(
          hostId: host.hostId,
          hostName: host.hostName,
          agent: agent,
        );
        bySection.putIfAbsent(entry.section, () => []).add(entry);
      }
    }
    final sections = <AgentInboxSection, List<AgentInboxGroup>>{};
    for (final section in AgentInboxSection.values) {
      final entries = bySection[section];
      if (entries == null || entries.isEmpty) {
        continue;
      }
      entries.sort((a, b) {
        if (grouped) {
          final byHost = hostOrder[a.hostId]!.compareTo(hostOrder[b.hostId]!);
          if (byHost != 0) {
            return byHost;
          }
          final byProject = a.project.toLowerCase().compareTo(
            b.project.toLowerCase(),
          );
          if (byProject != 0) {
            return byProject;
          }
        }
        return _newestFirst(a.agent, b.agent);
      });
      if (!grouped) {
        sections[section] = [AgentInboxGroup(entries: entries)];
        continue;
      }
      final groups = <AgentInboxGroup>[];
      for (final entry in entries) {
        final last = groups.lastOrNull;
        if (last != null &&
            last.entries.first.hostId == entry.hostId &&
            last.project == entry.project) {
          last.entries.add(entry);
        } else {
          groups.add(
            AgentInboxGroup(
              hostName: entry.hostName,
              project: entry.project,
              entries: [entry],
            ),
          );
        }
      }
      sections[section] = groups;
    }
    return AgentInbox(sections: sections, hiddenCount: hidden);
  }

  final Map<AgentInboxSection, List<AgentInboxGroup>> sections;
  final int hiddenCount;

  bool get isEmpty => sections.isEmpty;

  int countIn(AgentInboxSection section) => [
    for (final group in sections[section] ?? const <AgentInboxGroup>[])
      ...group.entries,
  ].length;

  /// Newest state change first; agents without a time go last, and ties
  /// are broken by name so the order is deterministic.
  static int _newestFirst(AgentInfo a, AgentInfo b) {
    final at = a.stateChangedAt;
    final bt = b.stateChangedAt;
    if (at != null && bt != null) {
      final byTime = bt.compareTo(at);
      if (byTime != 0) {
        return byTime;
      }
    } else if (at != null || bt != null) {
      return at == null ? 1 : -1;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }
}

/// Rows the user swiped away. A dismissal is local to this phone and only
/// lasts until the agent changes: any new state, sequence, message or
/// request brings the row back.
class AgentInboxDismissals extends ChangeNotifier {
  final Map<String, int> _hidden = {};

  static String _key(String hostId, String agentId) => '$hostId/$agentId';

  /// What "unchanged" means for a dismissed row.
  static int fingerprint(AgentInfo agent) => Object.hash(
    agent.state,
    agent.stateChangedAt,
    agent.stateSequence,
    agent.lastMessage,
    Object.hashAll(agent.pendingRequests.map((request) => request.id)),
  );

  int get count => _hidden.length;

  void dismiss(String hostId, AgentInfo agent) {
    _hidden[_key(hostId, agent.id)] = fingerprint(agent);
    notifyListeners();
  }

  /// Whether [agent] is still hidden; a changed agent drops its dismissal.
  bool isHidden(String hostId, AgentInfo agent) {
    final key = _key(hostId, agent.id);
    final stored = _hidden[key];
    if (stored == null) {
      return false;
    }
    if (stored == fingerprint(agent)) {
      return true;
    }
    _hidden.remove(key);
    return false;
  }

  /// Brings every dismissed row back.
  void restoreAll() {
    if (_hidden.isEmpty) {
      return;
    }
    _hidden.clear();
    notifyListeners();
  }
}
