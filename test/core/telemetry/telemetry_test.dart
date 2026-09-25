import 'dart:convert';

import 'package:conduit/core/diagnostics/app_error_log.dart';
import 'package:conduit/core/telemetry/crash_reporter.dart';
import 'package:conduit/core/telemetry/telemetry.dart';
import 'package:conduit/core/telemetry/telemetry_config.dart';
import 'package:conduit/core/telemetry/telemetry_events.dart';
import 'package:conduit/core/telemetry/telemetry_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_doubles.dart';

class _FakeCrashReporter implements CrashReporter {
  final captured = <Object>[];
  final screens = <TelemetryScreen>[];
  CrashReportContext? context;
  int opens = 0;
  int closes = 0;
  bool _open = false;

  @override
  bool get isOpen => _open;

  @override
  Future<void> open(CrashReportContext context) async {
    this.context = context;
    opens++;
    _open = true;
  }

  @override
  Future<void> close() async {
    closes++;
    _open = false;
  }

  @override
  Future<void> capture(Object error, StackTrace? stack) async =>
      captured.add(error);

  @override
  void screen(TelemetryScreen screen) => screens.add(screen);
}

const _enabled = TelemetryConfig(
  sentryDsn: 'https://public@glitchtip.invalid/1',
  plausibleHost: 'https://plausible.invalid',
  plausibleDomain: 'conductore.outsmartis.dev',
  environment: 'preview',
  sendEnabled: true,
);

const _info = TelemetryAppInfo(
  version: '1.2.3',
  buildNumber: '45',
  platform: 'android',
  flavor: 'full',
);

