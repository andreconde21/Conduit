import 'package:conduit/core/presentation/multiplexer_icon.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/desktop_shell/domain/sidebar_prefs.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/hosts/presentation/home_board_controller.dart';
import 'package:conduit/features/sessions/domain/remote_session_listing.dart';
import 'package:flutter/foundation.dart';

/// Keys of sidebar rows. A child's key extends its parent's, so "this row
/// and everything under it" is a prefix test (unread roll-ups, marking a
/// whole workspace read). Parts are URI-encoded, so names with `/` in them
/// stay one part.
abstract final class SidebarKeys {
  static String _e(String part) => Uri.encodeComponent(part);

  static String machine(String machineId) => 'm/${_e(machineId)}';

  static String herdrWorkspace(String machineId, String workspaceId) =>
      '${machine(machineId)}/h/${_e(workspaceId)}';

  static String herdrTab(String machineId, String workspaceId, String tabId) =>
      '${herdrWorkspace(machineId, workspaceId)}/t/${_e(tabId)}';

  static String agentPane(
    String machineId,
    String workspaceId,
    String? tabId,
    String paneId,
  ) =>
      '${tabId == null || tabId.isEmpty ? herdrWorkspace(machineId, workspaceId) : herdrTab(machineId, workspaceId, tabId)}'
      '/p/${_e(paneId)}';

  static String tmuxSession(String machineId, String name) =>
      '${machine(machineId)}/t/${_e(name)}';

  static String tmuxWindow(String machineId, String name, int index) =>
      '${tmuxSession(machineId, name)}/w/$index';

  static String openSession(String machineId, String sessionHostId) =>
      '${machine(machineId)}/s/${_e(sessionHostId)}';

  /// The machine id a key belongs to.
  static String? machineIdOf(String key) {
    final parts = key.split('/');
    if (parts.length < 2 || parts.first != 'm') return null;
    return Uri.decodeComponent(parts[1]);
  }

  /// Whether [key] is [ancestor] or lies under it.
  static bool isUnder(String key, String ancestor) =>
      key == ancestor || key.startsWith('$ancestor/');
}

/// The state dot of a row, most urgent last.
enum SidebarDot {
  none,
  idle,
  done,
  working,
  needsYou;

  static SidebarDot of(AgentAttentionState? state) => switch (state) {
    null => SidebarDot.none,
    AgentAttentionState.needsInput ||
    AgentAttentionState.blocked => SidebarDot.needsYou,
    AgentAttentionState.working => SidebarDot.working,
    AgentAttentionState.finished => SidebarDot.done,
    AgentAttentionState.idle || AgentAttentionState.unknown => SidebarDot.idle,
  };

  SidebarDot max(SidebarDot other) => other.index > index ? other : this;

  String get label => switch (this) {
    SidebarDot.none => '',
    SidebarDot.idle => 'Idle',
    SidebarDot.done => 'Done',
    SidebarDot.working => 'Working',
    SidebarDot.needsYou => 'Needs you',
  };
}

enum SidebarNodeKind {
  machine,
  herdrWorkspace,
  herdrTab,
  agentPane,
  tmuxSession,
  tmuxWindow,
  openSession,
}

/// What a row opens.
@immutable
sealed class SidebarTarget {
  const SidebarTarget(this.host);

  final SavedHost host;
}

class MachineTarget extends SidebarTarget {
  const MachineTarget(super.host);
}

class HerdrWorkspaceTarget extends SidebarTarget {
  const HerdrWorkspaceTarget(super.host, this.workspace);

  final HomeBoardWorkspace workspace;
}

class HerdrTabTarget extends SidebarTarget {
  const HerdrTabTarget(super.host, this.workspace, this.tab);

  final HomeBoardWorkspace workspace;
  final HerdrTabInfo tab;
}

class AgentPaneTarget extends SidebarTarget {
  const AgentPaneTarget(super.host, this.workspace, this.pane);

  final HomeBoardWorkspace workspace;
  final HomeBoardPane pane;
}

