import 'package:cohabit_analysis/cohabit_analysis.dart';

import '../domain/day_state.dart';
import '../domain/habit.dart';
import '../domain/habit_day.dart';

final _epoch = HabitDay(1970, 1, 1);

/// Days since 1970-01-01 of [day].
int epochDayOf(HabitDay day) => day.differenceInDays(_epoch);

/// Turns the app's habits and logs into the plain series the analysis reads.
///
/// Each cell comes from [Habit.effectiveState], so unlogged days follow the
/// schedule in force on that day: a scheduled day nothing was logged on is
/// `unknown` and an unscheduled one is `skipped`. Both, like an explicit
/// `skipped`, become [Observation.missing]; `unknown` is never `notDone`.
/// Done and slipped are `1`, notDone and confirmed clean are `0`.
///
/// The window runs from the earliest creation or logged day to [today].
/// Returns null when there is nothing to compare yet.
AnalysisInput? buildAnalysisInput({
  required List<Habit> habits,
  required Map<String, Map<HabitDay, DayState>> logged,
  required HabitDay today,
  AnalysisConfig config = const AnalysisConfig(),
}) {
  if (habits.length < 2) return null;
  var start = today;
  for (final h in habits) {
    if (h.createdDay < start) start = h.createdDay;
    for (final day in (logged[h.id] ?? const {}).keys) {
      if (day < start) start = day;
    }
  }
  final days = today.differenceInDays(start) + 1;
  return AnalysisInput(
    startEpochDay: epochDayOf(start),
    config: config,
    series: [
      for (final h in habits)
        HabitSeries(
          id: h.id,
          negative: h.isNegative,
          values: [
            for (var i = 0; i < days; i++)
              _observation(
                h.effectiveState(
                  start.addDays(i),
                  logged[h.id]?[start.addDays(i)],
                ),
              ),
          ],
        ),
    ],
  );
}

int _observation(DayState state) => switch (state) {
  DayState.done => Observation.done,
  DayState.notDone => Observation.notDone,
  DayState.skipped || DayState.unknown => Observation.missing,
};
