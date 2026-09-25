import 'dart:async';

import 'package:conduit/features/voice/presentation/dictation_controller.dart';
import 'package:conduit/features/voice/presentation/dictation_text_inserter.dart';
import 'package:conduit/features/voice/presentation/voice_settings_scope.dart';
import 'package:flutter/material.dart';

/// The mic button: starts dictation into [textController], streams partial
/// transcripts into it, and stops on a second tap or at the end of speech.
///
/// Continuous dictation, its silence and length limits come from
/// Settings → Speech (via [VoiceSettingsScope]) unless the controller has
/// its own options. While listening the button pulses with the input
/// level; after a continuous session paused itself it reads "Paused, tap
/// to continue".
///
/// Several buttons may share one [DictationController] (composer sheet and
/// inline bar); only the button that started the session animates and can
/// stop it. Unmounting a button mid-session cancels its own session so the
/// recognizer never talks to a field that is gone.
class DictationButton extends StatefulWidget {
  const DictationButton({
    required this.controller,
    required this.textController,
    this.focusNode,
    this.enabled = true,
    this.onMessage,
    super.key,
  });

  final DictationController controller;
  final TextEditingController textController;
  final FocusNode? focusNode;
  final bool enabled;

  /// Receives error text to show near the field (the button has no room).
  final ValueChanged<String>? onMessage;

  @override
  State<DictationButton> createState() => _DictationButtonState();
}

class _DictationButtonState extends State<DictationButton> {
  late DictationTextInserter _inserter;
  late DictationSink _sink;
  String? _shownMessage;
  bool _lastSessionMine = false;

  @override
  void initState() {
    super.initState();
    _inserter = DictationTextInserter(widget.textController);
    _sink = DictationSink(
      onBegin: _inserter.begin,
      onPartial: _inserter.partial,
      onFinish: (text) {
        _inserter.finish(text);
        widget.focusNode?.requestFocus();
      },
      onCancel: () {
        _inserter.cancel();
        widget.focusNode?.requestFocus();
      },
    );
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(DictationButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.textController != widget.textController) {
      _inserter = DictationTextInserter(widget.textController);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    if (widget.controller.owns(_sink)) {
      unawaited(widget.controller.cancel());
    }
    super.dispose();
  }

  void _handleControllerChanged() {
    if (widget.controller.isActive) {
      _lastSessionMine = widget.controller.owns(_sink);
    }
    final message = widget.controller.message;
    if (message != null &&
        message != _shownMessage &&
        widget.controller.status == DictationStatus.idle) {
      _shownMessage = message;
      widget.onMessage?.call(message);
    }
    if (message == null) {
      _shownMessage = null;
    }
  }

  bool get _mine => widget.controller.owns(_sink);

  DictationOptions? _options() {
    if (widget.controller.options != null) {
      return null; // The controller's own options win.
    }
    final settings = VoiceSettingsScope.maybeOf(context);
    return settings == null
        ? null
        : DictationOptions.fromPreferences(settings.voice);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        if (!controller.isAvailable) {
          return const SizedBox.shrink();
        }
        final status = controller.status;
        final active = status != DictationStatus.idle;
        final busy =
            status == DictationStatus.starting ||
            status == DictationStatus.finishing ||
            status == DictationStatus.requestingPermission;
        final colorScheme = Theme.of(context).colorScheme;
        final String tooltip;
        final IconData icon;
        if (active && _mine) {
          tooltip = status == DictationStatus.listening
              ? 'Stop dictating'
              : 'Finishing…';
          icon = status == DictationStatus.listening
              ? Icons.stop_circle_rounded
              : Icons.mic_rounded;
        } else if (controller.pause != null && _lastSessionMine) {
          tooltip = 'Paused, tap to continue';
          icon = Icons.mic_rounded;
        } else if (controller.permissionDenied) {
          tooltip = 'Microphone access denied';
          icon = Icons.mic_off_rounded;
        } else {
          tooltip = 'Dictate';
          icon = Icons.mic_none_rounded;
        }
        final Widget child = busy && _mine
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.primary,
                ),
              )
            : Icon(
                icon,
                color: active && _mine
                    ? colorScheme.error
                    : controller.pause != null && _lastSessionMine
                    ? colorScheme.primary
                    : null,
              );
        final listening = status == DictationStatus.listening && _mine;
        final canTap =
            widget.enabled &&
            (!active || _mine) &&
            status != DictationStatus.requestingPermission;
        return IconButton(
          key: const ValueKey('dictation-button'),
          tooltip: tooltip,
          icon: listening
              ? _Pulse(level: controller.level, child: child)
              : child,
          onPressed: canTap
              ? () => unawaited(controller.toggle(_sink, options: _options()))
              : null,
        );
      },
    );
  }
}

/// A soft halo behind the stop icon that grows with the input level, so
/// the mic visibly "hears" the user. Each change animates briefly and
/// settles (no endless animation).
class _Pulse extends StatelessWidget {
  const _Pulse({required this.level, required this.child});

  final double level;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          key: const ValueKey('dictation-pulse'),
          duration: const Duration(milliseconds: 120),
          width: 24 + 16 * level,
          height: 24 + 16 * level,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.12 + 0.18 * level),
          ),
        ),
        child,
      ],
    );
  }
}
