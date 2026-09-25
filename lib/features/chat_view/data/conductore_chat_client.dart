import 'dart:convert';

import 'package:conduit/core/app_failure.dart';
import 'package:conduit/features/agent_attention/data/conductore_host_attention_provider.dart';
import 'package:conduit/features/agent_attention/data/remote_tool_command.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/chat_view/domain/chat_transcript.dart';

/// Thrown when the host's companion is missing, or too old to know the
/// chat commands.
class ChatUnsupported implements Exception {
  const ChatUnsupported(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The chat view's side of the companion contract (`host/README.md`):
/// `transcript`, `send` and `interrupt`, each run over an exec channel
/// through the same PATH wrapper as the attention provider.
class ConductoreChatClient {
  const ConductoreChatClient(this._runner);

  final AgentCommandRunner _runner;

  static const _timeout = Duration(seconds: 15);

  /// How much of a long transcript the first load reads.
  static const defaultTailBytes = 256 * 1024;

  static const installHint =
      'Install the Conductore companion on this machine: run host/install.sh '
      'from the Conductore Mobile repository there, then check with '
      '"conductore-hostd doctor".';

  static String transcriptCommand(
    String sessionId, {
    int? since,
    int? before,
    int? tailBytes,
    int? maxBytes,
  }) {
    final args = [
      'transcript',
      shellQuoteArgument(sessionId),
      if (since != null) '--since $since',
      if (before != null) '--before $before',
      if (tailBytes != null) '--tail-bytes $tailBytes',
      if (maxBytes != null) '--max-bytes $maxBytes',
    ];
    return ConductoreHostAttentionProvider.remoteCommand(args.join(' '));
  }

  /// The text travels base64-encoded so no quoting, newline or length quirk
  /// of the exec channel's shell can alter it.
  static String sendCommand(
    String sessionId,
    String text, {
    bool enter = true,
  }) {
    final encoded = base64.encode(utf8.encode(text));
    return ConductoreHostAttentionProvider.remoteCommand(
      'send ${shellQuoteArgument(sessionId)} --text-b64 $encoded'
      '${enter ? '' : ' --no-enter'}',
    );
  }

  static String interruptCommand(String sessionId) =>
      ConductoreHostAttentionProvider.remoteCommand(
        'interrupt ${shellQuoteArgument(sessionId)}',
      );

  Future<TranscriptPage> transcript(
    String sessionId, {
    int? since,
    int? before,
    int? tailBytes,
    int? maxBytes,
  }) async {
    final result = await _runner.run(
      transcriptCommand(
        sessionId,
        since: since,
        before: before,
        tailBytes: tailBytes,
        maxBytes: maxBytes,
      ),
      timeout: _timeout,
    );
    _check(result);
    try {
      return TranscriptParser.parsePage(result.stdout);
    } on FormatException {
      throw const AppFailure(
        'The Conductore companion returned a transcript in an unexpected '
        'shape.',
      );
    }
  }

  Future<void> send(String sessionId, String text, {bool enter = true}) async {
    final result = await _runner.run(
      sendCommand(sessionId, text, enter: enter),
      timeout: _timeout,
    );
    _check(result);
  }

  Future<void> interrupt(String sessionId) async {
    final result = await _runner.run(
      interruptCommand(sessionId),
      timeout: _timeout,
    );
    _check(result);
  }

  static void _check(AgentCommandResult result) {
    final stderr = result.stderr.trim();
    if (result.exitCode == 127 ||
        stderr.contains('command not found') ||
        stderr.contains('conductore-hostd: not found')) {
      throw const ChatUnsupported(
        'The Conductore companion is not installed on this machine. '
        '$installHint',
      );
    }
    if (result.exitCode != null && result.exitCode != 0) {
      final failure = ConductoreHostAttentionProvider.failureFrom(
        result.stdout,
        stderr,
      );
      final cause = failure.cause;
      if (cause is String && cause.startsWith('unknown command')) {
        throw const ChatUnsupported(
          'The Conductore companion on this machine is too old for the chat '
          'view. Update it by running host/install.sh again.',
        );
      }
      throw failure;
    }
  }
}
