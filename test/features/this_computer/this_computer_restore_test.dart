import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/hosts/presentation/hosts_controller.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/sessions/domain/session_snapshot.dart';
import 'package:conduit/features/sessions/presentation/session_restore_controller.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';
import 'package:conduit/features/this_computer/domain/this_computer_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

void main() {
  test('local tmux and Herdr sessions come back on launch', () async {
    final hostsController = HostsController(
      FakeHostsRepository(),
      thisComputerStore: InMemoryThisComputerStore(
        ThisComputerSettings(host: SavedHost.thisComputer()),
      ),
    );
    final workspace = TerminalWorkspaceController(
      ImmediateTerminalRepository(TrackableTerminalSession()),
    );
    final store = InMemorySessionSnapshotRepository(
      const SessionSnapshot(
        entries: [
          SessionSnapshotEntry(
            hostId: thisComputerHostId,
            target: ConnectTarget.tmux('main'),
          ),
          SessionSnapshotEntry(
            hostId: thisComputerHostId,
            target: ConnectTarget.herdr(workspaceId: 'w1', label: 'api'),
          ),
        ],
        activeIndex: 1,
      ),
    );
    final restore = SessionRestoreController(
      workspace: workspace,
      repository: store,
      findHost: (id) async {
        await hostsController.firstLoad;
        return hostsController.findById(id);
      },
    );
    await hostsController.load();
    await restore.restore();

    final sessions = workspace.sessions;
    expect(sessions.map((s) => s.host.id), [
      '$thisComputerHostId#tmux:main',
      '$thisComputerHostId#herdr:w1',
    ]);
    expect(sessions.every((s) => s.host.isThisComputer), isTrue);
    expect(sessions.first.host.startTmuxOnConnect, isTrue);
    expect(sessions.last.startupCommand, contains('herdr'));
    expect(workspace.activeSession, sessions.last);
    expect(
      SessionRestoreController.modeFor(
        hostsController.thisComputer!,
        const ConnectTarget.tmux('main'),
      ),
      RestoredSessionMode.automatic,
    );

    // And the list written back keeps them.
    expect(restore.currentSnapshot().entries.map((e) => e.hostId), [
      thisComputerHostId,
      thisComputerHostId,
    ]);
    restore.dispose();
    workspace.dispose();
  });
}
