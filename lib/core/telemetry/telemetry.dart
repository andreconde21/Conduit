import 'dart:async';

import 'package:conduit/core/telemetry/crash_reporter.dart';
import 'package:conduit/core/telemetry/plausible_client.dart';
import 'package:conduit/core/telemetry/telemetry_config.dart';
import 'package:conduit/core/telemetry/telemetry_events.dart';
import 'package:conduit/core/telemetry/telemetry_preferences.dart';
import 'package:conduit/core/telemetry/telemetry_scrubber.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// What the app says about itself in reports: never anything about the
/// user or their machines.
@immutable
class TelemetryAppInfo {
  const TelemetryAppInfo({
    required this.version,
    required this.buildNumber,
    required this.platform,
    required this.flavor,
  });

  /// From the installed package (the pubspec version).
  static Future<TelemetryAppInfo> load() async {
    final info = await PackageInfo.fromPlatform();
    const flavor = appFlavor ?? 'default';
    var version = info.version;
    // Android's full flavor appends "-full" to the version name.
    if (version.endsWith('-$flavor')) {
      version = version.substring(0, version.length - flavor.length - 1);
    }
    return TelemetryAppInfo(
      version: version,
      buildNumber: info.buildNumber,
      platform: defaultTargetPlatform.name.toLowerCase(),
      flavor: flavor,
    );
  }

  final String version;
  final String buildNumber;

  /// android, ios, linux, windows or macos.
  final String platform;

  /// full, play, or "default" (iOS and desktops have no flavors).
  final String flavor;

  String get release => buildNumber.isEmpty
      ? 'conductore@$version'
      : 'conductore@$version+$buildNumber';

  Map<String, String> get tags => {'platform': platform, 'flavor': flavor};

  Map<String, String> get usageProps => {
    'platform': platform,
    'app_version': version,
    'flavor': flavor,
  };

  /// Browser-shaped, as Plausible drops requests it cannot parse as a
  /// client; the OS part is generic (no versions, no device model).
  String get userAgent {
    final os = switch (platform) {
      'android' => 'Linux; Android',
      'ios' => 'iPhone; CPU iPhone OS like Mac OS X',
      'macos' => 'Macintosh; Intel Mac OS X',
      'windows' => 'Windows NT 10.0; Win64; x64',
      _ => 'X11; Linux x86_64',
    };
    return 'Mozilla/5.0 ($os) Conductore/$version';
  }
}

/// Crash reports (GlitchTip) and anonymous usage counts (Plausible), both
/// behind Settings › Privacy and both off in debug builds and tests.
///
/// [instance] is inert until main() replaces it and calls [start]; code
/// anywhere calls `Telemetry.instance.track(...)` or `.screen(...)`, which
/// cost nothing when nothing is sent.
class Telemetry extends ChangeNotifier {
  Telemetry({
    required this.config,
    required this._store,
    CrashReporter? crashReporter,
    TelemetryScrubber? scrubber,
    Future<TelemetryAppInfo> Function()? appInfo,
    this._httpClient,
    this._flushDelay = const Duration(seconds: 15),
  }) : scrubber = scrubber ?? TelemetryScrubber(),
       _appInfo = appInfo ?? TelemetryAppInfo.load {
    _crash = crashReporter ?? SentryCrashReporter(this.scrubber);
  }

  static Telemetry instance = Telemetry(
    config: TelemetryConfig.disabled,
    store: MemoryTelemetryPreferencesStore(),
  );

  final TelemetryConfig config;
  final TelemetryScrubber scrubber;
  final TelemetryPreferencesStore _store;
  final Future<TelemetryAppInfo> Function() _appInfo;
  final http.Client Function()? _httpClient;
  final Duration _flushDelay;
  late final CrashReporter _crash;

  TelemetryPreferences _preferences = const TelemetryPreferences();
  TelemetryAppInfo? _info;
  bool _loaded = false;
  bool _started = false;
  PlausibleClient? _usage;
  Future<void> _applying = Future.value();

  // Before start() finishes: kept briefly, then sent or dropped by the
  // switches.
  final _pendingEvents = <TelemetryEvent>[];
  final _pendingErrors = <(Object, StackTrace?)>[];
  static const _maxPending = 10;

