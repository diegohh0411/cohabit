import 'package:cohabit/domain/day_state.dart';
import 'package:cohabit/domain/event.dart';
import 'package:cohabit/domain/habit_day.dart';
import 'package:cohabit/domain/hlc.dart';
import 'package:cohabit/domain/resolution.dart';
import 'package:flutter_test/flutter_test.dart';

Event dayEvent(
  String id, {
  required int wall,
  int counter = 0,
  String device = 'A',
  DayState state = DayState.done,
  EventSource source = EventSource.manual,
}) => Event(
  id: id,
  deviceId: device,
  hlc: Hlc(wall, counter),
  type: EventTypes.dayStateSet,
  payload: {
    'habitId': 'h1',
    'habitDay': '2026-11-01',
    'state': state.wireName,
    'loggedAt': '2026-11-01T10:00:00.000Z',
    'source': source.wireName,
  },
);

Event habitEvent(
  String type,
  String id, {
  required int wall,
  String device = 'A',
  Map<String, Object?> payload = const {},
}) => Event(
  id: id,
  deviceId: device,
  hlc: Hlc(wall, 0),
  type: type,
  payload: {'habitId': 'h1', ...payload},
);

Event created({int wall = 1, String name = 'Run'}) => habitEvent(
  EventTypes.habitCreated,
  'c$wall',
  wall: wall,
  payload: {
    'name': name,
    'polarity': 'positive',
    'schedule': [1, 3, 5],
    'createdDay': '2026-11-01',
  },
);

