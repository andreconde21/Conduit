// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:conduit/features/agent_attention/presentation/agent_attention_controller.dart';
import 'package:conduit/features/home_widget/domain/agent_status_snapshot.dart';
import 'package:conduit/features/home_widget/domain/agent_status_widget_channel.dart';
import 'package:flutter/foundation.dart';

/// Keeps the native widget and tile in sync with the agent dashboard.
///
/// Pushes one snapshot on [start] and then at most one per [debounce]
/// window after the source changes (the dashboard notifies on every poll of
/// every host, so bursts are common). Pushes never overlap: a change that
/// arrives while a push is in flight schedules exactly one more.
class AgentStatusWidgetPusher {
  AgentStatusWidgetPusher({
    required Listenable source,
    required AgentStatusSnapshot Function() snapshot,
    required AgentStatusWidgetChannel channel,
    this.debounce = const Duration(milliseconds: 500),
  }) : _source = source,
       _snapshot = snapshot,
       _channel = channel;

  /// Wires the pusher to the live [AgentAttentionController].
  factory AgentStatusWidgetPusher.forController(
    AgentAttentionController controller, {
    required AgentStatusWidgetChannel channel,
    Duration debounce = const Duration(milliseconds: 500),
  }) {
    return AgentStatusWidgetPusher(
      source: controller,
      snapshot: () => snapshotOf(controller),
      channel: channel,
      debounce: debounce,
    );
  }

  final Listenable _source;
  final AgentStatusSnapshot Function() _snapshot;
  final AgentStatusWidgetChannel _channel;
  final Duration debounce;

  Timer? _timer;
  bool _pushing = false;
  bool _pushAgain = false;
  bool _started = false;
  bool _disposed = false;

  /// Builds the snapshot the widget shows for [controller]'s current state.
  static AgentStatusSnapshot snapshotOf(AgentAttentionController controller) {
    final hosts = controller.monitoredHosts;
    return AgentStatusSnapshot.build(
      hosts: [
        for (final host in hosts)
          (
            hostName: host.name,
            agents: controller.statusFor(host.id)?.agents ?? const [],
          ),
      ],
      monitoring: hosts.isNotEmpty,
      now: DateTime.now(),
    );
  }

  /// Pushes the current state immediately and starts listening for changes.
  void start() {
    if (_started || _disposed) {
      return;
    }
    _started = true;
    _source.addListener(_onChanged);
    unawaited(_push());
  }

  void _onChanged() {
    if (_disposed || _timer != null) {
      return;
    }
    _timer = Timer(debounce, () {
      _timer = null;
      unawaited(_push());
    });
  }

  Future<void> _push() async {
    if (_disposed) {
      return;
    }
    if (_pushing) {
      _pushAgain = true;
      return;
    }
    _pushing = true;
    try {
      do {
        _pushAgain = false;
        try {
          await _channel.push(_snapshot());
        } catch (_) {
          // The widget is best-effort; never let it break the dashboard.
        }
      } while (_pushAgain && !_disposed);
    } finally {
      _pushing = false;
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    if (_started) {
      _source.removeListener(_onChanged);
    }
  }
}
