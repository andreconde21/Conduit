import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';

/// A tiny stateful Herdr server: `workspace focus`, `tab focus` and
/// `agent focus` move the focus, and `workspace list` reports it, so tests
/// can check where a sequence of commands leaves Herdr.
class FakeHerdrServer {
  FakeHerdrServer({
    this.workspaces = const ['w1', 'w2', 'w3'],
    this.focusedWorkspace = 'w1',
  });

  final List<String> workspaces;
  String focusedWorkspace;
  String focusedTab = '';
  String focusedPane = '';
  final List<String> commands = [];
  int runnersOpened = 0;
  int runnersClosed = 0;

  /// The herdr arguments of each command, without the PATH wrapper.
  List<String> get herdrArgs => [
    for (final command in commands)
      RegExp(r"exec herdr ([^']*)").firstMatch(command)?.group(1) ?? command,
  ];

  AgentCommandRunner runner() {
    runnersOpened += 1;
    return _FakeHerdrServerRunner(this);
  }

  AgentCommandResult handle(String command) {
    commands.add(command);
    final args = RegExp(r"exec herdr ([^']*)").firstMatch(command)?.group(1);
    if (args == null) {
      return const AgentCommandResult(stdout: '', stderr: '', exitCode: 0);
    }
    final parts = args.split(' ');
    if (args.contains('workspace list')) {
      final items = [
        for (final (index, id) in workspaces.indexed)
          '{"workspace_id":"$id","label":"W$id","number":${index + 1},'
              '"focused":${id == focusedWorkspace},"tab_count":1,'
              '"active_tab_id":"$id:t1"}',
      ];
      return AgentCommandResult(
        stdout: '{"result":{"workspaces":[${items.join(',')}]}}',
        stderr: '',
        exitCode: 0,
      );
    }
    if (args.contains('workspace focus')) {
      final id = parts.last;
      if (!workspaces.contains(id)) {
        return _notFound;
      }
      focusedWorkspace = id;
    } else if (args.contains('tab focus')) {
      focusedTab = parts.last;
      focusedWorkspace = focusedTab.split(':').first;
    } else if (args.contains('agent focus')) {
      focusedPane = parts.last;
      focusedWorkspace = focusedPane.split(':').first;
    }
    return const AgentCommandResult(stdout: '{}', stderr: '', exitCode: 0);
  }

  static const _notFound = AgentCommandResult(
    stdout: '{"error":{"code":"workspace_not_found"}}',
    stderr: '',
    exitCode: 1,
  );
}

class _FakeHerdrServerRunner implements AgentCommandRunner {
  _FakeHerdrServerRunner(this._server);

  final FakeHerdrServer _server;

  @override
  Future<AgentCommandResult> run(
    String command, {
    required Duration timeout,
  }) async => _server.handle(command);

  @override
  Future<void> close() async {
    _server.runnersClosed += 1;
  }
}