void main() {
  group('resolveDayState', () {
    test('latest HLC wins', () {
      final a = dayEvent('a', wall: 10, state: DayState.done);
      final b = dayEvent('b', wall: 20, state: DayState.notDone);
      expect(resolveDayState([a, b])!.id, 'b');
      expect(resolveDayState([b, a])!.id, 'b');
    });

    test('counter breaks a wall-time tie', () {
      final a = dayEvent('a', wall: 10, counter: 1);
      final b = dayEvent('b', wall: 10, counter: 2);
      expect(resolveDayState([a, b])!.id, 'b');
    });

    test('deviceId breaks an HLC tie, deterministically', () {
      final a = dayEvent('a', wall: 10, device: 'dev-a');
      final b = dayEvent('b', wall: 10, device: 'dev-b');
      expect(resolveDayState([a, b])!.id, 'b');
      expect(resolveDayState([b, a])!.id, 'b');
    });

    test('event id is the last-resort tie-breaker', () {
      final a = dayEvent('a', wall: 10);
      final b = dayEvent('b', wall: 10);
      expect(resolveDayState([a, b])!.id, 'b');
      expect(resolveDayState([b, a])!.id, 'b');
    });

    test('manual beats automatic regardless of HLC', () {
      final manual = dayEvent('m', wall: 10, state: DayState.notDone);
      for (final source in [EventSource.import, EventSource.healthConnect]) {
        final auto = dayEvent('x', wall: 99, source: source);
        expect(resolveDayState([manual, auto])!.id, 'm');
        expect(resolveDayState([auto, manual])!.id, 'm');
      }
    });

    test('a later manual event beats an earlier manual event', () {
      final m1 = dayEvent('m1', wall: 10);
      final m2 = dayEvent('m2', wall: 11, state: DayState.skipped);
      final auto = dayEvent('x', wall: 50, source: EventSource.healthConnect);
      expect(resolveDayState([m1, auto, m2])!.id, 'm2');
    });

    test('later automatic beats earlier automatic when no manual exists', () {
      final a1 = dayEvent('a1', wall: 10, source: EventSource.import);
      final a2 = dayEvent('a2', wall: 11, source: EventSource.healthConnect);
      expect(resolveDayState([a1, a2])!.id, 'a2');
    });

    test('result is independent of input order', () {
      final events = [
        dayEvent('a', wall: 10, device: 'x'),
        dayEvent('b', wall: 10, device: 'y'),
        dayEvent('c', wall: 12, source: EventSource.import),
        dayEvent('d', wall: 5),
      ];
      final expected = resolveDayState(events)!.id;
      for (var i = 0; i < events.length; i++) {
        final rotated = [...events.sublist(i), ...events.sublist(0, i)];
        expect(resolveDayState(rotated)!.id, expected);
        expect(resolveDayState(rotated.reversed)!.id, expected);
      }
      expect(expected, 'b');
    });

    test('empty input resolves to null', () {
      expect(resolveDayState([]), isNull);
    });

    test('entry carries the winning event\'s data', () {
      final entry = dayStateEntryFor(
        dayEvent('a', wall: 1, state: DayState.skipped),
      );
      expect(entry.habitDay, HabitDay(2026, 11, 1));
      expect(entry.state, DayState.skipped);
      expect(entry.source, EventSource.manual);
      expect(entry.eventId, 'a');
    });
  });

  group('foldHabit', () {
    test('null without a HabitCreated', () {
      expect(
        foldHabit([
          habitEvent(
            EventTypes.habitEdited,
            'e',
            wall: 2,
            payload: {'name': 'X'},
          ),
        ]),
        isNull,
      );
    });

    test('creation provides the baseline', () {
      final habit = foldHabit([created()])!;
      expect(habit.name, 'Run');
      expect(habit.schedule, {1, 3, 5});
      expect(habit.polarity, HabitPolarity.positive);
      expect(habit.createdDay, HabitDay(2026, 11, 1));
      expect(habit.isArchived, isFalse);
    });

    test('edits resolve per field, latest first', () {
      final habit = foldHabit([
        created(),
        habitEvent(
          EventTypes.habitEdited,
          'e2',
          wall: 4,
          payload: {'name': 'Jog'},
        ),
        habitEvent(
          EventTypes.habitEdited,
          'e1',
          wall: 3,
          device: 'B',
          payload: {
            'name': 'Old',
            'schedule': [2],
          },
        ),
      ])!;
      expect(habit.name, 'Jog');
      expect(habit.schedule, {2});
    });

    test('archive sets archivedAt', () {
      final habit = foldHabit([
        created(),
        habitEvent(
          EventTypes.habitArchived,
          'a',
          wall: 9,
          payload: {'archivedAt': '2026-11-05T00:00:00.000Z'},
        ),
      ])!;
      expect(habit.archivedAt, DateTime.utc(2026, 11, 5));
    });

    test('fold ignores input order', () {
      final events = [
        created(),
        habitEvent(
          EventTypes.habitEdited,
          'e1',
          wall: 3,
          payload: {'name': 'A'},
        ),
        habitEvent(
          EventTypes.habitEdited,
          'e2',
          wall: 4,
          payload: {'name': 'B'},
        ),
      ];
      expect(foldHabit(events.reversed)!.name, 'B');
      expect(foldHabit(events)!.name, 'B');
    });
  });

  group('Habit.effectiveState', () {
    final habit = foldHabit([created()])!; // Mon, Wed, Fri
    final monday = HabitDay(2026, 11, 2);
    final tuesday = HabitDay(2026, 11, 3);

    test('unlogged scheduled day is unknown, never notDone', () {
      expect(habit.effectiveState(monday, null), DayState.unknown);
      expect(habit.effectiveState(monday, DayState.unknown), DayState.unknown);
    });

    test('unlogged unscheduled day is skipped', () {
      expect(habit.effectiveState(tuesday, null), DayState.skipped);
    });

    test('an explicit log wins on any day', () {
      expect(habit.effectiveState(tuesday, DayState.done), DayState.done);
      expect(habit.effectiveState(monday, DayState.skipped), DayState.skipped);
    });
  });
  group('schedule history', () {
    // created(): Mon, Wed, Fri since 2026-11-01 (a Sunday).
    Event scheduleEdit(
      String id, {
      required int wall,
      required List<int> schedule,
      String? effectiveFrom,
      String device = 'A',
    }) => habitEvent(
      EventTypes.habitEdited,
      id,
      wall: wall,
      device: device,
      payload: {'schedule': schedule, 'effectiveFrom': ?effectiveFrom},
    );

    final mon2 = HabitDay(2026, 11, 2);
    final tue3 = HabitDay(2026, 11, 3);
    final wed4 = HabitDay(2026, 11, 4);
    final tue10 = HabitDay(2026, 11, 10);

    test('an edit applies only from its effective day', () {
      final habit = foldHabit([
        created(),
        scheduleEdit(
          's1',
          wall: 5,
          schedule: [2, 4],
          effectiveFrom: '2026-11-05',
        ),
      ])!;
      expect(habit.schedule, {2, 4}); // latest
      // Before the edit took effect, the old Mon/Wed/Fri schedule holds.
      expect(habit.isScheduledOn(mon2), isTrue);
      expect(habit.isScheduledOn(tue3), isFalse);
      expect(habit.isScheduledOn(wed4), isTrue); // Wed: still the old schedule
      expect(
        habit.isScheduledOn(HabitDay(2026, 11, 5)),
        isTrue,
      ); // Thu: the edit day
      // From the edit day on, Tue/Thu.
      expect(habit.isScheduledOn(HabitDay(2026, 11, 6)), isFalse); // Fri
      expect(habit.isScheduledOn(tue10), isTrue);
    });

    test('unlogged past days follow the schedule of their day', () {
      final habit = foldHabit([
        created(),
        scheduleEdit('s1', wall: 5, schedule: [2], effectiveFrom: '2026-11-04'),
      ])!;
      expect(habit.effectiveState(mon2, null), DayState.unknown);
      expect(habit.effectiveState(tue3, null), DayState.skipped);
      expect(habit.effectiveState(tue10, null), DayState.unknown);
      expect(
        habit.effectiveState(HabitDay(2026, 11, 9), null),
        DayState.skipped,
      );
    });

    test('days before creation use the creation schedule', () {
      final habit = foldHabit([
        created(),
        scheduleEdit('s1', wall: 5, schedule: [2], effectiveFrom: '2026-11-04'),
      ])!;
      expect(habit.isScheduledOn(HabitDay(2026, 10, 30)), isTrue); // Fri
      expect(habit.isScheduledOn(HabitDay(2026, 10, 27)), isFalse); // Tue
    });

    test('later edit wins where several apply; result ignores input order', () {
      final events = [
        created(),
        scheduleEdit('a', wall: 5, schedule: [2], effectiveFrom: '2026-11-10'),
        scheduleEdit(
          'b',
          wall: 6,
          schedule: [4],
          effectiveFrom: '2026-11-03',
          device: 'B',
        ),
      ];
      final forward = foldHabit(events)!;
      final backward = foldHabit(events.reversed)!;
      for (final h in [forward, backward]) {
        expect(h.schedule, {4});
        expect(h.scheduleOn(tue3), {4}); // only b has taken effect
        expect(h.scheduleOn(tue10), {4}); // both apply; b is later
        expect(h.scheduleOn(mon2), {1, 3, 5}); // neither yet
      }
      expect(forward.scheduleHistory, backward.scheduleHistory);
    });

    test('edits that predate effectiveFrom use their HLC date in UTC', () {
      // 2026-11-04T12:00:00Z
      final wall = DateTime.utc(2026, 11, 4, 12).millisecondsSinceEpoch;
      final habit = foldHabit([
        created(),
        scheduleEdit('legacy', wall: wall, schedule: [2]),
      ])!;
      expect(habit.scheduleOn(tue3), {1, 3, 5});
      expect(habit.scheduleOn(wed4), {2});
    });

    test('name-only edits leave the schedule history alone', () {
      final habit = foldHabit([
        created(),
        habitEvent(
          EventTypes.habitEdited,
          'n',
          wall: 4,
          payload: {'name': 'Jog'},
        ),
      ])!;
      expect(habit.scheduleHistory, hasLength(1));
    });
  });
}
