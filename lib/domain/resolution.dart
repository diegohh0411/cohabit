import 'day_state.dart';
import 'event.dart';
import 'habit.dart';
import 'habit_day.dart';

/// Total order over events: HLC, then `deviceId`, then event id so that the
/// order is deterministic even for events that tie on both.
int compareEvents(Event a, Event b) {
  final byHlc = a.hlc.compareTo(b.hlc);
  if (byHlc != 0) return byHlc;
  final byDevice = a.deviceId.compareTo(b.deviceId);
  if (byDevice != 0) return byDevice;
  return a.id.compareTo(b.id);
}

/// Whether day-state event [a] beats [b]: a manual event beats an automatic
/// one regardless of HLC, otherwise the later event wins.
bool dayStateWins(Event a, Event b) {
  final aManual = !a.source.isAutomatic;
  final bManual = !b.source.isAutomatic;
  if (aManual != bManual) return aManual;
  return compareEvents(a, b) > 0;
}

/// The winning `DayStateSet` among [events] (all for the same habit and day),
/// independent of the order they are given in.
Event? resolveDayState(Iterable<Event> events) {
  Event? winner;
  for (final e in events) {
    if (e.type != EventTypes.dayStateSet) continue;
    if (winner == null || dayStateWins(e, winner)) winner = e;
  }
  return winner;
}

DayStateEntry dayStateEntryFor(Event winner) => DayStateEntry(
  habitId: winner.habitId!,
  habitDay: winner.habitDay!,
  state: winner.dayState!,
  source: winner.source,
  loggedAt: DateTime.parse(winner.payload['loggedAt']! as String),
  eventId: winner.id,
);

/// Folds the habit events of a single habit into its current state.
///
/// Fields resolve independently, latest event first by [compareEvents]:
/// `HabitCreated` provides the baseline, `HabitEdited` events overlay the
/// fields they carry, and the latest `HabitArchived` sets `archivedAt`.
/// Returns null if there is no `HabitCreated`.
Habit? foldHabit(Iterable<Event> events) {
  final sorted =
      events.where((e) => EventTypes.habitTypes.contains(e.type)).toList()
        ..sort(compareEvents);

  Event? created;
  for (final e in sorted) {
    if (e.type == EventTypes.habitCreated) created = e;
  }
  if (created == null) return null;

  var name = created.payload['name']! as String;
  var schedule = _schedule(created.payload['schedule']);
  final history = [ScheduleChange(from: null, schedule: schedule)];
  DateTime? archivedAt;

  for (final e in sorted) {
    switch (e.type) {
      case EventTypes.habitEdited:
        if (e.payload['name'] != null) name = e.payload['name']! as String;
        if (e.payload['schedule'] != null) {
          schedule = _schedule(e.payload['schedule']);
          history.add(
            ScheduleChange(from: scheduleEffectiveFrom(e), schedule: schedule),
          );
        }
      case EventTypes.habitArchived:
        archivedAt = DateTime.parse(e.payload['archivedAt']! as String);
    }
  }

  return Habit(
    id: created.habitId!,
    name: name,
    polarity: HabitPolarity.parse(created.payload['polarity']! as String),
    schedule: schedule,
    createdDay: HabitDay.parse(created.payload['createdDay']! as String),
    archivedAt: archivedAt,
    scheduleHistory: history,
  );
}

/// The habit day from which the schedule set by [edit] applies.
///
/// New edits record `effectiveFrom`. Edits written before schedule history
/// existed do not, so they fall back to the UTC calendar date of their HLC:
/// close to the real day, and identical on every device.
HabitDay scheduleEffectiveFrom(Event edit) {
  final raw = edit.payload['effectiveFrom'] as String?;
  if (raw != null) return HabitDay.parse(raw);
  return HabitDay.fromDate(
    DateTime.fromMillisecondsSinceEpoch(edit.hlc.wallMillis, isUtc: true),
  );
}

Set<int> _schedule(Object? raw) => (raw! as List).map((d) => d as int).toSet();
