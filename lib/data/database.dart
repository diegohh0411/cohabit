import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// The append-only event log; the source of truth.
///
/// `habitId` and `habitDay` are denormalised from the payload so projections
/// can refold one habit or one day without scanning the log.
@DataClassName('EventRow')
@TableIndex(name: 'events_habit_day', columns: {#habitId, #habitDay})
class Events extends Table {
  TextColumn get id => text()();
  TextColumn get deviceId => text()();

  /// Fixed-width encoded HLC, so SQL string order equals HLC order.
  TextColumn get hlc => text()();
  IntColumn get schemaVersion => integer()();
  TextColumn get type => text()();
  TextColumn get payload => text()();
  TextColumn get habitId => text().nullable()();
  TextColumn get habitDay => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Projection: current state of each habit.
@DataClassName('HabitRow')
class Habits extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get polarity => text()();

  /// Bitmask of scheduled weekdays: bit 0 = Monday .. bit 6 = Sunday.
  IntColumn get scheduleMask => integer()();
  TextColumn get createdDay => text()();

  /// ISO-8601 UTC instant, or null.
  TextColumn get archivedAt => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Projection: winning day state per habit and day.
@DataClassName('DayStateRow')
class DayStates extends Table {
  TextColumn get habitId => text()();
  TextColumn get habitDay => text()();
  TextColumn get state => text()();
  TextColumn get source => text()();
  TextColumn get loggedAt => text()();
  TextColumn get eventId => text()();

  @override
  Set<Column> get primaryKey => {habitId, habitDay};
}

/// Local, non-synced key/value data (device id, settings).
@DataClassName('MetaRow')
class Meta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Events, Habits, DayStates, Meta])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// On-disk database for the running app.
  AppDatabase.persistent() : super(driftDatabase(name: 'cohabit'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // Events are never changed or deleted; enforce it in the database.
      await customStatement('''
            CREATE TRIGGER events_no_update BEFORE UPDATE ON events
            BEGIN SELECT RAISE(ABORT, 'events are append-only'); END
          ''');
      await customStatement('''
            CREATE TRIGGER events_no_delete BEFORE DELETE ON events
            BEGIN SELECT RAISE(ABORT, 'events are append-only'); END
          ''');
    },
  );
}
