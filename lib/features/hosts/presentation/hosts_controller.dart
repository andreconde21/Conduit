import 'dart:async';

import 'package:conduit/core/app_failure.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/hosts/domain/saved_hosts_repository.dart';
import 'package:conduit/features/this_computer/domain/local_shell_launch.dart';
import 'package:conduit/features/this_computer/domain/this_computer_settings.dart';
import 'package:flutter/foundation.dart';

class HostsController extends ChangeNotifier {
  /// With [thisComputerStore] (desktops), "This computer" is a machine
  /// too: listed first by [machines] and [sortedMachines], found by
  /// [findById], and its settings go to that store instead of the saved
  /// list, so they are never backed up or synced.
  HostsController(this._repository, {ThisComputerStore? thisComputerStore})
    : _thisComputerStore = thisComputerStore,
      _thisComputer = thisComputerStore == null
          ? null
          : ThisComputerSettings(host: SavedHost.thisComputer());

  final SavedHostsRepository _repository;
  final ThisComputerStore? _thisComputerStore;
  ThisComputerSettings? _thisComputer;

  List<SavedHost> _hosts = const [];
  List<SavedHost>? _sortedHostsCache;
  HostListSortMode _sortMode = HostListSortMode.lastConnected;
  List<String> _manualOrder = const [];
  bool _isLoading = true;
  String? _errorMessage;
  final Completer<void> _firstLoad = Completer<void>();

  /// Completes once the first [load] has finished (successfully or not),
  /// for work that must see the saved hosts right after app start.
  Future<void> get firstLoad => _firstLoad.future;

  /// The saved machines (what backups and sync carry).
  List<SavedHost> get hosts => _hosts;
  List<SavedHost> get sortedHosts =>
      _sortedHostsCache ??= _computeSortedHosts();

  /// "This computer" on a desktop, else null.
  SavedHost? get thisComputer => _thisComputer?.host;

  /// The shell "This computer" opens on Windows.
  WindowsShellKind get windowsShell =>
      _thisComputer?.windowsShell ?? WindowsShellKind.powershell;

  /// Every machine a session can open on: "This computer" first, then the
  /// saved ones.
  List<SavedHost> get machines => [?thisComputer, ..._hosts];

  /// [machines] in the machine list's order ("This computer" stays first).
  List<SavedHost> get sortedMachines => [?thisComputer, ...sortedHosts];

  /// The machine with [id] (a saved one or "This computer"), or null.
  SavedHost? findById(String id) {
    final local = thisComputer;
    if (local != null && id == local.id) return local;
    return _hosts.where((host) => host.id == id).firstOrNull;
  }

  Future<void> setWindowsShell(WindowsShellKind shell) async {
    final current = _thisComputer;
    if (current == null || current.windowsShell == shell) return;
    await _saveThisComputer(current.copyWith(windowsShell: shell));
  }

  Future<void> _saveThisComputer(ThisComputerSettings settings) async {
    _thisComputer = settings;
    notifyListeners();
    try {
      await _thisComputerStore?.save(settings);
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
    }
  }

