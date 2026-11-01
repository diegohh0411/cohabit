import 'dart:convert';

import 'package:cohabit/data/database.dart';
import 'package:cohabit/data/repository.dart';
import 'package:cohabit/domain/day_state.dart';
import 'package:cohabit/domain/event.dart';
import 'package:cohabit/domain/habit_day.dart';
import 'package:cohabit/domain/hlc.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DateTime now;
  late CohabitRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime(2026, 11, 1, 10, 0);
    repo = await CohabitRepository.open(db, now: () => now);
  });

  tearDown(() => db.close());

  Event remoteDayEvent(
    String id, {
    required String habitId,
    required int wall,
    String device = 'remote',
    DayState state = DayState.done,
    EventSource source = EventSource.manual,
    String day = '2026-11-01',
  }) => Event(
    id: id,
    deviceId: device,
    hlc: Hlc(wall, 0),
    type: EventTypes.dayStateSet,
    payload: {
      'habitId': habitId,
      'habitDay': day,
      'state': state.wireName,
      'loggedAt': '2026-11-01T10:00:00.000Z',
      'source': source.wireName,
    },
  );

  Future<String> newHabit({
    String name = 'Run',
    HabitPolarity polarity = HabitPolarity.positive,
    Set<int> schedule = everyDayInTests,
  }) => repo.createHabit(name: name, polarity: polarity, schedule: schedule);

  final day = HabitDay(2026, 11, 1);

  group('device and clock', () {
    test('device id is stable across reopen', () async {
      final again = await CohabitRepository.open(db, now: () => now);
      expect(again.deviceId, repo.deviceId);
      expect(repo.deviceId, isNotEmpty);
    });

    test(
      'events carry increasing HLCs, even if the wall clock regresses',
      () async {
        final id = await newHabit();
        await repo.setDayState(id, day, DayState.done);
        now = now.subtract(const Duration(hours: 1));
        await repo.setDayState(id, day, DayState.notDone);
        final events = await repo.events();
        expect(events.length, 3);
        for (var i = 1; i < events.length; i++) {
          expect(events[i].hlc > events[i - 1].hlc, isTrue);
        }
        expect((await repo.dayStates(day))[id]!.state, DayState.notDone);
      },
    );

    test('clock resumes past the newest logged HLC after reopen', () async {
      final id = await newHabit();
      final before = (await repo.events()).last.hlc;
      now = now.subtract(const Duration(days: 1));
      final again = await CohabitRepository.open(db, now: () => now);
      await again.setDayState(id, day, DayState.done);
      expect((await again.events()).last.hlc > before, isTrue);
    });
  });

  group('habits', () {
    test('create, edit and archive', () async {
      final id = await newHabit(
        name: '  Run ',
        polarity: HabitPolarity.negative,
        schedule: {1, 3},
      );
      var habit = (await repo.habit(id))!;
      expect(habit.name, 'Run');
      expect(habit.polarity, HabitPolarity.negative);
      expect(habit.schedule, {1, 3});
      expect(habit.createdDay, day);

      await repo.editHabit(id, name: 'Jog');
      await repo.editHabit(id, schedule: {2, 4, 6});
      habit = (await repo.habit(id))!;
      expect(habit.name, 'Jog');
      expect(habit.schedule, {2, 4, 6});

      expect(await repo.habits(), hasLength(1));
      await repo.archiveHabit(id);
      expect(await repo.habits(), isEmpty);
      expect(await repo.habits(includeArchived: true), hasLength(1));
      expect((await repo.habit(id))!.isArchived, isTrue);
    });

    test('createdDay honours the day boundary', () async {
      now = DateTime(2026, 11, 2, 2, 30);
      final id = await newHabit();
      expect((await repo.habit(id))!.createdDay, day);
    });

    test('validates input', () async {
      expect(() => newHabit(name: '  '), throwsArgumentError);
      expect(() => newHabit(schedule: {}), throwsArgumentError);
      expect(() => newHabit(schedule: {8}), throwsArgumentError);
      expect(() => repo.editHabit('missing', name: 'x'), throwsArgumentError);
      expect(
        () => repo.setDayState('missing', day, DayState.done),
        throwsArgumentError,
      );
    });

    test('every edit is a new event; the log only grows', () async {
      final id = await newHabit();
      await repo.editHabit(id, name: 'A');
      await repo.editHabit(id, name: 'B');
      final types = (await repo.events()).map((e) => e.type).toList();
      expect(types, [
        EventTypes.habitCreated,
        EventTypes.habitEdited,
        EventTypes.habitEdited,
      ]);
    });
  });

  group('schedule history', () {
    test('an edit applies from today and leaves earlier days alone', () async {
      // Sunday 1 Nov; Mon/Wed/Fri.
      final id = await newHabit(schedule: {1, 3, 5});
      final tue = HabitDay(2026, 11, 3);
      expect((await repo.habit(id))!.isScheduledOn(tue), isFalse);

      now = DateTime(2026, 11, 3, 10, 0); // Tue
      await repo.editHabit(id, schedule: {2, 4});
      final habit = (await repo.habit(id))!;

      expect(habit.schedule, {2, 4});
      expect(habit.isScheduledOn(tue), isTrue); // the edit day itself
      expect(habit.isScheduledOn(HabitDay(2026, 11, 2)), isTrue); // Mon, old
      expect(habit.isScheduledOn(HabitDay(2026, 11, 9)), isFalse); // Mon, new
      expect(
        habit.effectiveState(HabitDay(2026, 11, 2), null),
        DayState.unknown,
      );
      expect((await repo.events()).last.payload['effectiveFrom'], '2026-11-03');
    });

    test('edit day respects the day boundary', () async {
      final id = await newHabit(schedule: {1, 3, 5});
      now = DateTime(2026, 11, 3, 1, 0); // before 03:00: still Monday
      await repo.editHabit(id, schedule: {2});
      final habit = (await repo.habit(id))!;
      expect(habit.scheduleOn(HabitDay(2026, 11, 2)), {2});
      expect(habit.scheduleOn(HabitDay(2026, 11, 1)), {1, 3, 5});
    });

    test('history survives rebuild and reload', () async {
      final id = await newHabit(schedule: {1, 3, 5});
      now = DateTime(2026, 11, 3, 10, 0);
      await repo.editHabit(id, schedule: {2, 4});
      now = DateTime(2026, 11, 10, 10, 0);
      await repo.editHabit(id, schedule: {6});
      final live = (await repo.habit(id))!.scheduleHistory;
      expect(live, hasLength(3));

      await repo.rebuildProjections();
      expect((await repo.habit(id))!.scheduleHistory, live);
    });

    test('a pre-schema-2 projection is refolded on open', () async {
      final id = await newHabit(schedule: {1, 3, 5});
      now = DateTime(2026, 11, 3, 10, 0);
      await repo.editHabit(id, schedule: {2, 4});
      // As rows looked before the column existed.
      await db.customStatement("UPDATE habits SET schedule_history = ''");

      final reopened = await CohabitRepository.open(db, now: () => now);
      final habit = (await reopened.habit(id))!;
      expect(habit.scheduleOn(HabitDay(2026, 11, 2)), {1, 3, 5});
      expect(habit.scheduleOn(HabitDay(2026, 11, 3)), {2, 4});
    });
  });

  group('day states', () {
    test('logging, relogging, clearing and backfilling', () async {
      final id = await newHabit();
      final past = day.addDays(-10);

      await repo.setDayState(id, day, DayState.done);
      expect((await repo.dayStates(day))[id]!.state, DayState.done);

      await repo.setDayState(id, day, DayState.notDone);
      expect((await repo.dayStates(day))[id]!.state, DayState.notDone);

      await repo.setDayState(id, past, DayState.skipped);
      expect((await repo.dayStates(past))[id]!.state, DayState.skipped);
      expect((await repo.dayStates(day))[id]!.state, DayState.notDone);

      await repo.setDayState(id, day, DayState.unknown);
      expect((await repo.dayStates(day))[id]!.state, DayState.unknown);

      final dayEvents = (await repo.events())
          .where((e) => e.type == EventTypes.dayStateSet)
          .toList();
      expect(dayEvents, hasLength(4));
      expect(dayEvents.first.payload['source'], 'manual');
      expect(dayEvents.first.payload['loggedAt'], isA<String>());
    });

    test('watchDayStates emits on change', () async {
      final id = await newHabit();
      final stream = repo.watchDayStates(day);
      final expectation = expectLater(
        stream.map((m) => m[id]?.state),
        emitsInOrder([null, DayState.done]),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await repo.setDayState(id, day, DayState.done);
      await expectation;
    });
  });

  group('idempotency', () {
    test('applying the same event twice has no effect', () async {
      final id = await newHabit();
      final event = remoteDayEvent('e1', habitId: id, wall: 5000);

      expect(await repo.apply(event), isTrue);
      final eventsAfterFirst = await repo.events();
      final stateAfterFirst = (await repo.dayStates(day))[id]!;
      final clockBefore = (await repo.events()).length;

      expect(await repo.apply(event), isFalse);
      expect(await repo.apply(event), isFalse);

      expect((await repo.events()).length, clockBefore);
      expect(
        (await repo.events()).map((e) => e.id),
        eventsAfterFirst.map((e) => e.id),
      );
      final stateAfterRepeat = (await repo.dayStates(day))[id]!;
      expect(stateAfterRepeat.eventId, stateAfterFirst.eventId);
      expect(stateAfterRepeat.state, stateAfterFirst.state);
    });

    test('re-applying an old event does not resurrect its state', () async {
      final id = await newHabit();
      final old = remoteDayEvent(
        'old',
        habitId: id,
        wall: 1,
        state: DayState.skipped,
      );
      await repo.apply(old);
      await repo.setDayState(id, day, DayState.done);
      await repo.apply(old);
      expect((await repo.dayStates(day))[id]!.state, DayState.done);
    });

    test(
      'applying an event whose id was stored does not touch the clock',
      () async {
        final id = await newHabit();
        final event = remoteDayEvent('e1', habitId: id, wall: 5000);
        await repo.apply(event);
        await repo.setDayState(id, day, DayState.notDone);
        final mine = (await repo.events()).last;
        await repo.apply(event);
        await repo.setDayState(id, day, DayState.done);
        final next = (await repo.events()).last;
        expect(next.hlc > mine.hlc, isTrue);
      },
    );
  });

  group('conflict resolution via the store', () {
    test('later HLC wins over an earlier remote event', () async {
      final id = await newHabit();
      await repo.apply(
        remoteDayEvent(
          'r1',
          habitId: id,
          wall: now.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
        ),
      );
      // Local event is stamped after the merged remote HLC.
      await repo.setDayState(id, day, DayState.notDone);
      expect((await repo.dayStates(day))[id]!.state, DayState.notDone);
    });

    test('out-of-order arrival gives the same winner', () async {
      final id = await newHabit();
      final late = remoteDayEvent(
        'late',
        habitId: id,
        wall: 3000,
        state: DayState.notDone,
      );
      final early = remoteDayEvent(
        'early',
        habitId: id,
        wall: 2000,
        state: DayState.done,
      );
      await repo.apply(late);
      await repo.apply(early);
      expect((await repo.dayStates(day))[id]!.eventId, 'late');
    });

    test('equal HLC ties go to the greater deviceId', () async {
      final id = await newHabit();
      await repo.apply(
        remoteDayEvent(
          'a',
          habitId: id,
          wall: 3000,
          device: 'dev-a',
          state: DayState.done,
        ),
      );
      await repo.apply(
        remoteDayEvent(
          'b',
          habitId: id,
          wall: 3000,
          device: 'dev-b',
          state: DayState.notDone,
        ),
      );
      expect((await repo.dayStates(day))[id]!.state, DayState.notDone);
    });

    test('manual beats a later automatic event', () async {
      final id = await newHabit();
      await repo.apply(
        remoteDayEvent('m', habitId: id, wall: 3000, state: DayState.notDone),
      );
      await repo.apply(
        remoteDayEvent(
          'auto',
          habitId: id,
          wall: 4000,
          state: DayState.done,
          source: EventSource.healthConnect,
        ),
      );
      final entry = (await repo.dayStates(day))[id]!;
      expect(entry.state, DayState.notDone);
      expect(entry.source, EventSource.manual);
    });

    test('a later manual edit overrides an automatic result', () async {
      final id = await newHabit();
      await repo.setDayState(
        id,
        day,
        DayState.done,
        source: EventSource.import,
      );
      await repo.setDayState(id, day, DayState.notDone);
      expect((await repo.dayStates(day))[id]!.state, DayState.notDone);
    });

    test('a foreign event too far in the future is rejected', () async {
      final id = await newHabit();
      final far = remoteDayEvent(
        'far',
        habitId: id,
        wall: now.add(const Duration(days: 1)).millisecondsSinceEpoch,
      );
      await expectLater(repo.apply(far), throwsA(isA<ClockDriftException>()));
      expect((await repo.events()).where((e) => e.id == 'far'), isEmpty);
    });
  });

  group('append-only log', () {
    test('the database refuses to update or delete events', () async {
      await newHabit();
      await expectLater(
        db.customStatement("UPDATE events SET type = 'x'"),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement('DELETE FROM events'),
        throwsA(anything),
      );
      expect(await repo.events(), hasLength(1));
    });
  });

  group('projection rebuild', () {
    Future<String> snapshot() async {
      final habits =
          (await db.select(db.habits).get())
              .map((h) => jsonEncode(h.toJson()))
              .toList()
            ..sort();
      final days =
          (await db.select(db.dayStates).get())
              .map((d) => jsonEncode(d.toJson()))
              .toList()
            ..sort();
      return jsonEncode([habits, days]);
    }

    test('rebuilding reproduces the live projections', () async {
      final run = await newHabit(name: 'Run');
      final smoke = await newHabit(
        name: 'Smoke',
        polarity: HabitPolarity.negative,
        schedule: {1, 2, 3},
      );
      final gone = await newHabit(name: 'Gone');
      await repo.editHabit(run, name: 'Jog', schedule: {6, 7});
      await repo.archiveHabit(gone);
      await repo.setDayState(run, day, DayState.done);
      await repo.setDayState(run, day, DayState.notDone);
      await repo.setDayState(run, day.addDays(-1), DayState.skipped);
      await repo.setDayState(smoke, day, DayState.done);
      await repo.setDayState(smoke, day, DayState.unknown);
      await repo.apply(
        remoteDayEvent(
          'auto',
          habitId: run,
          wall: 99,
          source: EventSource.import,
        ),
      );

      final live = await snapshot();
      expect(await db.select(db.habits).get(), hasLength(3));
      expect(await db.select(db.dayStates).get(), hasLength(3));

      await repo.rebuildProjections();
      expect(await snapshot(), live);
    });

    test('rebuild recovers from wiped or corrupt projections', () async {
      final id = await newHabit(name: 'Run');
      await repo.setDayState(id, day, DayState.done);
      final live = await snapshot();

      await db.delete(db.habits).go();
      await db.delete(db.dayStates).go();
      expect(await repo.habits(), isEmpty);

      await repo.rebuildProjections();
      expect(await snapshot(), live);
      expect((await repo.dayStates(day))[id]!.state, DayState.done);
    });

    test('rebuild leaves the log and settings untouched', () async {
      final id = await newHabit();
      await repo.setDayState(id, day, DayState.done);
      await repo.setDayBoundaryMinutes(240);
      final before = (await repo.events()).map((e) => e.id).toList();
      await repo.rebuildProjections();
      expect((await repo.events()).map((e) => e.id).toList(), before);
      expect(await repo.dayBoundaryMinutes(), 240);
    });

    test('rebuild is stable when run twice', () async {
      final id = await newHabit();
      await repo.setDayState(id, day, DayState.done);
      await repo.rebuildProjections();
      final once = await snapshot();
      await repo.rebuildProjections();
      expect(await snapshot(), once);
    });
  });

  group('settings', () {
    test('day boundary defaults to 03:00 and is configurable', () async {
      expect(await repo.dayBoundaryMinutes(), 180);
      await repo.setDayBoundaryMinutes(300);
      expect(await repo.dayBoundaryMinutes(), 300);
      now = DateTime(2026, 11, 2, 4, 0);
      expect(await repo.currentHabitDay(), day);
      await repo.setDayBoundaryMinutes(0);
      expect(await repo.currentHabitDay(), HabitDay(2026, 11, 2));
      expect(() => repo.setDayBoundaryMinutes(-5), throwsRangeError);
    });
  });
}

const everyDayInTests = {1, 2, 3, 4, 5, 6, 7};
