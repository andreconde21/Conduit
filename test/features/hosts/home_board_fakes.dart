import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';

/// Canned `herdr` output for the home board tests.
abstract final class HerdrFixtures {
  static const workspaces =
      '{"id":"1","result":{"workspaces":['
      '{"workspace_id":"w1","label":"Infrastructure","number":1,'
      '"agent_status":"working","focused":true,"tab_count":2,'
      '"active_tab_id":"w1:t1"},'
      '{"workspace_id":"w2","label":"TheCalendar","number":2,'
      '"agent_status":"idle","tab_count":1}]}}';

  static const tabs =
      '{"id":"2","result":{"tabs":['
      '{"tab_id":"w1:t1","workspace_id":"w1","label":"main","number":1},'
      '{"tab_id":"w1:t2","workspace_id":"w1","label":"review","number":2},'
      '{"tab_id":"w2:t1","workspace_id":"w2","label":"","number":1}]}}';

  static const agents =
      '{"id":"3","result":{"agents":['
      '{"agent":"claude","pane_id":"w1:p2","tab_id":"w1:t2",'
      '"workspace_id":"w1","agent_status":"blocked",'
      '"terminal_title_stripped":"Proofing PR 398"},'
      '{"agent":"claude","pane_id":"w1:p1","tab_id":"w1:t1",'
      '"workspace_id":"w1","agent_status":"working",'
      '"terminal_title_stripped":"Deploying images"},'
      '{"agent":"codex","pane_id":"w2:p1","tab_id":"w2:t1",'
      '"workspace_id":"w2","agent_status":"done",'
      '"terminal_title_stripped":"Nightly E2E"}]}}';

  static const notRunning =
      '{"error":{"code":"server_not_running","message":"no server"}}';
}

/// Answers `herdr` commands by what they ask for; records every command.
class HerdrFakeRunner implements AgentCommandRunner {
  HerdrFakeRunner({
    this.workspaces = HerdrFixtures.workspaces,
    this.tabs = HerdrFixtures.tabs,
    this.agents = HerdrFixtures.agents,
    this.workspaceExitCode = 0,
    this.workspaceStderr = '',
    this.error,
  });

  String workspaces;
  String tabs;
  String agents;
  int workspaceExitCode;
  String workspaceStderr;

  /// Thrown by every call when set (a dead connection).
  Object? error;

  final List<String> commands = [];
  int closeCount = 0;

  @override
  Future<AgentCommandResult> run(
    String command, {
    required Duration timeout,
  }) async {
    commands.add(command);
    final failure = error;
    if (failure != null) {
      // ignore: only_throw_errors
      throw failure;
    }
    if (command.contains('workspace list')) {
      return AgentCommandResult(
        stdout: workspaces,
        stderr: workspaceStderr,
        exitCode: workspaceExitCode,
      );
    }
    if (command.contains('tab list')) {
      return AgentCommandResult(stdout: tabs, stderr: '', exitCode: 0);
    }
    if (command.contains('agent list')) {
      return AgentCommandResult(stdout: agents, stderr: '', exitCode: 0);
    }
    return const AgentCommandResult(stdout: '', stderr: '', exitCode: 0);
  }

  @override
  Future<void> close() async {
    closeCount += 1;
  }
}
