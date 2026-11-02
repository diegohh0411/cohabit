import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../domain/day_state.dart';
import '../domain/event.dart';
import '../domain/habit.dart';
import '../domain/habit_day.dart';
import '../domain/hlc.dart';
import '../domain/resolution.dart';
import 'database.dart';
import 'backup.dart';

const _deviceIdKey = 'deviceId';
const _dayBoundaryKey = 'dayBoundaryMinutes';

/// Event store plus projections.
///
/// All writes go through [apply]: the event is appended to the log (a no-op
/// if its id is already there) and the affected projection rows are refolded
/// from the log. Projections are therefore a pure function of the event set.
/// What a restore would add, shown before the user confirms.
typedef RestorePreview = ({
  int habits,
  int logs,
  int newEvents,
  int duplicates,
  int boundary,
});

class CohabitRepository {
  CohabitRepository._(this._db, this.deviceId, this._clock, this._now);

  final AppDatabase _db;
  HlcClock _clock;
  final DateTime Function() _now;
  static const _uuid = Uuid();

  /// Stable per installation.
  final String deviceId;

  /// Opens the repository, creating the device id on first run and resuming
  /// the clock from the newest HLC already in the log.
  static Future<CohabitRepository> open(
    AppDatabase db, {
    DateTime Function()? now,
  }) async {
    final clockNow = now ?? DateTime.now;

    final existing = await (db.select(
      db.meta,
    )..where((m) => m.key.equals(_deviceIdKey))).getSingleOrNull();
    final String deviceId;
    if (existing != null) {
      deviceId = existing.value;
    } else {
      deviceId = _uuid.v7();
      await db
          .into(db.meta)
          .insert(MetaCompanion.insert(key: _deviceIdKey, value: deviceId));
    }

    final maxHlc = db.events.hlc.max();
    final newest = await (db.selectOnly(
      db.events,
    )..addColumns([maxHlc])).getSingle();
    final newestHlc = newest.read(maxHlc);
    final clock = HlcClock(
      nowMillis: () => clockNow().millisecondsSinceEpoch,
      initial: newestHlc == null ? null : Hlc.parse(newestHlc),
    );
    final repository = CohabitRepository._(db, deviceId, clock, clockNow);
    // Habits projected before schema 2 lack their schedule history.
    final stale = await (db.select(
      db.habits,
    )..where((h) => h.scheduleHistory.equals(''))).get();
    if (stale.isNotEmpty) await repository.rebuildProjections();
    return repository;
  }

  Future<String> exportBackup() => _db.transaction(
    () async => BackupDocument(
      exportedAt: _now().toUtc(),
      dayBoundaryMinutes: await dayBoundaryMinutes(),
      events: await events(),
    ).encode(),
  );

  Future<RestorePreview> previewRestore(String input) =>
      _db.transaction(() async {
        final backup = BackupDocument.decode(input);
        final stored = {for (final e in await events()) e.id: e};
        validateEvents(
          backup.events,
          existingHabitIds: stored.values
              .where((e) => e.type == EventTypes.habitCreated)
              .map((e) => e.habitId!)
              .toSet(),
        );
        final creates = {...stored.values, ...backup.events}
            .where((e) => e.type == EventTypes.habitCreated)
            .map((e) => e.habitId)
            .toSet();
        var added = 0;
        final candidate = HlcClock(
          nowMillis: () => _now().millisecondsSinceEpoch,
          initial: _clock.latest,
        );
        for (final e in backup.events) {
          if (!creates.contains(e.habitId)) {
            throw const FormatException('Missing habit');
          }
          candidate.receive(e.hlc);
          final old = stored[e.id];
          if (old != null) {
            if (!_sameEvent(old, e)) {
              throw const FormatException('Conflicting event ID');
            }
          } else {
            stored[e.id] = e;
            added++;
          }
        }
        return (
          habits: backup.events.map((e) => e.habitId).toSet().length,
          logs: backup.events
              .where((e) => e.type == EventTypes.dayStateSet)
              .map((e) => (e.habitId, e.habitDay.toString()))
              .toSet()
              .length,
          newEvents: added,
          duplicates: backup.events.length - added,
          boundary: backup.dayBoundaryMinutes,
        );
      });

