import 'dart:async';

import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';

/// How long an orphaned mosh-server (its client gone, e.g. after a Herdr
/// detach) waits before exiting on its own: 7 days. mosh-server's default
/// is to wait forever.
const moshServerNetworkTimeout = Duration(days: 7);

/// Prefix for the `mosh-server new` bootstrap that gives the server the
/// [moshServerNetworkTimeout] (mosh-server reads it from its environment).
String get moshServerTimeoutEnv =>
    'MOSH_SERVER_NETWORK_TMOUT=${moshServerNetworkTimeout.inSeconds}';

/// The mosh-server a session started, as far as the bootstrap told us.
class MoshServerHandle {
  const MoshServerHandle({required this.port, this.pid, this.portArgument});

  /// The UDP port it listens on (from `MOSH CONNECT <port> <key>`).
  final int port;

  /// Its pid, from `[mosh-server detached, pid = N]`; null when missing.
  final int? pid;

  /// The `-p` argument the bootstrap passed (`60001` or `60001:60999`).
  final String? portArgument;

  static final _pidPattern = RegExp(r'mosh-server detached, pid = (\d+)');

  /// Reads the pid from the bootstrap's combined stdout and stderr.
  static int? parsePid(String bootstrapOutput) {
    final match = _pidPattern.firstMatch(bootstrapOutput);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// The shell command that stops exactly this server, or null when it
  /// cannot be identified safely.
  ///
  /// With the pid: kill it only if that pid is still a mosh-server (pids
  /// are reused). Without it: `pkill` on the user's `mosh-server new`
  /// processes whose `-p` names this port alone (a port range does not say
  /// which server got which port, so nothing is killed then).
  String? killCommand() {
    final pid = this.pid;
    if (pid != null) {
      return 'pid=$pid; '
          '[ "\$(ps -o comm= -p "\$pid" 2>/dev/null)" = mosh-server ] '
          '&& kill "\$pid"';
    }
    if (portArgument == '$port') {
      return 'pkill -u "\$(id -un)" -f '
          "'^([^ ]*/)?mosh-server new .*-p $port( |\$)'";
    }
    return null;
  }
}

/// A session whose remote server can be stopped over a separate command
/// channel after its transport closed.
abstract interface class ReapableTerminalSession {
  /// Stops the remote server; best effort, never throws.
  Future<void> reapServer();
}

/// Runs [handle]'s kill command over a runner from [runnerFactory], then
/// closes the runner. Best effort: every failure is swallowed.
Future<void> reapMoshServer(
  MoshServerHandle handle,
  AgentCommandRunner Function() runnerFactory, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final command = handle.killCommand();
  if (command == null) {
    return;
  }
  AgentCommandRunner? runner;
  try {
    runner = runnerFactory();
    await runner.run(command, timeout: timeout);
  } catch (_) {
    // The server may already be gone, or the machine unreachable.
  } finally {
    try {
      await runner?.close();
    } catch (_) {}
  }
}
