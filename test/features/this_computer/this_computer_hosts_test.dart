import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/hosts/presentation/hosts_controller.dart';
import 'package:conduit/features/this_computer/domain/local_shell_launch.dart';
import 'package:conduit/features/this_computer/domain/this_computer_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

void main() {
  const saved = SavedHost(
    id: 'box',
    name: 'Box',
    host: 'box.lan',
    port: 22,
    username: 'andre',
    authMethod: SshAuthMethod.password,
    password: 'secret',
  );

  test('This computer is a machine, never a saved host', () async {
    final repository = FakeHostsRepository()..persisted = [saved];
    final store = InMemoryThisComputerStore(
      ThisComputerSettings(host: SavedHost.thisComputer(hostname: 'omarchy')),
    );
    final controller = HostsController(repository, thisComputerStore: store);
    await controller.load();

    expect(controller.hosts.map((h) => h.id), ['box']);
    expect(controller.machines.map((h) => h.id), [thisComputerHostId, 'box']);
    expect(controller.sortedMachines.first.isThisComputer, isTrue);
    expect(controller.findById(thisComputerHostId)?.host, 'omarchy');
    expect(controller.findById('box'), saved);

    // Settings changes (agent monitoring, last use) go to its own store.
    await controller.upsert(
      controller.thisComputer!.copyWith(
        tmuxPrefixKey: MultiplexerPrefixKey.controlA,
      ),
    );
    await controller.markConnected(controller.thisComputer!);
    expect(repository.persisted.map((h) => h.id), ['box']);
    expect(store.saves, 2);
    expect(store.settings.host.tmuxPrefixKey, MultiplexerPrefixKey.controlA);
    expect(store.settings.host.lastConnectedAt, isNotNull);

    // It cannot be deleted, and imports or sync never bring one in.
    await controller.remove(controller.thisComputer!);
    await controller.replaceAll([saved, SavedHost.thisComputer(name: 'Other')]);
    expect(controller.thisComputer, isNotNull);
    expect(controller.thisComputer!.name, 'This computer');
    expect(repository.persisted.map((h) => h.id), ['box']);
  });

  test('phones have no This computer', () async {
    final controller = HostsController(
      FakeHostsRepository()..persisted = [saved],
    );
    await controller.load();
    expect(controller.thisComputer, isNull);
    expect(controller.machines, [saved]);
    expect(controller.findById(thisComputerHostId), isNull);
  });

  test('the Windows shell choice is kept per device', () async {
    final store = InMemoryThisComputerStore(
      ThisComputerSettings(host: SavedHost.thisComputer()),
    );
    final controller = HostsController(
      EmptyHostsRepository(),
      thisComputerStore: store,
    );
    await controller.load();
    expect(controller.windowsShell, WindowsShellKind.powershell);
    await controller.setWindowsShell(WindowsShellKind.wsl);
    expect(controller.windowsShell, WindowsShellKind.wsl);
    expect(store.settings.windowsShell, WindowsShellKind.wsl);
  });

  test('saved settings never override what describes the device', () {
    final settings = ThisComputerSettings.fromJson({
      'host': SavedHost.thisComputer(name: 'Old', hostname: 'old')
          .copyWith(password: 'x', useMosh: true, agentAttentionEnabled: false)
          .toJson(),
      'windowsShell': 'cmd',
    }, defaults: SavedHost.thisComputer(hostname: 'new', username: 'andre'));
    expect(settings.host.name, 'This computer');
    expect(settings.host.host, 'new');
    expect(settings.host.username, 'andre');
    expect(settings.host.password, isEmpty);
    expect(settings.host.useMosh, isFalse);
    expect(settings.host.agentAttentionEnabled, isFalse);
    expect(settings.windowsShell, WindowsShellKind.cmd);
  });

  test('ids and endpoint', () {
    final host = SavedHost.thisComputer(hostname: 'omarchy', username: 'andre');
    expect(host.isThisComputer, isTrue);
    expect(host.copyWith(id: 'this-computer#herdr').isThisComputer, isTrue);
    expect(host.copyWith(id: 'this-computer-2').isThisComputer, isFalse);
    expect(host.endpoint, 'andre@omarchy (local)');
    expect(host.isValid, isTrue);
  });
}
