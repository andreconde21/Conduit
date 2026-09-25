import 'dart:async';
import 'dart:convert';

import 'package:conduit/core/app_failure.dart';
import 'package:conduit/features/agent_attention/data/herdr_attention_provider.dart';
import 'package:conduit/features/agent_attention/data/remote_tool_command.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/sessions/domain/remote_session_listing.dart';

/// A neighbour direction for `herdr pane focus --direction`.
enum HerdrDirection { left, right, up, down }

/// Herdr CLI commands for one Herdr server (the default session, or a named
/// one via `--session`), wrapped for a non-interactive SSH shell.
///
/// Every command here was checked against Herdr 0.9.1 (each command's
/// `--help`), and the pane and zoom commands were run against a live
/// server: without `--pane`/`--current` they act on the UI-focused pane,
/// which is what a phone gesture means.
class HerdrCommands {
  const HerdrCommands([this.session = '']);

  /// Named Herdr session; empty for the default one.
  final String session;

  String _herdr(String args) => HerdrAttentionProvider.remoteCommand(
    session.isEmpty ? args : '--session ${shellQuoteArgument(session)} $args',
  );

  String get workspaceList => _herdr('workspace list');
  String get tabList => _herdr('tab list');
  String get paneList => _herdr('pane list');
  String get agentList => _herdr('agent list');

  String workspaceFocus(String workspaceId) =>
      _herdr('workspace focus ${shellQuoteArgument(workspaceId)}');

  String tabFocus(String tabId) =>
      _herdr('tab focus ${shellQuoteArgument(tabId)}');

  /// `herdr agent focus <pane_id>`: switches workspace and tab as needed.
  String agentFocus(String paneId) =>
      _herdr('agent focus ${shellQuoteArgument(paneId)}');

  String paneFocus(HerdrDirection direction) =>
      _herdr('pane focus --direction ${direction.name}');

  String paneZoom({required bool on}) =>
      _herdr('pane zoom ${on ? '--on' : '--off'}');

  String paneClose(String paneId) =>
      _herdr('pane close ${shellQuoteArgument(paneId)}');
}

/// Drives one Herdr server over a dedicated command channel (never the
/// terminal the user types in).
///
/// The channel is opened on first use and kept for [idleTimeout] so a burst
/// of gestures shares one SSH connection. Commands run one at a time in the
/// order they were asked for, so "remember where the old tab was, then
/// focus the new one" cannot overtake itself.
class HerdrRemoteControl {
  HerdrRemoteControl({
    required this.runnerFactory,
    this.session = '',
    this.idleTimeout = const Duration(minutes: 2),
  }) : commands = HerdrCommands(session);

  static const _timeout = Duration(seconds: 10);

  /// Opens the command channel; called again after an idle close.
  final AgentCommandRunner Function() runnerFactory;
  final String session;
  final HerdrCommands commands;
  final Duration idleTimeout;

  AgentCommandRunner? _runner;
  Timer? _idle;
  Future<void> _queue = Future<void>.value();
  bool _closed = false;

  /// Runs [command]; true when Herdr accepted it.
  Future<bool> run(String command) async {
    final result = await _enqueue(command);
    return result != null && _succeeded(result);
  }

  Future<AgentCommandResult?> _enqueue(String command) {
    final completer = Completer<AgentCommandResult?>();
    _queue = _queue.then((_) async {
      completer.complete(await _runNow(command));
    });
    return completer.future;
  }

  Future<AgentCommandResult?> _runNow(String command) async {
    if (_closed) {
      return null;
    }
    _idle?.cancel();
    try {
      final runner = _runner ??= runnerFactory();
      return await runner.run(command, timeout: _timeout);
    } on AppFailure {
      return null;
    } catch (_) {
      return null;
    } finally {
      if (!_closed) {
        _idle = Timer(idleTimeout, () => unawaited(_dropRunner()));
      }
    }
  }