class TmuxSessionTarget extends SidebarTarget {
  const TmuxSessionTarget(super.host, this.session);

  final TmuxSessionInfo session;
}

class TmuxWindowTarget extends SidebarTarget {
  const TmuxWindowTarget(super.host, this.session, this.window);

  final String session;
  final TmuxWindowInfo window;
}

/// A session open in the app that no listed workspace stands for (a plain
/// shell, or a tmux / Herdr session of a machine not listed yet).
class OpenSessionTarget extends SidebarTarget {
  const OpenSessionTarget(super.host, this.sessionHostId);

  final String sessionHostId;
}

/// One row of the sidebar.
@immutable
class SidebarNode {
  const SidebarNode({
    required this.key,
    required this.kind,
    required this.machineId,
    required this.label,
    required this.target,
    this.detail = '',
    this.dot = SidebarDot.none,
    this.agentKind,
    this.multiplexer,
    this.openInApp = false,
    this.children = const [],
    this.lazyChildren = false,
  });

  final String key;
  final SidebarNodeKind kind;
  final String machineId;

  /// A human name, never an id.
  final String label;
  final String detail;

  /// This row's state, rolled up from its children.
  final SidebarDot dot;

  /// The agent CLI running here (`claude`, `codex`), if one does.
  final String? agentKind;

  /// The multiplexer logo to show, for workspace and session rows.
  final MultiplexerKind? multiplexer;

  /// A session in the app shows this row (or its workspace).
  final bool openInApp;
  final List<SidebarNode> children;

  /// Children exist but are listed on demand (a tmux session's windows).
  final bool lazyChildren;

  final SidebarTarget target;

  bool get hasChildren => children.isNotEmpty || lazyChildren;

  /// Open by default: machines. Everything else starts closed.
  bool get expandedByDefault => kind == SidebarNodeKind.machine;

  /// Rows the user can drag within their machine.
  bool get isReorderableChild =>
      kind == SidebarNodeKind.herdrWorkspace ||
      kind == SidebarNodeKind.tmuxSession ||
      kind == SidebarNodeKind.openSession;

  /// Every row of this subtree, depth first.
  Iterable<SidebarNode> get descendantsAndSelf sync* {
    yield this;
    for (final child in children) {
      yield* child.descendantsAndSelf;
    }
  }

  SidebarNode copyWith({List<SidebarNode>? children, SidebarDot? dot}) =>
      SidebarNode(
        key: key,
        kind: kind,
        machineId: machineId,
        label: label,
        target: target,
        detail: detail,
        dot: dot ?? this.dot,
        agentKind: agentKind,
        multiplexer: multiplexer,
        openInApp: openInApp,
        children: children ?? this.children,
        lazyChildren: lazyChildren,
      );

  @override
  String toString() => 'SidebarNode($key, $label, $dot)';
}

/// A session open in the app, as the sidebar needs it.
@immutable
class SidebarOpenSession {
  const SidebarOpenSession({
    required this.sessionHostId,
    required this.title,
    this.herdrWorkspaceId,
    this.tmuxSession,
    this.agentState,
  });

  final String sessionHostId;
  final String title;

  /// The Herdr workspace it shows, for Herdr sessions.
  final String? herdrWorkspaceId;

  /// The tmux session it is attached to, for tmux sessions.
  final String? tmuxSession;
  final AgentAttentionState? agentState;
}

/// Everything the sidebar knows about one machine.
@immutable
class SidebarMachineInput {
  const SidebarMachineInput({
    required this.host,
    this.board,
    this.openSessions = const [],
    this.agents = const [],
    this.tmuxWindows = const {},
    this.status = '',
  });

  final SavedHost host;

  /// The machine's home board (Herdr workspaces, tmux sessions), if listed.
  final HomeBoardState? board;
  final List<SidebarOpenSession> openSessions;

  /// Agents the companion reports for the machine's open sessions.
  final List<AgentInfo> agents;

