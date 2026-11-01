import 'day_state.dart';
import 'habit_day.dart';

const Set<int> everyDay = {1, 2, 3, 4, 5, 6, 7};

class Habit {
  const Habit({
    required this.id,
    required this.name,
    required this.polarity,
    required this.schedule,
    required this.createdDay,
    this.archivedAt,
  });

  final String id;
  final String name;
  final HabitPolarity polarity;

  /// Weekdays on which the habit applies, [DateTime.monday]..[DateTime.sunday].
  final Set<int> schedule;

  /// Habit day on which the habit was created; the review prompt ignores
  /// earlier days.
  final HabitDay createdDay;
  final DateTime? archivedAt;

  bool get isArchived => archivedAt != null;
  bool get isNegative => polarity == HabitPolarity.negative;

  bool isScheduledOn(HabitDay day) => schedule.contains(day.weekday);

  /// State shown for [day] given the resolved logged [state], if any.
  ///
  /// Nothing logged is `skipped` on unscheduled days and `unknown` otherwise;
  /// `unknown` is never treated as `notDone`.
  DayState effectiveState(HabitDay day, DayState? state) {
    if (state != null && state != DayState.unknown) return state;
    return isScheduledOn(day) ? DayState.unknown : DayState.skipped;
  }
}

/// Resolved state of one habit on one day, with the event that produced it.
class DayStateEntry {
  const DayStateEntry({
    required this.habitId,
    required this.habitDay,
    required this.state,
    required this.source,
    required this.loggedAt,
    required this.eventId,
  });

  final String habitId;
  final HabitDay habitDay;
  final DayState state;
  final EventSource source;
  final DateTime loggedAt;
  final String eventId;
}
