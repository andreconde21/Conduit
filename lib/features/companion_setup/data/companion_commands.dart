import 'package:conduit/features/agent_attention/data/remote_tool_command.dart';

/// Shell commands the Agent hooks screen runs over the SSH exec channel.
///
/// Everything goes through `sh -c` with the usual user-local directories on
/// PATH (see [remoteToolCommand]): the companion links itself into
/// `~/.local/bin`, which a non-interactive SSH shell rarely has.
abstract final class CompanionCommands {
  static const hostd = 'conductore-hostd';
  static const hook = 'conductore-hook';

  /// Session id of the synthetic agent "Send test event" creates.
  static const testSessionId = 'conductore-test';

  static String hostdCommand(String args) => remoteToolCommand(hostd, args);

  static final version = hostdCommand('version');
  static final doctor = hostdCommand('doctor');
  static final status = hostdCommand('status');
  static final stop = hostdCommand('stop');
  static final node = remoteToolCommand('node', '--version');
  static final claude = remoteToolCommand('claude', '--version');

  /// Runs [script] under `sh` with the extended PATH exported.
  static String script(String script) {
    final inner =
        'PATH="${remoteToolExtraPathDirs.join(':')}:\$PATH"; export PATH; '
        '$script';
    return "sh -c '${inner.replaceAll("'", "'\\''")}'";
  }

  /// `mkdir -p` for the upload directories.
  static String makeDirectories(Iterable<String> paths) =>
      script('mkdir -p ${paths.map(shellQuoteArgument).join(' ')}');

  /// Runs the uploaded `install.sh` (optionally with `--uninstall`).
  static String runInstaller(String directory, {bool uninstall = false}) =>
      remoteToolCommand(
        'sh',
        '${shellQuoteArgument('$directory/install.sh')}'
            '${uninstall ? ' --uninstall' : ''}',
      );

  /// Feeds the hook client a Notification and then a SessionEnd for
  /// [testSessionId], exactly as Claude Code would (JSON on stdin, event
  /// name as the only argument; see host/bin/conductore-hook). The hook only
  /// spools the event; the `status` that follows applies it, starting the
  /// daemon if needed. The SessionEnd makes
  /// the daemon prune the test agent an hour later instead of keeping it.
  static final sendTestEvent = script(
    'printf "%s\\n" '
    '"{\\"session_id\\":\\"$testSessionId\\",'
    '\\"hook_event_name\\":\\"Notification\\",'
    '\\"message\\":\\"Test from Conductore\\",'
    '\\"cwd\\":\\"\$HOME\\"}" | $hook Notification && '
    'printf "%s\\n" '
    '"{\\"session_id\\":\\"$testSessionId\\",'
    '\\"hook_event_name\\":\\"SessionEnd\\",'
    '\\"reason\\":\\"other\\",'
    '\\"cwd\\":\\"\$HOME\\"}" | $hook SessionEnd',
  );
}
