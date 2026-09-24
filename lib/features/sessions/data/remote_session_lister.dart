import 'package:conduit/core/app_failure.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/sessions/domain/remote_session_listing.dart';

/// Lists tmux sessions and Herdr workspaces on a host over an
/// [AgentCommandRunner] (a dedicated SSH exec channel, never the PTY).
class RemoteSessionLister {
  const RemoteSessionLister(this._runner);

  static const _timeout = Duration(seconds: 10);

  final AgentCommandRunner _runner;

  Future<RemoteListing<TmuxSessionInfo>> listTmux() async {
    try {
      final result = await _runner.run(
        RemoteSessionListing.tmuxListCommand,
        timeout: _timeout,
      );
      return RemoteSessionListing.interpretTmux(result);
    } on AppFailure catch (failure) {
      return RemoteListingFailed(failure.toString());
    } catch (error) {
      return RemoteListingFailed(error.toString());
    }
  }

  Future<RemoteListing<HerdrWorkspaceInfo>> listHerdr() async {
    try {
      final result = await _runner.run(
        RemoteSessionListing.herdrWorkspaceListCommand,
        timeout: _timeout,
      );
      final listing = RemoteSessionListing.interpretHerdrWorkspaces(result);
      if (listing is! RemoteListingAvailable<HerdrWorkspaceInfo> ||
          listing.items.every((workspace) => workspace.tabCount <= 1)) {
        return listing;
      }
      // Tab labels are a nicety: a failure here must not hide workspaces.
      try {
        final tabs = await _runner.run(
          RemoteSessionListing.herdrTabListCommand,
          timeout: _timeout,
        );
        if (tabs.exitCode == 0) {
          return RemoteListingAvailable(
            RemoteSessionListing.attachTabs(
              listing.items,
              RemoteSessionListing.parseHerdrTabs(tabs.stdout),
            ),
          );
        }
      } catch (_) {
        // Fall through with workspaces only.
      }
      return listing;
    } on AppFailure catch (failure) {
      return RemoteListingFailed(failure.toString());
    } catch (error) {
      return RemoteListingFailed(error.toString());
    }
  }
}
