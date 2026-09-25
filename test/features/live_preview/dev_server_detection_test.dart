import 'dart:io';

import 'package:conduit/features/live_preview/domain/dev_server_detection.dart';
import 'package:conduit/features/live_preview/domain/listening_ports.dart';
import 'package:flutter_test/flutter_test.dart';

String _fixture(String name) =>
    File('test/fixtures/ss/$name').readAsStringSync();

void main() {
  group('ss fixtures', () {
    test('keeps the user\'s dev servers and drops system listeners', () {
      final ports = parseListeningPorts(
        _fixture('ss_ltnp_user.txt'),
      ).where(isDevServerCandidate).toList();
      // 53 and 22 are system ports, 443 without an owner is the system's
      // web server, 41234 is ephemeral; 8080 (another user's) stays: plain
      // ss cannot tell a teammate's server from a daemon.
      expect(ports.map((port) => port.port), [5173, 8080]);
      expect(ports.first.process, 'node');
    });

    test('parses builds that print no State column', () {
      final ports = parseListeningPorts(
        _fixture('ss_ltn_no_state.txt'),
      ).where(isDevServerCandidate);
      expect(ports.map((port) => port.port), [3000, 8000]);
    });

    test('ignores well-known daemons by process name', () {
      expect(
        isDevServerCandidate(
          const ListeningPort(port: 8080, process: 'docker-proxy'),
        ),
        isFalse,
      );
      expect(
        isDevServerCandidate(const ListeningPort(port: 443, process: 'node')),
        isTrue,
      );
    });
  });

  group('newListeningPorts', () {
    test('reports ports that were not listening before', () {
      const before = [ListeningPort(port: 3000), ListeningPort(port: 5432)];
      const after = [
        ListeningPort(port: 3000),
        ListeningPort(port: 5173, process: 'node'),
        ListeningPort(port: 5432),
      ];
      expect(newListeningPorts(before, after), [
        const ListeningPort(port: 5173, process: 'node'),
      ]);
      expect(newListeningPorts(after, before), isEmpty);
    });
  });

  group('parseCompanionPorts', () {
    test('reads seq, label and cwd', () {
      final reply = parseCompanionPorts(
        '{"seq":7,"source":"ss","cached":false,"ports":[{"port":5173,'
        '"address":"127.0.0.1","pid":1,"process":"node","label":"vite",'
        '"cwd":"/home/a/app","seq":7,"url":"http://localhost:5173/"},'
        '{"port":3000,"process":"ruby","label":null,"seq":6}]}\n',
      )!;
      expect(reply.seq, 7);
      expect(reply.offers.map((offer) => offer.port), [3000, 5173]);
      expect(reply.offers.first.label, 'ruby');
      expect(reply.offers.last.label, 'vite');
      expect(reply.offers.last.cwd, '/home/a/app');
      expect(reply.offers.last.chipText, 'Preview ready · :5173 · vite');
    });

    test('is null for an older companion or garbage', () {
      expect(
        parseCompanionPorts('{"error":"unknown command ports\\nusage: …"}'),
        isNull,
      );
      expect(parseCompanionPorts('sh: conductore-hostd: not found'), isNull);
      expect(parseCompanionPorts(''), isNull);
    });

    test('builds the command arguments', () {
      expect(companionPortsArguments(), 'ports');
      expect(companionPortsArguments(since: 12), 'ports --since 12');
    });
  });

  group('detectDevServerUrls', () {
    test('Vite', () {
      final offers = detectDevServerUrls([
        '',
        '  VITE v5.4.2  ready in 312 ms',
        '',
        '  ➜  Local:   http://localhost:5173/',
        '  ➜  Network: use --host to expose',
      ]);
      expect(offers, [
        const DevServerOffer(
          port: 5173,
          source: DevServerOfferSource.output,
          label: 'vite',
        ),
      ]);
    });

    test('Next.js keeps the path and names the framework', () {
      final offers = detectDevServerUrls([
        '  ▲ Next.js 14.2.3',
        '  - Local:        http://localhost:3000/dashboard?tab=1',
        '  - Environments: .env.local',
      ]);
      expect(offers.single.port, 3000);
      expect(offers.single.path, '/dashboard?tab=1');
      expect(offers.single.label, 'next');
    });

    test('create-react-app, Django, Flask and python http.server', () {
      expect(
        detectDevServerUrls([
          'You can now view my-app in the browser.',
          '',
          '  Local:            http://localhost:3001',
          '  On Your Network:  http://192.168.1.5:3001',
        ]).single.label,
        'create-react-app',
      );
      expect(
        detectDevServerUrls([
          'Django version 5.0, using settings \'site.settings\'',
          'Starting development server at http://127.0.0.1:8000/',
        ]).single.label,
        'django',
      );
      expect(
        detectDevServerUrls([
          ' * Serving Flask app \'app\'',
          ' * Running on http://127.0.0.1:5000',
        ]).single.port,
        5000,
      );
      expect(
        detectDevServerUrls([
          'Serving HTTP on 0.0.0.0 port 8000 (http://0.0.0.0:8000/) ...',
        ]).single.label,
        'python http.server',
      );
    });

    test('ignores typed commands and non-loopback URLs', () {
      expect(
        detectDevServerUrls([
          r'$ curl http://localhost:3000/api',
          'see https://example.com:8443/docs',
          'Local: http://192.168.1.5:3000',
        ]),
        isEmpty,
      );
    });

    test('one offer per port', () {
      final offers = detectDevServerUrls([
        'Local: http://localhost:5173/',
        'Local: http://127.0.0.1:5173/',
        'Local: http://localhost:4321/',
      ]);
      expect(offers.map((offer) => offer.port), [5173, 4321]);
    });
  });

  test('mergedWith combines a URL path with the companion label', () {
    const printed = DevServerOffer(
      port: 5173,
      source: DevServerOfferSource.output,
      path: '/app',
    );
    const listening = DevServerOffer(
      port: 5173,
      source: DevServerOfferSource.listening,
      label: 'vite',
      cwd: '/srv/app',
    );
    final merged = printed.mergedWith(listening);
    expect(merged.path, '/app');
    expect(merged.label, 'vite');
    expect(merged.cwd, '/srv/app');
  });
}
