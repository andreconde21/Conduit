import 'dart:convert';

import 'package:conduit/features/terminal/domain/terminal_remote_scroll.dart';
import 'package:conduit_vt/conduit_vt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('remoteScrollRouteFor', () {
    RemoteScrollRoute route({
      MouseMode mouse = MouseMode.none,
      bool alt = false,
      bool alternateScroll = false,
      bool multiplexer = false,
    }) => remoteScrollRouteFor(
      mouseMode: mouse,
      altBuffer: alt,
      alternateScroll: alternateScroll,
      multiplexer: multiplexer,
    );

    test('mouse tracking with wheel reports sends the wheel', () {
      for (final mode in [
        MouseMode.upDownScroll,
        MouseMode.upDownScrollDrag,
        MouseMode.upDownScrollMove,
      ]) {
        expect(route(mouse: mode), RemoteScrollRoute.wheel);
        expect(route(mouse: mode, alt: true), RemoteScrollRoute.wheel);
        expect(
          route(mouse: mode, alt: true, alternateScroll: true),
          RemoteScrollRoute.wheel,
        );
      }
    });

    test('the main screen without tracking scrolls locally', () {
      expect(route(), RemoteScrollRoute.local);
      expect(route(multiplexer: true), RemoteScrollRoute.local);
      // X10 click reports carry no wheel.
      expect(route(mouse: MouseMode.clickOnly), RemoteScrollRoute.local);
    });

    test('alternate scroll (DECSET 1007) sends arrows', () {
      expect(
        route(alt: true, alternateScroll: true, multiplexer: true),
        RemoteScrollRoute.arrows,
      );
    });

    test('a multiplexer on the alternate screen without tracking enters '
        'copy mode; a plain full-screen program gets arrows', () {
      expect(route(alt: true, multiplexer: true), RemoteScrollRoute.copyMode);
      expect(route(alt: true), RemoteScrollRoute.arrows);
    });
  });

  group('encodeWheelEvent', () {
    test('SGR: buttons 64/65 with one-based coordinates', () {
      expect(
        encodeWheelEvent(
          up: true,
          column: 9,
          row: 4,
          mode: MouseReportMode.sgr,
        ),
        '\x1b[<64;10;5M',
      );
      expect(
        encodeWheelEvent(
          up: false,
          column: 0,
          row: 0,
          mode: MouseReportMode.sgr,
        ),
        '\x1b[<65;1;1M',
      );
      // No upper bound in SGR.
      expect(
        encodeWheelEvent(
          up: true,
          column: 499,
          row: 299,
          mode: MouseReportMode.sgr,
        ),
        '\x1b[<64;500;300M',
      );
    });

    test('legacy (X10/normal): bytes are 32 + value', () {
      final seq = encodeWheelEvent(
        up: true,
        column: 9,
        row: 4,
        mode: MouseReportMode.normal,
      );
      expect(seq.codeUnits, [0x1b, 0x5b, 0x4d, 32 + 64, 32 + 10, 32 + 5]);
      final down = encodeWheelEvent(
        up: false,
        column: 0,
        row: 0,
        mode: MouseReportMode.normal,
      );
      expect(down.codeUnits, [0x1b, 0x5b, 0x4d, 32 + 65, 33, 33]);
    });

    test('legacy caps coordinates at 223 instead of sending NUL', () {
      final seq = encodeWheelEvent(
        up: true,
        column: 400,
        row: 300,
        mode: MouseReportMode.normal,
      );
      expect(seq.codeUnits.sublist(4), [32 + 223, 32 + 223]);
      expect(seq.codeUnits, isNot(contains(0)));
    });

    test('UTF-8 (DECSET 1005) encodes large coordinates as two bytes', () {
      final seq = encodeWheelEvent(
        up: false,
        column: 199,
        row: 2,
        mode: MouseReportMode.utf,
      );
      final bytes = utf8.encode(seq);
      // ESC [ M, button 65+32, then x = 200 + 32 = 232 as two UTF-8 bytes.
      expect(bytes, [0x1b, 0x5b, 0x4d, 97, 0xc3, 0xa8, 32 + 3]);
    });

    test('urxvt (DECSET 1015): decimal with the button offset by 32', () {
      expect(
        encodeWheelEvent(
          up: true,
          column: 2,
          row: 3,
          mode: MouseReportMode.urxvt,
        ),
        '\x1b[96;3;4M',
      );
    });
  });

  test('encodeScrollArrow follows DECSET 1', () {
    expect(encodeScrollArrow(up: true, applicationCursorKeys: false), '\x1b[A');
    expect(
      encodeScrollArrow(up: false, applicationCursorKeys: false),
      '\x1b[B',
    );
    expect(encodeScrollArrow(up: true, applicationCursorKeys: true), '\x1bOA');
    expect(encodeScrollArrow(up: false, applicationCursorKeys: true), '\x1bOB');
  });

  group('RemoteScrollAccumulator', () {
    test('one notch per 14 px, keeping the remainder', () {
      final acc = RemoteScrollAccumulator();
      expect(acc.add(10), 0);
      expect(acc.add(10), 1);
      expect(acc.add(8), 1);
      expect(acc.add(56), 4);
      expect(acc.add(-14), -1);
      expect(acc.add(-30), -2);
    });

    test('reset drops the partial notch', () {
      final acc = RemoteScrollAccumulator()..add(13);
      acc.reset();
      expect(acc.add(2), 0);
    });
  });

  group('remoteScrollMomentum', () {
    test('slow releases add nothing', () {
      expect(remoteScrollMomentum(0), isEmpty);
      expect(remoteScrollMomentum(150), isEmpty);
      expect(remoteScrollMomentum(-150), isEmpty);
    });

    test('a fling adds notches in its direction that decay', () {
      final up = remoteScrollMomentum(1500);
      expect(up, isNotEmpty);
      expect(up.every((n) => n >= 0), isTrue);
      final total = up.fold<int>(0, (a, b) => a + b);
      // 1500 px/s * 0.325 s ~ 487 px ~ 34 notches.
      expect(total, inInclusiveRange(25, maxMomentumNotches));
      // Front-loaded: more in the first quarter than in the last.
      final quarter = up.length ~/ 4;
      final head = up.take(quarter).fold<int>(0, (a, b) => a + b);
      final tail = up.skip(up.length - quarter).fold<int>(0, (a, b) => a + b);
      expect(head, greaterThan(tail));

      final down = remoteScrollMomentum(-1500);
      expect(down.every((n) => n <= 0), isTrue);
      expect(down.fold<int>(0, (a, b) => a + b), -total);
    });

    test('a hard flick is capped', () {
      for (final v in [8000.0, 20000.0, -50000.0]) {
        final total = remoteScrollMomentum(v).fold<int>(0, (a, b) => a + b);
        expect(total.abs(), maxMomentumNotches);
      }
      expect(
        remoteScrollMomentum(9000, maxNotches: 5).fold<int>(0, (a, b) => a + b),
        5,
      );
    });

    test('ends within a couple of seconds', () {
      final schedule = remoteScrollMomentum(6000);
      expect(schedule.length * momentumTick.inMilliseconds, lessThan(2000));
    });
  });
}