  /// tmux windows per session name, for the sessions listed so far.
  final Map<String, List<TmuxWindowInfo>> tmuxWindows;

  /// A short line under the machine name ("Not listed yet", "Offline").
  final String status;
}

/// Builds the sidebar's machine tree from the home boards, the open
/// sessions and the agent monitor.
abstract final class SidebarTreeBuilder {
  static List<SidebarNode> build(
    List<SidebarMachineInput> machines,
    SidebarPrefs prefs,
  ) {
    final nodes = [for (final input in machines) _machine(input, prefs)];
    return SidebarPrefs.applyOrder(
      nodes,
      (node) => node.machineId,
      prefs.machineOrder,
    );
  }

  static SidebarNode _machine(SidebarMachineInput input, SidebarPrefs prefs) {
    final host = input.host;
    final id = host.id;
    final board = input.board;
    final claimed = <String>{};
    final children = <SidebarNode>[];

    for (final workspace in board?.workspaces ?? const <HomeBoardWorkspace>[]) {
      final open = input.openSessions
          .where((session) => session.herdrWorkspaceId == workspace.id)
          .toList();
      claimed.addAll(open.map((session) => session.sessionHostId));
      children.add(_herdrWorkspace(input, workspace, open.isNotEmpty));
    }
    for (final session in board?.tmuxSessions ?? const <TmuxSessionInfo>[]) {
      final open = input.openSessions
          .where((open) => open.tmuxSession == session.name)
          .toList();
      claimed.addAll(open.map((open) => open.sessionHostId));
      children.add(_tmuxSession(input, session, open));
    }
    for (final session in input.openSessions) {
      if (claimed.contains(session.sessionHostId)) continue;
      children.add(
        SidebarNode(
          key: SidebarKeys.openSession(id, session.sessionHostId),
          kind: SidebarNodeKind.openSession,
          machineId: id,
          label: _sessionLabel(session.title, host.name),
          detail: session.herdrWorkspaceId != null
              ? 'Herdr'
              : session.tmuxSession != null
              ? 'tmux'
              : 'Shell',
          dot: SidebarDot.of(session.agentState),
          multiplexer: session.herdrWorkspaceId != null
              ? MultiplexerKind.herdr
              : session.tmuxSession != null
              ? MultiplexerKind.tmux
              : null,
          openInApp: true,
          target: OpenSessionTarget(host, session.sessionHostId),
        ),
      );
    }

    final ordered = SidebarPrefs.applyOrder(
      children,
      (node) => node.key,
      prefs.childOrder[id] ?? const [],
    );
    var dot = SidebarDot.none;
    for (final child in ordered) {
      dot = dot.max(child.dot);
    }
    return SidebarNode(
      key: SidebarKeys.machine(id),
      kind: SidebarNodeKind.machine,
      machineId: id,
      label: host.name,
      detail: input.status,
      dot: dot,
      openInApp: input.openSessions.isNotEmpty,
      children: ordered,
      target: MachineTarget(host),
    );
  }

  /// "workstation: api" shows "api" under the workstation row.
  static String _sessionLabel(String title, String machineName) {
    final prefix = '$machineName: ';
    return title.startsWith(prefix) && title.length > prefix.length
        ? title.substring(prefix.length)
        : title;
  }

