import 'package:cohabit/analysis/analysis_input.dart';
import 'package:cohabit/analysis/insight_text.dart';
import 'package:cohabit/domain/day_state.dart';
import 'package:cohabit/domain/habit.dart';
import 'package:cohabit/domain/habit_day.dart';
import 'package:cohabit_analysis/cohabit_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

final _today = HabitDay(2026, 11, 1); // a Sunday

Habit _habit(
  String id, {
  HabitPolarity polarity = HabitPolarity.positive,
  Set<int> schedule = everyDay,
  HabitDay? created,
  List<ScheduleChange>? history,
}) => Habit(
  id: id,
  name: id,
  polarity: polarity,
  schedule: schedule,
  createdDay: created ?? _today.addDays(-6),
  scheduleHistory: history,
);

List<int> _series(AnalysisInput input, String id) =>
    input.series.singleWhere((s) => s.id == id).values;

void main() {
  group('buildAnalysisInput', () {
    test('needs at least two habits', () {
      expect(
        buildAnalysisInput(habits: [_habit('a')], logged: {}, today: _today),
        isNull,
      );
    });

    test('unlogged days are missing, never notDone', () {
      final input = buildAnalysisInput(
        habits: [_habit('a'), _habit('b')],
        logged: {
          'a': {
            _today.addDays(-6): DayState.done,
            _today.addDays(-5): DayState.notDone,
            _today.addDays(-3): DayState.skipped,
            _today.addDays(-2): DayState.unknown,
          },
        },
        today: _today,
      )!;
      expect(_series(input, 'a'), [1, 0, -1, -1, -1, -1, -1]);
      expect(_series(input, 'b'), List.filled(7, -1));
      expect(input.series.length, 2);
    });

    test('unscheduled days are left out, but a log on one still counts', () {
      // Mon, Wed and Fri only. The window is Mon 26 Oct to Sun 1 Nov.
      final input = buildAnalysisInput(
        habits: [
          _habit('a', schedule: {1, 3, 5}),
          _habit('b'),
        ],
        logged: {
          'a': {
            _today.addDays(-6): DayState.done, // Monday
            _today.addDays(-4): DayState.notDone, // Wednesday
            _today.addDays(-5): DayState.done, // Tuesday: unscheduled, logged
          },
        },
        today: _today,
      )!;
      expect(_series(input, 'a'), [1, 1, 0, -1, -1, -1, -1]);
    });

    test('history of schedules never turns an unlogged day into notDone', () {
      // Every day until Wednesday 28 Oct, then Mondays only.
      final change = ScheduleChange(
        from: HabitDay(2026, 10, 28),
        schedule: const {1},
      );
      final habit = _habit(
        'a',
        schedule: const {1},
        history: [
          const ScheduleChange(from: null, schedule: everyDay),
          change,
        ],
      );
      final input = buildAnalysisInput(
        habits: [habit, _habit('b')],
        logged: {
          'a': {
            // Tuesday was scheduled, Thursday no longer is; both were logged.
            HabitDay(2026, 10, 27): DayState.notDone,
            HabitDay(2026, 10, 29): DayState.done,
          },
        },
        today: _today,
      )!;
      // A logged state wins on any day. Every other day is `unknown` (it was
      // scheduled) or `skipped` (it was not), and neither is used.
      expect(_series(input, 'a'), [-1, 0, -1, 1, -1, -1, -1]);
    });

    test('a negative habit: a slip is 1, a confirmed clean day is 0', () {
      final input = buildAnalysisInput(
        habits: [
          _habit('a', polarity: HabitPolarity.negative),
          _habit('b'),
        ],
        logged: {
          'a': {
            _today.addDays(-2): DayState.done, // slipped
            _today.addDays(-1): DayState.notDone, // confirmed clean
          },
        },
        today: _today,
      )!;
      final a = input.series.first;
      expect(a.negative, isTrue);
      expect(a.values, [-1, -1, -1, -1, 1, 0, -1]);
    });

    test('the window starts at the earliest creation or logged day', () {
      final input = buildAnalysisInput(
        habits: [
          _habit('a', created: _today.addDays(-3)),
          _habit('b', created: _today.addDays(-3)),
        ],
        logged: {
          'b': {_today.addDays(-10): DayState.done}, // backfilled
        },
        today: _today,
      )!;
      expect(input.series.first.values.length, 11);
      expect(_series(input, 'b').first, 1);
      expect(input.startEpochDay, epochDayOf(_today.addDays(-10)));
    });

    test('equal data gives equal inputs, so unchanged logs do not re-run', () {
      AnalysisInput? build() => buildAnalysisInput(
        habits: [_habit('a'), _habit('b')],
        logged: {
          'a': {_today: DayState.done},
        },
        today: _today,
      );
      expect(build(), build());
      expect(build().hashCode, build().hashCode);
    });
  });

  group('epochDayOf', () {
    test('counts days since 1970-01-01', () {
      expect(epochDayOf(HabitDay(1970, 1, 1)), 0);
      expect(epochDayOf(HabitDay(2026, 10, 5)), 20731);
    });
  });

  group('wording', () {
    final run = _habit('Run');
    final scroll = _habit('Doomscrolling', polarity: HabitPolarity.negative);
    PairResult pair(double phi, int lag) => PairResult(
      fromId: 'a',
      toId: 'b',
      lag: lag,
      status: PairStatus.tested,
      n: 84,
      phi: phi,
      ratio: 2.34,
      ratioLow: 1.61,
      ratioHigh: 3.2,
    );

    test('matches the design system example', () {
      final t = describeInsight(pair(0.41, 1), run, _habit('Gym'));
      expect(t.sentence, 'Run tends to go with Gym the next day.');
      expect(
        t.stats.join('  '),
        'Run -> Gym  +1d  2.3x  n=84  CI 1.6-3.2  phi +0.41',
      );
    });

    test('same day uses "&" and no delay', () {
      final t = describeInsight(pair(0.41, 0), run, _habit('Gym'));
      expect(t.sentence, endsWith('on the same day.'));
      expect(t.stats.first, 'Run & Gym');
    });

    test('longer lags count days', () {
      expect(
        describeInsight(pair(0.4, 3), run, _habit('Gym')).sentence,
        'Run tends to go with Gym 3 days later.',
      );
    });

    test('a negative habit speaks of slipping', () {
      expect(
        describeInsight(pair(-0.3, 0), scroll, run).sentence,
        'Slipping on Doomscrolling tends to go with less Run on the same day.',
      );
      expect(
        describeInsight(pair(0.3, 0), run, scroll).sentence,
        'Run tends to go with slipping on Doomscrolling on the same day.',
      );
    });

    test('always "tends to go with", never a cause', () {
      for (final phi in [-0.5, 0.5]) {
        for (final lag in [0, 1, 2]) {
          final s = describeInsight(pair(phi, lag), run, scroll).sentence;
          expect(s, contains('tends to go with'));
          expect(s.toLowerCase(), isNot(contains('caus')));
        }
      }
    });

    test('numbers are formatted by size', () {
      expect(formatRatio(23.4), '23');
      expect(formatRatio(2.34), '2.3');
      expect(formatRatio(0.5), '0.5');
      expect(formatRatio(0.05), '0.05');
      expect(formatPhi(-0.314), '−0.31');
      expect(formatPhi(0.4), '+0.40');
    });

    test('a missing ratio leaves it out instead of inventing one', () {
      final t = describeInsight(
        const PairResult(
          fromId: 'a',
          toId: 'b',
          lag: 0,
          status: PairStatus.tested,
          n: 50,
          phi: 0.3,
        ),
        run,
        _habit('Gym'),
      );
      expect(t.stats, ['Run & Gym', 'n=50', 'phi +0.30']);
    });
  });
}
