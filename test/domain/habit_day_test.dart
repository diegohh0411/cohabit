import 'package:cohabit/domain/habit_day.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const utc = Duration.zero;

  group('habitDayFor', () {
    test('default boundary is 03:00', () {
      expect(defaultDayBoundaryMinutes, 180);
    });

    test('02:59 belongs to the previous day, 03:00 to the new one', () {
      expect(
        habitDayFor(DateTime.utc(2026, 11, 2, 2, 59), utcOffset: utc),
        HabitDay(2026, 11, 1),
      );
      expect(
        habitDayFor(DateTime.utc(2026, 11, 2, 3, 0), utcOffset: utc),
        HabitDay(2026, 11, 2),
      );
    });

    test('midnight and late evening', () {
      expect(
        habitDayFor(DateTime.utc(2026, 11, 2, 0, 0), utcOffset: utc),
        HabitDay(2026, 11, 1),
      );
      expect(
        habitDayFor(DateTime.utc(2026, 11, 1, 23, 59), utcOffset: utc),
        HabitDay(2026, 11, 1),
      );
    });

    test('crosses month and year ends', () {
      expect(
        habitDayFor(DateTime.utc(2027, 1, 1, 1, 0), utcOffset: utc),
        HabitDay(2026, 12, 31),
      );
      expect(
        habitDayFor(DateTime.utc(2026, 3, 1, 2, 0), utcOffset: utc),
        HabitDay(2026, 2, 28),
      );
      expect(
        habitDayFor(DateTime.utc(2028, 3, 1, 2, 0), utcOffset: utc),
        HabitDay(2028, 2, 29),
      );
    });

    test('boundary is configurable', () {
      final instant = DateTime.utc(2026, 11, 2, 4, 30);
      expect(
        habitDayFor(instant, boundaryMinutes: 5 * 60, utcOffset: utc),
        HabitDay(2026, 11, 1),
      );
      expect(
        habitDayFor(instant, boundaryMinutes: 0, utcOffset: utc),
        HabitDay(2026, 11, 2),
      );
      expect(
        habitDayFor(
          DateTime.utc(2026, 11, 2, 4, 29),
          boundaryMinutes: 4 * 60 + 30,
          utcOffset: utc,
        ),
        HabitDay(2026, 11, 1),
      );
    });

    test('uses the wall clock at the given offset', () {
      // 06:00 UTC is 22:00 the previous evening in UTC-8.
      expect(
        habitDayFor(
          DateTime.utc(2026, 11, 2, 6, 0),
          utcOffset: const Duration(hours: -8),
        ),
        HabitDay(2026, 11, 1),
      );
      // 20:00 UTC is 05:00 next day in UTC+9.
      expect(
        habitDayFor(
          DateTime.utc(2026, 11, 1, 20, 0),
          utcOffset: const Duration(hours: 9),
        ),
        HabitDay(2026, 11, 2),
      );
    });

    test('a DST shift cannot skip or repeat a habit day', () {
      // US fall-back: wall clock 01:30 happens twice; both are 1 Nov habit day.
      expect(
        habitDayFor(
          DateTime.utc(2026, 11, 1, 5, 30),
          utcOffset: const Duration(hours: -4),
        ),
        HabitDay(2026, 10, 31),
      );
      expect(
        habitDayFor(
          DateTime.utc(2026, 11, 1, 6, 30),
          utcOffset: const Duration(hours: -5),
        ),
        HabitDay(2026, 10, 31),
      );
      expect(
        habitDayFor(
          DateTime.utc(2026, 11, 1, 8, 0),
          utcOffset: const Duration(hours: -5),
        ),
        HabitDay(2026, 11, 1),
      );
    });

    test('defaults to the instant\'s local offset', () {
      final local = DateTime(2026, 11, 2, 2, 59);
      expect(habitDayFor(local), HabitDay(2026, 11, 1));
      expect(habitDayFor(local.toUtc()), HabitDay(2026, 11, 1));
      expect(habitDayFor(DateTime(2026, 11, 2, 3, 0)), HabitDay(2026, 11, 2));
    });

    test('rejects out-of-range boundaries', () {
      expect(
        () => habitDayFor(DateTime.utc(2026), boundaryMinutes: -1),
        throwsRangeError,
      );
      expect(
        () => habitDayFor(DateTime.utc(2026), boundaryMinutes: 13 * 60),
        throwsRangeError,
      );
    });
  });

  group('HabitDay', () {
    test('formats and parses', () {
      final day = HabitDay(2026, 1, 5);
      expect(day.toString(), '2026-01-05');
      expect(HabitDay.parse('2026-01-05'), day);
      expect(() => HabitDay.parse('2026-02-30'), throwsFormatException);
      expect(() => HabitDay.parse('2026-1-5'), throwsFormatException);
    });

    test('addDays and weekday', () {
      final day = HabitDay(2026, 11, 1); // a Sunday
      expect(day.weekday, DateTime.sunday);
      expect(day.addDays(1), HabitDay(2026, 11, 2));
      expect(day.addDays(-1), HabitDay(2026, 10, 31));
      expect(day.addDays(60), HabitDay(2026, 12, 31));
    });

    test('compares and hashes by date', () {
      expect(HabitDay(2026, 1, 1) < HabitDay(2026, 1, 2), isTrue);
      expect({HabitDay(2026, 1, 1), HabitDay(2026, 1, 1)}.length, 1);
    });
  });
}
