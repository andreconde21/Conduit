import 'dart:async';

import 'package:conduit/features/agent_attention/domain/agent_permission_actions.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_controller.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:flutter/material.dart';

/// Completes Allow / Deny / Always taps made on permission notifications.
///
/// Mount it around the unlocked home page: queued taps are consumed when
/// this widget mounts (a tap that cold-started the app is answered once
/// the app is unlocked, never over the lock screen) and again whenever the
/// platform reports a new one while the app runs. Each tap is answered on
/// its host through [AgentAttentionController.completePermissionAction],
/// which also dismisses or rewrites the notification.
class AgentPermissionActionListener extends StatefulWidget {
  const AgentPermissionActionListener({
    required this.source,
    required this.agentAttention,
    required this.findHost,
    required this.child,
    super.key,
  });

  final AgentPermissionActionSource source;
  final AgentAttentionController agentAttention;

  /// Looks up a saved host by id (null when it was deleted meanwhile).
  final SavedHost? Function(String hostId) findHost;
  final Widget child;

  @override
  State<AgentPermissionActionListener> createState() =>
      _AgentPermissionActionListenerState();
}

class _AgentPermissionActionListenerState
    extends State<AgentPermissionActionListener> {
  bool _draining = false;
  bool _drainAgain = false;

  @override
  void initState() {
    super.initState();
    widget.source.setListener(_drain);
    _drain();
  }

  @override
  void didUpdateWidget(AgentPermissionActionListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      oldWidget.source.setListener(null);
      widget.source.setListener(_drain);
    }
  }

  @override
  void dispose() {
    widget.source.setListener(null);
    super.dispose();
  }

  /// Answers every queued tap in order; taps that arrive meanwhile are
  /// picked up by one more pass.
  void _drain() {
    if (_draining) {
      _drainAgain = true;
      return;
    }
    _draining = true;
    unawaited(() async {
      try {
        do {
          _drainAgain = false;
          final actions = await widget.source.consumeActions();
          for (final action in actions) {
            if (!mounted) {
              return;
            }
            await widget.agentAttention.completePermissionAction(
              action,
              widget.findHost(action.hostId),
            );
            _report(action);
          }
        } while (_drainAgain && mounted);
      } finally {
        _draining = false;
      }
    }());
  }

  void _report(AgentPermissionAction action) {
    if (!mounted) {
      return;
    }
    final host = widget.findHost(action.hostId);
    final verdict = switch (action.verdict) {
      'allow' => 'Allowed',
      'deny' => 'Denied',
      'always' => 'Always allowed',
      _ => 'Answered',
    };
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          '$verdict the permission request'
          '${host == null ? '' : ' on ${host.name}'}.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
