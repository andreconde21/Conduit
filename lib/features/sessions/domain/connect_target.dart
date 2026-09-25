import 'package:conduit/features/hosts/domain/saved_host.dart';

/// What a terminal session should attach to once the shell is up.
enum ConnectTargetKind {
  /// A plain login shell, exactly what connecting did before the picker.
  shell,

  /// `tmux new-session -A -s <name>`: attach to a tmux session, creating it
  /// if needed.
  tmux,

  /// Attach to the persistent Herdr session, with one workspace (and
  /// optionally one tab) focused first when a workspace id is given.
  herdr,

  /// A plain shell that starts with `cd <directory>` (a recent directory
  /// picked in the connect picker).
  directory,
}

/// The choice made in the connect picker for one host.
///
/// A target is applied to a [SavedHost] with [apply]: the resulting copy
/// carries a derived id (`<hostId>#<key>`, mirroring how the local shell
/// numbers its instances) so several sessions to the same machine can be
/// open at once, and a title that names the workspace, like Moshi does.
class ConnectTarget {
  const ConnectTarget._({
    required this.kind,
    this.name = '',
    this.label = '',
    this.tabId = '',
  });

  const ConnectTarget.shell() : this._(kind: ConnectTargetKind.shell);

  const ConnectTarget.tmux(String sessionName)
    : this._(kind: ConnectTargetKind.tmux, name: sessionName);

  const ConnectTarget.directory(String path)
    : this._(kind: ConnectTargetKind.directory, name: path);

  const ConnectTarget.herdr({
    required String workspaceId,
    String label = '',
    String tabId = '',
  }) : this._(
         kind: ConnectTargetKind.herdr,
         name: workspaceId,
         label: label,
         tabId: tabId,
       );

  final ConnectTargetKind kind;

  /// tmux session name, Herdr workspace id (empty for "just run herdr",
  /// which launches or attaches the default session) or directory path.
  final String name;

  /// Human label (Herdr workspace label); empty for tmux and shell.
  final String label;

  /// Optional Herdr tab id to focus inside the workspace.
  final String tabId;

  /// Separator between a saved host id and the target key in a session's
  /// derived host id.
  static const idSeparator = '#';

  /// Stable identity of the target on one host, used in derived host ids,
  /// recents deduplication and the picker's "Active" badges.
  String get key => switch (kind) {
    ConnectTargetKind.shell => 'shell',
    ConnectTargetKind.tmux => 'tmux:$name',
    ConnectTargetKind.herdr =>
      name.isEmpty
          ? 'herdr'
          : tabId.isEmpty
          ? 'herdr:$name'
          : 'herdr:$name:$tabId',
    ConnectTargetKind.directory => 'dir:$name',
  };

  /// Short display name of the target: what the session tile and header show
  /// next to the host name.
  String get title => switch (kind) {
    ConnectTargetKind.shell => 'Shell',
    ConnectTargetKind.tmux => name,
    ConnectTargetKind.herdr =>
      label.isNotEmpty
          ? label
          : name.isNotEmpty
          ? name
          : 'Herdr',
    ConnectTargetKind.directory => _basename(name),
  };

  static String _basename(String path) {
    final segments = path.split('/').where((s) => s.isNotEmpty);
    return segments.isEmpty ? '/' : segments.last;
  }

  /// Command typed into the shell right after connecting, or null when the
  /// target is handled by the host's own tmux settings.
  String? get startupCommand => switch (kind) {
    ConnectTargetKind.shell || ConnectTargetKind.tmux => null,
    ConnectTargetKind.herdr => _herdrAttachCommand(),
    ConnectTargetKind.directory => 'cd ${shellQuote(name)}',
  };

  String _herdrAttachCommand() {
    if (name.isEmpty) {
      return 'herdr';
    }
    // Focus over the socket API first (a no-op when the server is not up
    // yet), then attach the TUI. Without `exec` a detach lands back in the
    // shell, like the tmux path does.
    final focus = tabId.isNotEmpty
        ? 'herdr tab focus ${shellQuote(tabId)}'
        : 'herdr workspace focus ${shellQuote(name)}';
    return '$focus >/dev/null 2>&1; herdr';
  }

