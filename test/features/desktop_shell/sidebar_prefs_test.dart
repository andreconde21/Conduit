import 'package:conduit/features/desktop_shell/domain/sidebar_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SidebarPrefs', () {
    const machines = ['this-computer', 'a', 'b', 'c'];

    test('applyOrder puts saved keys first and keeps the rest in order', () {
      expect(SidebarPrefs.applyOrder(machines, (id) => id, ['c', 'a']), [
        'c',
        'a',
        'this-computer',
        'b',
      ]);
      expect(SidebarPrefs.applyOrder(machines, (id) => id, []), machines);
      // Unknown saved keys are ignored.
      expect(SidebarPrefs.applyOrder(machines, (id) => id, ['gone', 'b']), [
        'b',
        'this-computer',
        'a',
        'c',
      ]);
    });

    test('drag reorders machines', () {
      var prefs = const SidebarPrefs();
      prefs = prefs.moveMachine('c', visibleOrder: machines, beforeId: 'a');
      expect(prefs.machineOrder, ['this-computer', 'c', 'a', 'b']);
      prefs = prefs.moveMachine(
        'this-computer',
        visibleOrder: prefs.machineOrder,
      );
      expect(prefs.machineOrder, ['c', 'a', 'b', 'this-computer']);
      expect(
        SidebarPrefs.applyOrder(machines, (id) => id, prefs.machineOrder),
        ['c', 'a', 'b', 'this-computer'],
      );
    });

    test('dropping a machine on a group moves it there', () {
      var prefs = const SidebarPrefs()
          .addGroup(const SidebarGroup(id: 'g1', name: 'Clients'))
          .addGroup(const SidebarGroup(id: 'g2', name: 'Infra'));
      prefs = prefs.moveMachine('a', visibleOrder: machines, groupId: 'g1');
      prefs = prefs.moveMachine(
        'b',
        visibleOrder: machines,
        groupId: 'g1',
        beforeId: 'a',
      );
      expect(prefs.groupOf('a')?.name, 'Clients');
      expect(prefs.groups.first.machineIds, ['b', 'a']);
      // Moving to another group leaves the first one.
      prefs = prefs.moveMachine('a', visibleOrder: machines, groupId: 'g2');
      expect(prefs.groups.first.machineIds, ['b']);
      expect(prefs.groups.last.machineIds, ['a']);
      // Back to "Machines".
      prefs = prefs.moveMachine('a', visibleOrder: machines);
      expect(prefs.groupOf('a'), isNull);
      prefs = prefs.setGroup('c', 'g2');
      expect(prefs.groupOf('c')?.id, 'g2');
      prefs = prefs.removeGroup('g2');
      expect(prefs.groupOf('c'), isNull);
    });

    test('pins toggle and reorder', () {
      var prefs = const SidebarPrefs().togglePin('x').togglePin('y');
      expect(prefs.pinned, ['x', 'y']);
      prefs = prefs.movePin('y', 'x');
      expect(prefs.pinned, ['y', 'x']);
      prefs = prefs.togglePin('y');
      expect(prefs.pinned, ['x']);
      expect(prefs.isPinned('y'), isFalse);
    });

    test('children reorder within a machine', () {
      final prefs = const SidebarPrefs().moveChild(
        'a',
        'k3',
        visibleOrder: ['k1', 'k2', 'k3'],
        beforeKey: 'k1',
      );
      expect(prefs.childOrder['a'], ['k3', 'k1', 'k2']);
    });

    test('round-trips through JSON', () {
      const prefs = SidebarPrefs(
        machineOrder: ['b', 'a'],
        childOrder: {
          'a': ['k2', 'k1'],
        },
        pinned: ['k1'],
        groups: [
          SidebarGroup(id: 'g', name: 'Clients', machineIds: ['a']),
        ],
        expanded: {'k1': true, 'm/a': false},
      );
      expect(SidebarPrefs.fromJson(prefs.toJson()), prefs);
      expect(SidebarPrefs.fromJson('garbage'), const SidebarPrefs());
    });
  });
}