  static SidebarNode _herdrWorkspace(
    SidebarMachineInput input,
    HomeBoardWorkspace workspace,
    bool open,
  ) {
    final host = input.host;
    final id = host.id;
    // The companion knows Claude's own session names and exact states;
    // it wins over Herdr's view of the same pane.
    final companion = {
      for (final agent in input.agents)
        if (agent.workspace == workspace.id && (agent.pane ?? '').isNotEmpty)
          agent.pane!: agent,
    };
    final panes = <HomeBoardPane>[
      for (final pane in workspace.panes)
        switch (companion.remove(pane.agent.pane)) {
          final agent? => HomeBoardPane(
            agent: _withKind(agent, pane.agent.kind),
            tabLabel: pane.tabLabel,
          ),
          null => pane,
        },
      for (final agent in companion.values) HomeBoardPane(agent: agent),
    ];
    final merged = HomeBoardWorkspace(
      workspace: workspace.workspace,
      panes: panes,
    );

    SidebarNode paneNode(HomeBoardPane pane, String? tabId) {
      final agent = pane.agent;
      return SidebarNode(
        key: SidebarKeys.agentPane(
          id,
          workspace.id,
          tabId,
          agent.pane ?? agent.id,
        ),
        kind: SidebarNodeKind.agentPane,
        machineId: id,
        label: pane.title.isEmpty ? _agentName(agent.kind) : pane.title,
        detail: agent.state.label,
        dot: SidebarDot.of(agent.state),
        agentKind: agent.kind,
        target: AgentPaneTarget(host, merged, pane),
      );
    }

    final tabs = workspace.workspace.tabs;
    final children = <SidebarNode>[];
    final placed = <HomeBoardPane>{};
    for (final (index, tab) in tabs.indexed) {
      final inTab = [
        for (final pane in panes)
          if (pane.agent.tab == tab.id) pane,
      ];
      placed.addAll(inTab);
      var dot = SidebarDot.of(herdrStatusToState(tab.agentStatus));
      final paneNodes = [for (final pane in inTab) paneNode(pane, tab.id)];
      for (final node in paneNodes) {
        dot = dot.max(node.dot);
      }
      children.add(
        SidebarNode(
          key: SidebarKeys.herdrTab(id, workspace.id, tab.id),
          kind: SidebarNodeKind.herdrTab,
          machineId: id,
          label: tab.displayLabel(index + 1),
          // One agent: the tab row carries its title instead of a child.
          detail: inTab.length == 1 && inTab.single.title.isNotEmpty
              ? inTab.single.title
              : tab.summary,
          dot: dot,
          agentKind: inTab.isEmpty
              ? (tab.paneAgent.isEmpty ? null : tab.paneAgent)
              : inTab.first.agent.kind,
          children: paneNodes.length == 1 && inTab.length == 1
              // One agent in the tab: the tab row already says it all.
              ? const []
              : paneNodes,
          target: HerdrTabTarget(host, merged, tab),
        ),
      );
    }
    for (final pane in panes) {
      if (!placed.contains(pane)) children.add(paneNode(pane, null));
    }

    var dot = SidebarDot.of(merged.summary);
    for (final child in children) {
      dot = dot.max(child.dot);
    }
    final agentKinds = {for (final pane in panes) pane.agent.kind};
    return SidebarNode(
      key: SidebarKeys.herdrWorkspace(id, workspace.id),
      kind: SidebarNodeKind.herdrWorkspace,
      machineId: id,
      label: workspace.label,
      detail: _herdrDetail(merged),
      dot: dot,
      agentKind: agentKinds.length == 1 ? agentKinds.single : null,
      multiplexer: MultiplexerKind.herdr,
      openInApp: open,
      children: children,
      target: HerdrWorkspaceTarget(host, merged),
    );
  }

  /// [agent] with Herdr's [kind] when the companion did not name one.
  static AgentInfo _withKind(AgentInfo agent, String kind) =>
      agent.kind.isNotEmpty || kind.isEmpty
      ? agent
      : AgentInfo(
          id: agent.id,
          name: agent.name,
          state: agent.state,
          kind: kind,
          workspace: agent.workspace,
          tab: agent.tab,
          pane: agent.pane,
          stateChangedAt: agent.stateChangedAt,
          stateSequence: agent.stateSequence,
          pendingRequests: agent.pendingRequests,
          lastMessage: agent.lastMessage,
          project: agent.project,
          usage: agent.usage,
        );

  static String _herdrDetail(HomeBoardWorkspace workspace) {
    final tabs = workspace.workspace.tabCount;
    final agents = workspace.panes.length;
    return [
      if (tabs > 1) '$tabs tabs',
      if (agents == 1) '1 agent' else if (agents > 1) '$agents agents',
    ].join(' · ');
  }

