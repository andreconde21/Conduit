import 'dart:async';
import 'dart:io';

import 'package:conduit/core/app_failure.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:fido2/fido2_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Why a connection to a machine failed, in the terms the user can act on.
enum ConnectionProblemKind {
  /// The phone never got an SSH conversation going: no network route,
  /// DNS failure, refused or timed-out connect, a socket dropped before
  /// the handshake.
  unreachable,

  /// The machine answered but did not accept the saved sign-in (password,
  /// key, security key).
  authentication,

  /// The machine's host key was not trusted.
  hostKey,

  /// Connected, but the command (or anything else) failed; callers keep
  /// their own wording.
  commandFailed,
}

/// An [AppFailure] from opening a connection that remembers what kind of
/// failure it was, since [cause] is usually already flattened to text.
class ConnectionFailure extends AppFailure {
  const ConnectionFailure(super.message, super.cause, {required this.kind});

  final ConnectionProblemKind kind;
}

/// What to tell the user about a failed connection: a [title] headline, a
/// plain [message], and the raw technical [detail] to show secondary.
@immutable
class ConnectionProblem {
  const ConnectionProblem({
    required this.kind,
    required this.title,
    required this.message,
    this.detail,
  });

  final ConnectionProblemKind kind;
  final String title;
  final String message;
  final String? detail;
}

/// Sorts [error] into a [ConnectionProblemKind]. Looks through the wrappers
/// (AppFailure, dartssh2's abort and internal errors) at the error that
/// actually happened; text-only failures fall back to the phrases the
/// socket and SSH layers use.
ConnectionProblemKind classifyConnectionError(Object error) {
  var current = error;
  while (true) {
    if (current is ConnectionFailure) return current.kind;
    if (current is AppFailure) {
      final cause = current.cause;
      if (cause == null || cause is String) {
        // Only text is left: a plain AppFailure is the app's own wording
        // (a timed-out command, a failed listing), not a connect error.
        return ConnectionProblemKind.commandFailed;
      }
      current = cause;
      continue;
    }
    if (current is SSHAuthAbortError && current.reason != null) {
      current = current.reason!;
      continue;
    }
    if (current is SSHInternalError) {
      current = current.error;
      continue;
    }
    break;
  }
  return switch (current) {
    SocketException() || SSHSocketError() => ConnectionProblemKind.unreachable,
    SSHHostkeyError() => ConnectionProblemKind.hostKey,
    SSHAuthFailError() ||
    SSHSecurityKeyNotPresentError() ||
    SSHKeyDecodeError() ||
    CtapError() ||
    PlatformException() => ConnectionProblemKind.authentication,
    TimeoutException() => ConnectionProblemKind.unreachable,
    String() => classifyConnectionErrorText(current),
    _ => ConnectionProblemKind.commandFailed,
  };
}

final _unreachablePattern = RegExp(
  'SocketException|SSHSocketError|Failed host lookup|'
  'No address associated with hostname|nodename nor servname|'
  'Name or service not known|Network is unreachable|No route to host|'
  'Host is down|Connection refused|Connection timed out|'
  'Connection reset by peer|Software caused connection abort',
  caseSensitive: false,
);

final _hostKeyPattern = RegExp(
  'SSHHostkeyError|Hostkey verification failed|host key',
  caseSensitive: false,
);

final _authPattern = RegExp(
  'SSHAuthFailError|rejected the configured credentials|'
  'All authentication methods failed',
  caseSensitive: false,
);

/// [classifyConnectionError] for a message that is only text (an error
/// flattened by `describeSshConnectionError` or `toString`). Use it only
/// on connection errors: a command's own stderr can say "connection
/// refused" about something else.
ConnectionProblemKind classifyConnectionErrorText(String text) {
  if (_hostKeyPattern.hasMatch(text)) return ConnectionProblemKind.hostKey;
  if (_authPattern.hasMatch(text)) return ConnectionProblemKind.authentication;
  if (_unreachablePattern.hasMatch(text)) {
    return ConnectionProblemKind.unreachable;
  }
  return ConnectionProblemKind.commandFailed;
}

/// Whether [host] (as saved: a name, IPv4 or IPv6 address) is on a
/// Tailscale network: 100.64.0.0/10, fd7a:115c:a1e0::/48 or a MagicDNS
/// `*.ts.net` name.
bool isTailscaleAddress(String host) {
  var value = host.trim().toLowerCase();
  if (value.startsWith('[') && value.endsWith(']')) {
    value = value.substring(1, value.length - 1);
  }
  final zone = value.indexOf('%');
  if (zone >= 0) value = value.substring(0, zone);
  if (value.endsWith('.')) value = value.substring(0, value.length - 1);
  final address = InternetAddress.tryParse(value);
  if (address == null) {
    return value.endsWith('.ts.net');
  }
  final bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    return bytes[0] == 100 && (bytes[1] & 0xC0) == 64;
  }
  if (address.type == InternetAddressType.IPv6) {
    const prefix = [0xfd, 0x7a, 0x11, 0x5c, 0xa1, 0xe0];
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }
  return false;
}

/// The technical reason behind [error], for a secondary "Details" line.
String connectionErrorDetail(Object error) {
  if (error is AppFailure) {
    final cause = error.cause;
    if (cause is String && cause.trim().isNotEmpty) return cause.trim();
    if (cause != null) return '$cause';
    return error.message;
  }
  return '$error';
}

/// What to tell the user about [error] while connecting to [machine]
/// (its label) at [address], or null when it is a command failure the
/// caller words itself. [retryLabel] names the button that tries again;
/// null when there is none (the advice then says "try again").
ConnectionProblem? connectionProblemFor(
  Object error, {
  required String machine,
  required String address,
  String? retryLabel = 'Retry',
}) {
  return connectionProblemOfKind(
    classifyConnectionError(error),
    machine: machine,
    address: address,
    detail: connectionErrorDetail(error),
    retryLabel: retryLabel,
  );
}

/// [connectionProblemFor] when the kind is already known (say, stored
/// with a board state) and only the text [detail] is left.
ConnectionProblem? connectionProblemOfKind(
  ConnectionProblemKind kind, {
  required String machine,
  required String address,
  String? detail,
  String? retryLabel = 'Retry',
}) {
  final name = machine.trim().isEmpty ? address : machine.trim();
  final text = detail?.trim();
  final shownDetail = text == null || text.isEmpty ? null : text;
  switch (kind) {
    case ConnectionProblemKind.unreachable:
      return ConnectionProblem(
        kind: kind,
        title: "Can't reach $name",
        message: isTailscaleAddress(address)
            ? 'This machine is on your Tailscale network. Check that '
                  'Tailscale is on, then '
                  '${retryLabel == null ? 'try again' : 'tap $retryLabel'}.'
            : "Your device couldn't connect to ${address.trim()}. "
                  'Check your network.',
        detail: shownDetail,
      );
    case ConnectionProblemKind.authentication:
      return ConnectionProblem(
        kind: kind,
        title: 'Sign-in to $name failed',
        message:
            'The machine answered but did not accept the saved sign-in. '
            'Check the user name and the key or password saved for it.',
        detail: shownDetail,
      );
    case ConnectionProblemKind.hostKey:
      return ConnectionProblem(
        kind: kind,
        title: 'Sign-in to $name failed',
        message:
            "The machine's host key was not trusted, so the connection "
            'stopped. If it was reinstalled, forget its old key in '
            'Settings › Trusted host keys and connect again.',
        detail: shownDetail,
      );
    case ConnectionProblemKind.commandFailed:
      return null;
  }
}
