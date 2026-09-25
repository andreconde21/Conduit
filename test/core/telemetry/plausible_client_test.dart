import 'dart:convert';
import 'dart:io';

import 'package:conduit/core/connection_problem.dart';
import 'package:conduit/core/telemetry/plausible_client.dart';
import 'package:conduit/core/telemetry/telemetry_events.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late List<http.Request> requests;
  late http.Client client;

  setUp(() {
    requests = [];
    client = MockClient((request) async {
      requests.add(request);
      return http.Response('ok', 202);
    });
  });

  PlausibleClient build({http.Client? using, DateTime Function()? clock}) =>
      PlausibleClient(
        host: 'https://plausible.test',
        domain: 'conductore.outsmartis.dev',
        userAgent: 'Mozilla/5.0 (Linux; Android) Conductore/1.2.3',
        baseProps: const {
          'platform': 'android',
          'app_version': '1.2.3',
          'flavor': 'full',
        },
        client: using ?? client,
        clock: clock ?? DateTime.now,
      );

  test('posts name, a synthetic app:// URL, the domain and coarse props '
      'only', () async {
    final plausible = build();
    plausible.add(
      TelemetryEvent.sessionConnect(
        transport: TelemetryTransport.mosh,
        multiplexer: TelemetryMultiplexer.herdr,
        failure: TelemetryFailure.auth,
      ),
    );
    await plausible.flush();

    final request = requests.single;
    expect(request.method, 'POST');
    expect(request.url.toString(), 'https://plausible.test/api/event');
    expect(request.headers['User-Agent'], contains('Conductore/1.2.3'));
    expect(request.headers['Content-Type'], startsWith('application/json'));
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body.keys.toSet(), {'name', 'url', 'domain', 'props'});
    expect(body['name'], 'session_connect');
    expect(body['url'], 'app://conductore/terminal');
    expect(body['domain'], 'conductore.outsmartis.dev');
    expect(body['props'], {
      'platform': 'android',
      'app_version': '1.2.3',
      'flavor': 'full',
      'transport': 'mosh',
      'multiplexer': 'herdr',
      'result': 'fail',
      'failure': 'auth',
    });
  });

  test('every event has a closed-set name, URL and props', () {
    final plausible = build();
    final allowedProps = {
      'platform',
      'app_version',
      'flavor',
      'transport',
      'multiplexer',
      'result',
      'failure',
      'kind',
      'companion_version',
    };
    final events = [
      const TelemetryEvent.appOpen(),
      for (final screen in TelemetryScreen.values)
        TelemetryEvent.screenView(screen),
      TelemetryEvent.sessionConnect(
        transport: TelemetryTransport.ssh,
        multiplexer: TelemetryMultiplexer.none,
      ),
      const TelemetryEvent.chatModeOpened(),
      for (final kind in TelemetryVoice.values) TelemetryEvent.voiceUsed(kind),
      TelemetryEvent.companionDetected('0.4.1'),
    ];
    for (final event in events) {
      final payload = plausible.payloadFor(event);
      expect(payload.keys.toSet(), {'name', 'url', 'domain', 'props'});
      expect(
        payload['url'],
        matches(
          RegExp(r'^app://conductore/(home|terminal|chat|settings|files)$'),
        ),
      );
      expect(
        (payload['props']! as Map).keys.toSet().difference(allowedProps),
        isEmpty,
        reason: event.name,
      );
    }
    plausible.close();
  });

  test('a companion version that is not a release number is "other"', () {
    expect(TelemetryEvent.companionDetected('1.4.0').props, {
      'companion_version': '1.4.0',
    });
    expect(TelemetryEvent.companionDetected('0.3.1-beta.2').props, {
      'companion_version': '0.3.1-beta.2',
    });
    for (final odd in [null, '', 'devbox 1.0', '1.0', '/home/andre/1.2.3']) {
      expect(
        TelemetryEvent.companionDetected(odd).props['companion_version'],
        'other',
      );
    }
  });

  test('never more than maxPerMinute requests a minute; the rest waits, '
      'then overflow is dropped', () {
    fakeAsync((async) {
      final plausible = build(
        clock: () => async.getClock(DateTime(2026)).now(),
      );
      for (var i = 0; i < 30; i++) {
        plausible.add(const TelemetryEvent.chatModeOpened());
      }
      expect(plausible.queued, plausible.maxQueued);

      async.elapse(plausible.flushDelay);
      expect(requests, hasLength(plausible.maxPerMinute));

      async.elapse(const Duration(seconds: 30));
      expect(requests, hasLength(plausible.maxPerMinute));

      async.elapse(const Duration(minutes: 1));
      expect(requests, hasLength(plausible.maxPerMinute * 2));

      async.elapse(const Duration(minutes: 5));
      expect(requests, hasLength(plausible.maxQueued));
      plausible.close();
    });
  });

  test('offline: the request fails quietly and is not retried', () async {
    var calls = 0;
    final plausible = build(
      using: MockClient((_) async {
        calls++;
        throw const SocketException('Network is unreachable');
      }),
    );
    plausible.add(const TelemetryEvent.appOpen());
    await plausible.flush();
    await plausible.flush();
    expect(calls, 1);
    expect(plausible.queued, 0);
  });

  test('close drops the queue', () {
    fakeAsync((async) {
      final plausible = build();
      plausible
        ..add(const TelemetryEvent.appOpen())
        ..close()
        ..add(const TelemetryEvent.appOpen());
      async.elapse(const Duration(minutes: 1));
      expect(requests, isEmpty);
    });
  });

  test('connection failures map to coarse classes', () {
    // The same classifier as the on-screen "Can't reach" messages.
    expect(
      classifyConnectFailure(const SocketException('Connection timed out')),
      TelemetryFailure.unreachable,
    );
    expect(
      classifyConnectFailure(
        const ConnectionFailure(
          'Could not connect.',
          'rejected',
          kind: ConnectionProblemKind.authentication,
        ),
      ),
      TelemetryFailure.auth,
    );
    expect(
      classifyConnectFailure(
        const ConnectionFailure(
          'Could not connect.',
          'hostkey',
          kind: ConnectionProblemKind.hostKey,
        ),
      ),
      TelemetryFailure.hostkey,
    );
    expect(classifyConnectFailure(StateError('boom')), TelemetryFailure.other);
  });
}
