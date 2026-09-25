import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/local_shell/domain/pty_process.dart';
import 'package:conduit/features/terminal/domain/ssh_terminal_session.dart';
import 'package:conduit/features/terminal/presentation/terminal_session_controller.dart';
import 'package:conduit/features/this_computer/data/desktop_terminal_repository.dart';
import 'package:conduit/features/this_computer/domain/local_shell_launch.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePty implements PtyProcess {
  final _output = StreamController<Uint8List>.broadcast();
  final _exit = Completer<int>();
  final writes = <List<int>>[];
  final resizes = <(int, int)>[];
  var killed = false;

  void exit(int code) {
    if (!_exit.isCompleted) _exit.complete(code);
  }

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void write(Uint8List data) => writes.add(data);

  @override
  void resize(int rows, int columns) => resizes.add((rows, columns));

  @override
  void kill() {
    killed = true;
    exit(-9);
  }
}

/// A real short-lived process behind the PTY interface (no terminal: the
/// flutter_pty native library is not loaded under `flutter test`).
class _ProcessPty implements PtyProcess {
  _ProcessPty(this._process) {
    _process.stdout.listen(
      (chunk) => _output.add(Uint8List.fromList(chunk)),
      onDone: _output.close,
    );
    _process.stderr.listen((chunk) => _output.add(Uint8List.fromList(chunk)));
  }

  static Future<_ProcessPty> start(LocalShellLaunch launch) async =>
      _ProcessPty(
        await Process.start(
          launch.executable,
          launch.arguments,
          environment: launch.environment,
          workingDirectory: launch.workingDirectory,
        ),
      );

  final Process _process;
  final _output = StreamController<Uint8List>();

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  void write(Uint8List data) => _process.stdin.add(data);

  @override
  void resize(int rows, int columns) {}

  @override
  void kill() => _process.kill(ProcessSignal.sigkill);
}

