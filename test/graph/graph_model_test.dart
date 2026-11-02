import 'package:cohabit/domain/day_state.dart';
import 'package:cohabit/domain/habit.dart';
import 'package:cohabit/domain/habit_day.dart';
import 'package:cohabit/graph/graph_model.dart';
import 'package:flutter_test/flutter_test.dart';

Habit habit({
  String id = 'h',
  String name = 'Run',
  HabitPolarity polarity = HabitPolarity.positive,
  Set<int> schedule = const {1, 2, 3, 4, 5, 6, 7},
  HabitDay? createdDay,
  List<ScheduleChange>? history,
}) => Habit(
  id: id,
  name: name,
  polarity: polarity,
  schedule: schedule,
  createdDay: createdDay ?? HabitDay(2026, 10, 1),
  scheduleHistory: history,
);

// Sunday 1 Nov 2026.
final today = HabitDay(2026, 11, 1);
final saturday = HabitDay(2026, 10, 31);

void main() {
  group('GraphRange', () {
    test('weeks run Monday to Sunday and end in the week of today', () {
      final range = GraphRange.covering(
        today: today,
        earliest: HabitDay(2026, 10, 14),
      );
      expect(range.first, HabitDay(2026, 10, 12)); // Monday
      expect(range.first.weekday, DateTime.monday);
      expect(range.weeks, 3);
      expect(range.last, today); // Sunday
      expect(range.length, 21);
    });

    test('minWeeks pads back in time', () {
      final range = GraphRange.covering(
        today: today,
        earliest: today,
        minWeeks: 53,
      );
      expect(range.weeks, 53);
      expect(range.first.weekday, DateTime.monday);
      expect(range.last, today);
    });

    test('indexing round-trips and rows are weekdays', () {
      final range = GraphRange.covering(
        today: today,
        earliest: HabitDay(2026, 9, 1),
      );
      for (var i = 0; i < range.length; i++) {
        expect(range.indexOf(range.dayAt(i)), i);
        expect(range.rowOf(i), range.dayAt(i).weekday - 1);
      }
      expect(range.contains(today), isTrue);
      expect(range.contains(today.addDays(1)), isFalse);
      expect(range.contains(range.first.addDays(-1)), isFalse);
    });
  });

  group('habitCell', () {
    final run = habit();
    final smoke = habit(name: 'Smoke', polarity: HabitPolarity.negative);

    CellStyle style(Habit h, DayState? s, [HabitDay? day]) =>
        habitCell(h, day ?? saturday, s, today).style;

    test('positive: done is blue, not done is off', () {
      expect(style(run, DayState.done), CellStyle.done);
      expect(style(run, DayState.notDone), CellStyle.notDone);
    });

    test('negative: slipped is orange, confirmed clean is blue', () {
      expect(style(smoke, DayState.done), CellStyle.slipped);
      expect(style(smoke, DayState.notDone), CellStyle.done);
      expect(habitCell(smoke, saturday, DayState.done, today).label, 'Slipped');
      expect(
        habitCell(smoke, saturday, DayState.notDone, today).label,
        'Clean day',
      );
    });

    test('logged skip is hatched', () {
      expect(style(run, DayState.skipped), CellStyle.skipped);
      expect(
        habitCell(run, saturday, DayState.skipped, today).label,
        'Skipped',
      );
    });

    test('unlogged scheduled day is hollow unknown, never off', () {
      expect(style(run, null), CellStyle.unknown);
      expect(style(run, DayState.unknown), CellStyle.unknown);
      expect(habitCell(run, saturday, null, today).label, 'Not logged');
    });

    test('unlogged unscheduled day is hatched', () {
      final weekdays = habit(schedule: {1, 2, 3, 4, 5});
      expect(style(weekdays, null, saturday), CellStyle.skipped);
      expect(style(weekdays, null, HabitDay(2026, 10, 30)), CellStyle.unknown);
    });

    test('future days and days before the habit existed are blank', () {
      expect(style(run, null, today.addDays(1)), CellStyle.none);
      expect(style(run, DayState.done, today.addDays(1)), CellStyle.none);
      expect(style(run, null, HabitDay(2026, 9, 30)), CellStyle.none);
      // A backfilled log before creation still shows.
      expect(style(run, DayState.done, HabitDay(2026, 9, 30)), CellStyle.done);
    });

    test('unlogged past days follow the schedule in force that day', () {
      // Daily until Wed 28 Oct, then weekdays only: the weekend before the
      // change must stay unknown, the one after is skipped.
      final changed = habit(
        schedule: {1, 2, 3, 4, 5},
        history: [
          ScheduleChange(from: null, schedule: const {1, 2, 3, 4, 5, 6, 7}),
          ScheduleChange(
            from: HabitDay(2026, 10, 28),
            schedule: const {1, 2, 3, 4, 5},
          ),
        ],
      );
      expect(style(changed, null, HabitDay(2026, 10, 24)), CellStyle.unknown);
      expect(style(changed, null, HabitDay(2026, 10, 31)), CellStyle.skipped);
    });
  });

  group('habitSeries', () {
    test('cells, descriptions and a text summary', () {
      final run = habit();
      final range = GraphRange(first: HabitDay(2026, 10, 26), weeks: 1);
      final series = habitSeries(
        run,
        {
          HabitDay(2026, 10, 26): DayState.done,
          HabitDay(2026, 10, 27): DayState.notDone,
          HabitDay(2026, 10, 28): DayState.skipped,
        },
        range,
        today,
      );
      expect(series.styles, [
        CellStyle.done,
        CellStyle.notDone,
        CellStyle.skipped,
        CellStyle.unknown,
        CellStyle.unknown,
        CellStyle.unknown,
        CellStyle.unknown,
      ]);
      expect(series.describe(HabitDay(2026, 10, 26)), 'Done');
      expect(series.describe(HabitDay(2026, 10, 29)), 'Not logged');
      expect(
        series.summary,
        'Run: 1 done, 1 not done, 1 skipped, 4 not logged',
      );
      expect(series.styleOf(HabitDay(2026, 10, 27)), CellStyle.notDone);
      expect(series.styleOf(HabitDay(2027, 1, 1)), CellStyle.none);
    });

    test('negative habit summary words', () {
      final smoke = habit(name: 'Smoke', polarity: HabitPolarity.negative);
      final range = GraphRange(first: HabitDay(2026, 10, 26), weeks: 1);
      final series = habitSeries(
        smoke,
        {
          HabitDay(2026, 10, 26): DayState.notDone,
          HabitDay(2026, 10, 27): DayState.done,
        },
        range,
        today,
      );
      expect(series.summary, startsWith('Smoke: 1 clean, 1 slipped'));
    });
  });

  group('overview', () {
    final run = habit(id: 'run');
    final smoke = habit(
      id: 'smoke',
      name: 'Smoke',
      polarity: HabitPolarity.negative,
    );
    final range = GraphRange(first: HabitDay(2026, 10, 26), weeks: 1);
    final mon = HabitDay(2026, 10, 26);

    GraphSeries build(List<Habit> habits, LoggedStates logged) =>
        overviewSeries(habits, logged, range, today);

    test('levels from the share of scheduled habits completed', () {
      expect(overviewLevel(0), 0);
      expect(overviewLevel(0.2), 1);
      expect(overviewLevel(0.5), 2);
      expect(overviewLevel(0.9), 3);
      expect(overviewLevel(1), 4);
    });

    test('negative habits count clean days, not slips', () {
      final s = build(
        [run, smoke],
        {
          'run': {mon: DayState.done},
          'smoke': {mon: DayState.notDone}, // confirmed clean
        },
      );
      expect(s.styleOf(mon), CellStyle.level4);
      expect(s.describe(mon), '2 of 2 habits completed (100%)');

      final slipped = build(
        [run, smoke],
        {
          'run': {mon: DayState.done},
          'smoke': {mon: DayState.done}, // slipped
        },
      );
      expect(slipped.styleOf(mon), CellStyle.level2);
      expect(slipped.describe(mon), '1 of 2 habits completed (50%)');
    });

    test('unlogged days count against; nothing done is level 0', () {
      final s = build([run, smoke], {});
      expect(s.styleOf(mon), CellStyle.level0);
      expect(s.describe(mon), '0 of 2 habits completed (0%)');
    });

    test('skipped habits leave the denominator', () {
      final s = build(
        [run, smoke],
        {
          'run': {mon: DayState.done},
          'smoke': {mon: DayState.skipped},
        },
      );
      expect(s.describe(mon), '1 of 1 habits completed (100%)');
    });

    test('only habits scheduled that day and already created count', () {
      final weekdays = habit(id: 'wk', schedule: {1, 2, 3, 4, 5});
      final later = habit(id: 'late', createdDay: HabitDay(2026, 10, 28));
      final s = build(
        [weekdays, later],
        {
          'wk': {HabitDay(2026, 10, 26): DayState.done},
        },
      );
      expect(
        s.describe(HabitDay(2026, 10, 26)),
        '1 of 1 habits completed (100%)',
      );
      // Sat 31: weekdays not scheduled, `late` exists and is unlogged.
      expect(s.describe(saturday), '0 of 1 habits completed (0%)');
    });

    test('schedule history decides what was scheduled on a past day', () {
      final changed = habit(
        id: 'c',
        schedule: {1},
        history: [
          ScheduleChange(from: null, schedule: const {1, 2, 3, 4, 5, 6, 7}),
          ScheduleChange(from: HabitDay(2026, 10, 30), schedule: const {1}),
        ],
      );
      final s = build([changed], {});
      expect(s.styleOf(HabitDay(2026, 10, 29)), CellStyle.level0);
      expect(s.styleOf(HabitDay(2026, 10, 31)), CellStyle.none);
      expect(s.describe(HabitDay(2026, 10, 31)), 'Nothing scheduled');
    });

    test('future days are blank and the summary is a sentence', () {
      final wide = GraphRange(first: HabitDay(2026, 10, 26), weeks: 2);
      final s = overviewSeries(
        [run],
        {
          'run': {mon: DayState.done},
        },
        wide,
        today,
      );
      expect(s.styleOf(today.addDays(1)), CellStyle.none);
      expect(s.describe(today.addDays(1)), 'Upcoming');
      expect(s.summary, startsWith('Overview: 7 days measured'));
      expect(build([], {}).summary, 'Overview: no days to measure');
    });
  });

  group('monthMarkers', () {
    test('one label where each month starts, none too close together', () {
      final range = GraphRange.covering(
        today: today,
        earliest: today,
        minWeeks: 20,
      );
      final markers = monthMarkers(range);
      expect(markers.first.column, 0);
      expect(markers.map((m) => m.label).toSet().length, markers.length);
      for (var i = 1; i < markers.length; i++) {
        expect(
          markers[i].column - markers[i - 1].column,
          greaterThanOrEqualTo(3),
        );
      }
      // Nov 1 falls in the week of Monday 26 Oct, so that column reads Oct.
      expect(markers.last.label, 'Oct');
    });
  });
}
