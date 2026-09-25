import 'package:conduit/core/app_failure.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/companion_setup/data/companion_commands.dart';
import 'package:conduit/features/companion_setup/domain/companion_status.dart';

/// Collects what [classifyCompanionStatus] needs from one machine in two
/// round trips: `version`, `node --version` and `claude --version` in
/// parallel, then (when the CLI answered) `doctor` and `status`.
class CompanionProbe {
  const CompanionProbe({
    this.timeout = const Duration(seconds: 20),
    this.clock = DateTime.now,
  });

  final Duration timeout;
  final DateTime Function() clock;

  Future<CompanionStatus> check(AgentCommandRunner runner) async {
    Future<AgentCommandResult?> optional(String command) async {
      try {
        return await runner.run(command, timeout: timeout);
      } catch (_) {
        return null;
      }
    }

    AgentCommandResult version;
    try {
      final first = await Future.wait([
        runner.run(CompanionCommands.version, timeout: timeout),
        optional(CompanionCommands.node),
        optional(CompanionCommands.claude),
      ]);
      version = first[0]!;
      final node = first[1];
      final claude = first[2];
      if (version.exitCode != 0) {
        return classifyCompanionStatus(
          CompanionProbeResults(version: version, node: node, claude: claude),
          now: clock(),
        );
      }
      final second = await Future.wait([
        optional(CompanionCommands.doctor),
        optional(CompanionCommands.status),
      ]);
      return classifyCompanionStatus(
        CompanionProbeResults(
          version: version,
          node: node,
          claude: claude,
          doctor: second[0],
          status: second[1],
        ),
        now: clock(),
      );
    } catch (error) {
      return classifyCompanionStatus(
        CompanionProbeResults(
          connectionError: _describe(error),
          connectionFailure: error,
        ),
        now: clock(),
      );
    }
  }
}

String _describe(Object error) =>
    error is AppFailure ? error.userMessage : error.toString();
