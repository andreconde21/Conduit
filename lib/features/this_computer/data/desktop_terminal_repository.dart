import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:conduit/core/app_failure.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/local_shell/data/flutter_pty_process.dart';
import 'package:conduit/features/local_shell/domain/pty_process.dart';
import 'package:conduit/features/terminal/domain/ssh_terminal_repository.dart';
import 'package:conduit/features/terminal/domain/ssh_terminal_session.dart';
import 'package:conduit/features/this_computer/data/local_agent_command_runner.dart';
import 'package:conduit/features/this_computer/domain/local_shell_launch.dart';

/// Starts a process in a PTY. [hangUp] asks it to end the way closing a
/// terminal window does; null means only [PtyProcess.kill] is available.
typedef DesktopPtyStarter =
    ({PtyProcess process, void Function()? hangUp}) Function(
      LocalShellLaunch launch, {
      required int columns,
      required int rows,
    });

/// "This computer": the desktop's own login shell in a PTY (flutter_pty),
/// in the home directory.
///
/// Everything else a session does (tmux or Herdr attach, the connect
/// snippet) is typed into that shell by the session, as over SSH.
class DesktopTerminalRepository implements SshTerminalRepository {
  DesktopTerminalRepository({
    LocalOs? os,
    this._environment,
    bool Function(String path)? fileExists,
    String? Function(String executable)? findOnPath,
    this._windowsShell,
    DesktopPtyStarter? start,
  }) : _os = os ?? currentLocalOs(),
       _fileExists = fileExists ?? _defaultFileExists,
       _findOnPath = findOnPath ?? findExecutableOnPath,
       _start = start ?? _startFlutterPty;

  final LocalOs _os;
  final Map<String, String>? _environment;
  final bool Function(String path) _fileExists;
  final String? Function(String executable) _findOnPath;
  final WindowsShellKind Function()? _windowsShell;
  final DesktopPtyStarter _start;

  static bool _defaultFileExists(String path) => File(path).existsSync();

  static ({PtyProcess process, void Function()? hangUp}) _startFlutterPty(
    LocalShellLaunch launch, {
    required int columns,
    required int rows,
  }) {
    final process = FlutterPtyProcess.start(
      executable: launch.executable,
      arguments: launch.arguments,
      environment: launch.environment,
      workingDirectory: launch.workingDirectory,
      rows: rows,
      columns: columns,
    );
    return (
      process: process,
      hangUp: Platform.isWindows
          ? null
          : () => process.signal(ProcessSignal.sighup),
    );
  }

  /// The shell a new session starts.
  LocalShellLaunch resolveLaunch() => resolveLocalShellLaunch(
    os: _os,
    environment: _environment ?? Platform.environment,
    fileExists: _fileExists,
    findOnPath: _findOnPath,
    windowsShell: _windowsShell?.call() ?? WindowsShellKind.powershell,
  );

  @override
  Future<SshTerminalSession> connect(
    SavedHost host, {
    required int columns,
    required int rows,
  }) async {
    final launch = resolveLaunch();
    try {
      final started = _start(launch, columns: columns, rows: rows);
      return DesktopTerminalSession(started.process, hangUp: started.hangUp);
    } catch (error) {
      throw AppFailure('Could not start $launch on this computer.', '$error');
    }
  }
}

/// A local shell session: PTY output as stdout, the exit code once the
/// shell ends.
class DesktopTerminalSession
    implements SshTerminalSession, ExitStatusTerminalSession {
  DesktopTerminalSession(
    this._process, {
    this._hangUp,
    this.hangUpGrace = const Duration(seconds: 2),
  });

  final PtyProcess _process;
  final void Function()? _hangUp;

  /// How long a hung-up shell gets before it is killed.
  final Duration hangUpGrace;
  bool _closed = false;

  @override
  Stream<List<int>> get stdout => _process.output;

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  Future<void> get done => _process.exitCode.then((_) {});

  @override
  Future<void> send(List<int> data) async {
    if (_closed) {
      throw const AppFailure('The shell on this computer has ended.');
    }
    _process.write(data is Uint8List ? data : Uint8List.fromList(data));
  }

  @override
  void resize(int columns, int rows, int pixelWidth, int pixelHeight) {
    if (_closed || columns <= 0 || rows <= 0) return;
    _process.resize(rows, columns);
  }

  /// Hangs the shell up (SIGHUP, like closing a terminal window) so a tmux
  /// or Herdr client in it detaches cleanly and leaves its server running,
  /// then kills it if it is still there after [hangUpGrace].
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final exited = _process.exitCode
        .then<bool>((_) => true)
        .catchError((_) => true);
    final hangUp = _hangUp;
    if (hangUp != null) {
      hangUp();
      final ended = await Future.any([
        exited,
        Future<bool>.delayed(hangUpGrace, () => false),
      ]);
      if (ended) return;
    }
    _process.kill();
    await exited;
  }
}

/// The full path of [executable] on PATH, or null. Callers pass the full
/// file name (`pwsh.exe`), so PATHEXT is not consulted.
String? findExecutableOnPath(String executable) {
  final path = Platform.environment['PATH'] ?? Platform.environment['Path'];
  if (path == null) return null;
  final separator = Platform.isWindows ? ';' : ':';
  for (final dir in path.split(separator)) {
    if (dir.isEmpty) continue;
    final candidate = '$dir${Platform.pathSeparator}$executable';
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}
