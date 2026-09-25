import 'package:conduit/core/telemetry/telemetry.dart';
import 'package:conduit/core/telemetry/telemetry_config.dart';
import 'package:conduit/core/telemetry/telemetry_preferences.dart';
import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/settings/presentation/privacy_notice.dart';
import 'package:conduit/features/settings/presentation/privacy_settings.dart';
import 'package:conduit/features/settings/presentation/settings_services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

void main() {
  late MemoryTelemetryPreferencesStore store;
  late Telemetry telemetry;
  late Telemetry previousInstance;

  setUp(() async {
    store = MemoryTelemetryPreferencesStore();
    telemetry = Telemetry(config: TelemetryConfig.disabled, store: store);
    await telemetry.start();
    previousInstance = Telemetry.instance;
    Telemetry.instance = telemetry;
  });

  tearDown(() {
    Telemetry.instance = previousInstance;
    telemetry.dispose();
  });

  Future<void> pumpNotice(WidgetTester tester) async {
    final theme = ThemeController(InMemoryThemePreferences());
    await theme.load();
    await tester.pumpWidget(
      SettingsScope(
        services: SettingsServices(theme: theme),
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                PrivacyNotice(telemetry: telemetry),
                const Text('below'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('the notice shows once and OK dismisses it for good', (
    tester,
  ) async {
    await pumpNotice(tester);
    expect(find.text(privacyNoticeText), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('privacy-notice-ok')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('privacy-notice')), findsNothing);
    expect(store.value.noticeSeen, isTrue);
    // Nothing but the switches changed.
    expect(store.value.crashReports, isTrue);
    expect(store.value.usageStats, isTrue);

    // A new launch reads the stored flag: no notice.
    final next = Telemetry(config: TelemetryConfig.disabled, store: store);
    addTearDown(next.dispose);
    await next.start();
    expect(next.showNotice, isFalse);
  });

  testWidgets('the notice is hidden until preferences are loaded', (
    tester,
  ) async {
    final unstarted = Telemetry(
      config: TelemetryConfig.disabled,
      store: MemoryTelemetryPreferencesStore(),
    );
    addTearDown(unstarted.dispose);
    await tester.pumpWidget(
      MaterialApp(home: PrivacyNotice(telemetry: unstarted)),
    );
    expect(find.byKey(const ValueKey('privacy-notice')), findsNothing);
  });

  testWidgets('Settings opens the Privacy section, whose switches apply '
      'and persist', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await pumpNotice(tester);

    await tester.tap(find.byKey(const ValueKey('privacy-notice-settings')));
    await tester.pumpAndSettle();
    expect(store.value.noticeSeen, isTrue);
    expect(find.text('Send crash reports'), findsOneWidget);
    expect(find.text(crashReportsCaption), findsOneWidget);
    expect(find.text('Send anonymous usage stats'), findsOneWidget);
    expect(find.text(usageStatsCaption), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('privacy-crash-reports')));
    await tester.pumpAndSettle();
    expect(telemetry.preferences.crashReports, isFalse);
    expect(store.value.crashReports, isFalse);

    await tester.tap(find.byKey(const ValueKey('privacy-usage-stats')));
    await tester.pumpAndSettle();
    expect(store.value.usageStats, isFalse);
    // A development build says so.
    expect(find.textContaining('sends nothing'), findsOneWidget);
  });

  testWidgets('desktop: one-row banner', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpNotice(tester);

    final text = tester.getRect(find.text(privacyNoticeText));
    final ok = tester.getRect(find.byKey(const ValueKey('privacy-notice-ok')));
    expect(ok.left, greaterThan(text.right));
    expect((ok.center.dy - text.center.dy).abs(), lessThan(12));
    debugDefaultTargetPlatformOverride = null;
  });
}
