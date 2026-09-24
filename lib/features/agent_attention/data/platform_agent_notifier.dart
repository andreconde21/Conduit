import 'package:conduit/features/agent_attention/domain/agent_attention_notifier.dart';
import 'package:conduit/features/agent_attention/domain/agent_permission_actions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android implementation of agent notifications over a platform channel,
/// following the app's native-notification precedent (the background
/// keepalive service). Notification permission rides the existing
/// POST_NOTIFICATIONS request flow in `main.dart`.
///
/// On platforms without a native handler (currently iOS) every call is a
/// no-op; the dashboard itself works everywhere.
class PlatformAgentAttentionNotifier implements AgentAttentionNotifier {
  const PlatformAgentAttentionNotifier();

  static const channel = MethodChannel('conduit/agent_notifications');

  @override
  Future<void> show({
    required String id,
    required String title,
    required String body,
  }) {
    return _invoke('show', {'id': id, 'title': title, 'body': body});
  }

  @override
  Future<void> showPermissionRequest({
    required String id,
    required String title,
    required String body,
    required String hostId,
    required String requestId,
  }) {
    return _invoke('showPermissionRequest', {
      'id': id,
      'title': title,
      'body': body,
      'hostId': hostId,
      'requestId': requestId,
    });
  }

  @override
  Future<void> cancel({required String id}) => _invoke('cancel', {'id': id});

  Future<void> _invoke(String method, Map<String, Object?> arguments) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // No native handler registered (e.g. tests); notifications are
      // best-effort.
    } on PlatformException {
      // Notification permission may be denied; never let that break polling.
    }
  }
}

/// Receives Allow / Deny / Always taps from the Android notification
/// actions over the same channel. The native side queues each tap in
/// SharedPreferences (so a tap that started the app is delivered after
/// Dart is ready) and calls `permissionActionAvailable` while the engine
/// is alive.
class PlatformAgentPermissionActions implements AgentPermissionActionSource {
  PlatformAgentPermissionActions._();

  static final instance = PlatformAgentPermissionActions._();

  void Function()? _listener;
  bool _handlerInstalled = false;

  @override
  void setListener(void Function()? listener) {
    _listener = listener;
    if (!_handlerInstalled && defaultTargetPlatform == TargetPlatform.android) {
      _handlerInstalled = true;
      PlatformAgentAttentionNotifier.channel.setMethodCallHandler((call) async {
        if (call.method == 'permissionActionAvailable') {
          _listener?.call();
        }
      });
    }
  }

  @override
  Future<List<AgentPermissionAction>> consumeActions() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const [];
    }
    try {
      final raw = await PlatformAgentAttentionNotifier.channel
          .invokeMethod<List<Object?>>('consumePermissionActions');
      return parseActions(raw);
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  @visibleForTesting
  static List<AgentPermissionAction> parseActions(List<Object?>? raw) {
    if (raw == null) {
      return const [];
    }
    return [
      for (final item in raw)
        if (item is Map)
          if (item['hostId'] is String && item['requestId'] is String)
            AgentPermissionAction(
              notificationId: item['notificationId'] as String? ?? '',
              hostId: item['hostId'] as String,
              requestId: item['requestId'] as String,
              verdict: item['verdict'] as String? ?? '',
            ),
    ];
  }
}
