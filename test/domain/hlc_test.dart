import 'package:cohabit/domain/hlc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Hlc', () {
    test('encodes fixed-width and round-trips', () {
      const hlc = Hlc(0x18c3a2b1f00, 0x2a);
      expect(hlc.encoded, '018c3a2b1f00-002a');
      expect(Hlc.parse(hlc.encoded), hlc);
    });

    test('string order equals HLC order', () {
      final stamps = [
        const Hlc(1000, 0),
        const Hlc(1000, 1),
        const Hlc(1000, 0xFFFF),
        const Hlc(1001, 0),
        const Hlc(0xFFFFFFFFFFF, 0),
      ];
      final shuffled = [...stamps.reversed];
      shuffled.sort((a, b) => a.encoded.compareTo(b.encoded));
      expect(shuffled, stamps);
    });

    test('orders by wall time then counter', () {
      expect(const Hlc(5, 9) < const Hlc(6, 0), isTrue);
      expect(const Hlc(5, 1) < const Hlc(5, 2), isTrue);
      expect(const Hlc(5, 2) > const Hlc(5, 1), isTrue);
    });

    test('rejects malformed input', () {
      expect(() => Hlc.parse('nope'), throwsFormatException);
      expect(() => Hlc.parse('zz-01'), throwsFormatException);
    });
  });

  group('HlcClock', () {
    test('send advances with wall time and resets the counter', () {
      var now = 1000;
      final clock = HlcClock(nowMillis: () => now);
      expect(clock.send(), const Hlc(1000, 0));
      now = 1005;
      expect(clock.send(), const Hlc(1005, 0));
    });

    test('send increments the counter when time does not advance', () {
      final clock = HlcClock(nowMillis: () => 1000);
      expect(clock.send(), const Hlc(1000, 0));
      expect(clock.send(), const Hlc(1000, 1));
      expect(clock.send(), const Hlc(1000, 2));
    });

    test('send stays monotonic when the wall clock goes backwards', () {
      var now = 2000;
      final clock = HlcClock(nowMillis: () => now);
      final a = clock.send();
      now = 1000;
      final b = clock.send();
      expect(b > a, isTrue);
      expect(b, const Hlc(2000, 1));
    });

    test('counter overflow borrows a millisecond', () {
      final clock = HlcClock(
        nowMillis: () => 1000,
        initial: const Hlc(1000, Hlc.maxCounter),
      );
      expect(clock.send(), const Hlc(1001, 0));
    });

    test('receive jumps ahead of a later remote timestamp', () {
      final clock = HlcClock(nowMillis: () => 1000);
      clock.send();
      final merged = clock.receive(const Hlc(1200, 7));
      expect(merged, const Hlc(1200, 8));
      expect(clock.send() > merged, isTrue);
    });

    test('receive takes the max counter when walls tie', () {
      final clock = HlcClock(
        nowMillis: () => 1000,
        initial: const Hlc(1000, 3),
      );
      expect(clock.receive(const Hlc(1000, 9)), const Hlc(1000, 10));
    });

    test('receive from the past still moves the clock forward', () {
      final clock = HlcClock(
        nowMillis: () => 1000,
        initial: const Hlc(1000, 3),
      );
      expect(clock.receive(const Hlc(500, 99)), const Hlc(1000, 4));
    });

    test('receive resets the counter when local time is ahead of both', () {
      final clock = HlcClock(
        nowMillis: () => 3000,
        initial: const Hlc(1000, 3),
      );
      expect(clock.receive(const Hlc(2000, 5)), const Hlc(3000, 0));
    });

    test('receive rejects timestamps beyond the drift limit', () {
      final clock = HlcClock(
        nowMillis: () => 1000,
        maxDrift: const Duration(seconds: 1),
      );
      expect(
        () => clock.receive(const Hlc(1000 + 1001, 0)),
        throwsA(isA<ClockDriftException>()),
      );
      expect(clock.latest, Hlc.zero);
    });
  });
}
