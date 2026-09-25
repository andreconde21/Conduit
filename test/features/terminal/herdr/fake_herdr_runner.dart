import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';

/// Answers Herdr CLI commands from canned output and records what ran.
class FakeHerdrRunner implements AgentCommandRunner {
  FakeHerdrRunner(this._respond);

  /// Two workspaces: Infrastructure (focused; tab "main" with a working
  /// Claude, tab "logs" with no agent) and TheCalendar (tab "api" with a
  /// blocked Codex).
  factory FakeHerdrRunner.withPanes() => FakeHerdrRunner(panesResponse);

  factory FakeHerdrRunner.notInstalled() => FakeHerdrRunner(
    (_) => const AgentCommandResult(
      stdout: '',
      stderr: 'sh: 1: exec: herdr: not found',
      exitCode: 127,
    ),
  );

  final AgentCommandResult Function(String command) _respond;
  final List<String> commands = [];
  bool closed = false;

  static AgentCommandResult panesResponse(String command) {
    if (command.contains('herdr/config.toml')) {
      // Tests that care about the machine's keymap script it themselves.
      return const AgentCommandResult(
        stdout: '',
        stderr: 'cat: Permission denied',
        exitCode: 1,
      );
    }
    if (command.contains('workspace list')) {
      return const AgentCommandResult(
        stdout:
            '{"id":"1","result":{"workspaces":['
            '{"workspace_id":"w1","label":"Infrastructure","number":1,'
            '"focused":true,"tab_count":2,"active_tab_id":"w1:t1"},'
            '{"workspace_id":"w2","label":"TheCalendar","number":2,'
            '"focused":false,"tab_count":1,"active_tab_id":"w2:t1"}]}}',
        stderr: '',
        exitCode: 0,
      );
    }
    if (command.contains('tab list')) {
      return const AgentCommandResult(
        stdout:
            '{"result":{"tabs":['
            '{"tab_id":"w1:t2","workspace_id":"w1","label":"logs","number":2},'
            '{"tab_id":"w1:t1","workspace_id":"w1","label":"main","number":1,'
            '"focused":true},'
            '{"tab_id":"w2:t1","workspace_id":"w2","label":"api","number":1,'
            '"focused":true}]}}',
        stderr: '',
        exitCode: 0,
      );
    }
    if (command.contains('agent list')) {
      return const AgentCommandResult(
        stdout:
            '{"result":{"agents":['
            '{"agent":"claude","name":"reviewer","agent_status":"working",'
            '"pane_id":"w1:p1","tab_id":"w1:t1","workspace_id":"w1"},'
            '{"agent":"codex","agent_status":"blocked",'
            '"terminal_title_stripped":"fix-auth",'
            '"pane_id":"w2:p1","tab_id":"w2:t1","workspace_id":"w2"}]}}',
        stderr: '',
        exitCode: 0,
      );
    }
    return const AgentCommandResult(stdout: '', stderr: '', exitCode: 0);
  }

  @override
  Future<AgentCommandResult> run(
    String command, {
    required Duration timeout,
  }) async {
    commands.add(command);
    return _respond(command);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