  /// The host a session should be opened with for this target.
  SavedHost apply(SavedHost host) {
    if (kind == ConnectTargetKind.shell) {
      return host;
    }
    final base = host.copyWith(
      id: '${host.id}$idSeparator$key',
      name: '${host.name}: $title',
    );
    return switch (kind) {
      ConnectTargetKind.tmux => base.copyWith(
        startTmuxOnConnect: true,
        tmuxSessionName: name,
      ),
      ConnectTargetKind.herdr ||
      ConnectTargetKind.directory => base.copyWith(startTmuxOnConnect: false),
      ConnectTargetKind.shell => base,
    };
  }

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'name': name,
    'label': label,
    'tabId': tabId,
  };

  static ConnectTarget? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final kind = ConnectTargetKind.values
        .where((value) => value.name == json['kind'])
        .firstOrNull;
    if (kind == null) {
      return null;
    }
    final name = json['name'];
    final label = json['label'];
    final tabId = json['tabId'];
    final target = ConnectTarget._(
      kind: kind,
      name: name is String ? name : '',
      label: label is String ? label : '',
      tabId: tabId is String ? tabId : '',
    );
    if ((kind == ConnectTargetKind.tmux ||
            kind == ConnectTargetKind.directory) &&
        target.name.isEmpty) {
      return null;
    }
    return target;
  }

  /// Parses the target key back out of a derived session host id; null for
  /// a plain (undecorated) host id.
  static String? keyFromSessionHostId(String sessionHostId) {
    final separator = sessionHostId.indexOf(idSeparator);
    if (separator == -1) {
      return null;
    }
    return sessionHostId.substring(separator + 1);
  }

  /// Rebuilds the target from a derived session host id. The Herdr label is
  /// not encoded in the key, so it comes back empty; callers that need it
  /// keep the original target.
  static ConnectTarget? fromSessionHostId(String sessionHostId) {
    final key = keyFromSessionHostId(sessionHostId);
    if (key == null) {
      return null;
    }
    if (key == 'shell') {
      return const ConnectTarget.shell();
    }
    if (key.startsWith('tmux:')) {
      final name = key.substring('tmux:'.length);
      return name.isEmpty ? null : ConnectTarget.tmux(name);
    }
    if (key.startsWith('dir:')) {
      final path = key.substring('dir:'.length);
      return path.isEmpty ? null : ConnectTarget.directory(path);
    }
    if (key == 'herdr') {
      return const ConnectTarget.herdr(workspaceId: '');
    }
    if (key.startsWith('herdr:')) {
      final rest = key.substring('herdr:'.length);
      final colon = rest.indexOf(':');
      final workspaceId = colon == -1 ? rest : rest.substring(0, colon);
      final tabId = colon == -1 ? '' : rest.substring(colon + 1);
      if (workspaceId.isEmpty) {
        return null;
      }
      return ConnectTarget.herdr(workspaceId: workspaceId, tabId: tabId);
    }
    return null;
  }

  static final _unquoted = RegExp(r'^[A-Za-z0-9_~./:=+-]+$');

  static String shellQuote(String value) =>
      _unquoted.hasMatch(value) ? value : "'${value.replaceAll("'", r"'\''")}'";

  @override
  bool operator ==(Object other) {
    return other is ConnectTarget &&
        other.kind == kind &&
        other.name == name &&
        other.label == label &&
        other.tabId == tabId;
  }

  @override
  int get hashCode => Object.hash(kind, name, label, tabId);

  @override
  String toString() => 'ConnectTarget($key)';
}

/// The saved host id behind a session's (possibly derived) host id.
String baseHostId(String sessionHostId) {
  final separator = sessionHostId.indexOf(ConnectTarget.idSeparator);
  return separator == -1
      ? sessionHostId
      : sessionHostId.substring(0, separator);
}
