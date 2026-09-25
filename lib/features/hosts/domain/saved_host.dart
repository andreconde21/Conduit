import 'package:conduit/features/hosts/domain/multiplexer_prefix_key.dart';
import 'package:conduit/features/snippets/domain/terminal_snippet.dart';

export 'package:conduit/features/hosts/domain/multiplexer_prefix_key.dart';

enum SshAuthMethod { password, privateKey, hardwareKey, external }

/// Which agent manager Agent Attention talks to on a host.
enum AgentMonitorKind {
  /// Conductore companion when `conductore-hostd` is installed, else Herdr.
  auto,
  herdr,
  companion;

  String get label => switch (this) {
    AgentMonitorKind.auto => 'Auto',
    AgentMonitorKind.herdr => 'Herdr',
    AgentMonitorKind.companion => 'Conductore companion',
  };

  static AgentMonitorKind parse(Object? raw) {
    return AgentMonitorKind.values
            .where((kind) => kind.name == raw)
            .firstOrNull ??
        AgentMonitorKind.auto;
  }
}

/// How loudly Agent Attention notifies for one host.
///
/// Stored as the two legacy flags ([SavedHost.agentNotifyInput],
/// [SavedHost.agentNotifyFinished]) so older builds keep reading it.
/// Approvals and errors (permission prompts, an agent blocked on a human)
/// are loud; a finished agent only notifies at [all]; every other state
/// change only updates the inbox and the home-screen widget.
enum AgentNotifyLevel {
  all,
  approvalsAndErrors,
  none;

  String get label => switch (this) {
    AgentNotifyLevel.all => 'All',
    AgentNotifyLevel.approvalsAndErrors => 'Approvals and errors',
    AgentNotifyLevel.none => 'None',
  };

  String get description => switch (this) {
    AgentNotifyLevel.all =>
      'Approvals, agents waiting for you, and finished agents.',
    AgentNotifyLevel.approvalsAndErrors =>
      'Only approvals and agents waiting for you. Other changes update the '
          'inbox quietly.',
    AgentNotifyLevel.none => 'No notifications. The inbox still updates.',
  };

  /// The level the legacy flags encode. Input notifications off means
  /// the user muted approvals, so it maps to [none] even with "finished"
  /// on (a finished-only setting predates approvals being loud).
  static AgentNotifyLevel fromFlags({
    required bool input,
    required bool finished,
  }) {
    if (!input) {
      return AgentNotifyLevel.none;
    }
    return finished
        ? AgentNotifyLevel.all
        : AgentNotifyLevel.approvalsAndErrors;
  }

  bool get inputFlag => this != AgentNotifyLevel.none;
  bool get finishedFlag => this == AgentNotifyLevel.all;

  /// Permission prompts and agents waiting on a human.
  bool get notifiesApprovalsAndErrors => this != AgentNotifyLevel.none;

  /// Agents that finished their work.
  bool get notifiesFinished => this == AgentNotifyLevel.all;
}

/// The prefix a host's multiplexer (tmux or Herdr) is driven with unless the
/// host says otherwise.
const defaultTmuxPrefixKey = MultiplexerPrefixKey.defaultKey;
const defaultTmuxSessionName = 'conduit';

/// Id of the "This computer" machine on a desktop: the device the app runs
/// on, reached through a local PTY instead of SSH. It is never saved in the
/// machine list nor synced; its per-device settings live apart.
const thisComputerHostId = 'this-computer';

bool _parseStartTmuxOnConnect(Map<String, Object?> json) {
  return json['startTmuxOnConnect'] as bool? ?? false;
}

class HardwareKeyEntry {
  const HardwareKeyEntry({
    required this.id,
    required this.privateKey,
    this.label = '',
    this.passphrase = '',
  });

  final String id;
  final String privateKey;
  final String label;
  final String passphrase;

  bool get isValid => id.isNotEmpty && privateKey.trim().isNotEmpty;

