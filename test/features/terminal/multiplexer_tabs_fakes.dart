import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';

/// One `list-windows` line as [TmuxWindowCommands.list] prints it.
String tmuxWindowLine(
  String id,
  int index,
  String name, {
  bool active = false,
  int activity = 0,
  bool bell = false,
}) => [
  'W',
  id,
  '$index',
  active ? '1' : '0',
  '0',
  bell ? '1' : '0',
  '$activity',
  name,
].join('\t');

/// A real `herdr tab list` answer (Herdr 0.9.1), focused on w4:t2.
const herdrTabList =
    '{"id":"cli:tab:list","result":{"tabs":['
    '{"agent_status":"idle","focused":false,"label":"Main","number":1,'
    '"pane_count":1,"tab_id":"w7:t1","workspace_id":"w7"},'
    '{"agent_status":"idle","focused":false,"label":"","number":3,'
    '"pane_count":1,"tab_id":"w4:t3","workspace_id":"w4"},'
    '{"agent_status":"blocked","focused":false,"label":"Infrastructure",'
    '"number":1,"pane_count":1,"tab_id":"w4:t1","workspace_id":"w4"},'
    '{"agent_status":"working","focused":true,"label":"review","number":2,'
    '"pane_count":2,"tab_id":"w4:t2","workspace_id":"w4"}]}}';

const _herdrWorkspaces =
    '{"id":"cli:workspace:list","result":{"type":"workspace_list",'
    '"workspaces":[{"active_tab_id":"w4:t2","agent_status":"idle",'
    '"focused":false,"label":"Infra","number":1,"tab_count":3,'
    '"workspace_id":"w4"}]}}';

const _herdrPanes =
    '{"result":{"panes":[{"pane_id":"w4:p2","focused":true,'
    '"workspace_id":"w4","tab_id":"w4:t2","cwd":"/srv/infra"}]}}';

AgentCommandResult _ok(String stdout) =>
    AgentCommandResult(stdout: stdout, stderr: '', exitCode: 0);

/// A tmux server with one session's windows, acting on the window
/// commands the strip sends; records every command.
class FakeTmux implements AgentCommandRunner {
  FakeTmux(List<String> names, {int active = 0})
    : windows = [
        for (final (i, name) in names.indexed)
          FakeWindow('@$i', name, active: i == active),
      ];

  final List<FakeWindow> windows;
  final List<String> commands = [];

  /// Commands containing one of these fail (exit 1).
  final Set<String> failing = {};
  int closeCount = 0;
  int _next = 100;

  static final _target = RegExp(r'-t \S*?(@\d+)');
  static final _source = RegExp(r'-s \S*?(@\d+)');

  @override
  Future<AgentCommandResult> run(
    String command, {
    required Duration timeout,
  }) async {
    commands.add(command);
    if (failing.any(command.contains)) {
      return const AgentCommandResult(stdout: '', stderr: 'no', exitCode: 1);
    }
    if (command.contains('list-windows')) {
      return _ok(
        [
          for (final (i, w) in windows.indexed)
            tmuxWindowLine(
              w.id,
              i,
              w.name,
              active: w.active,
              activity: w.unread ? 99 : 0,
              bell: w.unread,
            ),
        ].join('\n'),
      );
    }
    final target = _target.firstMatch(command)?.group(1);
    int at(String? id) => windows.indexWhere((w) => w.id == id);
    if (command.contains('swap-window')) {
      final a = at(_source.firstMatch(command)?.group(1));
      final b = at(target);
      final moved = windows[a];
      windows[a] = windows[b];
      windows[b] = moved;
    } else if (command.contains('select-window')) {
      for (final w in windows) {
        w.active = w.id == target;
      }
    } else if (command.contains('new-window')) {
      for (final w in windows) {
        w.active = false;
      }
      windows.insert(
        at(target) + 1,
        FakeWindow('@${_next++}', 'bash', active: true),
      );
    } else if (command.contains('rename-window')) {
      final name = RegExp(
        r"rename-window -t \S+ (.*)'$",
      ).firstMatch(command)!.group(1)!.replaceAll("'\\''", '');
      windows[at(target)].name = name;
    } else if (command.contains('kill-window')) {
      windows.removeAt(at(target));
    }
    return _ok('');
  }

  @override
  Future<void> close() async => closeCount += 1;
}

class FakeWindow {
  FakeWindow(this.id, this.name, {this.active = false});

  final String id;
  String name;
  bool active;

  /// Raises the bell flag, as news in the window would.
  bool unread = false;
}

/// A Herdr server answering the tab strip's commands; records them.
class FakeHerdr implements AgentCommandRunner {
  FakeHerdr({this.focused = true});

  final bool focused;
  final List<String> commands = [];

  @override
  Future<AgentCommandResult> run(
    String command, {
    required Duration timeout,
  }) async {
    commands.add(command);
    if (command.contains('tab list')) {
      return _ok(
        focused
            ? herdrTabList
            : herdrTabList.replaceAll('"focused":true', '"focused":false'),
      );
    }
    if (command.contains('workspace list')) return _ok(_herdrWorkspaces);
    if (command.contains('pane list')) return _ok(_herdrPanes);
    return _ok('{"result":{}}');
  }

  @override
  Future<void> close() async {}
}
