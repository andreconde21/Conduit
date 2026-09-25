import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/desktop_shell/domain/sidebar_prefs.dart';
import 'package:conduit/features/desktop_shell/domain/sidebar_tree.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/hosts/domain/saved_hosts_repository.dart';
import 'package:conduit/features/hosts/presentation/hosts_controller.dart';
import 'package:conduit/features/live_preview/domain/live_preview_port_store.dart';
import 'package:conduit/features/session_navigation/domain/session_view_preferences.dart';
import 'package:conduit/features/session_navigation/presentation/session_view_controller.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/sessions/domain/session_snapshot.dart';
import 'package:conduit/features/sessions/presentation/session_restore_controller.dart';
import 'package:conduit/features/sync/data/app_local_sync_store.dart';
import 'package:conduit/features/sync/domain/local_data_changes.dart';
import 'package:conduit/features/sync/domain/local_sync_store.dart';
import 'package:conduit/features/sync/domain/sync_category.dart';
import 'package:conduit/features/terminal/domain/host_key_verifier.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';
import 'package:conduit/features/this_computer/data/self_machine_matcher.dart';
import 'package:conduit/features/this_computer/domain/this_computer_settings.dart';
import 'package:conduit/features/this_computer/presentation/self_machine_watcher.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';
import '../sync/sync_test_support.dart';

/// The phone's SSH entry for André's PC, synced to the PC.
final omarchy = buildHost('omarchy-ssh').copyWith(
  name: 'omarchy',
  host: '100.97.235.112',
  startTmuxOnConnect: true,
  tmuxPrefixKey: MultiplexerPrefixKey.controlA,
  tmuxSessionName: 'work',
);
final box = buildHost('box').copyWith(name: 'box', host: 'box.lan');

SelfMachineProbes probesFor(
  List<String> addresses, {
  void Function()? onProbe,
}) => SelfMachineProbes(
  interfaceAddresses: () async {
    onProbe?.call();
    return addresses;
  },
  localHostname: () => 'omarchy',
  tailscale: () async => null,
  hostKeys: () async => const [],
);

/// A desktop's machines with [omarchy] synced in and matched as this
/// device.
Future<(HostsController, FakeHostsRepository, InMemoryThisComputerStore)>
desktop({
  ThisComputerSettings? settings,
  bool match = true,
  List<SavedHost>? hosts,
}) async {
  final repository = FakeHostsRepository()..persisted = hosts ?? [omarchy, box];
  final store = InMemoryThisComputerStore(
    settings ??
        ThisComputerSettings(host: SavedHost.thisComputer(hostname: 'omarchy')),
  );
  final controller = HostsController(repository, thisComputerStore: store);
  await controller.load();
  if (match) controller.setSelfMachineId(omarchy.id);
  return (controller, repository, store);
}