  HardwareKeyEntry copyWith({String? label}) {
    return HardwareKeyEntry(
      id: id,
      privateKey: privateKey,
      label: label ?? this.label,
      passphrase: passphrase,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'label': label,
      'privateKey': privateKey,
      'passphrase': passphrase,
    };
  }

  static HardwareKeyEntry? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final id = json['id'];
    final privateKey = json['privateKey'];
    final label = json['label'];
    final passphrase = json['passphrase'];
    if (id is! String || privateKey is! String) {
      return null;
    }
    final entry = HardwareKeyEntry(
      id: id,
      privateKey: privateKey,
      label: label is String ? label : '',
      passphrase: passphrase is String ? passphrase : '',
    );
    return entry.isValid ? entry : null;
  }
}

List<HardwareKeyEntry> _parseHardwareKeys(Map<String, Object?> json) {
  final entries = (json['hardwareKeys'] as List? ?? const [])
      .map(HardwareKeyEntry.fromJson)
      .whereType<HardwareKeyEntry>()
      .toList(growable: false);
  if (entries.isNotEmpty) {
    return entries;
  }
  final authMethod = json['authMethod'];
  final legacyKey = json['privateKey'] as String? ?? '';
  if (authMethod == SshAuthMethod.hardwareKey.name &&
      legacyKey.trim().isNotEmpty) {
    return [
      HardwareKeyEntry(
        id: 'legacy',
        privateKey: legacyKey,
        passphrase: json['passphrase'] as String? ?? '',
      ),
    ];
  }
  return const [];
}

class MoshPortRange {
  const MoshPortRange(this.first, this.last);

  final int first;
  final int last;

  static final RegExp _pattern = RegExp(r'^(\d{1,5})(?::(\d{1,5}))?$');

  static MoshPortRange? tryParse(String value) {
    final match = _pattern.firstMatch(value.trim());
    if (match == null) {
      return null;
    }
    final first = int.parse(match.group(1)!);
    final last = match.group(2) == null ? first : int.parse(match.group(2)!);
    if (first < 1 || last > 65535 || last < first) {
      return null;
    }
    return MoshPortRange(first, last);
  }
}

String _parseMoshPorts(Map<String, Object?> json) {
  final raw = (json['moshPorts'] as String?)?.trim() ?? '';
  return MoshPortRange.tryParse(raw) == null ? '' : raw;
}

class SavedHost {
  const SavedHost({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.authMethod,
    this.password = '',
    this.privateKey = '',
    this.passphrase = '',
    this.hardwareKeys = const [],
    this.externalAuthOfferKey = true,
    this.forwardAgent = false,
    this.tags = const [],
    this.connectionTimeoutSeconds = 12,
    this.useMosh = false,
    this.moshLocale = 'C.UTF-8',
    this.moshPorts = '',
    this.predictiveEchoEnabled = false,
    this.startTmuxOnConnect = false,
    this.tmuxPrefixKey = defaultTmuxPrefixKey,
    this.tmuxSessionName = defaultTmuxSessionName,
    this.tmuxStartDirectory = '',
    this.snippets = const [],
    this.connectSnippetId = '',
    this.agentAttentionEnabled = false,
    this.agentNotifyInput = true,
    this.agentNotifyFinished = true,
    this.agentMonitor = AgentMonitorKind.auto,
    this.shareInboxDirectory = '',
    this.lastConnectedAt,
    this.isLocal = false,
  });

  factory SavedHost.localShell({required String id, required String name}) {
    return SavedHost(
      id: id,
      name: name,
      host: 'localhost',
      port: 0,
      username: 'root',
      authMethod: SshAuthMethod.external,
      isLocal: true,
    );
  }