  static String _agentName(String kind) =>
      kind.isEmpty ? 'Agent' : kind[0].toUpperCase() + kind.substring(1);

  static SidebarNode _tmuxSession(
    SidebarMachineInput input,
    TmuxSessionInfo session,
    List<SidebarOpenSession> open,
  ) {
    final host = input.host;
    final id = host.id;
    final name = session.name;
    AgentInfo? agentIn(bool Function(String tab) matches) {
      AgentInfo? best;
      for (final agent in input.agents) {
        final tab = agent.tab;
        if (tab == null || !matches(tab)) continue;
        if (best == null ||
            homeBoardPriority(agent.state) < homeBoardPriority(best.state)) {
          best = agent;
        }
      }
      return best;
    }

    final windows = input.tmuxWindows[name];
    final children = [
      for (final window in windows ?? const <TmuxWindowInfo>[])
        () {
          final agent = agentIn((tab) => tab == '$name:${window.index}');
          return SidebarNode(
            key: SidebarKeys.tmuxWindow(id, name, window.index),
            kind: SidebarNodeKind.tmuxWindow,
            machineId: id,
            label: '${window.index}: ${window.name}',
            detail: window.panes > 1 ? '${window.panes} panes' : '',
            dot: SidebarDot.of(agent?.state),
            agentKind: agent?.kind,
            target: TmuxWindowTarget(host, name, window),
          );
        }(),
    ];
    final agent = agentIn((tab) => tab == name || tab.startsWith('$name:'));
    var dot = SidebarDot.of(agent?.state);
    for (final session in open) {
      dot = dot.max(SidebarDot.of(session.agentState));
    }
    for (final child in children) {
      dot = dot.max(child.dot);
    }
    return SidebarNode(
      key: SidebarKeys.tmuxSession(id, name),
      kind: SidebarNodeKind.tmuxSession,
      machineId: id,
      label: name,
      detail: session.windows == 1 ? '1 window' : '${session.windows} windows',
      dot: dot,
      agentKind: agent?.kind,
      multiplexer: MultiplexerKind.tmux,
      openInApp: open.isNotEmpty,
      children: children,
      lazyChildren: windows == null && session.windows > 0,
      target: TmuxSessionTarget(host, session),
    );
  }

  /// [nodes] reduced to rows matching [query] (name or detail, any case)
  /// and their ancestors. A matching row keeps all its children.
  static List<SidebarNode> filter(List<SidebarNode> nodes, String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return nodes;
    SidebarNode? keep(SidebarNode node) {
      if (node.label.toLowerCase().contains(needle) ||
          node.detail.toLowerCase().contains(needle) ||
          (node.agentKind?.toLowerCase().contains(needle) ?? false)) {
        return node;
      }
      final children = [for (final child in node.children) ?keep(child)];
      return children.isEmpty ? null : node.copyWith(children: children);
    }

    return [for (final node in nodes) ?keep(node)];
  }

  /// The rows that need the user, deepest first: an agent pane rather than
  /// its workspace when the pane is the one waiting.
  static List<SidebarNode> needsYou(List<SidebarNode> machines) {
    final result = <SidebarNode>[];
    void walk(SidebarNode node) {
      if (node.dot != SidebarDot.needsYou) return;
      final deeper = node.children
          .where((child) => child.dot == SidebarDot.needsYou)
          .toList();
      if (deeper.isEmpty) {
        if (node.kind != SidebarNodeKind.machine) result.add(node);
        return;
      }
      deeper.forEach(walk);
    }

    machines.forEach(walk);
    return result;
  }

  /// Finds the row with [key] anywhere in [nodes].
  static SidebarNode? find(List<SidebarNode> nodes, String key) {
    for (final node in nodes) {
      if (!SidebarKeys.isUnder(key, node.key)) continue;
      if (node.key == key) return node;
      final found = find(node.children, key);
      if (found != null) return found;
    }
    return null;
  }
}
