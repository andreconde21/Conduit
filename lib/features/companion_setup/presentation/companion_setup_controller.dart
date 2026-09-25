import 'dart:async';

import 'package:conduit/core/app_failure.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_controller.dart';
import 'package:conduit/features/companion_setup/data/companion_bundle.dart';
import 'package:conduit/features/companion_setup/data/companion_commands.dart';
import 'package:conduit/features/companion_setup/data/companion_installer.dart';
import 'package:conduit/features/companion_setup/data/companion_probe.dart';
import 'package:conduit/features/companion_setup/domain/companion_status.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/sftp/domain/sftp_repository.dart';
import 'package:flutter/widgets.dart';

typedef CompanionRunnerFactory = AgentCommandRunner Function(SavedHost host);

/// Outcome of "Send test event".
class CompanionTestEventResult {
  const CompanionTestEventResult({required this.ok, required this.message});

  final bool ok;
  final String message;
}

/// Checks, installs and removes the host companion, one machine at a time.
///
/// Keeps one exec connection per machine (opened lazily, reused for every
/// check) and caches the last status for as long as that connection's
/// settings stay the same, so chips and banners across the app share one
/// check instead of each opening a connection. Editing the machine's
/// address or credentials starts over with a new connection.
class CompanionSetupController extends ChangeNotifier {
  CompanionSetupController({
    required CompanionRunnerFactory runnerFactory,
    required SftpRepository sftpRepository,
    CompanionBundleLoader? loadBundle,
    CompanionProbe probe = const CompanionProbe(),
    this.staleAfter = const Duration(minutes: 5),
    DateTime Function() clock = DateTime.now,
  }) : _makeRunner = runnerFactory,
       _prober = probe,
       _now = clock,
       _loadBundle = loadBundle ?? CompanionBundle.load,
       _installer = CompanionInstaller(
         sftpRepository: sftpRepository,
         loadBundle: loadBundle ?? CompanionBundle.load,
       );

  final CompanionRunnerFactory _makeRunner;
  final CompanionProbe _prober;
  final DateTime Function() _now;
  final CompanionBundleLoader _loadBundle;
  final CompanionInstaller _installer;

  /// A cached status older than this is re-checked by [ensureChecked].
  final Duration staleAfter;

  final Map<String, _HostEntry> _entries = {};
  Future<CompanionBundle>? _bundle;
  bool _disposed = false;

  /// The version the app would install (from the bundled manifest).
  Future<String> bundledVersion() async =>
      (await (_bundle ??= _loadBundle())).version;

  CompanionStatus? statusFor(SavedHost host) => _entry(host)?.status;

  bool isChecking(SavedHost host) => _entry(host)?.checking != null;

  /// Checks [host] unless a fresh status is cached or a check is running.
  void ensureChecked(SavedHost host) {
    final entry = _entryFor(host);
    final status = entry.status;
    if (entry.checking != null) return;
    if (status != null && _now().difference(status.checkedAt) < staleAfter) {
      return;
    }
    unawaited(refresh(host));
  }

  /// Runs a fresh check (joining one already in flight).
  Future<CompanionStatus> refresh(SavedHost host) {
    final entry = _entryFor(host);
    final running = entry.checking;
    if (running != null) return running;
    final future = _prober.check(entry.runner).then((status) {
      entry.status = status;
      return status;
    });
    entry.checking = future;
    _notify();
    return future.whenComplete(() {
      if (identical(entry.checking, future)) entry.checking = null;
      _notify();
    });
  }

  /// Uploads and installs the bundled companion, then re-checks.
  Future<CompanionInstallOutcome> install(
    SavedHost host, {
    void Function(String line)? onLog,
  }) async {
    final entry = _entryFor(host);
    try {
      return await _installer.install(host, entry.runner, onLog: onLog);
    } finally {
      await refresh(host);
    }
  }

  /// Runs the uploaded `install.sh --uninstall`, then re-checks.
  Future<CompanionInstallOutcome> uninstall(
    SavedHost host, {
    void Function(String line)? onLog,
  }) async {
    final entry = _entryFor(host);
    try {
      return await _installer.uninstall(host, entry.runner, onLog: onLog);
    } finally {
      await refresh(host);
    }
  }

