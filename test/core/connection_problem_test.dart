import 'dart:async';
import 'dart:io';

import 'package:conduit/core/app_failure.dart';
import 'package:conduit/core/connection_problem.dart';
import 'package:conduit/features/terminal/data/ssh_error_formatter.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

const _unreachable = ConnectionProblemKind.unreachable;
const _auth = ConnectionProblemKind.authentication;
const _hostKey = ConnectionProblemKind.hostKey;
const _command = ConnectionProblemKind.commandFailed;

SocketException _socket(String message, String os, int errno) =>
    SocketException(
      message,
      osError: OSError(os, errno),
      address: InternetAddress('100.101.102.103'),
      port: 22,
    );

void main() {
  group('classifyConnectionError', () {
    final timedOut = _socket(
      'Connection timed out',
      'Connection timed out',
      110,
    );
    const lookup = SocketException(
      "Failed host lookup: 'devbox.tail574592.ts.net'",
      osError: OSError('No address associated with hostname', 7),
    );
    final unreachableNetwork = _socket(
      'Connection failed',
      'Network is unreachable',
      101,
    );
    final noRoute = _socket('Connection failed', 'No route to host', 113);
    final refused = _socket('Connection refused', 'Connection refused', 111);

    test('socket errors before the handshake are unreachable', () {
      for (final error in [
        timedOut,
        lookup,
        unreachableNetwork,
        noRoute,
        refused,
      ]) {
        expect(classifyConnectionError(error), _unreachable, reason: '$error');
      }
      expect(
        classifyConnectionError(TimeoutException('connect')),
        _unreachable,
      );
    });

    test('looks through AppFailure and dartssh2 wrappers', () {
      expect(
        classifyConnectionError(AppFailure('Could not connect.', timedOut)),
        _unreachable,
      );
      expect(
        classifyConnectionError(
          SSHAuthAbortError(
            'Connection closed before authentication',
            SSHSocketError(const SocketException('Connection reset by peer')),
          ),
        ),
        _unreachable,
      );
      expect(
        classifyConnectionError(
          SSHAuthAbortError(
            'Connection closed before authentication',
            SSHHostkeyError('Hostkey verification failed'),
          ),
        ),
        _hostKey,
      );
      expect(
        classifyConnectionError(SSHInternalError(SSHSocketError(noRoute))),
        _unreachable,
      );
    });

    test('rejected credentials are an authentication problem', () {
      expect(
        classifyConnectionError(
          SSHAuthFailError('All authentication methods failed'),
        ),
        _auth,
      );
      expect(
        classifyConnectionError(SSHKeyDecryptError('bad passphrase')),
        _auth,
      );
      expect(
        classifyConnectionError(
          SSHSecurityKeyNotPresentError('not on this key'),
        ),
        _auth,
      );
    });

    test('a ConnectionFailure keeps the kind its origin found', () {
      const failure = ConnectionFailure(
        'Could not reach box.',
        'SSH server rejected the configured credentials.',
        kind: _auth,
      );
      expect(classifyConnectionError(failure), _auth);
      expect(
        classifyConnectionError(const AppFailure('Outer.', failure)),
        _auth,
      );
    });

    test('the app\'s own failures and other errors keep their wording', () {
      expect(
        classifyConnectionError(const AppFailure('The command timed out.')),
        _command,
      );
      // A command's stderr is text: never read as a connect error.
      expect(
        classifyConnectionError(
          const AppFailure('herdr failed', 'connection refused'),
        ),
        _command,
      );
      expect(
        classifyConnectionError(StateError('connection refused')),
        _command,
      );
      expect(
        classifyConnectionError(SSHChannelOpenError(2, 'open failed')),
        _command,
      );
    });

    test('a real refused connect is unreachable', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close();
      Object? error;
      try {
        await Socket.connect(InternetAddress.loopbackIPv4, port);
      } catch (e) {
        error = e;
      }
      expect(error, isA<SocketException>());
      expect(classifyConnectionError(error!), _unreachable);
    });
  });

  group('classifyConnectionErrorText', () {
    test('reads the text describeSshConnectionError produces', () {
      String text(Object error) => describeSshConnectionError(error);
      expect(
        classifyConnectionErrorText(
          text(_socket('Connection timed out', 'Connection timed out', 110)),
        ),
        _unreachable,
      );
      expect(
        classifyConnectionErrorText(
          text(
            const SocketException(
              "Failed host lookup: 'box'",
              osError: OSError('No address associated with hostname', 7),
            ),
          ),
        ),
        _unreachable,
      );
      expect(
        classifyConnectionErrorText(
          text(SSHAuthFailError('All authentication methods failed')),
        ),
        _auth,
      );
      expect(
        classifyConnectionErrorText(
          text(SSHHostkeyError('Hostkey verification failed')),
        ),
        _hostKey,
      );
      expect(classifyConnectionErrorText('exit status 2'), _command);
      expect(classifyConnectionError('No route to host'), _unreachable);
    });
  });

  group('isTailscaleAddress', () {
    test('matches the CGNAT range, the ULA prefix and MagicDNS names', () {
      for (final host in [
        '100.64.0.1',
        '100.101.102.103',
        '100.127.255.255',
        ' 100.100.100.100 ',
        'fd7a:115c:a1e0::1',
        'FD7A:115C:A1E0:ab12:4843:cd96:6258:b240',
        '[fd7a:115c:a1e0::53]',
        'development-central.tail574592.ts.net',
        'Box.Tail574592.TS.NET.',
      ]) {
        expect(isTailscaleAddress(host), isTrue, reason: host);
      }
    });

    test('leaves other addresses alone', () {
      for (final host in [
        '100.63.255.255',
        '100.128.0.1',
        '10.0.0.5',
        '192.168.1.20',
        '65.108.142.178',
        'fd7a:115c:a1e1::1',
        'fd00::1',
        '::1',
        'devbox',
        'example.com',
        'ts.net.example.com',
        '',
      ]) {
        expect(isTailscaleAddress(host), isFalse, reason: host);
      }
    });
  });

  group('connectionProblemFor', () {
    final timedOut = _socket(
      'Connection timed out',
      'Connection timed out',
      110,
    );

    test('a Tailscale machine that is not reached says to check Tailscale', () {
      final problem = connectionProblemFor(
        AppFailure('Could not reach dev.', timedOut),
        machine: 'dev-central',
        address: '100.106.7.32',
      )!;
      expect(problem.kind, _unreachable);
      expect(problem.title, "Can't reach dev-central");
      expect(
        problem.message,
        'This machine is on your Tailscale network. Check that Tailscale '
        'is on, then tap Retry.',
      );
      expect(problem.detail, contains('Connection timed out'));
    });

    test('another unreachable machine names its address', () {
      final problem = connectionProblemFor(
        timedOut,
        machine: 'web',
        address: '203.0.113.9',
        retryLabel: 'Reconnect',
      )!;
      expect(problem.title, "Can't reach web");
      expect(
        problem.message,
        "Your device couldn't connect to 203.0.113.9. Check your network.",
      );
    });

    test('without a retry button the advice says try again', () {
      final problem = connectionProblemFor(
        timedOut,
        machine: 'dev',
        address: 'dev.tail574592.ts.net',
        retryLabel: null,
      )!;
      expect(problem.message, endsWith('Tailscale is on, then try again.'));
    });

    test('sign-in and host-key failures say so plainly', () {
      final auth = connectionProblemFor(
        const ConnectionFailure(
          'Running a command on dev failed.',
          'SSH server rejected the configured credentials.',
          kind: _auth,
        ),
        machine: 'dev',
        address: '100.106.7.32',
      )!;
      expect(auth.title, 'Sign-in to dev failed');
      expect(auth.detail, 'SSH server rejected the configured credentials.');
      final hostKey = connectionProblemFor(
        SSHHostkeyError('Hostkey verification failed'),
        machine: 'dev',
        address: 'dev',
      )!;
      expect(hostKey.title, 'Sign-in to dev failed');
      expect(hostKey.message, contains('host key was not trusted'));
    });

    test('a failed command is left to the caller', () {
      expect(
        connectionProblemFor(
          const AppFailure('The command timed out.'),
          machine: 'dev',
          address: '100.106.7.32',
        ),
        isNull,
      );
    });
  });
}
