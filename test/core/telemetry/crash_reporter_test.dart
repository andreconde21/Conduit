import 'dart:convert';

import 'package:conduit/core/telemetry/crash_reporter.dart';
import 'package:conduit/core/telemetry/telemetry_events.dart';
import 'package:conduit/core/telemetry/telemetry_scrubber.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry/sentry.dart';

/// Keeps envelopes instead of sending them.
class _CapturingTransport implements Transport {
  final envelopes = <SentryEnvelope>[];

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    envelopes.add(envelope);
    return SentryId.newId();
  }

  Future<List<Map<String, dynamic>>> events() async => [
    for (final envelope in envelopes)
      for (final item in envelope.items)
        if (item.header.type == 'event')
          jsonDecode(utf8.decode(await item.dataFactory()))
              as Map<String, dynamic>,
  ];
}

/// Everything a report must never contain, for the machines in [_scrubber].
const _forbidden = [
  'devbox',
  'andre',
  '10.0.0.7',
  '2222',
  'Build Server',
  'hunter2',
  '/home/',
  'notes.txt',
  'secret-workspace',
  'sudo shutdown',
  'fe80::',
];

// secret-workspace stands for a Herdr workspace name the app knows.
final _scrubber = TelemetryScrubber(
  sensitiveTerms: () => [
    'Build Server',
    'devbox',
    'andre',
    'hunter2',
    'secret-workspace',
  ],
);

void expectClean(Map<String, dynamic> json) {
  // Random ids and times can contain any digits.
  final text = jsonEncode(
    {...json}
      ..remove('event_id')
      ..remove('timestamp'),
  );
  for (final word in _forbidden) {
    expect(text, isNot(contains(word)), reason: 'leaked "$word": $text');
  }
}

