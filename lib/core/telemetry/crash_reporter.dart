import 'dart:async';

import 'package:conduit/core/telemetry/telemetry_events.dart';
import 'package:conduit/core/telemetry/telemetry_scrubber.dart';
import 'package:flutter/foundation.dart';
import 'package:sentry/sentry.dart';

/// What a crash report says about the app itself (never about the user).
class CrashReportContext {
  const CrashReportContext({
    required this.dsn,
    required this.release,
    required this.dist,
    required this.environment,
    required this.tags,
  });

  final String dsn;

  /// `conductore@<version>+<build>`.
  final String release;

  /// The build number.
  final String dist;
  final String environment;

  /// platform and flavor.
  final Map<String, String> tags;
}

/// Sends crash reports. [SentryCrashReporter] in the app; tests use a fake.
abstract class CrashReporter {
  bool get isOpen;
  Future<void> open(CrashReportContext context);
  Future<void> close();
  Future<void> capture(Object error, StackTrace? stack);

  /// A navigation breadcrumb: which top-level screen was showing.
  void screen(TelemetryScreen screen);
}

/// The Dart Sentry SDK (pure Dart on every platform: no native crash
/// handler, so nothing changes in the Android, iOS or desktop projects)
/// pointed at GlitchTip, with [scrubSentryEvent] and [scrubBreadcrumb] as
/// the last step before anything is sent.
class SentryCrashReporter implements CrashReporter {
  SentryCrashReporter(this.scrubber, {@visibleForTesting this.transport});

  final TelemetryScrubber scrubber;

  /// Replaces the HTTP transport (tests read the envelopes instead).
  final Transport? transport;
  bool _open = false;

  @override
  bool get isOpen => _open;

  @override
  Future<void> open(CrashReportContext context) async {
    if (_open) return;
    await Sentry.init((options) {
      options
        ..dsn = context.dsn
        ..release = context.release
        ..dist = context.dist
        ..environment = context.environment
        ..sendDefaultPii = false
        ..attachStacktrace = true
        ..attachThreads = false
        ..maxBreadcrumbs = 20
        ..sendClientReports = false
        ..tracesSampleRate = null
        ..debug = false
        ..transport = transport ?? options.transport
        ..beforeSend = ((event, hint) =>
            scrubSentryEvent(event, scrubber, tags: context.tags))
        ..beforeBreadcrumb = ((breadcrumb, hint) =>
            scrubBreadcrumb(breadcrumb));
    });
    _open = true;
  }

  @override
  Future<void> close() async {
    if (!_open) return;
    _open = false;
    await Sentry.close();
  }

  @override
  Future<void> capture(Object error, StackTrace? stack) async {
    if (!_open) return;
    await Sentry.captureException(error, stackTrace: stack);
  }

  @override
  void screen(TelemetryScreen screen) {
    if (!_open) return;
    unawaited(Sentry.addBreadcrumb(navigationBreadcrumb(screen)));
  }
}

Breadcrumb navigationBreadcrumb(TelemetryScreen screen) => Breadcrumb(
  category: 'navigation',
  type: 'navigation',
  data: {'to': screen.name},
);

final _screenNames = {for (final screen in TelemetryScreen.values) screen.name};

/// Keeps only the app's own navigation breadcrumbs (a screen name from
/// [TelemetryScreen]); console, log, HTTP and everything else is dropped.
Breadcrumb? scrubBreadcrumb(Breadcrumb? breadcrumb) {
  if (breadcrumb == null || breadcrumb.category != 'navigation') return null;
  final to = breadcrumb.data?['to'];
  if (to is! String || !_screenNames.contains(to)) return null;
  return Breadcrumb(
    category: 'navigation',
    type: 'navigation',
    timestamp: breadcrumb.timestamp,
    data: {'to': to},
  );
}

