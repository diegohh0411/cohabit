import 'dart:convert';

import 'package:cohabit/data/database.dart';
import 'package:cohabit/data/repository.dart';
import 'package:cohabit/domain/habit_day.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schema 1 database upgrades and gains schedule history', () async {
    final createdAt = DateTime.utc(2026, 11, 1, 12).millisecondsSinceEpoch;
    final editedAt = DateTime.utc(2026, 11, 4, 12).millisecondsSinceEpoch;
    String hlc(int wall) => '${wall.toRadixString(16).padLeft(12, '0')}-0000';

    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          // Schema 1 as shipped in Milestone 1: no schedule_history column.
          raw.execute('''
            CREATE TABLE events (
              id TEXT NOT NULL PRIMARY KEY, device_id TEXT NOT NULL,
              hlc TEXT NOT NULL, schema_version INTEGER NOT NULL,
              type TEXT NOT NULL, payload TEXT NOT NULL,
              habit_id TEXT NULL, habit_day TEXT NULL);
            CREATE INDEX events_habit_day ON events (habit_id, habit_day);
            CREATE TABLE habits (
              id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL,
              polarity TEXT NOT NULL, schedule_mask INTEGER NOT NULL,
              created_day TEXT NOT NULL, archived_at TEXT NULL);
            CREATE TABLE day_states (
              habit_id TEXT NOT NULL, habit_day TEXT NOT NULL,
              state TEXT NOT NULL, source TEXT NOT NULL,
              logged_at TEXT NOT NULL, event_id TEXT NOT NULL,
              PRIMARY KEY (habit_id, habit_day));
            CREATE TABLE meta (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL);
            CREATE TRIGGER events_no_update BEFORE UPDATE ON events
              BEGIN SELECT RAISE(ABORT, 'events are append-only'); END;
            CREATE TRIGGER events_no_delete BEFORE DELETE ON events
              BEGIN SELECT RAISE(ABORT, 'events are append-only'); END;
          ''');
          final insert = raw.prepare(
            'INSERT INTO events VALUES (?, ?, ?, 1, ?, ?, ?, NULL)',
          );
          insert.execute([
            'e1',
            'dev',
            hlc(createdAt),
            'HabitCreated',
            jsonEncode({
              'habitId': 'h1',
              'name': 'Run',
              'polarity': 'positive',
              'schedule': [1, 3, 5],
              'createdDay': '2026-11-01',
            }),
            'h1',
          ]);
          // A Milestone 1 edit: no effectiveFrom.
          insert.execute([
            'e2',
            'dev',
            hlc(editedAt),
            'HabitEdited',
            jsonEncode({
              'habitId': 'h1',
              'schedule': [2, 4],
            }),
            'h1',
          ]);
          insert.close();
          // The M1 projection already holds the *latest* schedule only.
          raw.execute(
            "INSERT INTO habits VALUES ('h1', 'Run', 'positive', 10, "
            "'2026-11-01', NULL)",
          );
          raw.execute('PRAGMA user_version = 1');
        },
      ),
    );
    addTearDown(db.close);

    final repo = await CohabitRepository.open(
      db,
      now: () => DateTime(2026, 11, 10, 10),
    );
    final habit = (await repo.habit('h1'))!;
    expect(habit.schedule, {2, 4});
    // The old schedule now holds for days before the edit.
    expect(habit.scheduleOn(HabitDay(2026, 11, 3)), {1, 3, 5});
    expect(habit.scheduleOn(HabitDay(2026, 11, 4)), {2, 4});
  });
}
