import 'dart:async';

import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/hosts/presentation/hosts_controller.dart';
import 'package:conduit/features/terminal/domain/host_key_verifier.dart';
import 'package:conduit/features/this_computer/data/self_machine_matcher.dart';
import 'package:conduit/features/this_computer/domain/self_machine.dart';
import 'package:flutter/widgets.dart';

/// Keeps [HostsController.selfMachineId] pointing at the saved machine
/// that is this device, so a machine synced from a phone folds into "This
/// computer" here.
///
/// Matches in the background after the machines load, again when they or
/// the trusted host keys change (sync pulls, imports), and with a fresh
/// look at the device on a network change or app resume. Never blocks
/// startup, never throws. On phones ([SelfMachineMatcher.enabled] false)
/// [start] does nothing.
class SelfMachineWatcher with WidgetsBindingObserver {
  SelfMachineWatcher({
    required this.hosts,
    required this.matcher,
    required this.trustedKeys,
    this.networkChanges,
    this.dataChanges,
    this.observeLifecycle = true,
  });

  final HostsController hosts;
  final SelfMachineMatcher matcher;

  /// The trusted host keys (known hosts), by `host:port`.
  final Future<List<HostKeyRecord>> Function() trustedKeys;

  /// Fires when the device's network changes.
  final Stream<void>? networkChanges;

  /// Fires when saved data is replaced (sync pulls, backup imports).
  final Listenable? dataChanges;

  final bool observeLifecycle;

  StreamSubscription<void>? _network;
  List<SavedHost>? _checkedHosts;
  Future<void>? _running;
  bool _again = false;
  bool _started = false;
  bool _disposed = false;

  /// The last match, with the signal that decided it (null: none).
  SelfMachineMatch? get lastMatch => _lastMatch;
  SelfMachineMatch? _lastMatch;

  /// Starts watching. Completes after the first match (tests); callers
  /// need not wait for it.
  Future<void> start() async {
    if (_started || !matcher.enabled) return;
    _started = true;
    await hosts.firstLoad;
    if (_disposed) return;
    hosts.addListener(_onHostsChanged);
    dataChanges?.addListener(_onDataChanged);
    _network = networkChanges?.listen((_) => refresh());
    if (observeLifecycle) WidgetsBinding.instance.addObserver(this);
    await check();
  }

  /// Looks at the device again (network change, resume) and re-matches.
  Future<void> refresh() {
    matcher.invalidate();
    return check();
  }

  /// Re-matches the saved machines against the device.
  Future<void> check() {
    if (_disposed) return Future.value();
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    return _running = _loop().whenComplete(() => _running = null);
  }

  Future<void> _loop() async {
    do {
      _again = false;
      await _matchOnce();
    } while (_again && !_disposed);
  }

  Future<void> _matchOnce() async {
    final saved = hosts.hosts;
    _checkedHosts = saved;
    List<HostKeyRecord> keys;
    try {
      keys = await trustedKeys();
    } catch (_) {
      keys = const [];
    }
    final match = await matcher.match(saved, trustedKeys: keys);
    if (_disposed) return;
    _lastMatch = match;
    hosts.setSelfMachineId(match?.host.id);
  }

  void _onHostsChanged() {
    // The controller also notifies for its own changes (the match, "This
    // computer" settings); only a new machine list needs a new match.
    if (identical(hosts.hosts, _checkedHosts)) return;
    unawaited(check());
  }

  void _onDataChanged() => unawaited(check());

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  void dispose() {
    _disposed = true;
    hosts.removeListener(_onHostsChanged);
    dataChanges?.removeListener(_onDataChanged);
    unawaited(_network?.cancel());
    if (_started && observeLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
    }
  }
}