/// The event as it may leave the device: exception types and the app's
/// stack frames, scrubbed messages, coarse device facts and [tags].
/// Everything identifying (user, device name, server name, request,
/// extras, other tags, frame variables and source context) is removed.
SentryEvent scrubSentryEvent(
  SentryEvent event,
  TelemetryScrubber scrubber, {
  Map<String, String> tags = const {},
}) {
  String? scrub(String? text) => text == null ? null : scrubber.scrub(text);

  final throwable = event.throwable;
  event
    ..user = null
    ..serverName = null
    ..request = null
    // Deprecated upstream, but still sent when something sets it.
    // ignore: deprecated_member_use
    ..extra = null
    ..modules = null
    ..tags = {...tags}
    ..transaction = scrub(event.transaction)
    ..culprit = scrub(event.culprit)
    ..message = event.message == null
        ? null
        : SentryMessage(scrub(event.message!.formatted)!)
    ..breadcrumbs = [
      for (final crumb in event.breadcrumbs ?? const <Breadcrumb>[])
        ?scrubBreadcrumb(crumb),
    ];
  for (final exception in event.exceptions ?? const <SentryException>[]) {
    // A FormatException's text quotes the input it choked on (companion
    // output, a config file): keep only its message.
    final value =
        identical(exception.throwable, throwable) &&
            throwable is FormatException
        ? throwable.message
        : exception.value;
    exception
      ..value = scrub(value)
      ..stackTrace = _scrubStack(exception.stackTrace, scrubber);
  }
  for (final thread in event.threads ?? const <SentryThread>[]) {
    thread
      ..name = null
      ..stacktrace = _scrubStack(thread.stacktrace, scrubber);
  }

  final contexts = event.contexts;
  final device = contexts.device;
  if (device != null) {
    contexts.device = SentryDevice(
      family: device.family,
      model: device.model,
      modelId: device.modelId,
      arch: device.arch,
      processorCount: device.processorCount,
      memorySize: device.memorySize,
      simulator: device.simulator,
    );
  }
  final os = contexts.operatingSystem;
  if (os != null) {
    contexts.operatingSystem = SentryOperatingSystem(
      name: os.name,
      version: os.version,
    );
  }
  final culture = contexts.culture;
  if (culture != null) {
    contexts.culture = SentryCulture(locale: culture.locale);
  }
  final dart = contexts['dart_context'];
  contexts.remove('dart_context');
  if (dart is Map && dart['compile_mode'] is String) {
    contexts['dart_context'] = {'compile_mode': dart['compile_mode']};
  }
  for (final key in contexts.keys.toList()) {
    if (!_keptContexts.contains(key)) contexts.remove(key);
  }
  return event;
}

const _keptContexts = {
  'device',
  'os',
  'culture',
  'app',
  'runtime',
  'runtimes',
  'dart_context',
};

SentryStackTrace? _scrubStack(
  SentryStackTrace? stack,
  TelemetryScrubber scrubber,
) {
  if (stack == null) return null;
  return SentryStackTrace(
    lang: stack.lang,
    snapshot: stack.snapshot,
    frames: [for (final frame in stack.frames) _scrubFrame(frame, scrubber)],
  );
}

bool _isCodeUri(String? path) =>
    path == null || path.startsWith('package:') || path.startsWith('dart:');

/// A frame without variables or source lines; a file outside `package:`
/// and `dart:` (a local path in a debug build) loses its path.
SentryStackFrame _scrubFrame(SentryStackFrame frame, TelemetryScrubber s) {
  final code = _isCodeUri(frame.absPath);
  return SentryStackFrame(
    absPath: code ? frame.absPath : '<path>',
    fileName: code ? frame.fileName : '<path>',
    // Function names of the app's code are code; elsewhere, scrubbed.
    function: code || frame.function == null
        ? frame.function
        : s.scrub(frame.function!),
    module: frame.module,
    lineNo: frame.lineNo,
    colNo: frame.colNo,
    inApp: frame.inApp,
    package: frame.package,
    native: frame.native,
    platform: frame.platform,
    imageAddr: frame.imageAddr,
    symbolAddr: frame.symbolAddr,
    instructionAddr: frame.instructionAddr,
    stackStart: frame.stackStart,
    framesOmitted: frame.framesOmitted.isEmpty ? null : frame.framesOmitted,
  );
}
