import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:conduit/core/telemetry/telemetry_events.dart';
import 'package:http/http.dart' as http;

/// Posts usage events to Plausible's events API, a handful at most.
///
/// Events queue up and go out on a timer, never more than [maxPerMinute]
/// requests in any minute; past [maxQueued] waiting events new ones are
/// dropped. A failed request (offline, server down) is dropped too, not
/// retried. Nothing here blocks the caller or throws.
class PlausibleClient {
  PlausibleClient({
    required this.host,
    required this.domain,
    required this.userAgent,
    required this.baseProps,
    http.Client? client,
    this.flushDelay = const Duration(seconds: 15),
    this.maxPerMinute = 6,
    this.maxQueued = 20,
    DateTime Function() clock = DateTime.now,
  }) : _client = client ?? http.Client(),
       _now = clock;

  /// `https://plausible.example`, no trailing path.
  final String host;

  /// The Plausible site the events count for.
  final String domain;

  /// Plausible ignores requests without a browser-like User-Agent.
  final String userAgent;

  /// Props every event carries (platform, app version, flavor).
  final Map<String, String> baseProps;

  final Duration flushDelay;
  final int maxPerMinute;
  final int maxQueued;

  final http.Client _client;
  final DateTime Function() _now;
  final _queue = Queue<TelemetryEvent>();
  final _sentAt = Queue<DateTime>();
  Timer? _timer;
  bool _closed = false;

  int get queued => _queue.length;

  Uri get endpoint => Uri.parse('$host/api/event');

  void add(TelemetryEvent event) {
    if (_closed || _queue.length >= maxQueued) return;
    _queue.add(event);
    _timer ??= Timer(flushDelay, () {
      _timer = null;
      unawaited(flush());
    });
  }

  /// Sends what the rate limit allows now; the rest waits for the next
  /// timer.
  Future<void> flush() async {
    final now = _now();
    while (_sentAt.isNotEmpty &&
        now.difference(_sentAt.first) >= const Duration(minutes: 1)) {
      _sentAt.removeFirst();
    }
    final sends = <Future<void>>[];
    while (_queue.isNotEmpty && _sentAt.length < maxPerMinute) {
      _sentAt.add(now);
      sends.add(_post(_queue.removeFirst()));
    }
    if (_queue.isNotEmpty && !_closed) {
      final wait = const Duration(minutes: 1) - now.difference(_sentAt.first);
      _timer ??= Timer(wait < flushDelay ? flushDelay : wait, () {
        _timer = null;
        unawaited(flush());
      });
    }
    await Future.wait(sends);
  }

  /// The JSON body for [event]: name, a synthetic `app://` URL, the site
  /// domain and props. Nothing else: no referrer, no identifiers.
  Map<String, Object> payloadFor(TelemetryEvent event) => {
    'name': event.name,
    'url': 'app://conductore/${event.screen.name}',
    'domain': domain,
    'props': {...baseProps, ...event.props},
  };

  Future<void> _post(TelemetryEvent event) async {
    try {
      await _client
          .post(
            endpoint,
            headers: {
              'User-Agent': userAgent,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payloadFor(event)),
          )
          .timeout(const Duration(seconds: 10));
    } on Object {
      // Offline or the server is away: counts are best effort.
    }
  }

  /// Drops what is queued and stops the timer.
  void close() {
    _closed = true;
    _timer?.cancel();
    _timer = null;
    _queue.clear();
    _client.close();
  }
}
