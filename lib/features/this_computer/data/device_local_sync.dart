import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/sessions/domain/session_snapshot.dart';
import 'package:conduit/features/sync/data/app_local_sync_store.dart';

/// Whether a per-host record belongs to "This computer", which means a
/// different machine on every device and so is never backed up or synced.
bool isDeviceLocalHostId(String hostId) =>
    hostId == thisComputerHostId || hostId.startsWith('$thisComputerHostId#');

/// A per-host map (connect-picker memory, recent directories) as backups
/// and sync see it: without "This computer", whose entries survive every
/// write that comes back.
class DeviceLocalJsonMapStore implements JsonMapStore {
  const DeviceLocalJsonMapStore(this._inner);

  final JsonMapStore _inner;

  @override
  Future<Map<String, Object?>> readAll() async => {
    for (final MapEntry(:key, :value) in (await _inner.readAll()).entries)
      if (!isDeviceLocalHostId(key)) key: value,
  };

  @override
  Future<void> writeAll(Map<String, Object?> values) async {
    final current = await _inner.readAll();
    await _inner.writeAll({
      for (final MapEntry(:key, :value) in values.entries)
        if (!isDeviceLocalHostId(key)) key: value,
      for (final MapEntry(:key, :value) in current.entries)
        if (isDeviceLocalHostId(key)) key: value,
    });
  }
}

/// The session-restore list as backups and sync see it: without the
/// sessions on "This computer", which a synced list keeps on this device
/// (after the synced ones) instead of dropping.
class DeviceLocalSessionSnapshots implements SessionSnapshotRepository {
  const DeviceLocalSessionSnapshots(this._inner);

  final SessionSnapshotRepository _inner;

  @override
  Future<SessionSnapshot> load() async {
    final snapshot = await _inner.load();
    final entries = snapshot.entries
        .where((entry) => !isDeviceLocalHostId(entry.hostId))
        .toList();
    if (entries.length == snapshot.entries.length) return snapshot;
    final active = snapshot.entries.elementAtOrNull(snapshot.activeIndex);
    final activeIndex = active == null ? -1 : entries.indexOf(active);
    return SessionSnapshot(
      entries: entries,
      activeIndex: activeIndex < 0 ? 0 : activeIndex,
    );
  }

  @override
  Future<void> save(SessionSnapshot snapshot) async {
    final local = (await _inner.load()).entries
        .where((entry) => isDeviceLocalHostId(entry.hostId))
        .toList();
    final synced = snapshot.entries
        .where((entry) => !isDeviceLocalHostId(entry.hostId))
        .toList();
    await _inner.save(
      SessionSnapshot(
        entries: [...synced, ...local],
        activeIndex: synced.isEmpty
            ? 0
            : snapshot.activeIndex.clamp(0, synced.length - 1),
      ),
    );
  }

  @override
  Future<void> clear() async {
    final local = (await _inner.load()).entries
        .where((entry) => isDeviceLocalHostId(entry.hostId))
        .toList();
    if (local.isEmpty) {
      await _inner.clear();
    } else {
      await _inner.save(SessionSnapshot(entries: local));
    }
  }
}