  /// `conductore-hostd stop`; returns whether a daemon was running.
  Future<bool> stopDaemon(SavedHost host) async {
    final entry = _entryFor(host);
    try {
      final result = await entry.runner.run(
        CompanionCommands.stop,
        timeout: const Duration(seconds: 15),
      );
      if (result.exitCode != 0) {
        throw AppFailure(
          'conductore-hostd stop failed.',
          [
            result.stderr.trim(),
            result.stdout.trim(),
          ].where((s) => s.isNotEmpty).join('\n'),
        );
      }
      return result.stdout.contains('"stopped":true');
    } finally {
      await refresh(host);
    }
  }

  /// Sends a synthetic Notification (then SessionEnd) through the hook
  /// client and checks that the daemon reports the test agent.
  Future<CompanionTestEventResult> sendTestEvent(SavedHost host) async {
    final entry = _entryFor(host);
    final sent = await entry.runner.run(
      CompanionCommands.sendTestEvent,
      timeout: const Duration(seconds: 20),
    );
    if (sent.exitCode != 0) {
      return CompanionTestEventResult(
        ok: false,
        message: [
          'conductore-hook failed (exit ${sent.exitCode ?? 'unknown'}).',
          sent.stderr.trim(),
        ].where((s) => s.isNotEmpty).join(' '),
      );
    }
    final status = await entry.runner.run(
      CompanionCommands.status,
      timeout: const Duration(seconds: 15),
    );
    await refresh(host);
    if (status.stdout.contains('"${CompanionCommands.testSessionId}"')) {
      return const CompanionTestEventResult(
        ok: true,
        message:
            'The test agent "${CompanionCommands.testSessionId}" reached the '
            'daemon. It shows as ended and is pruned after an hour.',
      );
    }
    return const CompanionTestEventResult(
      ok: false,
      message:
          'The hook ran but the daemon does not list the test agent. '
          'See ~/.conductore/hostd.log on the machine.',
    );
  }

  _HostEntry? _entry(SavedHost host) {
    final entry = _entries[host.id];
    return entry != null && entry.fingerprint == _fingerprint(host)
        ? entry
        : null;
  }

  _HostEntry _entryFor(SavedHost host) {
    final existing = _entry(host);
    if (existing != null) return existing;
    final stale = _entries.remove(host.id);
    if (stale != null) unawaited(stale.runner.close());
    return _entries[host.id] = _HostEntry(
      fingerprint: _fingerprint(host),
      runner: _makeRunner(host),
    );
  }

  static String _fingerprint(SavedHost host) => [
    host.username,
    host.host,
    host.port,
    host.authMethod.name,
    host.password.hashCode,
    host.privateKey.hashCode,
    host.passphrase.hashCode,
    host.hardwareKeys.length,
  ].join('|');

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final entry in _entries.values) {
      unawaited(entry.runner.close());
    }
    _entries.clear();
    super.dispose();
  }
}

class _HostEntry {
  _HostEntry({required this.fingerprint, required this.runner});

  final String fingerprint;
  final AgentCommandRunner runner;
  CompanionStatus? status;
  Future<CompanionStatus>? checking;
}

/// Makes the [CompanionSetupController] reachable from any route, so
/// [showCompanionSetup] and [CompanionStatusChip] need only a context.
class CompanionSetupScope extends InheritedWidget {
  const CompanionSetupScope({
    required this.controller,
    required super.child,
    this.agentAttention,
    super.key,
  });

  final CompanionSetupController controller;

  /// The app's agent monitor, so the Agent hooks screen can offer to turn
  /// monitoring on for a machine whose companion is working.
  final AgentAttentionController? agentAttention;

  static CompanionSetupController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<CompanionSetupScope>()
      ?.controller;

  static AgentAttentionController? agentAttentionOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<CompanionSetupScope>()
          ?.agentAttention;

  @override
  bool updateShouldNotify(CompanionSetupScope oldWidget) =>
      controller != oldWidget.controller ||
      agentAttention != oldWidget.agentAttention;
}
