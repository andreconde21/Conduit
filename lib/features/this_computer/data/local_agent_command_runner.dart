import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conduit/core/app_failure.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/this_computer/domain/local_shell_launch.dart';

/// Runs agent, listing and git commands on the desktop itself: the
/// [AgentCommandRunner] of "This computer".
///
/// The commands are the POSIX shell strings the SSH runner sends to a
/// remote exec channel, so they run the same way here: `sh -c <command>`
/// with the tool directories put on PATH ([localCommandEnvironment]). On
/// Windows they run inside WSL (`wsl.exe -e sh -c`), where tmux and Herdr
/// live, and only when "This computer" uses the WSL shell.
class LocalAgentCommandRunner implements StdinAgentCommandRunner {
  LocalAgentCommandRunner({
    LocalOs? os,
    this._environment,
    this._windowsShell,
    this.shell = '/bin/sh',
  }) : _os = os ?? currentLocalOs();

  final LocalOs _os;
  final Map<String, String>? _environment;
  final WindowsShellKind Function()? _windowsShell;

  /// The POSIX shell commands run under on Linux and macOS.
  final String shell;

  final Set<Process> _running = {};
  bool _closed = false;

  /// The program and arguments [command] runs as.
  (String, List<String>) invocation(String command) {
    if (_os == LocalOs.windows) {
      return ('wsl.exe', ['-e', 'sh', '-c', command]);
    }
    return (shell, ['-c', command]);
  }

  @override
  Future<AgentCommandResult> run(String command, {required Duration timeout}) =>
      _run(command, timeout: timeout);

  @override
  Future<AgentCommandResult> runWithStdin(
    String command, {
    required String stdin,
    required Duration timeout,
    Future<void>? cancel,
  }) => _run(command, timeout: timeout, stdin: stdin, cancel: cancel);

  Future<AgentCommandResult> _run(
    String command, {
    required Duration timeout,
    String? stdin,
    Future<void>? cancel,
  }) async {
    if (_closed) {
      throw const AppFailure('This connection is closed.');
    }
    if (_os == LocalOs.windows &&
        (_windowsShell?.call() ?? WindowsShellKind.powershell) !=
            WindowsShellKind.wsl) {
      throw const AppFailure(
        'tmux, Herdr and the companion run inside WSL on Windows.',
        'Choose WSL as the shell of This computer to use them.',
      );
    }
    final (executable, arguments) = invocation(command);
    final Process process;
    try {
      process = await Process.start(
        executable,
        arguments,
        // WSL brings its own PATH; Windows' own uses `;` separators.
        environment: _os == LocalOs.windows
            ? (_environment ?? Platform.environment)
            : localCommandEnvironment(_environment ?? Platform.environment),
        includeParentEnvironment: false,
        workingDirectory: _home,
      );
    } on ProcessException catch (error) {
      throw AppFailure('Could not run a command on this computer.', error);
    }
    _running.add(process);
    // Without input a command waiting on stdin must see end of file, like
    // an SSH exec channel without a PTY.
    if (stdin != null) process.stdin.add(utf8.encode(stdin));
    unawaited(process.stdin.close().catchError((_) {}));
    var cancelled = false;
    unawaited(
      cancel?.then((_) {
        if (!_running.contains(process)) return;
        cancelled = true;
        process.kill(ProcessSignal.sigkill);
      }),
    );
    final stdout = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final stderr = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    try {
      final exitCode = await process.exitCode.timeout(timeout);
      if (cancelled) throw const AgentCommandCancelled();
      return AgentCommandResult(
        stdout: await stdout,
        stderr: await stderr,
        exitCode: exitCode,
      );
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      throw const AppFailure('The command timed out.');
    } finally {
      _running.remove(process);
    }
  }

  String? get _home {
    final env = _environment ?? Platform.environment;
    final home = _os == LocalOs.windows ? env['USERPROFILE'] : env['HOME'];
    if (home == null || home.isEmpty) return null;
    return Directory(home).existsSync() ? home : null;
  }

  @override
  Future<void> close() async {
    _closed = true;
    for (final process in _running.toList()) {
      process.kill(ProcessSignal.sigkill);
    }
    _running.clear();
  }
}

/// The desktop OS the app runs on (Linux for anything else, which only
/// tests reach).
LocalOs currentLocalOs() {
  if (Platform.isWindows) return LocalOs.windows;
  if (Platform.isMacOS) return LocalOs.macos;
  return LocalOs.linux;
}
