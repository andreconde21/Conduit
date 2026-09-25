/// Where tapping a notification's body takes the app: one agent on one
/// host, with its Herdr location when the provider reports it.
class AgentOpenTarget {
  const AgentOpenTarget({
    required this.hostId,
    this.agentId = '',
    this.workspaceId = '',
    this.tabId = '',
    this.paneId = '',
  });

  final String hostId;
  final String agentId;
  final String workspaceId;
  final String tabId;
  final String paneId;

  /// Channel arguments (`openHostId`, ...) for the platform notifier.
  Map<String, String> toArguments() => {
    'openHostId': hostId,
    'openAgentId': agentId,
    'openWorkspaceId': workspaceId,
    'openTabId': tabId,
    'openPaneId': paneId,
  };

  /// Reads the map the platform hands back after a tap; null without a
  /// host.
  static AgentOpenTarget? fromMap(Object? map) {
    if (map is! Map) {
      return null;
    }
    String field(String key) {
      final value = map[key];
      return value is String ? value : '';
    }

    final hostId = field('hostId');
    if (hostId.isEmpty) {
      return null;
    }
    return AgentOpenTarget(
      hostId: hostId,
      agentId: field('agentId'),
      workspaceId: field('workspaceId'),
      tabId: field('tabId'),
      paneId: field('paneId'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AgentOpenTarget &&
      other.hostId == hostId &&
      other.agentId == agentId &&
      other.workspaceId == workspaceId &&
      other.tabId == tabId &&
      other.paneId == paneId;

  @override
  int get hashCode => Object.hash(hostId, agentId, workspaceId, tabId, paneId);

  @override
  String toString() =>
      'AgentOpenTarget($hostId, $workspaceId, $tabId, $paneId)';
}

/// Posts local "agent needs attention" notifications.
///
/// Titles must be lock-screen safe (agent labels, host names, tool
/// names). Bodies may carry the agent's last message and the one-line
/// summary of a pending permission request, so the platform shows only the
/// title on a secure lock screen; never pass terminal output or full tool
/// inputs.
abstract class AgentAttentionNotifier {
  /// Shows (or replaces, for the same [id]) one notification. Tapping it
  /// opens the app at [open] when given.
  Future<void> show({
    required String id,
    required String title,
    required String body,
    AgentOpenTarget? open,
  });

  /// Shows (or replaces, for the same [id]) one notification with
  /// Allow / Deny / Always actions for a pending permission request. The
  /// platform reports the tapped action back through the app's permission
  /// action source with [hostId] and [requestId].
  Future<void> showPermissionRequest({
    required String id,
    required String title,
    required String body,
    required String hostId,
    required String requestId,
    AgentOpenTarget? open,
  });

  /// Removes the notification with [id], if it is still showing.
  Future<void> cancel({required String id});
}

/// Delivers notification taps that should open an agent.
abstract class AgentOpenRequestSource {
  /// Takes the pending tap, if any.
  Future<AgentOpenTarget?> consume();

  /// Called when a tap arrives while the app runs; the listener then calls
  /// [consume].
  void setListener(void Function()? listener);
}
