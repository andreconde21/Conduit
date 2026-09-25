import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/this_computer/domain/local_shell_launch.dart';

/// The per-device settings of "This computer": its machine entry (agent
/// monitoring, multiplexer prefix, snippets, last use) and, on Windows,
/// the shell it opens. Kept on this device only, never synced.
class ThisComputerSettings {
  const ThisComputerSettings({
    required this.host,
    this.windowsShell = WindowsShellKind.powershell,
  });

  final SavedHost host;
  final WindowsShellKind windowsShell;

  ThisComputerSettings copyWith({
    SavedHost? host,
    WindowsShellKind? windowsShell,
  }) => ThisComputerSettings(
    host: host ?? this.host,
    windowsShell: windowsShell ?? this.windowsShell,
  );

  Map<String, Object?> toJson() => {
    'host': host.toJson(),
    'windowsShell': windowsShell.name,
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
    );
  }
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