  HostListSortMode get sortMode => _sortMode;
  List<String> get manualOrder => List.unmodifiable(_manualOrder);

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final thisComputerStore = _thisComputerStore;
    if (thisComputerStore != null) {
      try {
        _thisComputer = await thisComputerStore.load();
      } catch (_) {
        // Defaults stay: the machine itself always works.
      }
    }
    try {
      final hosts = (await _repository.loadHosts())
          .where((host) => !host.isThisComputer)
          .toList(growable: false);
      _sortMode = await _repository.loadSortMode();
      _manualOrder = await _repository.loadManualOrder();
      _setHosts(hosts);
    } on AppFailure catch (failure) {
      _errorMessage = failure.toString();
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;
      if (!_firstLoad.isCompleted) {
        _firstLoad.complete();
      }
      notifyListeners();
    }
  }

  Future<void> setSortMode(HostListSortMode mode) async {
    if (mode == _sortMode) return;

    final seedManualOrder =
        mode == HostListSortMode.manual && _manualOrder.isEmpty;
    if (seedManualOrder) {
      _manualOrder = sortedHosts.map((host) => host.id).toList();
    }

    _sortMode = mode;
    _sortedHostsCache = null;
    notifyListeners();

    try {
      await _repository.saveSortMode(mode);
      if (seedManualOrder) {
        await _repository.saveManualOrder(_manualOrder);
      }
    } on AppFailure catch (failure) {
      _errorMessage = failure.toString();
      notifyListeners();
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
    }
  }

  Future<void> reorderManual(int oldIndex, int newIndex) async {
    final ordered = [...sortedHosts];
    if (oldIndex < 0 || oldIndex >= ordered.length) return;
    newIndex = newIndex.clamp(0, ordered.length - 1);
    if (oldIndex == newIndex) return;

    final moved = ordered.removeAt(oldIndex);
    ordered.insert(newIndex, moved);
    _manualOrder = ordered.map((host) => host.id).toList();
    _sortMode = HostListSortMode.manual;
    _sortedHostsCache = null;
    notifyListeners();

    try {
      await _repository.saveManualOrder(_manualOrder);
    } on AppFailure catch (failure) {
      _errorMessage = failure.toString();
      notifyListeners();
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
    }
  }

  Future<void> upsert(SavedHost host) async {
    if (host.isThisComputer) {
      final current = _thisComputer;
      if (current == null) return;
      await _saveThisComputer(
        current.copyWith(host: host.copyWith(id: thisComputerHostId)),
      );
      return;
    }
    final index = _hosts.indexWhere((currentHost) => currentHost.id == host.id);
    final updatedHosts = [..._hosts];

    if (index == -1) {
      updatedHosts.add(host);
    } else {
      updatedHosts[index] = host;
    }

    await _save(updatedHosts);
  }

  Future<void> mergeImported({
    required List<SavedHost> hosts,
    required HostListSortMode sortMode,
    required List<String> manualOrder,
  }) async {
    final mergedById = {for (final host in _hosts) host.id: host};
    for (final host in hosts) {
      if (host.id.isNotEmpty && !host.isThisComputer) {
        mergedById[host.id] = host;
      }
    }

    _errorMessage = null;
    notifyListeners();

    try {
      final mergedHosts = mergedById.values.toList(growable: false);
      final importedIds = hosts.map((host) => host.id).toSet();
      final currentManualOrder = _manualOrder.where(mergedById.containsKey);
      final mergedManualOrder = <String>[
        ...manualOrder.where(mergedById.containsKey),
        ...currentManualOrder.where((id) => !importedIds.contains(id)),
        ...mergedById.keys.where(
          (id) => !manualOrder.contains(id) && !_manualOrder.contains(id),
        ),
      ];
      await _repository.saveHosts(mergedHosts);
      await _repository.saveSortMode(sortMode);
      await _repository.saveManualOrder(mergedManualOrder);
      _sortMode = sortMode;
      _manualOrder = mergedManualOrder;
      _setHosts(mergedHosts);
    } on AppFailure catch (failure) {
      _errorMessage = failure.toString();
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      notifyListeners();
    }
  }

  /// Replaces the saved machines with [hosts] (device sync). Unlike
  /// [mergeImported], machines missing from [hosts] are removed. The sort
  /// mode and manual order change only when given.
  Future<void> replaceAll(
    List<SavedHost> hosts, {
    HostListSortMode? sortMode,
    List<String>? manualOrder,
  }) async {
    _errorMessage = null;
    hosts = hosts.where((host) => !host.isThisComputer).toList();
    try {
      await _repository.saveHosts(hosts);
      if (sortMode != null && sortMode != _sortMode) {
        await _repository.saveSortMode(sortMode);
        _sortMode = sortMode;
      }
      if (manualOrder != null) {
        await _repository.saveManualOrder(manualOrder);
        _manualOrder = List.of(manualOrder);
      }
      _setHosts(List.unmodifiable(hosts));
    } on AppFailure catch (failure) {
      _errorMessage = failure.toString();
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      notifyListeners();
    }
  }

  Future<void> remove(SavedHost host) async {
    if (host.isThisComputer) return;
    await _save(
      _hosts.where((currentHost) => currentHost.id != host.id).toList(),
    );
  }

  Future<void> markConnected(SavedHost host) async {
    if (host.isThisComputer) {
      final local = thisComputer;
      if (local == null) return;
      await upsert(local.copyWith(lastConnectedAt: DateTime.now()));
      return;
    }
    final current = _hosts.firstWhere(
      (currentHost) => currentHost.id == host.id,
      orElse: () => host,
    );
    await upsert(current.copyWith(lastConnectedAt: DateTime.now()));
  }

  Future<void> _save(List<SavedHost> hosts) async {
    _errorMessage = null;
    notifyListeners();

    try {
      await _repository.saveHosts(hosts);
      _setHosts(hosts);
    } on AppFailure catch (failure) {
      _errorMessage = failure.toString();
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      notifyListeners();
    }
  }

  void _setHosts(List<SavedHost> hosts) {
    _hosts = hosts;
    _sortedHostsCache = null;
  }

  List<SavedHost> _computeSortedHosts() {
    final sorted = [..._hosts];
    switch (_sortMode) {
      case HostListSortMode.lastConnected:
        sorted.sort(_compareLastConnected);
      case HostListSortMode.name:
        sorted.sort(_compareName);
      case HostListSortMode.added:
        break;
      case HostListSortMode.manual:
        return _computeManualOrder();
    }
    return List.unmodifiable(sorted);
  }

  List<SavedHost> _computeManualOrder() {
    final byId = {for (final host in _hosts) host.id: host};
    final ordered = <SavedHost>[];
    final seen = <String>{};
    for (final id in _manualOrder) {
      final host = byId[id];
      if (host != null && seen.add(id)) {
        ordered.add(host);
      }
    }
    for (final host in _hosts) {
      if (seen.add(host.id)) {
        ordered.add(host);
      }
    }
    return List.unmodifiable(ordered);
  }

  int _compareLastConnected(SavedHost a, SavedHost b) {
    final aDate = a.lastConnectedAt;
    final bDate = b.lastConnectedAt;
    if (aDate == null && bDate == null) {
      return _compareName(a, b);
    }
    if (aDate == null) {
      return 1;
    }
    if (bDate == null) {
      return -1;
    }
    final byDate = bDate.compareTo(aDate);
    return byDate == 0 ? _compareName(a, b) : byDate;
  }

  int _compareName(SavedHost a, SavedHost b) {
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    if (byName != 0) return byName;
    final byHost = a.host.toLowerCase().compareTo(b.host.toLowerCase());
    if (byHost != 0) return byHost;
    return a.id.compareTo(b.id);
  }
}