  bool _sameEvent(Event a, Event b) {
    return canonicalJson(a.toJson()) == canonicalJson(b.toJson());
  }

  Future<void> restoreBackup(String input, {bool restoreBoundary = false}) =>
      _coordinate(() async {
        HlcClock? committed;
        await _db.transaction(() async {
          await previewRestore(input);
          final backup = BackupDocument.decode(input);
          final candidate = HlcClock(
            nowMillis: () => _now().millisecondsSinceEpoch,
            initial: _clock.latest,
          );
          final ids = (await events()).map((e) => e.id).toSet();
          for (final e in backup.events) {
            if (!ids.add(e.id)) continue;
            candidate.receive(e.hlc);
            await _db
                .into(_db.events)
                .insert(
                  EventsCompanion.insert(
                    id: e.id,
                    deviceId: e.deviceId,
                    hlc: e.hlc.encoded,
                    schemaVersion: e.schemaVersion,
                    type: e.type,
                    payload: e.payloadJson,
                    habitId: Value(e.habitId),
                    habitDay: Value(e.habitDay?.toString()),
                  ),
                );
          }
          await rebuildProjections();
          if (restoreBoundary) {
            await _setDayBoundaryMinutes(backup.dayBoundaryMinutes);
          }
          committed = candidate;
        });
        _clock = committed!;
      });

