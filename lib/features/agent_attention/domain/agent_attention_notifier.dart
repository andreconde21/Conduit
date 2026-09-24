/// Posts local "agent needs attention" notifications.
///
/// Content passed here must be lock-screen safe: agent labels, host names,
/// tool names and the one-line summary of a pending permission request —
/// never prompt contents, terminal output, or full tool inputs.
abstract class AgentAttentionNotifier {
  /// Shows (or replaces, for the same [id]) one notification.
  Future<void> show({
    required String id,
    required String title,
    required String body,
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
  });

  /// Removes the notification with [id], if it is still showing.
  Future<void> cancel({required String id});
}
