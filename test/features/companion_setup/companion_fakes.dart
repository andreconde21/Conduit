import 'dart:convert';
import 'dart:typed_data';

import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/companion_setup/data/companion_bundle.dart';

AgentCommandResult ok(String stdout) =>
    AgentCommandResult(stdout: stdout, stderr: '', exitCode: 0);

AgentCommandResult failed(int code, {String stdout = '', String stderr = ''}) =>
    AgentCommandResult(stdout: stdout, stderr: stderr, exitCode: code);

final notFound = failed(
  127,
  stderr: 'sh: 1: exec: conductore-hostd: not found',
);

String versionJson({String version = '0.1.0', int protocol = 1}) =>
    jsonEncode({'version': version, 'protocol': protocol, 'node': '22.1.0'});

String doctorJson({
  bool hooks = true,
  bool daemon = false,
  bool hookClient = true,
}) => jsonEncode({
  'ok': hooks && hookClient,
  'user': 'andre',
  'checks': [
    {'name': 'node', 'ok': true, 'detail': 'node 22.1.0 (need >= 18)'},
    {'name': 'hook client', 'ok': hookClient, 'detail': '/x/conductore-hook'},
    {'name': 'settings.json', 'ok': true, 'detail': '/h/.claude/settings.json'},
    {
      'name': 'hooks registered',
      'ok': hooks,
      'detail': hooks ? '9 events' : 'missing: SessionStart, Stop',
    },
    {
      'name': 'daemon',
      'ok': daemon,
      'detail': daemon ? 'pid 42, seq 7' : 'not running (ENOENT)',
    },
    {'name': 'herdr', 'ok': false, 'detail': 'not found (optional)'},
  ],
});

String statusJson({
  List<Map<String, Object?>> agents = const [],
  String source = 'none',
  int seq = 0,
}) =>
    jsonEncode({'version': 1, 'seq': seq, 'source': source, 'agents': agents});

Map<String, Object?> agent(
  String id, {
  required DateTime updatedAt,
  String state = 'working',
}) => {
  'sessionId': id,
  'name': id,
  'state': state,
  'updatedAt': updatedAt.millisecondsSinceEpoch,
  'pending': <Object?>[],
};

/// Answers each command by the first key it contains; unmatched commands
/// exit 127. [responses] can be changed between calls (e.g. after an
/// install) and a value may be an exception to throw.
class MatchingRunner implements AgentCommandRunner {
  MatchingRunner(this.responses);

  final Map<String, Object> responses;
  final List<String> commands = [];
  int closeCount = 0;

  @override
  Future<AgentCommandResult> run(
    String command, {
    required Duration timeout,
  }) async {
    commands.add(command);
    for (final entry in responses.entries) {
      if (command.contains(entry.key)) {
        final value = entry.value;
        if (value is AgentCommandResult) return value;
        // ignore: only_throw_errors
        throw value;
      }
    }
    return failed(127, stderr: 'not found');
  }

  bool ran(String fragment) => commands.any((c) => c.contains(fragment));

  @override
  Future<void> close() async => closeCount += 1;
}

/// The commands a healthy, active companion answers.
Map<String, Object> healthyResponses({bool daemon = true}) => {
  'conductore-hostd version': ok(versionJson()),
  'conductore-hostd doctor': ok(doctorJson(daemon: daemon)),
  'conductore-hostd status': ok(statusJson()),
  'exec node --version': ok('v22.1.0\n'),
  'exec claude --version': ok('2.1.0 (Claude Code)\n'),
};

CompanionBundle fakeBundle() => CompanionBundle(
  version: '0.2.0',
  files: {
    'install.sh': Uint8List.fromList(utf8.encode('#!/bin/sh\n')),
    'bin/conductore-hostd': Uint8List.fromList(utf8.encode('hostd')),
    'bin/conductore-hook': Uint8List.fromList(utf8.encode('hook')),
    'lib/cli.js': Uint8List.fromList(utf8.encode('cli')),
  },
);