  static bool _succeeded(AgentCommandResult result) {
    if (result.exitCode != null && result.exitCode != 0) {
      return false;
    }
    // Herdr 0.9.1 exits 1 on API errors; the error envelope is a second
    // signal in case a wrapper swallows the status.
    return !result.stdout.trimLeft().startsWith('{"error"');
  }

  Future<bool> focusWorkspace(String workspaceId) =>
      run(commands.workspaceFocus(workspaceId));

  Future<bool> focusTab(String tabId) => run(commands.tabFocus(tabId));

  Future<bool> focusPane(HerdrDirection direction) =>
      run(commands.paneFocus(direction));

  Future<bool> setZoom({required bool on}) => run(commands.paneZoom(on: on));

  /// Focuses the exact place an agent is in: its pane when known (which
  /// switches workspace and tab too), else its tab, else its workspace.
  Future<bool> focusLocation({
    String workspaceId = '',
    String tabId = '',
    String paneId = '',
  }) async {
    if (paneId.isNotEmpty && await run(commands.agentFocus(paneId))) {
      return true;
    }
    if (tabId.isNotEmpty && await focusTab(tabId)) {
      return true;
    }
    return workspaceId.isNotEmpty && await focusWorkspace(workspaceId);
  }

  /// Lists the server's workspaces in Herdr's order; null when that failed.
  Future<List<HerdrWorkspaceInfo>?> workspaces() async {
    final result = await _enqueue(commands.workspaceList);
    if (result == null) {
      return null;
    }
    final listing = RemoteSessionListing.interpretHerdrWorkspaces(result);
    return listing is RemoteListingAvailable<HerdrWorkspaceInfo>
        ? listing.items
        : null;
  }

  /// Id of the workspace Herdr has focused; null when unknown.
  Future<String?> focusedWorkspaceId() async {
    final items = await workspaces();
    if (items == null) {
      return null;
    }
    for (final workspace in items) {
      if (workspace.focused) {
        return workspace.id;
      }
    }
    return null;
  }

  /// Focuses the workspace [delta] places after the focused one, wrapping
  /// around. Returns the id it focused, or null when nothing changed.
  Future<String?> focusAdjacentWorkspace(int delta) async {
    final items = await workspaces();
    if (items == null || items.length < 2) {
      return null;
    }
    final current = items.indexWhere((workspace) => workspace.focused);
    final start = current == -1 ? 0 : current;
    final next = (start + delta) % items.length;
    final target = items[next < 0 ? next + items.length : next];
    return await focusWorkspace(target.id) ? target.id : null;
  }

  /// Closes the focused pane (looked up with `herdr pane list`).
  Future<bool> closeFocusedPane() async {
    final result = await _enqueue(commands.paneList);
    if (result == null || !_succeeded(result)) {
      return false;
    }
    final paneId = focusedPaneId(result.stdout);
    return paneId != null && await run(commands.paneClose(paneId));
  }

  /// The focused pane's id in `herdr pane list` output (the
  /// `{"result": {"panes": [...]}}` envelope of Herdr 0.9, or a bare
  /// `{"panes": [...]}` object); null when none is focused or the output is
  /// not JSON.
  static String? focusedPaneId(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw.trim());
    } catch (_) {
      return null;
    }
    Object? panes;
    if (decoded is Map) {
      final result = decoded['result'];
      panes = result is Map ? result['panes'] : decoded['panes'];
    }
    if (panes is! List) {
      return null;
    }
    for (final pane in panes) {
      if (pane is Map && pane['focused'] == true) {
        final id = pane['pane_id'];
        if (id is String && id.isNotEmpty) {
          return id;
        }
      }
    }
    return null;
  }

  Future<void> _dropRunner() async {
    final runner = _runner;
    _runner = null;
    if (runner != null) {
      try {
        await runner.close();
      } catch (_) {
        // Already gone.
      }
    }
  }

  /// Closes the channel; later calls do nothing and report failure.
  Future<void> close() async {
    _closed = true;
    _idle?.cancel();
    await _queue;
    await _dropRunner();
  }
}