  TelemetryPreferences get preferences => _preferences;

  /// Preferences are loaded (the notice and Settings can show them).
  bool get loaded => _loaded;

  /// The one-time notice on home.
  bool get showNotice => _loaded && !_preferences.noticeSeen;

  bool get crashReportsActive => _crash.isOpen;

  bool get usageStatsActive => _usage != null;

  /// For tests: the Plausible client while usage stats are on.
  @visibleForTesting
  PlausibleClient? get usageClient => _usage;

  /// Loads the switches and app facts, opens what they allow, and counts
  /// the cold start.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _preferences = await _store.load();
    if (config.crashReportsAvailable || config.usageStatsAvailable) {
      try {
        _info = await _appInfo();
      } on Object {
        _info = null;
      }
    }
    _loaded = true;
    notifyListeners();
    await _apply();
    track(const TelemetryEvent.appOpen());
  }

  Future<void> setCrashReports(bool enabled) =>
      _update(_preferences.copyWith(crashReports: enabled));

  Future<void> setUsageStats(bool enabled) =>
      _update(_preferences.copyWith(usageStats: enabled));

  Future<void> dismissNotice() =>
      _update(_preferences.copyWith(noticeSeen: true));

  Future<void> _update(TelemetryPreferences next) async {
    if (next == _preferences) return;
    _preferences = next;
    notifyListeners();
    await _store.save(next);
    await _apply();
  }

  /// Opens or closes the crash reporter and the usage client to match the
  /// switches, one change at a time.
  Future<void> _apply() => _applying = _applying.then((_) async {
    final info = _info;
    final wantCrash =
        info != null &&
        config.crashReportsAvailable &&
        _preferences.crashReports;
    try {
      if (wantCrash && !_crash.isOpen) {
        await _crash.open(
          CrashReportContext(
            dsn: config.sentryDsn,
            release: info.release,
            dist: info.buildNumber,
            environment: config.environment,
            tags: info.tags,
          ),
        );
      } else if (!wantCrash && _crash.isOpen) {
        await _crash.close();
      }
    } on Object {
      // Crash reporting must never take the app down with it.
    }
    if (_crash.isOpen) {
      for (final (error, stack) in _pendingErrors) {
        unawaited(_crash.capture(error, stack).catchError((_) {}));
      }
    }
    _pendingErrors.clear();

    final wantUsage =
        info != null && config.usageStatsAvailable && _preferences.usageStats;
    if (wantUsage && _usage == null) {
      _usage = PlausibleClient(
        host: config.plausibleHost,
        domain: config.plausibleDomain,
        userAgent: info.userAgent,
        baseProps: info.usageProps,
        client: _httpClient?.call(),
        flushDelay: _flushDelay,
      );
    } else if (!wantUsage && _usage != null) {
      _usage!.close();
      _usage = null;
    }
    final usage = _usage;
    if (usage != null) _pendingEvents.forEach(usage.add);
    _pendingEvents.clear();
    notifyListeners();
  });

  /// Counts [event] if usage stats are on; never blocks or throws.
  void track(TelemetryEvent event) {
    if (!config.usageStatsAvailable) return;
    if (!_loaded) {
      if (_pendingEvents.length < _maxPending) _pendingEvents.add(event);
      return;
    }
    _usage?.add(event);
  }

  /// A top-level screen was shown: a page view, and a crash-report
  /// breadcrumb.
  void screen(TelemetryScreen screen) {
    if (_crash.isOpen) _crash.screen(screen);
    track(TelemetryEvent.screenView(screen));
  }

  /// An error the app log caught (see AppErrorLog.onRecord).
  void recordError(Object error, StackTrace? stack) {
    if (!config.crashReportsAvailable) return;
    if (!_loaded) {
      if (_pendingErrors.length < _maxPending) {
        _pendingErrors.add((error, stack));
      }
      return;
    }
    if (!_crash.isOpen) return;
    unawaited(_crash.capture(error, stack).catchError((_) {}));
  }

  @override
  void dispose() {
    _usage?.close();
    _usage = null;
    unawaited(_crash.close().catchError((_) {}));
    super.dispose();
  }
}
