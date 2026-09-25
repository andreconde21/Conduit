import 'package:conduit/features/agent_attention/data/remote_tool_command.dart';

/// Which shell "This computer" opens on Windows.
enum WindowsShellKind {
  /// PowerShell 7 (`pwsh.exe`) when installed, else Windows PowerShell.
  powershell,

  /// The classic command prompt (`%ComSpec%`, `cmd.exe`).
  cmd,

  /// The default WSL distribution (`wsl.exe`), where tmux and Herdr live
  /// on a Windows machine.
  wsl;

  String get label => switch (this) {
    WindowsShellKind.powershell => 'PowerShell',
    WindowsShellKind.cmd => 'Command Prompt',
    WindowsShellKind.wsl => 'WSL',
  };

  static WindowsShellKind parse(Object? raw) =>
      WindowsShellKind.values.where((kind) => kind.name == raw).firstOrNull ??
      WindowsShellKind.powershell;
}

/// The operating systems a local terminal runs on.
enum LocalOs { linux, macos, windows }

/// How to start the local login shell in a PTY.
class LocalShellLaunch {
  const LocalShellLaunch({
    required this.executable,
    required this.arguments,
    required this.environment,
    required this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;

  /// The home directory; null when the environment names none.
  final String? workingDirectory;

  @override
  String toString() => '$executable ${arguments.join(' ')}';
}

/// Resolves the login shell of the desktop the app runs on.
///
/// Pure: the environment, file checks and PATH lookups are passed in, so
/// every OS is testable anywhere.
///
/// * Linux and macOS: `$SHELL -l`, else the first of zsh (macOS only),
///   bash and sh that exists, all as login shells.
/// * Windows: PowerShell (`pwsh.exe` on PATH, else `powershell.exe`),
///   `cmd.exe` or `wsl.exe` as [windowsShell] says.
///
/// The environment is the app's own plus `TERM=xterm-256color`,
/// `COLORTERM=truecolor` and a UTF-8 `LANG` when none is set. `TMUX` and
/// `TMUX_PANE` are blanked: an app started from inside tmux would
/// otherwise make every `tmux attach` refuse to nest.
LocalShellLaunch resolveLocalShellLaunch({
  required LocalOs os,
  required Map<String, String> environment,
  required bool Function(String path) fileExists,
  String? Function(String executable)? findOnPath,
  WindowsShellKind windowsShell = WindowsShellKind.powershell,
}) {
  final env = localShellEnvironment(environment, os: os);
  if (os == LocalOs.windows) {
    final home = _lookup(environment, 'USERPROFILE');
    final (executable, arguments) = switch (windowsShell) {
      WindowsShellKind.powershell => (
        findOnPath?.call('pwsh.exe') ?? 'powershell.exe',
        const ['-NoLogo'],
      ),
      WindowsShellKind.cmd => (
        _lookup(environment, 'ComSpec') ?? 'cmd.exe',
        const <String>[],
      ),
      // `~` starts WSL in the Linux home instead of the Windows directory.
      WindowsShellKind.wsl => ('wsl.exe', const ['~']),
    };
    return LocalShellLaunch(
      executable: executable,
      arguments: arguments,
      environment: env,
      workingDirectory: home,
    );
  }
  final candidates = [
    ?_nonEmpty(environment['SHELL']),
    if (os == LocalOs.macos) '/bin/zsh',
    '/bin/bash',
    '/usr/bin/bash',
    '/bin/sh',
  ];
  final shell = candidates.firstWhere(fileExists, orElse: () => '/bin/sh');
  return LocalShellLaunch(
    executable: shell,
    arguments: const ['-l'],
    environment: env,
    workingDirectory: _nonEmpty(environment['HOME']),
  );
}

/// The environment a local terminal starts with (see
/// [resolveLocalShellLaunch]).
Map<String, String> localShellEnvironment(
  Map<String, String> environment, {
  required LocalOs os,
}) {
  final env = Map<String, String>.of(environment);
  env['TERM'] = 'xterm-256color';
  env['COLORTERM'] = 'truecolor';
  env['TERM_PROGRAM'] = 'Conductore';
  if (os != LocalOs.windows &&
      _nonEmpty(env['LANG']) == null &&
      _nonEmpty(env['LC_ALL']) == null) {
    env['LANG'] = os == LocalOs.macos ? 'en_US.UTF-8' : 'C.UTF-8';
  }
  for (final name in const ['TMUX', 'TMUX_PANE']) {
    if (env.containsKey(name)) env[name] = '';
  }
  return env;
}

/// The environment of local commands (listing, companion, git): the app's
/// own with the directories agent tools install into put in front of PATH,
/// the same ones the SSH runner adds (see [remoteToolExtraPathDirs]).
///
/// A desktop app started from a launcher often has only the system PATH,
/// so without them tmux from Homebrew, Herdr from `~/.local/bin` or a mise
/// shim would read as "not installed".
Map<String, String> localCommandEnvironment(Map<String, String> environment) {
  final env = Map<String, String>.of(environment);
  final home = _nonEmpty(env['HOME']) ?? '';
  final extra = [
    for (final dir in remoteToolExtraPathDirs)
      if (!dir.contains(r'$HOME') || home.isNotEmpty)
        dir.replaceAll(r'$HOME', home),
  ];
  final current = (env['PATH'] ?? '')
      .split(':')
      .where((dir) => dir.isNotEmpty)
      .toList();
  env['PATH'] = [
    ...extra.where((dir) => !current.contains(dir)),
    ...current,
    if (current.isEmpty) ...['/usr/bin', '/bin'],
  ].join(':');
  for (final name in const ['TMUX', 'TMUX_PANE']) {
    env.remove(name);
  }
  return env;
}

String? _nonEmpty(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();

/// Windows environment names are case-insensitive.
String? _lookup(Map<String, String> environment, String name) {
  final lower = name.toLowerCase();
  for (final MapEntry(:key, :value) in environment.entries) {
    if (key.toLowerCase() == lower) return _nonEmpty(value);
  }
  return null;
}
