import '../domain/day_state.dart';
import '../domain/habit.dart';
import '../domain/habit_day.dart';

const weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// e.g. `Sun 1 Nov 2026`.
String formatDay(HabitDay day) =>
    '${weekdayNames[day.weekday - 1].substring(0, 3)} ${day.day} '
    '${_months[day.month - 1]} ${day.year}';

/// The action buttons for a habit, in display order.
List<({DayState state, String label})> actionsFor(Habit habit) =>
    habit.isNegative
    ? const [
        (state: DayState.done, label: 'Slipped'),
        (state: DayState.notDone, label: 'Clean day'),
        (state: DayState.skipped, label: 'Skip'),
      ]
    : const [
        (state: DayState.done, label: 'Done'),
        (state: DayState.notDone, label: 'Not done'),
        (state: DayState.skipped, label: 'Skip'),
      ];

/// Human label for a logged state of [habit].
String stateLabel(Habit habit, DayState state) => switch (state) {
  DayState.unknown => 'Not logged',
  DayState.skipped => 'Skipped',
  DayState.done => habit.isNegative ? 'Slipped' : 'Done',
  DayState.notDone => habit.isNegative ? 'Clean day' : 'Not done',
};

String scheduleLabel(Set<int> schedule) {
  if (schedule.length == 7) return 'Every day';
  final days = schedule.toList()..sort();
  return days.map((d) => weekdayNames[d - 1].substring(0, 3)).join(' ');
}
