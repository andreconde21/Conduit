import 'package:conduit/core/app_failure.dart';
import 'package:conduit/core/connection_problem.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/terminal/domain/ssh_terminal_repository.dart';
import 'package:conduit/features/terminal/domain/ssh_terminal_session.dart';
import 'package:conduit/features/terminal/presentation/terminal_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

class _FailingRepository implements SshTerminalRepository {
  _FailingRepository(this.error);

  final Object error;

  @override
  Future<SshTerminalSession> connect(
    SavedHost host, {
    required int columns,
    required int rows,
  }) async {
    // ignore: only_throw_errors
    throw error;
  }
}

Future<String> _failWith(
  Object error, {
  String address = '100.106.7.32',
}) async {
  final controller = TerminalSessionController(
    host: buildHost('dev').copyWith(host: address),
    repository: _FailingRepository(error),
  );
  addTearDown(controller.dispose);
  await controller.connect();
  expect(controller.status, TerminalConnectionStatus.failed);
  final buffer = controller.terminal.buffer;
  return [
    for (var i = 0; i < buffer.lines.length; i++)
      buffer.lines[i].toString().trimRight(),
  ].where((line) => line.isNotEmpty).join('\n');
}

void main() {
  test('an unreachable machine gets the shared headline and advice', () async {
    final text = await _failWith(
      const ConnectionFailure(
        'Could not connect to 100.106.7.32:22.',
        'SocketException: Connection timed out',
        kind: ConnectionProblemKind.unreachable,
      ),
    );
    expect(text, contains("Can't reach Host dev"));
    expect(text, contains('Check that Tailscale is on, then tap'));
    expect(text, contains('Reconnect.'));
    expect(text, contains('SocketException: Connection timed out'));
  });

  test('a rejected sign-in says so', () async {
    final text = await _failWith(
      const ConnectionFailure(
        'Could not connect to web:22.',
        'SSH server rejected the configured credentials.',
        kind: ConnectionProblemKind.authentication,
      ),
      address: 'web',
    );
    expect(text, contains('Sign-in to Host dev failed'));
    expect(text, contains('rejected the configured credentials'));
  });

  test('other failures keep their own text', () async {
    final text = await _failWith(
      const AppFailure('Timed out waiting for mosh-server startup.'),
    );
    expect(text, contains('Timed out waiting for mosh-server startup.'));
    expect(text, isNot(contains("Can't reach")));
  });
}