void main() {
  final thisComputer = SavedHost.thisComputer(hostname: 'omarchy');

  group('DesktopTerminalRepository', () {
    test('starts the login shell at the requested size', () async {
      LocalShellLaunch? started;
      (int, int)? size;
      final pty = _FakePty();
      final repository = DesktopTerminalRepository(
        os: LocalOs.linux,
        environment: const {'SHELL': '/bin/zsh', 'HOME': '/home/andre'},
        fileExists: (path) => path == '/bin/zsh',
        start: (launch, {required columns, required rows}) {
          started = launch;
          size = (columns, rows);
          return (process: pty, hangUp: null);
        },
      );
      final session = await repository.connect(
        thisComputer,
        columns: 120,
        rows: 40,
      );
      expect(started!.executable, '/bin/zsh');
      expect(started!.arguments, ['-l']);
      expect(started!.workingDirectory, '/home/andre');
      expect(started!.environment['TERM'], 'xterm-256color');
      expect(size, (120, 40));
      expect(session, isA<ExitStatusTerminalSession>());
    });

    test('uses the Windows shell setting', () async {
      LocalShellLaunch? started;
      var shell = WindowsShellKind.powershell;
      final repository = DesktopTerminalRepository(
        os: LocalOs.windows,
        environment: const {'USERPROFILE': r'C:\Users\a'},
        findOnPath: (_) => null,
        windowsShell: () => shell,
        start: (launch, {required columns, required rows}) {
          started = launch;
          return (process: _FakePty(), hangUp: null);
        },
      );
      await repository.connect(thisComputer, columns: 80, rows: 24);
      expect(started!.executable, 'powershell.exe');
      shell = WindowsShellKind.wsl;
      await repository.connect(thisComputer, columns: 80, rows: 24);
      expect(started!.executable, 'wsl.exe');
    });
  });

  group('DesktopTerminalSession', () {
    test('resizes the PTY (rows, columns) and ignores empty sizes', () {
      final pty = _FakePty();
      final session = DesktopTerminalSession(pty)
        ..resize(100, 30, 0, 0)
        ..resize(0, 0, 0, 0);
      expect(pty.resizes, [(30, 100)]);
      unawaited(session.close());
    });

    test('close hangs up first and kills only a shell that stays', () async {
      final polite = _FakePty();
      var hungUp = 0;
      await DesktopTerminalSession(
        polite,
        hangUp: () {
          hungUp += 1;
          polite.exit(-1);
        },
      ).close();
      expect(hungUp, 1);
      expect(polite.killed, isFalse);

      final stubborn = _FakePty();
      await DesktopTerminalSession(
        stubborn,
        hangUp: () {},
        hangUpGrace: const Duration(milliseconds: 10),
      ).close();
      expect(stubborn.killed, isTrue);
    });
  });

  group('session lifecycle', () {
    TerminalSessionController controllerWith(DesktopTerminalRepository repo) =>
        TerminalSessionController(host: thisComputer, repository: repo);

    String screen(TerminalSessionController controller) {
      final lines = <String>[];
      final buffer = controller.terminal.buffer;
      for (var i = 0; i < buffer.lines.length; i++) {
        lines.add(buffer.lines[i].toString());
      }
      return lines.join('\n');
    }

    test(
      'a real short-lived shell prints, exits and reports its code',
      () async {
        final repository = DesktopTerminalRepository(
          os: LocalOs.linux,
          environment: {
            'HOME': Directory.systemTemp.path,
            'PATH': '/usr/bin:/bin',
          },
          fileExists: (path) => path == '/bin/sh',
          start: (launch, {required columns, required rows}) =>
              throw UnimplementedError(),
        );
        final launch = repository.resolveLaunch();
        final pty = await _ProcessPty.start(
          LocalShellLaunch(
            executable: launch.executable,
            arguments: const ['-c', r'echo hi from $TERM; exit 7'],
            environment: launch.environment,
            workingDirectory: launch.workingDirectory,
          ),
        );
        final controller = controllerWith(
          DesktopTerminalRepository(
            os: LocalOs.linux,
            environment: const {'HOME': '/'},
            fileExists: (_) => true,
            start: (_, {required columns, required rows}) =>
                (process: pty, hangUp: null),
          ),
        );
        await controller.connect();
        expect(controller.status, TerminalConnectionStatus.connected);
        await pty.exitCode;
        await pumpEventQueue();
        expect(controller.status, TerminalConnectionStatus.disconnected);
        expect(controller.exitCode, 7);
        expect(controller.isLocalShell, isTrue);
        final text = screen(controller);
        expect(text, contains('hi from xterm-256color'));
        expect(text, contains('[Shell exited (code 7)]'));
        controller.dispose();
      },
    );

    test('restart starts a new shell and clears the exit code', () async {
      final ptys = <_FakePty>[];
      final controller = controllerWith(
        DesktopTerminalRepository(
          os: LocalOs.linux,
          environment: const {'HOME': '/'},
          fileExists: (_) => true,
          start: (_, {required columns, required rows}) {
            final pty = _FakePty();
            ptys.add(pty);
            return (process: pty, hangUp: null);
          },
        ),
      );
      await controller.connect();
      ptys.single.exit(0);
      await pumpEventQueue();
      expect(controller.exitCode, 0);
      expect(controller.shouldConnect, isTrue);

      await controller.connect();
      expect(ptys, hasLength(2));
      expect(controller.status, TerminalConnectionStatus.connected);
      expect(controller.exitCode, isNull);
      controller.dispose();
    });

    test('a startup command is typed into the local shell', () async {
      final pty = _FakePty();
      final controller = TerminalSessionController(
        host: thisComputer,
        startupCommand: 'herdr',
        repository: DesktopTerminalRepository(
          os: LocalOs.linux,
          environment: const {'HOME': '/'},
          fileExists: (_) => true,
          start: (_, {required columns, required rows}) =>
              (process: pty, hangUp: null),
        ),
      );
      await controller.connect();
      await pumpEventQueue();
      expect(pty.writes.map(utf8.decode).join(), 'herdr\r');
      controller.dispose();
    });
  });
}