  Future<String> exportCsv() => _db.transaction(() async {
    final habits = {
      for (final h in await this.habits(includeArchived: true)) h.id: h,
    };
    final rows = await _db.select(_db.dayStates).get();
    rows.sort(
      (a, b) => ('${a.habitId}/${a.habitDay}').compareTo(
        '${b.habitId}/${b.habitDay}',
      ),
    );
    return '${[
      ['habitId', 'name', 'polarity', 'archivedAt', 'date', 'state', 'source', 'timestamp'],
      for (final r in rows) [r.habitId, habits[r.habitId]!.name, habits[r.habitId]!.polarity.wireName, habits[r.habitId]!.archivedAt?.toIso8601String() ?? '', r.habitDay, r.state, r.source, r.loggedAt],
    ].map((r) => r.map((v) => csvCell(v.toString())).join(',')).join('\r\n')}\r\n';
  });

  // ---------------------------------------------------------------- writes

  /// Appends [event] and updates projections. Returns false, changing
  /// nothing, if the event was already applied.
  Future<void> _pending = Future.value();
  Future<T> _coordinate<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  HlcClock _candidate() => HlcClock(
    nowMillis: () => _now().millisecondsSinceEpoch,
    initial: _clock.latest,
  );
  Future<bool> apply(Event event) => _coordinate(() async {
    final candidate = _candidate()..receive(event.hlc);
    final result = await _apply(event);
    if (result) _clock = candidate;
    return result;
  });
  Future<bool> _apply(Event event) {
    return _db.transaction(() async {
      final seen = await (_db.select(
        _db.events,
      )..where((e) => e.id.equals(event.id))).getSingleOrNull();
      if (seen != null) return false;

      await _db
          .into(_db.events)
          .insert(
            EventsCompanion.insert(
              id: event.id,
              deviceId: event.deviceId,
              hlc: event.hlc.encoded,
              schemaVersion: event.schemaVersion,
              type: event.type,
              payload: event.payloadJson,
              habitId: Value(event.habitId),
              habitDay: Value(event.habitDay?.toString()),
            ),
          );

      if (event.schemaVersion <= currentSchemaVersion) {
        await _project(event);
      }
      return true;
    });
  }

  Future<Event> _record(
    String type,
    Future<Map<String, Object?>> Function() payload,
  ) => _coordinate(() async {
    final candidate = _candidate();
    final event = Event(
      id: _uuid.v7(),
      deviceId: deviceId,
      hlc: candidate.send(),
      type: type,
      payload: await payload(),
    );
    await _apply(event);
    _clock = candidate;
    return event;
  });

  /// Creates a habit and returns its id.
  Future<String> createHabit({
    required String name,
    required HabitPolarity polarity,
    required Set<int> schedule,
  }) async {
    final trimmed = _validName(name);
    _validSchedule(schedule);
    final habitId = _uuid.v7();
    final now = _now();
    await _record(
      EventTypes.habitCreated,
      () async => {
        'habitId': habitId,
        'name': trimmed,
        'polarity': polarity.wireName,
        'schedule': _sortedSchedule(schedule),
        'createdDay': (await currentHabitDay()).toString(),
        'createdAt': now.toUtc().toIso8601String(),
      },
    );
    return habitId;
  }

  /// Edits the given fields only; omitted fields keep their value.
  Future<void> editHabit(
    String habitId, {
    String? name,
    Set<int>? schedule,
  }) async {
    await _requireHabit(habitId);
    if (schedule != null) _validSchedule(schedule);
    await _record(
      EventTypes.habitEdited,
      () async => {
        'habitId': habitId,
        if (name != null) 'name': _validName(name),
        if (schedule != null) ...{
          'schedule': _sortedSchedule(schedule),
          // A schedule applies from the day it was set, never to earlier days.
          'effectiveFrom': (await currentHabitDay()).toString(),
        },
      },
    );
  }

  Future<void> archiveHabit(String habitId) async {
    await _requireHabit(habitId);
    await _record(
      EventTypes.habitArchived,
      () async => {
        'habitId': habitId,
        'archivedAt': _now().toUtc().toIso8601String(),
      },
    );
  }

  /// Records the state of [habitId] on [day]. Any past day can be edited;
  /// [DayState.unknown] clears an earlier log.
  Future<void> setDayState(
    String habitId,
    HabitDay day,
    DayState state, {
    EventSource source = EventSource.manual,
  }) async {
    await _requireHabit(habitId);
    await _record(
      EventTypes.dayStateSet,
      () async => {
        'habitId': habitId,
        'habitDay': day.toString(),
        'state': state.wireName,
        'loggedAt': _now().toUtc().toIso8601String(),
        'source': source.wireName,
      },
    );
  }

  Future<void> _requireHabit(String habitId) async {
    final row = await (_db.select(
      _db.habits,
    )..where((h) => h.id.equals(habitId))).getSingleOrNull();
    if (row == null) throw ArgumentError.value(habitId, 'habitId', 'unknown');
  }

  String _validName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(name, 'name', 'empty');
    return trimmed;
  }

  void _validSchedule(Set<int> schedule) {
    if (schedule.isEmpty || schedule.any((d) => d < 1 || d > 7)) {
      throw ArgumentError.value(schedule, 'schedule', 'needs weekdays 1-7');
    }
  }

  List<int> _sortedSchedule(Set<int> schedule) => schedule.toList()..sort();

  // ----------------------------------------------------------- projections

  Future<void> _project(Event event) async {
    final habitId = event.habitId;
    if (habitId == null) return;
    if (EventTypes.habitTypes.contains(event.type)) {
      await _refoldHabit(habitId);
    } else if (event.type == EventTypes.dayStateSet) {
      await _refoldDay(habitId, event.habitDay!);
    }
  }

  Future<void> _refoldHabit(String habitId) async {
    final rows =
        await (_db.select(_db.events)..where(
              (e) =>
                  e.habitId.equals(habitId) &
                  e.type.isIn(EventTypes.habitTypes),
            ))
            .get();
    final habit = foldHabit(rows.map(_eventFromRow));
    if (habit == null) return;
    await _db.into(_db.habits).insertOnConflictUpdate(_habitCompanion(habit));
  }

  Future<void> _refoldDay(String habitId, HabitDay day) async {
    final rows =
        await (_db.select(_db.events)..where(
              (e) =>
                  e.habitId.equals(habitId) &
                  e.habitDay.equals(day.toString()) &
                  e.type.equals(EventTypes.dayStateSet),
            ))
            .get();
    final winner = resolveDayState(rows.map(_eventFromRow));
    if (winner == null) return;
    await _db
        .into(_db.dayStates)
        .insertOnConflictUpdate(_dayStateCompanion(dayStateEntryFor(winner)));
  }

  /// Discards every projection and rebuilds it from the event log.
  Future<void> rebuildProjections() {
    return _db.transaction(() async {
      await _db.delete(_db.habits).go();
      await _db.delete(_db.dayStates).go();

      final rows = await (_db.select(
        _db.events,
      )..orderBy([(e) => OrderingTerm.asc(e.hlc)])).get();
      final habitEvents = <String, List<Event>>{};
      final dayEvents = <(String, String), List<Event>>{};
      for (final row in rows) {
        final event = _eventFromRow(row);
        if (event.schemaVersion > currentSchemaVersion) continue;
        final habitId = event.habitId;
        if (habitId == null) continue;
        if (EventTypes.habitTypes.contains(event.type)) {
          (habitEvents[habitId] ??= []).add(event);
        } else if (event.type == EventTypes.dayStateSet) {
          (dayEvents[(habitId, event.habitDay.toString())] ??= []).add(event);
        }
      }

      for (final events in habitEvents.values) {
        final habit = foldHabit(events);
        if (habit != null) {
          await _db.into(_db.habits).insert(_habitCompanion(habit));
        }
      }
      for (final events in dayEvents.values) {
        final winner = resolveDayState(events);
        if (winner != null) {
          await _db
              .into(_db.dayStates)
              .insert(_dayStateCompanion(dayStateEntryFor(winner)));
        }
      }
    });
  }

  // ----------------------------------------------------------------- reads

  /// The full event log in HLC order.
  Future<List<Event>> events() async {
    final rows = await (_db.select(
      _db.events,
    )..orderBy([(e) => OrderingTerm.asc(e.hlc)])).get();
    return rows.map(_eventFromRow).toList()..sort(compareEvents);
  }

  Future<List<Habit>> habits({bool includeArchived = false}) =>
      _habitsQuery(includeArchived).get().then(_toHabits);

  Stream<List<Habit>> watchHabits({bool includeArchived = false}) =>
      _habitsQuery(includeArchived).watch().map(_toHabits);

  Future<Habit?> habit(String id) async {
    final row = await (_db.select(
      _db.habits,
    )..where((h) => h.id.equals(id))).getSingleOrNull();
    return row == null ? null : _habitFromRow(row);
  }

  SimpleSelectStatement<$HabitsTable, HabitRow> _habitsQuery(
    bool includeArchived,
  ) => _db.select(_db.habits)
    ..where(
      (h) => includeArchived ? const Constant(true) : h.archivedAt.isNull(),
    )
    ..orderBy([
      (h) => OrderingTerm.asc(h.createdDay),
      (h) => OrderingTerm.asc(h.id),
    ]);

  /// Resolved states for [day], keyed by habit id.
  Future<Map<String, DayStateEntry>> dayStates(HabitDay day) =>
      _dayStatesQuery(day).get().then(_toEntries);

  Stream<Map<String, DayStateEntry>> watchDayStates(HabitDay day) =>
      _dayStatesQuery(day).watch().map(_toEntries);

  SimpleSelectStatement<$DayStatesTable, DayStateRow> _dayStatesQuery(
    HabitDay day,
  ) =>
      _db.select(_db.dayStates)
        ..where((d) => d.habitDay.equals(day.toString()));

  /// Every resolved day state, as logged state by habit and day. Feeds the
  /// commit graphs.
  Stream<Map<String, Map<HabitDay, DayState>>> watchLoggedStates() =>
      _db.select(_db.dayStates).watch().map(_toLogged);

  Future<Map<String, Map<HabitDay, DayState>>> loggedStates() =>
      _db.select(_db.dayStates).get().then(_toLogged);

  Map<String, Map<HabitDay, DayState>> _toLogged(List<DayStateRow> rows) {
    final out = <String, Map<HabitDay, DayState>>{};
    for (final r in rows) {
      (out[r.habitId] ??= {})[HabitDay.parse(r.habitDay)] = DayState.parse(
        r.state,
      );
    }
    return out;
  }

  // -------------------------------------------------------------- settings

  Future<int> dayBoundaryMinutes() async {
    final row = await (_db.select(
      _db.meta,
    )..where((m) => m.key.equals(_dayBoundaryKey))).getSingleOrNull();
    return row == null ? defaultDayBoundaryMinutes : int.parse(row.value);
  }

  Stream<int> watchDayBoundaryMinutes() =>
      (_db.select(
        _db.meta,
      )..where((m) => m.key.equals(_dayBoundaryKey))).watchSingleOrNull().map(
        (r) => r == null ? defaultDayBoundaryMinutes : int.parse(r.value),
      );

  /// Changes the boundary for future logging; existing events keep their
  /// stored `habitDay`.
  Future<void> setDayBoundaryMinutes(int minutes) =>
      _coordinate(() => _setDayBoundaryMinutes(minutes));

  Future<void> _setDayBoundaryMinutes(int minutes) async {
    if (minutes < 0 || minutes > maxDayBoundaryMinutes) {
      throw RangeError.range(minutes, 0, maxDayBoundaryMinutes);
    }
    await _db
        .into(_db.meta)
        .insertOnConflictUpdate(
          MetaCompanion.insert(key: _dayBoundaryKey, value: '$minutes'),
        );
  }

  Future<HabitDay> currentHabitDay() async =>
      habitDayFor(_now(), boundaryMinutes: await dayBoundaryMinutes());

  // --------------------------------------------------------------- mapping

  Event _eventFromRow(EventRow r) => Event(
    id: r.id,
    deviceId: r.deviceId,
    hlc: Hlc.parse(r.hlc),
    schemaVersion: r.schemaVersion,
    type: r.type,
    payload: Map<String, Object?>.from(jsonDecode(r.payload) as Map),
  );

  List<Habit> _toHabits(List<HabitRow> rows) =>
      rows.map(_habitFromRow).toList();

  Habit _habitFromRow(HabitRow r) => Habit(
    id: r.id,
    name: r.name,
    polarity: HabitPolarity.parse(r.polarity),
    schedule: _fromMask(r.scheduleMask),
    createdDay: HabitDay.parse(r.createdDay),
    archivedAt: r.archivedAt == null ? null : DateTime.parse(r.archivedAt!),
    scheduleHistory: r.scheduleHistory.isEmpty
        ? null
        : [
            for (final c in jsonDecode(r.scheduleHistory) as List)
              ScheduleChange(
                from: (c as List)[0] == null
                    ? null
                    : HabitDay.parse(c[0] as String),
                schedule: _fromMask(c[1] as int),
              ),
          ],
  );

  static int _mask(Set<int> schedule) =>
      schedule.fold(0, (m, d) => m | (1 << (d - 1)));

  static Set<int> _fromMask(int mask) => {
    for (var d = 1; d <= 7; d++)
      if (mask & (1 << (d - 1)) != 0) d,
  };

  HabitsCompanion _habitCompanion(Habit h) => HabitsCompanion.insert(
    id: h.id,
    name: h.name,
    polarity: h.polarity.wireName,
    scheduleMask: _mask(h.schedule),
    scheduleHistory: Value(
      jsonEncode([
        for (final c in h.scheduleHistory)
          [c.from?.toString(), _mask(c.schedule)],
      ]),
    ),
    createdDay: h.createdDay.toString(),
    archivedAt: Value(h.archivedAt?.toUtc().toIso8601String()),
  );

  Map<String, DayStateEntry> _toEntries(List<DayStateRow> rows) => {
    for (final r in rows)
      r.habitId: DayStateEntry(
        habitId: r.habitId,
        habitDay: HabitDay.parse(r.habitDay),
        state: DayState.parse(r.state),
        source: EventSource.parse(r.source),
        loggedAt: DateTime.parse(r.loggedAt),
        eventId: r.eventId,
      ),
  };

  DayStatesCompanion _dayStateCompanion(DayStateEntry e) =>
      DayStatesCompanion.insert(
        habitId: e.habitId,
        habitDay: e.habitDay.toString(),
        state: e.state.wireName,
        source: e.source.wireName,
        loggedAt: e.loggedAt.toUtc().toIso8601String(),
        eventId: e.eventId,
      );

  Future<void> close() => _db.close();
}
