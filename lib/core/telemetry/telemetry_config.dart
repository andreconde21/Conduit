import 'package:flutter/foundation.dart';

/// Where crash reports and usage counts go, and whether this build sends
/// anything at all.
///
/// Both endpoints are Outsmartis' own servers: GlitchTip (Sentry protocol)
/// for crashes, Plausible for anonymous counts. A Sentry DSN is a public
/// ingest key, not a secret, so the default ships in the app; every value
/// can be replaced (or emptied, which turns that half off) with
/// `--dart-define`.
@immutable
class TelemetryConfig {
  const TelemetryConfig({
    required this.sentryDsn,
    required this.plausibleHost,
    required this.plausibleDomain,
    required this.environment,
    required this.sendEnabled,
  });

  /// Reads the `--dart-define` overrides. Debug and profile builds (and
  /// `flutter test`) send nothing unless `CONDUCTORE_TELEMETRY_IN_DEBUG`
  /// is true, for checking the pipeline by hand.
  factory TelemetryConfig.fromEnvironment() => const TelemetryConfig(
    sentryDsn: String.fromEnvironment(
      'CONDUCTORE_SENTRY_DSN',
      defaultValue: defaultSentryDsn,
    ),
    plausibleHost: String.fromEnvironment(
      'CONDUCTORE_PLAUSIBLE_HOST',
      defaultValue: defaultPlausibleHost,
    ),
    plausibleDomain: String.fromEnvironment(
      'CONDUCTORE_PLAUSIBLE_DOMAIN',
      defaultValue: defaultPlausibleDomain,
    ),
    environment: String.fromEnvironment(
      'CONDUCTORE_TELEMETRY_ENV',
      defaultValue: 'preview',
    ),
    sendEnabled:
        kReleaseMode || bool.fromEnvironment('CONDUCTORE_TELEMETRY_IN_DEBUG'),
  );

  /// Sends nothing (tests, and the app before [TelemetryController.start]).
  static const disabled = TelemetryConfig(
    sentryDsn: '',
    plausibleHost: '',
    plausibleDomain: '',
    environment: 'test',
    sendEnabled: false,
  );

  static const defaultSentryDsn =
      'https://34c04d4fb3d94460b4df5d51d0058564@glitchtip.outsmartis.dev/24';
  static const defaultPlausibleHost = 'https://plausible.outsmartis.dev';
  static const defaultPlausibleDomain = 'conductore.outsmartis.dev';

  final String sentryDsn;
  final String plausibleHost;
  final String plausibleDomain;

  /// Sentry environment ("preview" until there are stable releases).
  final String environment;

  /// False in debug builds and tests: nothing leaves the device.
  final bool sendEnabled;

  bool get crashReportsAvailable => sendEnabled && sentryDsn.isNotEmpty;

  bool get usageStatsAvailable =>
      sendEnabled && plausibleHost.isNotEmpty && plausibleDomain.isNotEmpty;
}
