import 'dart:async';
import 'dart:typed_data';

import 'package:conduit/core/app_failure.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/companion_setup/data/companion_bundle.dart';
import 'package:conduit/features/companion_setup/data/companion_commands.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/sftp/domain/sftp_repository.dart';

/// What an install or uninstall did, for the screen's log.
class CompanionInstallOutcome {
  const CompanionInstallOutcome({
    required this.ok,
    required this.directory,
    required this.log,
    this.exitCode,
  });

  final bool ok;

  /// Absolute remote directory the bundle was uploaded to.
  final String directory;
  final List<String> log;
  final int? exitCode;
}

/// Installs the bundled companion on a machine:
///
/// 1. uploads the bundle over SFTP to
///    `~/.local/share/conductore-src/<version>/`;
/// 2. runs `sh <that dir>/install.sh` (or `--uninstall`) over the exec
///    channel, which copies it to `~/.local/share/conductore`, links
///    `~/.local/bin/conductore-{hostd,hook}` and runs
///    `conductore-hostd install` to merge the hooks into
///    `~/.claude/settings.json`.
///
/// The caller re-checks the status afterwards.
class CompanionInstaller {
  const CompanionInstaller({
    required this.sftpRepository,
    required this.loadBundle,
    this.installTimeout = const Duration(seconds: 90),
  });

  final SftpRepository sftpRepository;
  final CompanionBundleLoader loadBundle;
  final Duration installTimeout;

  /// Remote upload directory relative to the home directory.
  static String uploadDirectory(String version) =>
      '.local/share/conductore-src/$version';

  Future<CompanionInstallOutcome> install(
    SavedHost host,
    AgentCommandRunner runner, {
    void Function(String line)? onLog,
  }) => _run(host, runner, uninstall: false, onLog: onLog);

  Future<CompanionInstallOutcome> uninstall(
    SavedHost host,
    AgentCommandRunner runner, {
    void Function(String line)? onLog,
  }) => _run(host, runner, uninstall: true, onLog: onLog);

  Future<CompanionInstallOutcome> _run(
    SavedHost host,
    AgentCommandRunner runner, {
    required bool uninstall,
    void Function(String line)? onLog,
  }) async {
    final log = <String>[];
    void say(String line) {
      log.add(line);
      onLog?.call(line);
    }

    final bundle = await loadBundle();
    say(
      'Uploading companion ${bundle.version} (${bundle.files.length} files)…',
    );
    final session = await sftpRepository.connect(host);
    String directory;
    try {
      final home = await session.resolve('.');
      directory = '$home/${uploadDirectory(bundle.version)}';
      final mkdir = await runner.run(
        CompanionCommands.makeDirectories([
          directory,
          for (final dir in bundle.directories) '$directory/$dir',
        ]),
        timeout: const Duration(seconds: 20),
      );
      if (mkdir.exitCode != 0) {
        throw AppFailure(
          'Could not create $directory.',
          [
            mkdir.stderr.trim(),
            mkdir.stdout.trim(),
          ].where((s) => s.isNotEmpty).join('\n'),
        );
      }
      for (final entry in bundle.files.entries) {
        final bytes = entry.value;
        await session.write(
          '$directory/${entry.key}',
          Stream<Uint8List>.value(bytes),
          bytes.length,
        );
      }
      say('Uploaded to $directory');
    } finally {
      await session.close();
    }

    say(uninstall ? 'Running install.sh --uninstall…' : 'Running install.sh…');
    final result = await runner.run(
      CompanionCommands.runInstaller(directory, uninstall: uninstall),
      timeout: installTimeout,
    );
    for (final line in [
      ...result.stdout.trim().split('\n'),
      ...result.stderr.trim().split('\n'),
    ]) {
      if (line.trim().isNotEmpty) say(line);
    }
    final ok = result.exitCode == 0;
    say(
      ok
          ? (uninstall ? 'Uninstalled.' : 'Installed.')
          : 'install.sh failed (exit ${result.exitCode ?? 'unknown'}).',
    );
    return CompanionInstallOutcome(
      ok: ok,
      directory: directory,
      log: log,
      exitCode: result.exitCode,
    );
  }
}
