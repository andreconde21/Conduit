import 'package:conduit/features/this_computer/domain/local_shell_launch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveLocalShellLaunch', () {
    test(r'Linux runs $SHELL as a login shell in the home directory', () {
      final launch = resolveLocalShellLaunch(
        os: LocalOs.linux,
        environment: const {
          'SHELL': '/usr/bin/zsh',
          'HOME': '/home/andre',
          'LANG': 'pt_PT.UTF-8',
          'PATH': '/usr/bin',
        },
        fileExists: (path) => path == '/usr/bin/zsh',
      );
      expect(launch.executable, '/usr/bin/zsh');
      expect(launch.arguments, ['-l']);
      expect(launch.workingDirectory, '/home/andre');
      expect(launch.environment['TERM'], 'xterm-256color');
      expect(launch.environment['COLORTERM'], 'truecolor');
      expect(launch.environment['LANG'], 'pt_PT.UTF-8');
      expect(launch.environment['PATH'], '/usr/bin');
    });

    test(r'falls back to bash, then sh, when $SHELL is missing', () {
      final bash = resolveLocalShellLaunch(
        os: LocalOs.linux,
        environment: const {'SHELL': '/usr/bin/fish', 'HOME': '/h'},
        fileExists: (path) => path == '/bin/bash',
      );
      expect(bash.executable, '/bin/bash');
      final sh = resolveLocalShellLaunch(
        os: LocalOs.linux,
        environment: const {'HOME': '/h'},
        fileExists: (path) => false,
      );
      expect(sh.executable, '/bin/sh');
      expect(sh.arguments, ['-l']);
    });

    test('macOS prefers zsh without SHELL and sets a UTF-8 LANG', () {
      final launch = resolveLocalShellLaunch(
        os: LocalOs.macos,
        environment: const {'HOME': '/Users/andre'},
        fileExists: (path) => path == '/bin/zsh' || path == '/bin/bash',
      );
      expect(launch.executable, '/bin/zsh');
      expect(launch.environment['LANG'], 'en_US.UTF-8');
    });

    test('blanks TMUX so tmux attach does not refuse to nest', () {
      final launch = resolveLocalShellLaunch(
        os: LocalOs.linux,
        environment: const {'HOME': '/h', 'TMUX': '/tmp/tmux-0/default,1,0'},
        fileExists: (_) => true,
      );
      expect(launch.environment['TMUX'], '');
      expect(launch.environment.containsKey('TMUX_PANE'), isFalse);
    });

    test('Windows opens pwsh when installed, else Windows PowerShell', () {
      const env = {'USERPROFILE': r'C:\Users\andre', 'ComSpec': r'C:\cmd.exe'};
      final pwsh = resolveLocalShellLaunch(
        os: LocalOs.windows,
        environment: env,
        fileExists: (_) => false,
        findOnPath: (name) => name == 'pwsh.exe' ? r'C:\pwsh\pwsh.exe' : null,
      );
      expect(pwsh.executable, r'C:\pwsh\pwsh.exe');
      expect(pwsh.arguments, ['-NoLogo']);
      expect(pwsh.workingDirectory, r'C:\Users\andre');
      final legacy = resolveLocalShellLaunch(
        os: LocalOs.windows,
        environment: env,
        fileExists: (_) => false,
        findOnPath: (_) => null,
      );
      expect(legacy.executable, 'powershell.exe');
      final cmd = resolveLocalShellLaunch(
        os: LocalOs.windows,
        environment: env,
        fileExists: (_) => false,
        windowsShell: WindowsShellKind.cmd,
      );
      expect(cmd.executable, r'C:\cmd.exe');
      final wsl = resolveLocalShellLaunch(
        os: LocalOs.windows,
        environment: env,
        fileExists: (_) => false,
        windowsShell: WindowsShellKind.wsl,
      );
      expect(wsl.executable, 'wsl.exe');
      expect(wsl.arguments, ['~']);
      expect(wsl.environment.containsKey('LANG'), isFalse);
    });
  });

  group('localCommandEnvironment', () {
    test('puts the tool directories in front of PATH once', () {
      final env = localCommandEnvironment(const {
        'HOME': '/home/andre',
        'PATH': '/home/andre/.local/bin:/usr/bin',
        'TMUX': 'x',
      });
      final path = env['PATH']!.split(':');
      expect(path.first, '/home/andre/.local/share/mise/shims');
      expect(path, contains('/home/andre/.cargo/bin'));
      expect(path, contains('/opt/homebrew/bin'));
      expect(
        path.where((dir) => dir == '/home/andre/.local/bin'),
        hasLength(1),
      );
      expect(path.last, '/usr/bin');
      expect(env.containsKey('TMUX'), isFalse);
    });

    test('keeps a usable PATH when the app has none', () {
      final env = localCommandEnvironment(const {'HOME': '/h'});
      expect(env['PATH'], endsWith('/usr/bin:/bin'));
    });
  });

  test('WindowsShellKind parses saved names', () {
    expect(WindowsShellKind.parse('wsl'), WindowsShellKind.wsl);
    expect(WindowsShellKind.parse('bogus'), WindowsShellKind.powershell);
  });
}