void main() {
  group('HostsController with a machine that is this device', () {
    test('hides it from every list but keeps it saved', () async {
      final (hosts, repository, _) = await desktop();

      expect(hosts.selfMachine, omarchy);
      expect(hosts.hiddenSelfMachine, omarchy);
      expect(hosts.hosts, [omarchy, box]);
      expect(hosts.sortedHosts, [box]);
      expect(hosts.machines.map((h) => h.id), [thisComputerHostId, 'box']);
      expect(hosts.sortedMachines.map((h) => h.id), [
        thisComputerHostId,
        'box',
      ]);
      expect(repository.persisted, [omarchy, box]);
    });

    test(
      'This computer carries its name, and its id opens This computer',
      () async {
        final (hosts, _, _) = await desktop();

        expect(hosts.thisComputer!.name, 'This computer · omarchy');
        final found = hosts.findById(omarchy.id);
        expect(found?.id, thisComputerHostId);
        expect(found?.isThisComputer, isTrue);
        expect(hosts.findById('box'), box);
      },
    );

    test('preferences fall back to it, read-only', () async {
      final (hosts, repository, store) = await desktop();

      final local = hosts.thisComputer!;
      expect(local.startTmuxOnConnect, isTrue);
      expect(local.tmuxPrefixKey, MultiplexerPrefixKey.controlA);
      expect(local.tmuxSessionName, 'work');

      // Using This computer saves only its own settings, and borrows
      // nothing for good.
      await hosts.markConnected(local);
      expect(repository.persisted, [omarchy, box]);
      expect(store.settings.host.startTmuxOnConnect, isFalse);
      expect(store.settings.host.name, 'This computer');
      expect(store.settings.ownPrefs, isEmpty);

      // A choice made on This computer is its own, even the default.
      await hosts.upsert(
        hosts.thisComputer!.copyWith(startTmuxOnConnect: false),
      );
      expect(store.settings.ownPrefs, {SelfMachinePref.startMultiplexer});
      expect(hosts.thisComputer!.startTmuxOnConnect, isFalse);
      expect(hosts.thisComputer!.tmuxPrefixKey, MultiplexerPrefixKey.controlA);
      expect(repository.persisted, [omarchy, box]);
    });

    test('a value This computer already had stays its own', () async {
      final (hosts, _, _) = await desktop(
        settings: ThisComputerSettings(
          host: SavedHost.thisComputer().copyWith(
            tmuxPrefixKey: MultiplexerPrefixKey.controlSpace,
          ),
        ),
      );
      expect(
        hosts.thisComputer!.tmuxPrefixKey,
        MultiplexerPrefixKey.controlSpace,
      );
      expect(hosts.thisComputer!.startTmuxOnConnect, isTrue);
    });

    test('per-host lookups fall back from This computer to it', () async {
      final (hosts, _, _) = await desktop();
      expect(hosts.fallbackHostIdFor(thisComputerHostId), omarchy.id);
      expect(
        hosts.fallbackHostIdFor('$thisComputerHostId#tmux:main'),
        '${omarchy.id}#tmux:main',
      );
      expect(hosts.fallbackHostIdFor('box'), isNull);

      final views = SessionViewController(
        InMemorySessionViewPreferencesRepository(
          const SessionViewPreferences().withOverride(
            '${omarchy.id}#tmux:main',
            SessionView.chat,
          ),
        ),
      )..fallbackHostOf = hosts.fallbackHostIdFor;
      await views.load();
      expect(
        views.viewFor('$thisComputerHostId#tmux:main', runsClaude: true),
        SessionView.chat,
      );
      // Choosing on This computer saves under This computer only.
      await views.setOverride(
        '$thisComputerHostId#tmux:main',
        SessionView.terminal,
      );
      expect(
        views.overrideFor('$thisComputerHostId#tmux:main'),
        SessionView.terminal,
      );
      expect(
        views.preferences.overrideFor('${omarchy.id}#tmux:main'),
        SessionView.chat,
      );

      final ports = InMemoryLivePreviewPortStore()..ports[omarchy.id] = 5173;
      final store = FallbackLivePreviewPortStore(
        ports,
        hosts.fallbackHostIdFor,
      );
      expect(await store.read(thisComputerHostId), 5173);
      await store.write(thisComputerHostId, 3000);
      expect(await store.read(thisComputerHostId), 3000);
      expect(ports.ports[omarchy.id], 5173);
    });

    test('reordering the list keeps it in the synced order', () async {
      final (hosts, repository, _) = await desktop(
        hosts: [
          box,
          omarchy,
          buildHost('c').copyWith(name: 'c'),
        ],
      );
      await hosts.setSortMode(HostListSortMode.manual);
      expect(hosts.manualOrder, ['box', 'c', omarchy.id]);
      await hosts.reorderManual(1, 0);
      expect(hosts.sortedHosts.map((h) => h.id), ['c', 'box']);
      expect(hosts.manualOrder, ['c', 'box', omarchy.id]);
      expect(repository.persistedManualOrder, ['c', 'box', omarchy.id]);
    });

    test('"Show it separately here too" lists it again', () async {
      final (hosts, repository, store) = await desktop();

      await hosts.setShowSelfSeparately(true);
      expect(store.settings.showSelfSeparately, isTrue);
      expect(hosts.selfMachine, omarchy);
      expect(hosts.hiddenSelfMachine, isNull);
      expect(hosts.sortedHosts.map((h) => h.id), contains(omarchy.id));
      expect(hosts.findById(omarchy.id), omarchy);
      expect(hosts.thisComputer!.name, 'This computer');
      expect(hosts.thisComputer!.startTmuxOnConnect, isFalse);
      expect(hosts.fallbackHostIdFor(thisComputerHostId), isNull);
      expect(repository.persisted, [omarchy, box]);

      // Kept per device: it comes back on the next start.
      final again = HostsController(repository, thisComputerStore: store);
      await again.load();
      again.setSelfMachineId(omarchy.id);
      expect(again.showSelfSeparately, isTrue);
      expect(again.hiddenSelfMachine, isNull);

      await hosts.setShowSelfSeparately(false);
      expect(hosts.hiddenSelfMachine, omarchy);
    });

    test('phones ignore a match', () async {
      final repository = FakeHostsRepository()..persisted = [omarchy, box];
      final hosts = HostsController(repository);
      await hosts.load();
      hosts.setSelfMachineId(omarchy.id);
      expect(hosts.selfMachine, isNull);
      expect(hosts.sortedHosts, contains(omarchy));
      expect(hosts.findById(omarchy.id), omarchy);
      await hosts.selfMachineKnown();
    });
  });

  test('sync exports the machine that is this device unchanged', () async {
    final repository = FakeHostsRepository()..persisted = [omarchy, box];
    final hosts = HostsController(
      repository,
      thisComputerStore: InMemoryThisComputerStore(
        ThisComputerSettings(host: SavedHost.thisComputer()),
      ),
    );
    await hosts.load();
    final store = AppLocalSyncStore(
      hosts: hosts,
      theme: await _theme(),
      hostKeys: MemoryVerifier(),
      connectPreferences: MemoryJsonMapStore(),
      recentDirectoriesStore: MemoryJsonMapStore(),
      sessions: InMemorySessionSnapshotRepository(),
    );
    const options = LocalSyncOptions(categories: SyncCategory.defaults);
    final before = await store.snapshot(options);

    hosts.setSelfMachineId(omarchy.id);
    await hosts.markConnected(hosts.thisComputer!);
    final after = await store.snapshot(options);

    expect(after[SyncKeys.host(omarchy.id)], isNotNull);
    expect(after[SyncKeys.host(omarchy.id)], before[SyncKeys.host(omarchy.id)]);
    expect(after.keys.toSet(), before.keys.toSet());
    expect(
      after.keys.where((key) => key.contains(thisComputerHostId)),
      isEmpty,
    );
  });

  test('a restored session on it opens on This computer', () async {
    final (hosts, _, _) = await desktop();
    final workspace = TerminalWorkspaceController(
      ImmediateTerminalRepository(TrackableTerminalSession()),
    );
    final restore = SessionRestoreController(
      workspace: workspace,
      repository: InMemorySessionSnapshotRepository(
        SessionSnapshot(
          entries: [
            SessionSnapshotEntry(
              hostId: omarchy.id,
              target: const ConnectTarget.tmux('main'),
            ),
            const SessionSnapshotEntry(
              hostId: 'box',
              target: ConnectTarget.shell(),
            ),
          ],
        ),
      ),
      findHost: (id) async {
        await hosts.selfMachineKnown();
        return hosts.findById(id);
      },
    );
    await restore.restore();

    expect(workspace.sessions.map((s) => s.host.id), [
      '$thisComputerHostId#tmux:main',
      'box',
    ]);
    expect(workspace.sessions.first.host.isThisComputer, isTrue);
    restore.dispose();
    workspace.dispose();
  });

  test('sidebar pins and groups of it carry over to This computer', () {
    final pin = SidebarKeys.herdrWorkspace(omarchy.id, 'w1');
    final session = SidebarKeys.openSession(omarchy.id, '${omarchy.id}#tmux:x');
    final prefs = SidebarPrefs(
      machineOrder: ['box', omarchy.id],
      pinned: [pin, session, SidebarKeys.machine('box')],
      groups: [
        SidebarGroup(id: 'g', name: 'Home', machineIds: [omarchy.id]),
      ],
      expanded: {SidebarKeys.machine(omarchy.id): false},
    );

    final aliased = prefs.withMachineAlias(omarchy.id, thisComputerHostId);
    expect(aliased.pinned, [
      SidebarKeys.herdrWorkspace(thisComputerHostId, 'w1'),
      SidebarKeys.openSession(thisComputerHostId, '$thisComputerHostId#tmux:x'),
      SidebarKeys.machine('box'),
    ]);
    expect(aliased.groupOf(thisComputerHostId)?.id, 'g');
    expect(aliased.machineOrder, ['box', thisComputerHostId]);
    expect(
      aliased.isExpanded(
        SidebarKeys.machine(thisComputerHostId),
        byDefault: true,
      ),
      isFalse,
    );
    // What This computer has of its own wins.
    final own = prefs
        .setGroup(thisComputerHostId, null)
        .copyWith(machineOrder: [thisComputerHostId, 'box', omarchy.id]);
    expect(own.withMachineAlias(omarchy.id, thisComputerHostId).machineOrder, [
      thisComputerHostId,
      'box',
    ]);
  });

  group('SelfMachineWatcher', () {
    test('matches after load and when machines or keys change', () async {
      final repository = FakeHostsRepository()..persisted = [box];
      final hosts = HostsController(
        repository,
        thisComputerStore: InMemoryThisComputerStore(
          ThisComputerSettings(host: SavedHost.thisComputer()),
        ),
      );
      var probes = 0;
      final verifier = MemoryVerifier();
      final changes = LocalDataChanges();
      final watcher = SelfMachineWatcher(
        hosts: hosts,
        matcher: SelfMachineMatcher(
          enabled: true,
          probes: probesFor(['100.97.235.112'], onProbe: () => probes += 1),
        ),
        trustedKeys: verifier.loadTrustedKeys,
        dataChanges: changes,
        observeLifecycle: false,
      );
      await hosts.load();
      await watcher.start();
      await hosts.selfMachineKnown();
      expect(hosts.selfMachine, isNull);

      // Sync brings the phone's entry for this PC in.
      await hosts.replaceAll([omarchy, box]);
      await watcher.check();
      expect(hosts.selfMachine, omarchy);
      expect(watcher.lastMatch?.host, omarchy);
      expect(hosts.sortedHosts, [box]);

      // A synced known host says it is another machine after all.
      verifier.records = [
        HostKeyRecord(
          host: omarchy.host,
          port: 22,
          type: 'ssh-ed25519',
          fingerprint: 'MD5:00',
          trustedAt: DateTime.utc(2026),
        ),
      ];
      final withKeys = SelfMachineWatcher(
        hosts: hosts,
        matcher: SelfMachineMatcher(
          enabled: true,
          probes: SelfMachineProbes(
            interfaceAddresses: () async => ['100.97.235.112'],
            localHostname: () => 'omarchy',
            tailscale: () async => null,
            hostKeys: () async => const [
              'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIACR5Qr1xMX44j3jiFQRYSMgmbSos6s187FvZyIauZw9',
            ],
          ),
        ),
        trustedKeys: verifier.loadTrustedKeys,
        observeLifecycle: false,
      );
      await withKeys.check();
      expect(hosts.selfMachine, isNull);
      expect(probes, 1);

      // A network change looks at the device again.
      await watcher.refresh();
      expect(probes, 2);
      watcher.dispose();
      withKeys.dispose();
    });

    test('never probes on a phone', () async {
      final hosts = HostsController(
        FakeHostsRepository()..persisted = [omarchy],
      );
      var probes = 0;
      final watcher = SelfMachineWatcher(
        hosts: hosts,
        matcher: SelfMachineMatcher(
          enabled: false,
          probes: probesFor(['100.97.235.112'], onProbe: () => probes += 1),
        ),
        trustedKeys: () async => const [],
        observeLifecycle: false,
      );
      await hosts.load();
      await watcher.start();
      await watcher.check();
      expect(probes, 0);
      expect(hosts.sortedHosts, [omarchy]);
      watcher.dispose();
    });
  });
}

Future<ThemeController> _theme() async {
  final theme = ThemeController(InMemoryThemePreferences());
  await theme.load();
  return theme;
}