  /// The desktop's own "This computer" machine (see [thisComputerHostId]),
  /// with the default [name] and the local account as [username].
  factory SavedHost.thisComputer({
    String name = 'This computer',
    String hostname = 'localhost',
    String username = '',
  }) {
    return SavedHost(
      id: thisComputerHostId,
      name: name,
      host: hostname,
      port: 22,
      username: username,
      authMethod: SshAuthMethod.external,
      agentAttentionEnabled: true,
    );
  }

  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final SshAuthMethod authMethod;
  final String password;
  final String privateKey;
  final String passphrase;
  final List<HardwareKeyEntry> hardwareKeys;
  final bool externalAuthOfferKey;
  final bool forwardAgent;
  final List<String> tags;
  final int connectionTimeoutSeconds;
  final bool useMosh;
  final String moshLocale;
  final String moshPorts;
  final bool predictiveEchoEnabled;
  final bool startTmuxOnConnect;

  /// Prefix sent before tmux and Herdr bindings on this host.
  final MultiplexerPrefixKey tmuxPrefixKey;
  final String tmuxSessionName;
  final String tmuxStartDirectory;
  final List<TerminalSnippet> snippets;
  final String connectSnippetId;

  /// Opt-in agent monitoring (Agent Attention) for this machine.
  final bool agentAttentionEnabled;

  /// Notify when a monitored agent starts needing input or is blocked.
  final bool agentNotifyInput;

  /// Notify when a monitored agent finishes background work.
  final bool agentNotifyFinished;

  /// Which agent manager to read (see [AgentMonitorKind]).
  final AgentMonitorKind agentMonitor;

  /// The notification level the two notify flags encode.
  AgentNotifyLevel get agentNotifyLevel => AgentNotifyLevel.fromFlags(
    input: agentNotifyInput,
    finished: agentNotifyFinished,
  );

  /// Remote directory shared files are uploaded to (share-to-agent). Empty
  /// means `~/conductore-inbox`; `~` and relative paths resolve under home.
  final String shareInboxDirectory;

  final DateTime? lastConnectedAt;
  final bool isLocal;

  /// The desktop's own machine, or a session opened on it (a derived
  /// `this-computer#<target>` id).
  bool get isThisComputer =>
      id == thisComputerHostId || id.startsWith('$thisComputerHostId#');

  bool get isValid =>
      id.isNotEmpty &&
      name.trim().isNotEmpty &&
      host.trim().isNotEmpty &&
      port > 0 &&
      port <= 65535 &&
      connectionTimeoutSeconds >= 3 &&
      connectionTimeoutSeconds <= 120 &&
      switch (authMethod) {
        SshAuthMethod.password => password.isNotEmpty,
        SshAuthMethod.privateKey => privateKey.trim().isNotEmpty,
        SshAuthMethod.hardwareKey =>
          hardwareKeys.isNotEmpty
              ? hardwareKeys.every((key) => key.isValid)
              : privateKey.trim().isNotEmpty,
        SshAuthMethod.external => true,
      };

  /// Hardware-key stubs to authenticate with, tolerating hosts created
  /// before multi-key support that only carry the legacy single-stub fields.
  List<HardwareKeyEntry> get effectiveHardwareKeys {
    if (hardwareKeys.isNotEmpty) {
      return hardwareKeys;
    }
    if (privateKey.trim().isEmpty) {
      return const [];
    }
    return [
      HardwareKeyEntry(
        id: 'legacy',
        privateKey: privateKey,
        passphrase: passphrase,
      ),
    ];
  }

  String get endpoint {
    if (isThisComputer) {
      final machine = host.trim().isEmpty ? 'localhost' : host.trim();
      final user = username.trim();
      return user.isEmpty ? '$machine (local)' : '$user@$machine (local)';
    }
    final trimmedUsername = username.trim();
    final trimmedHost = host.trim();
    if (trimmedUsername.isEmpty) {
      return '$trimmedHost:$port';
    }
    return '$trimmedUsername@$trimmedHost:$port';
  }