void main() {
  late _FakeCrashReporter crash;
  late List<http.Request> posts;
  late MemoryTelemetryPreferencesStore store;

  setUp(() {
    crash = _FakeCrashReporter();
    posts = [];
    store = MemoryTelemetryPreferencesStore();
  });

  Telemetry build({TelemetryConfig config = _enabled}) {
    final telemetry = Telemetry(
      config: config,
      store: store,
      crashReporter: crash,
      appInfo: () async => _info,
      httpClient: () => MockClient((request) async {
        posts.add(request);
        return http.Response('ok', 202);
      }),
      flushDelay: Duration.zero,
    );
    addTearDown(telemetry.dispose);
    return telemetry;
  }

  Future<List<String>> sentNames(Telemetry telemetry) async {
    await telemetry.usageClient?.flush();
    return [
      for (final post in posts)
        (jsonDecode(post.body) as Map<String, dynamic>)['name'] as String,
    ];
  }

  group('gating', () {
    test('the default instance and debug builds (tests) send nothing', () {
      expect(TelemetryConfig.fromEnvironment().sendEnabled, isFalse);
      expect(Telemetry.instance.config.sendEnabled, isFalse);
    });

    test('disabled config: nothing opens, nothing is sent', () async {
      final telemetry = build(config: TelemetryConfig.disabled);
      await telemetry.start();
      telemetry
        ..track(const TelemetryEvent.chatModeOpened())
        ..screen(TelemetryScreen.terminal)
        ..recordError(StateError('x'), null);
      expect(crash.opens, 0);
      expect(telemetry.usageClient, isNull);
      expect(await sentNames(telemetry), isEmpty);
      expect(crash.captured, isEmpty);
    });

    test('an empty DSN or Plausible host turns that half off', () {
      const noDsn = TelemetryConfig(
        sentryDsn: '',
        plausibleHost: 'https://p',
        plausibleDomain: 'd',
        environment: 'preview',
        sendEnabled: true,
      );
      expect(noDsn.crashReportsAvailable, isFalse);
      expect(noDsn.usageStatsAvailable, isTrue);
      const noHost = TelemetryConfig(
        sentryDsn: 'https://k@h/1',
        plausibleHost: '',
        plausibleDomain: 'd',
        environment: 'preview',
        sendEnabled: true,
      );
      expect(noHost.crashReportsAvailable, isTrue);
      expect(noHost.usageStatsAvailable, isFalse);
    });

    test('enabled: opens with release, dist, environment and tags, counts '
        'the cold start', () async {
      final telemetry = build();
      await telemetry.start();
      expect(crash.isOpen, isTrue);
      expect(crash.context?.release, 'conductore@1.2.3+45');
      expect(crash.context?.dist, '45');
      expect(crash.context?.environment, 'preview');
      expect(crash.context?.tags, {'platform': 'android', 'flavor': 'full'});
      expect(await sentNames(telemetry), ['app_open']);
      expect(posts.single.headers['User-Agent'], contains('Conductore/1.2.3'));
    });

    test('events and errors from before start are kept, then sent', () async {
      final telemetry = build();
      telemetry
        ..screen(TelemetryScreen.home)
        ..recordError(StateError('early'), null);
      await telemetry.start();
      await pumpEventQueue();
      expect(await sentNames(telemetry), ['pageview', 'app_open']);
      expect(crash.captured, hasLength(1));
    });

    test('switching crash reports off closes the client at once; on opens '
        'it again', () async {
      final telemetry = build();
      await telemetry.start();
      await telemetry.setCrashReports(false);
      expect(crash.isOpen, isFalse);
      telemetry.recordError(StateError('ignored'), null);
      expect(crash.captured, isEmpty);

      await telemetry.setCrashReports(true);
      expect(crash.isOpen, isTrue);
      telemetry.recordError(StateError('sent'), null);
      await pumpEventQueue();
      expect(crash.captured, hasLength(1));
    });

    test(
      'switching usage stats off drops queued events and sends no more',
      () async {
        final telemetry = build();
        await telemetry.start();
        telemetry.track(const TelemetryEvent.chatModeOpened());
        await telemetry.setUsageStats(false);
        telemetry.track(const TelemetryEvent.chatModeOpened());
        expect(telemetry.usageClient, isNull);
        expect(posts, isEmpty);
      },
    );

    test('both off from the stored preferences: nothing opens', () async {
      store.value = const TelemetryPreferences(
        crashReports: false,
        usageStats: false,
      );
      final telemetry = build();
      await telemetry.start();
      telemetry.track(const TelemetryEvent.chatModeOpened());
      expect(crash.opens, 0);
      expect(telemetry.usageClient, isNull);
      expect(await sentNames(telemetry), isEmpty);
    });

    test('screen views also leave a navigation breadcrumb', () async {
      final telemetry = build();
      await telemetry.start();
      telemetry.screen(TelemetryScreen.files);
      expect(crash.screens, [TelemetryScreen.files]);
    });
  });

  test('the app error log forwards what it records, and keeps working when '
      'the reporter throws', () {
    final log = AppErrorLog();
    final seen = <Object>[];
    log.onRecord = (error, _) => seen.add(error);
    log.recordError(StateError('one'), null);
    expect(seen, hasLength(1));

    log.onRecord = (_, _) => throw StateError('reporter broke');
    log.recordError(StateError('two'), null);
    expect(log.entries, hasLength(2));
  });

  group('preferences', () {
    test('default to both on, notice not seen', () {
      const preferences = TelemetryPreferences();
      expect(preferences.crashReports, isTrue);
      expect(preferences.usageStats, isTrue);
      expect(preferences.noticeSeen, isFalse);
      expect(TelemetryPreferences.fromJson(null), preferences);
      expect(TelemetryPreferences.fromJson({}), preferences);
    });

    test('persist in secure storage under their own key', () async {
      final storage = InMemorySecureStorage();
      final secure = SecureTelemetryPreferencesStore(storage);
      expect(await secure.load(), const TelemetryPreferences());

      final telemetry = Telemetry(
        config: TelemetryConfig.disabled,
        store: secure,
      );
      addTearDown(telemetry.dispose);
      await telemetry.start();
      await telemetry.setCrashReports(false);
      await telemetry.dismissNotice();

      final raw = await storage.read(
        key: SecureTelemetryPreferencesStore.storageKey,
      );
      expect(jsonDecode(raw!), {
        'crashReports': false,
        'usageStats': true,
        'noticeSeen': true,
      });
      expect(
        await secure.load(),
        const TelemetryPreferences(crashReports: false, noticeSeen: true),
      );
    });

    test('a corrupt value falls back to the defaults', () async {
      final storage = InMemorySecureStorage();
      await storage.write(
        key: SecureTelemetryPreferencesStore.storageKey,
        value: '{not json',
      );
      expect(
        await SecureTelemetryPreferencesStore(storage).load(),
        const TelemetryPreferences(),
      );
    });
  });

  test('app info: release name, props and a browser-shaped user agent', () {
    expect(_info.release, 'conductore@1.2.3+45');
    expect(_info.usageProps, {
      'platform': 'android',
      'app_version': '1.2.3',
      'flavor': 'full',
    });
    expect(_info.userAgent, 'Mozilla/5.0 (Linux; Android) Conductore/1.2.3');
  });
}
