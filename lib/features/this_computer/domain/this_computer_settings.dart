import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/this_computer/domain/local_shell_launch.dart';

/// The per-device settings of "This computer": its machine entry (agent
/// monitoring, multiplexer prefix, snippets, last use), on Windows the
/// shell it opens, and how it treats a synced machine that is this device
/// (see `SelfMachineMatcher`). Kept on this device only, never synced.
class ThisComputerSettings {
  const ThisComputerSettings({
    required this.host,
    this.windowsShell = WindowsShellKind.powershell,
    this.showSelfSeparately = false,
    this.ownPrefs = const {},
  });

  final SavedHost host;
  final WindowsShellKind windowsShell;

  /// Keep listing a synced machine that is this device next to "This
  /// computer" (SSH to itself) instead of folding it in.
  final bool showSelfSeparately;

  /// The [SelfMachinePref]s set on "This computer" itself: the others
  /// follow the synced machine that is this device, when there is one.
  final Set<SelfMachinePref> ownPrefs;

  ThisComputerSettings copyWith({
    SavedHost? host,
    WindowsShellKind? windowsShell,
    bool? showSelfSeparately,
    Set<SelfMachinePref>? ownPrefs,
  }) => ThisComputerSettings(
    host: host ?? this.host,
    windowsShell: windowsShell ?? this.windowsShell,
    showSelfSeparately: showSelfSeparately ?? this.showSelfSeparately,
    ownPrefs: ownPrefs ?? this.ownPrefs,
  );

  Map<String, Object?> toJson() => {
    'host': host.toJson(),
    'windowsShell': windowsShell.name,
    'showSelfSeparately': showSelfSeparately,
    'ownPrefs': [for (final pref in ownPrefs) pref.name],
  };

  /// Reads saved settings over [defaults] (the name, hostname and account
  /// always come from [defaults]: they describe the device, not a choice).
  static ThisComputerSettings fromJson(
    Object? json, {
    required SavedHost defaults,
  }) {
    if (json is! Map) return ThisComputerSettings(host: defaults);
    final rawHost = json['host'];
    final saved = rawHost is Map
        ? SavedHost.fromJson(Map<String, Object?>.from(rawHost))
        : null;
    return ThisComputerSettings(
      host: saved == null
          ? defaults
          : saved.copyWith(
              id: thisComputerHostId,
              name: defaults.name,
              host: defaults.host,
              port: defaults.port,
              username: defaults.username,
              authMethod: SshAuthMethod.external,
              password: '',
              privateKey: '',
              passphrase: '',
              hardwareKeys: const [],
              useMosh: false,
              isLocal: false,
            ),
      windowsShell: WindowsShellKind.parse(json['windowsShell']),
      showSelfSeparately: json['showSelfSeparately'] == true,
      ownPrefs: {
        if (json['ownPrefs'] case final List<Object?> names)
          for (final name in names)
            ?SelfMachinePref.values
                .where((pref) => pref.name == name)
                .firstOrNull,
      },
    );
  }

  /// "This computer" as the machines list shows it while [self] (a synced
  /// machine that is this device) is folded into it: named after both,
  /// and with [self]'s value for each [SelfMachinePref] it has none of its
  /// own for. [self] is only read, never changed.
  SavedHost hostFoldedWith(SavedHost self) {
    var folded = host.copyWith(name: '${host.name} · ${self.name}');
    for (final pref in SelfMachinePref.values) {
      if (!hasOwn(pref)) folded = pref.copy(from: self, to: folded);
    }
    return folded;
  }

  /// Whether "This computer" has a value of its own for [pref]: one set
  /// here, or one that differs from the default.
  bool hasOwn(SelfMachinePref pref) =>
      ownPrefs.contains(pref) || !pref.same(host, SavedHost.thisComputer());

  /// Takes [edited] (the folded "This computer" after an edit) as the new
  /// machine entry: a [SelfMachinePref] the edit changed becomes its own,
  /// the others keep their stored value. [shown] is what the edit started
  /// from.
  ThisComputerSettings withEdit(SavedHost edited, {required SavedHost shown}) {
    var next = edited.copyWith(id: thisComputerHostId, name: host.name);
    final own = {...ownPrefs};
    for (final pref in SelfMachinePref.values) {
      if (pref.same(edited, shown)) {
        next = pref.copy(from: host, to: next);
      } else {
        own.add(pref);
      }
    }
    return copyWith(host: next, ownPrefs: own);
  }
}

/// A machine preference "This computer" takes from the synced machine
/// that is this device while it has none of its own: how a session opens
/// (tmux or Herdr on open, its session and directory) and the multiplexer
/// prefix.
enum SelfMachinePref {
  startMultiplexer,
  multiplexerPrefix,
  multiplexerSession,
  startDirectory;

  bool same(SavedHost a, SavedHost b) => switch (this) {
    startMultiplexer => a.startTmuxOnConnect == b.startTmuxOnConnect,
    multiplexerPrefix => a.tmuxPrefixKey == b.tmuxPrefixKey,
    multiplexerSession => a.tmuxSessionName == b.tmuxSessionName,
    startDirectory => a.tmuxStartDirectory == b.tmuxStartDirectory,
  };

  /// [to] with [from]'s value of this preference.
  SavedHost copy({
    required SavedHost from,
    required SavedHost to,
  }) => switch (this) {
    startMultiplexer => to.copyWith(
      startTmuxOnConnect: from.startTmuxOnConnect,
    ),
    multiplexerPrefix => to.copyWith(tmuxPrefixKey: from.tmuxPrefixKey),
    multiplexerSession => to.copyWith(tmuxSessionName: from.tmuxSessionName),
    startDirectory => to.copyWith(tmuxStartDirectory: from.tmuxStartDirectory),
  };
}

/// Where the settings of "This computer" are kept.
abstract interface class ThisComputerStore {
  Future<ThisComputerSettings> load();

  Future<void> save(ThisComputerSettings settings);
}

/// A [ThisComputerStore] that lives as long as the app run (tests).
class InMemoryThisComputerStore implements ThisComputerStore {
  InMemoryThisComputerStore(this.settings);

  ThisComputerSettings settings;
  int saves = 0;

  @override
  Future<ThisComputerSettings> load() async => settings;

  @override
  Future<void> save(ThisComputerSettings settings) async {
    saves += 1;
    this.settings = settings;
  }
}
