import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/terminal/domain/ssh_terminal_repository.dart';
import 'package:conduit/features/terminal/domain/ssh_terminal_session.dart';

class RoutingTerminalRepository implements SshTerminalRepository {
  const RoutingTerminalRepository({
    required this.ssh,
    required this.mosh,
    required this.local,
    this.thisComputer,
  });

  final SshTerminalRepository ssh;
  final SshTerminalRepository mosh;
  final SshTerminalRepository local;

  /// The desktop's own shell ("This computer"); null on phones.
  final SshTerminalRepository? thisComputer;

  @override
  Future<SshTerminalSession> connect(
    SavedHost host, {
    required int columns,
    required int rows,
  }) {
    final desktop = thisComputer;
    if (desktop != null && host.isThisComputer) {
      return desktop.connect(host, columns: columns, rows: rows);
    }
    final repository = host.isLocal
        ? local
        : host.useMosh
        ? mosh
        : ssh;
    return repository.connect(host, columns: columns, rows: rows);
  }
}
