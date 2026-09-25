import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/sessions/domain/session_snapshot.dart';
import 'package:conduit/features/sync/data/app_local_sync_store.dart';
import 'package:conduit/features/this_computer/data/device_local_sync.dart';
import 'package:flutter_test/flutter_test.dart';

class _MapStore implements JsonMapStore {
  Map<String, Object?> values = {};

  @override
  Future<Map<String, Object?>> readAll() async => Map.of(values);

  @override
  Future<void> writeAll(Map<String, Object?> values) async =>
      this.values = Map.of(values);
}

void main() {
  test('connect memory of This computer never leaves the device', () async {
    final inner = _MapStore()
      ..values = {
        'box': {'remember': true},
        'this-computer': {'remember': false},
      };
    final store = DeviceLocalJsonMapStore(inner);
    expect((await store.readAll()).keys, ['box']);

    // A synced write (even one naming This computer) keeps the local entry.
    await store.writeAll({
      'other': {'x': 1},
      'this-computer': {'remember': true},
    });
    expect(inner.values, {
      'other': {'x': 1},
      'this-computer': {'remember': false},
    });
  });

  test('local sessions stay out of the synced session list', () async {
    const box = SessionSnapshotEntry(
      hostId: 'box',
      target: ConnectTarget.tmux('main'),
    );
    const local = SessionSnapshotEntry(
      hostId: 'this-computer',
      target: ConnectTarget.herdr(workspaceId: 'w1'),
    );
    final inner = InMemorySessionSnapshotRepository(
      const SessionSnapshot(entries: [local, box], activeIndex: 1),
    );
    final synced = DeviceLocalSessionSnapshots(inner);

    final exported = await synced.load();
    expect(exported.entries, [box]);
    expect(exported.activeIndex, 0);

    const other = SessionSnapshotEntry(
      hostId: 'nas',
      target: ConnectTarget.shell(),
    );
    await synced.save(const SessionSnapshot(entries: [other]));
    expect(inner.stored.entries, [other, local]);

    await synced.clear();
    expect(inner.stored.entries, [local]);
  });
}
