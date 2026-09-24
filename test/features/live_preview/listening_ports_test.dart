import 'package:conduit/features/live_preview/domain/listening_ports.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses ss -ltnpH output, merging v4/v6 and keeping process names', () {
    final ports = parseListeningPorts('''
LISTEN 0      511          0.0.0.0:3000       0.0.0.0:*    users:(("node",pid=123,fd=20))
LISTEN 0      511             [::]:3000          [::]:*    users:(("node",pid=123,fd=21))
LISTEN 0      128          0.0.0.0:22         0.0.0.0:*
LISTEN 0      4096       127.0.0.1:5173       0.0.0.0:*    users:(("vite",pid=99,fd=18))
LISTEN 0      4096   [::ffff:127.0.0.1]:8080       *:*
''');
    expect(ports.map((port) => port.port), [22, 3000, 5173, 8080]);
    expect(ports[1].process, 'node');
    expect(ports[1].label, '3000 · node');
    expect(ports[0].process, isNull);
    expect(ports[0].label, '22');
    expect(ports[2].address, '127.0.0.1');
    expect(ports[3].address, '::ffff:127.0.0.1');
  });

  test('tolerates output without the State column and blank lines', () {
    final ports = parseListeningPorts('\n0 128 *:8000 *:*\n\n');
    expect(ports.single.port, 8000);
    expect(ports.single.address, '*');
  });

  test('ignores lines without an address', () {
    expect(parseListeningPorts('garbage line\n'), isEmpty);
    expect(parseListeningPorts(''), isEmpty);
  });
}
