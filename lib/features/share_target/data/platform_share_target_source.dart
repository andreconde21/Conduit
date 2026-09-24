import 'dart:async';

import 'package:conduit/features/share_target/domain/share_target_source.dart';
import 'package:conduit/features/share_target/domain/shared_payload.dart';
import 'package:flutter/services.dart';

/// Android implementation over the `conduit/share_target` method channel
/// (see ShareTargetBridge.kt). The native side queues payloads; a
/// `sharedContentAvailable` call nudges Dart to drain the queue.
class PlatformShareTargetSource implements ShareTargetSource {
  PlatformShareTargetSource({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('conduit/share_target') {
    _channel.setMethodCallHandler(_handleCall);
  }

  final MethodChannel _channel;
  final _controller = StreamController<SharedPayload>.broadcast();

  @override
  Stream<SharedPayload> get shares => _controller.stream;

  @override
  Future<List<SharedPayload>> takePending() async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('takePending');
      return (raw ?? const [])
          .map(SharedPayload.fromMap)
          .whereType<SharedPayload>()
          .toList();
    } on MissingPluginException {
      return const [];
    }
  }

  Future<Object?> _handleCall(MethodCall call) async {
    if (call.method == 'sharedContentAvailable') {
      for (final payload in await takePending()) {
        _controller.add(payload);
      }
    }
    return null;
  }
}
