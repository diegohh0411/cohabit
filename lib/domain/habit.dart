import 'day_state.dart';
import 'habit_day.dart';

const Set<int> everyDay = {1, 2, 3, 4, 5, 6, 7};

/// A schedule that applies from [from] (inclusive) until a later change
/// supersedes it. A null [from] means "since the beginning of time"; the
/// creation schedule uses it so days before creation can still be backfilled.
class ScheduleChange {
  const ScheduleChange({required this.from, required this.schedule});

  final HabitDay? from;
  final Set<int> schedule;

  bool appliesOn(HabitDay day) => from == null || from! <= day;

  @override
  bool operator ==(Object other) =>
      other is ScheduleChange &&
      other.from == from &&
      other.schedule.length == schedule.length &&
      other.schedule.containsAll(schedule);

  @override
  int get hashCode => Object.hash(from, Object.hashAllUnordered(schedule));

  @override
  String toString() => 'ScheduleChange($from, $schedule)';
}

class Habit {
  Habit({
    required this.id,
    required this.name,
    required this.polarity,
    required this.schedule,
    required this.createdDay,
    this.archivedAt,
    List<ScheduleChange>? scheduleHistory,
  }) : scheduleHistory =
           scheduleHistory ?? [ScheduleChange(from: null, schedule: schedule)];

  final String id;
  final String name;
  final HabitPolarity polarity;

  /// The latest schedule, [DateTime.monday]..[DateTime.sunday]. Past days use
  /// [scheduleOn] instead, since a schedule only applies from the day it took
  /// effect.
  final Set<int> schedule;

  /// Every schedule the habit has had, in event order (the last entry is
  /// [schedule]). Which one applies on a day is decided by [scheduleOn].
  final List<ScheduleChange> scheduleHistory;

  /// Habit day on which the habit was created; the review prompt ignores
  /// earlier days.
  final HabitDay createdDay;
  final DateTime? archivedAt;

  bool get isArchived => archivedAt != null;
  bool get isNegative => polarity == HabitPolarity.negative;

  /// The schedule in force on [day]: the most recent change, in event order,
  /// that had taken effect by then.
  Set<int> scheduleOn(HabitDay day) {
    for (var i = scheduleHistory.length - 1; i >= 0; i--) {
      if (scheduleHistory[i].appliesOn(day)) return scheduleHistory[i].schedule;
    }
    return scheduleHistory.first.schedule;
  }

  bool isScheduledOn(HabitDay day) => scheduleOn(day).contains(day.weekday);

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