  SavedHost copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    SshAuthMethod? authMethod,
    String? password,
    String? privateKey,
    String? passphrase,
    List<HardwareKeyEntry>? hardwareKeys,
    bool? externalAuthOfferKey,
    bool? forwardAgent,
    List<String>? tags,
    int? connectionTimeoutSeconds,
    bool? useMosh,
    String? moshLocale,
    String? moshPorts,
    bool? predictiveEchoEnabled,
    bool? startTmuxOnConnect,
    MultiplexerPrefixKey? tmuxPrefixKey,
    String? tmuxSessionName,
    String? tmuxStartDirectory,
    List<TerminalSnippet>? snippets,
    String? connectSnippetId,
    bool? agentAttentionEnabled,
    bool? agentNotifyInput,
    bool? agentNotifyFinished,
    AgentNotifyLevel? agentNotifyLevel,
    AgentMonitorKind? agentMonitor,
    String? shareInboxDirectory,
    DateTime? lastConnectedAt,
    bool clearLastConnectedAt = false,
    bool? isLocal,
  }) {
    return SavedHost(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authMethod: authMethod ?? this.authMethod,
      password: password ?? this.password,
      privateKey: privateKey ?? this.privateKey,
      passphrase: passphrase ?? this.passphrase,
      hardwareKeys: hardwareKeys ?? this.hardwareKeys,
      externalAuthOfferKey: externalAuthOfferKey ?? this.externalAuthOfferKey,
      forwardAgent: forwardAgent ?? this.forwardAgent,
      tags: tags ?? this.tags,
      connectionTimeoutSeconds:
          connectionTimeoutSeconds ?? this.connectionTimeoutSeconds,
      useMosh: useMosh ?? this.useMosh,
      moshLocale: moshLocale ?? this.moshLocale,
      moshPorts: moshPorts ?? this.moshPorts,
      predictiveEchoEnabled:
          predictiveEchoEnabled ?? this.predictiveEchoEnabled,
      startTmuxOnConnect: startTmuxOnConnect ?? this.startTmuxOnConnect,
      tmuxPrefixKey: tmuxPrefixKey ?? this.tmuxPrefixKey,
      tmuxSessionName: tmuxSessionName ?? this.tmuxSessionName,
      tmuxStartDirectory: tmuxStartDirectory ?? this.tmuxStartDirectory,
      snippets: snippets ?? this.snippets,
      connectSnippetId: connectSnippetId ?? this.connectSnippetId,
      agentAttentionEnabled:
          agentAttentionEnabled ?? this.agentAttentionEnabled,
      agentNotifyInput:
          agentNotifyLevel?.inputFlag ??
          agentNotifyInput ??
          this.agentNotifyInput,
      agentNotifyFinished:
          agentNotifyLevel?.finishedFlag ??
          agentNotifyFinished ??
          this.agentNotifyFinished,
      agentMonitor: agentMonitor ?? this.agentMonitor,
      shareInboxDirectory: shareInboxDirectory ?? this.shareInboxDirectory,
      lastConnectedAt: clearLastConnectedAt
          ? null
          : lastConnectedAt ?? this.lastConnectedAt,
      isLocal: isLocal ?? this.isLocal,
    );
  }

  Map<String, Object?> toJson() {
    final effectiveKeys = authMethod == SshAuthMethod.hardwareKey
        ? effectiveHardwareKeys
        : const <HardwareKeyEntry>[];
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'authMethod': authMethod.name,
      'password': password,
      'privateKey': effectiveKeys.isNotEmpty
          ? effectiveKeys.first.privateKey
          : privateKey,
      'passphrase': effectiveKeys.isNotEmpty
          ? effectiveKeys.first.passphrase
          : passphrase,
      'hardwareKeys': [for (final key in effectiveKeys) key.toJson()],
      'externalAuthOfferKey': externalAuthOfferKey,
      'forwardAgent': forwardAgent,
      'tags': tags,
      'connectionTimeoutSeconds': connectionTimeoutSeconds,
      'useMosh': useMosh,
      'moshLocale': moshLocale,
      'moshPorts': moshPorts,
      'predictiveEchoEnabled': predictiveEchoEnabled,
      'startTmuxOnConnect': startTmuxOnConnect,
      'tmuxPrefixKey': tmuxPrefixKey.encode(),
      'tmuxSessionName': tmuxSessionName,
      'tmuxStartDirectory': tmuxStartDirectory,
      'snippets': [for (final snippet in snippets) snippet.toJson()],
      'connectSnippetId': connectSnippetId,
      'agentAttentionEnabled': agentAttentionEnabled,
      'agentNotifyInput': agentNotifyInput,
      'agentNotifyFinished': agentNotifyFinished,
      'agentMonitor': agentMonitor.name,
      'shareInboxDirectory': shareInboxDirectory,
      'lastConnectedAt': lastConnectedAt?.toIso8601String(),
      'isLocal': isLocal,
    };
  }

  factory SavedHost.fromJson(Map<String, Object?> json) {
    final authMethod = SshAuthMethod.values.firstWhere(
      (method) => method.name == json['authMethod'],
      orElse: () => SshAuthMethod.password,
    );
    final lastConnectedAtRaw = json['lastConnectedAt'] as String?;

    final tags = (json['tags'] as List? ?? const [])
        .whereType<String>()
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);

    return SavedHost(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      host: json['host'] as String? ?? '',
      port: json['port'] as int? ?? 22,
      username: json['username'] as String? ?? '',
      authMethod: authMethod,
      password: json['password'] as String? ?? '',
      privateKey: json['privateKey'] as String? ?? '',
      passphrase: json['passphrase'] as String? ?? '',
      hardwareKeys: _parseHardwareKeys(json),
      externalAuthOfferKey: json['externalAuthOfferKey'] as bool? ?? true,
      forwardAgent: json['forwardAgent'] as bool? ?? false,
      tags: tags,
      connectionTimeoutSeconds: json['connectionTimeoutSeconds'] as int? ?? 12,
      useMosh: json['useMosh'] as bool? ?? false,
      moshLocale: (json['moshLocale'] as String?)?.trim().isNotEmpty == true
          ? (json['moshLocale'] as String).trim()
          : 'C.UTF-8',
      moshPorts: _parseMoshPorts(json),
      predictiveEchoEnabled: json['predictiveEchoEnabled'] as bool? ?? false,
      startTmuxOnConnect: _parseStartTmuxOnConnect(json),
      tmuxPrefixKey: MultiplexerPrefixKey.decode(
        json['tmuxPrefixKey'] as String?,
      ),
      tmuxSessionName:
          (json['tmuxSessionName'] as String?)?.trim().isNotEmpty == true
          ? (json['tmuxSessionName'] as String).trim()
          : defaultTmuxSessionName,
      tmuxStartDirectory: (json['tmuxStartDirectory'] as String?)?.trim() ?? '',
      snippets: (json['snippets'] as List? ?? const [])
          .map(TerminalSnippet.fromJson)
          .whereType<TerminalSnippet>()
          .toList(growable: false),
      connectSnippetId: json['connectSnippetId'] as String? ?? '',
      agentAttentionEnabled: json['agentAttentionEnabled'] as bool? ?? false,
      agentNotifyInput: json['agentNotifyInput'] as bool? ?? true,
      agentNotifyFinished: json['agentNotifyFinished'] as bool? ?? true,
      agentMonitor: AgentMonitorKind.parse(json['agentMonitor']),
      shareInboxDirectory:
          (json['shareInboxDirectory'] as String?)?.trim() ?? '',
      lastConnectedAt: lastConnectedAtRaw == null
          ? null
          : DateTime.tryParse(lastConnectedAtRaw),
      isLocal: json['isLocal'] as bool? ?? false,
    );
  }
}