void main() {
  group('scrubSentryEvent', () {
    SentryEvent dirtyEvent({Object? throwable}) {
      final frame = SentryStackFrame(
        absPath: 'file:///home/andre/src/app/lib/main.dart',
        fileName: 'main.dart',
        function: 'connect',
        lineNo: 12,
        contextLine: 'final pw = "hunter2";',
        preContext: const ['host = "devbox"'],
        vars: const {'host': 'devbox'},
      );
      final appFrame = SentryStackFrame(
        absPath: 'package:conduit/main.dart',
        fileName: 'main.dart',
        function: 'main',
        lineNo: 3,
        inApp: true,
      );
      return SentryEvent(
          throwable: throwable,
          serverName: 'devbox',
          user: SentryUser(id: 'andre', ipAddress: '10.0.0.7'),
          request: SentryRequest(url: 'https://devbox/secret-workspace'),
          message: SentryMessage('ssh andre@devbox -p 2222'),
          transaction: '/home/andre/notes.txt',
          tags: {'machine': 'Build Server'},
          // Deprecated in the SDK but still serialised when set.
          // ignore: deprecated_member_use
          extra: {'cmd': 'sudo shutdown now'},
          exceptions: [
            SentryException(
              type: 'SocketException',
              value:
                  'Connection refused (10.0.0.7:2222, fe80::1%eth0) for '
                  'Build Server in secret-workspace',
              throwable: throwable,
              stackTrace: SentryStackTrace(frames: [frame, appFrame]),
            ),
          ],
          threads: [
            SentryThread(
              name: 'devbox-worker',
              stacktrace: SentryStackTrace(frames: [frame]),
            ),
          ],
          breadcrumbs: [
            Breadcrumb.console(message: 'sudo shutdown now on devbox'),
            Breadcrumb.http(url: Uri.parse('https://devbox/'), method: 'GET'),
            Breadcrumb(message: 'typed hunter2', category: 'ui.click'),
            Breadcrumb(
              category: 'navigation',
              data: {'to': '/home/andre/notes.txt'},
            ),
            navigationBreadcrumb(TelemetryScreen.terminal),
          ],
          contexts: Contexts(
            device: SentryDevice(
              name: 'devbox',
              model: 'Pixel 8',
              arch: 'arm64',
            ),
            operatingSystem: SentryOperatingSystem(
              name: 'Linux',
              version: '6.8',
              rawDescription: 'Linux devbox 6.8.0 andre',
              kernelVersion: 'devbox-6.8',
            ),
            culture: SentryCulture(locale: 'pt_PT', timezone: 'Europe/Lisbon'),
          ),
        )
        ..contexts['dart_context'] = {
          'compile_mode': 'aot',
          'executable': '/home/andre/app',
        }
        ..contexts['workspace'] = {'name': 'secret-workspace'};
    }

    test('removes identity, extras, and everything machine-specific', () {
      final event = scrubSentryEvent(
        dirtyEvent(),
        _scrubber,
        tags: {'platform': 'android', 'flavor': 'full'},
      );
      final json = event.toJson();
      expectClean(json);

      expect(json['user'], isNull);
      expect(json['server_name'], isNull);
      expect(json['request'], isNull);
      expect(json['extra'], isNull);
      expect(json['tags'], {'platform': 'android', 'flavor': 'full'});
      expect(event.contexts.device?.name, isNull);
      expect(event.contexts.device?.model, 'Pixel 8');
      expect(event.contexts.operatingSystem?.rawDescription, isNull);
      expect(event.contexts.culture?.timezone, isNull);
      expect(event.contexts.culture?.locale, 'pt_PT');
      expect(event.contexts['dart_context'], {'compile_mode': 'aot'});
      expect(event.contexts['workspace'], isNull);
    });

    test('keeps the exception type and app frames, drops frame variables '
        'and source context', () {
      final event = scrubSentryEvent(dirtyEvent(), _scrubber);
      final exception = event.exceptions!.single;
      expect(exception.type, 'SocketException');
      expect(exception.value, startsWith('Connection refused (<ip>'));
      final frames = exception.stackTrace!.frames;
      expect(frames.first.absPath, '<path>');
      expect(frames.first.vars, isEmpty);
      expect(frames.first.contextLine, isNull);
      expect(frames.first.preContext, isEmpty);
      expect(frames.last.absPath, 'package:conduit/main.dart');
      expect(frames.last.function, 'main');
      expect(frames.last.lineNo, 3);
      expect(event.threads!.single.name, isNull);
    });

    test("keeps only the app's own navigation breadcrumbs", () {
      final event = scrubSentryEvent(dirtyEvent(), _scrubber);
      expect(event.breadcrumbs, hasLength(1));
      expect(event.breadcrumbs!.single.data, {'to': 'terminal'});
    });

    test('a FormatException keeps its message, not the input it quotes', () {
      const error = FormatException(
        'Unexpected character',
        '{"agents":[{"cwd":"/home/andre/secret-workspace"}]}',
        3,
      );
      final event = scrubSentryEvent(dirtyEvent(throwable: error), _scrubber);
      expect(event.exceptions!.single.value, 'Unexpected character');
    });
  });

  group('scrubBreadcrumb', () {
    test('drops everything but known screens', () {
      expect(scrubBreadcrumb(null), isNull);
      expect(scrubBreadcrumb(Breadcrumb.console(message: 'x')), isNull);
      expect(
        scrubBreadcrumb(Breadcrumb(category: 'navigation', data: {'to': 'x'})),
        isNull,
      );
      final kept = scrubBreadcrumb(
        Breadcrumb(
          category: 'navigation',
          message: 'devbox',
          data: {'to': 'files', 'from': '/home/andre'},
        ),
      );
      expect(kept?.data, {'to': 'files'});
      expect(kept?.message, isNull);
    });
  });

  test(
    'SentryCrashReporter sends only scrubbed events through the SDK',
    () async {
      final transport = _CapturingTransport();
      final reporter = SentryCrashReporter(_scrubber, transport: transport);
      await reporter.open(
        const CrashReportContext(
          dsn: 'https://public@glitchtip.invalid/1',
          release: 'conductore@1.2.3+45',
          dist: '45',
          environment: 'preview',
          tags: {'platform': 'android', 'flavor': 'full'},
        ),
      );
      addTearDown(reporter.close);
      expect(reporter.isOpen, isTrue);

      reporter.screen(TelemetryScreen.terminal);
      await Sentry.addBreadcrumb(Breadcrumb.console(message: 'reboot devbox'));
      try {
        throw StateError('ssh andre@devbox -p 2222 failed in /home/andre/x');
      } catch (error, stack) {
        await reporter.capture(error, stack);
      }

      final events = await transport.events();
      expect(events, hasLength(1));
      final event = events.single;
      expectClean(event);
      expect(event['release'], 'conductore@1.2.3+45');
      expect(event['environment'], 'preview');
      expect(event['tags'], {'platform': 'android', 'flavor': 'full'});
      expect(event['user'], isNull);
      expect(
        (((event['exception'] as Map)['values'] as List).single
            as Map)['value'],
        'Bad state: ssh <user@host> -p <port> failed in <path>',
      );
      expect(
        [
          for (final crumb in event['breadcrumbs'] as List<dynamic>)
            (crumb as Map)['data'],
        ],
        [
          {'to': 'terminal'},
        ],
      );

      await reporter.close();
      expect(reporter.isOpen, isFalse);
      await reporter.capture(StateError('after close'), null);
      expect(await transport.events(), hasLength(1));
    },
  );
}
