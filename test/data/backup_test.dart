import 'dart:convert';

import 'package:cohabit/data/database.dart';
import 'package:cohabit/data/repository.dart';
import 'package:cohabit/domain/day_state.dart';
import 'package:cohabit/domain/habit_day.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'malformed timestamps reject atomically and settings serialize',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = await CohabitRepository.open(db);
      final original =
          jsonDecode(await repo.exportBackup()) as Map<String, dynamic>;
      for (final stamp in [
        '2026-11-01',
        '2026-02-30T12:00:00Z',
        '2026-11-01T24:00:00Z',
        '2026-11-01T12:00:00',
        '2026-11-01T12:60:00Z',
        '2026-11-01T12:00:00+24:00',
      ]) {
        final doc = {...original, 'exportedAt': stamp};
        await expectLater(
          repo.restoreBackup(jsonEncode(doc)),
          throwsFormatException,
        );
        expect(await repo.events(), isEmpty);
        expect(await repo.dayBoundaryMinutes(), 180);
      }
      await Future.wait([
        repo.setDayBoundaryMinutes(60),
        repo.restoreBackup(jsonEncode(original)),
        repo.setDayBoundaryMinutes(120),
      ]).timeout(const Duration(seconds: 5));
      expect(await repo.dayBoundaryMinutes(), 120);
    },
  );

  test('portable archived history, idempotency, CSV and rollback', () async {
    final a = AppDatabase(NativeDatabase.memory());
    final b = AppDatabase(NativeDatabase.memory());
    addTearDown(a.close);
    addTearDown(b.close);
    final now = DateTime.utc(2026, 11, 1, 12);
    final source = await CohabitRepository.open(a, now: () => now);
    final target = await CohabitRepository.open(b, now: () => now);
    final id = await source.createHabit(
      name: '=雪,"\n',
      polarity: HabitPolarity.negative,
      schedule: {1, 7},
    );
    await source.editHabit(id, schedule: {2});
    await source.setDayState(id, HabitDay(2026, 11, 1), DayState.unknown);
    await source.setDayState(id, HabitDay(2026, 10, 31), DayState.skipped);
    await source.archiveHabit(id);
    await source.setDayBoundaryMinutes(240);
    final backup = await source.exportBackup();
    final device = target.deviceId;
    await b.customStatement(
      "CREATE TRIGGER fail_restore BEFORE INSERT ON day_states BEGIN SELECT RAISE(ABORT, 'test'); END",
    );
    await expectLater(
      target.restoreBackup(backup, restoreBoundary: true),
      throwsA(anything),
    );
    expect(await target.events(), isEmpty);
    expect(await target.dayBoundaryMinutes(), 180);
    await b.customStatement('DROP TRIGGER fail_restore');
    await target.restoreBackup(backup, restoreBoundary: true);
    await target.restoreBackup(backup, restoreBoundary: true);
    expect(target.deviceId, device);
    expect(await target.dayBoundaryMinutes(), 240);
    expect(
      (await target.events()).map((e) => e.toJson()).toList(),
      (await source.events()).map((e) => e.toJson()).toList(),
    );
    await target.rebuildProjections();
    final reopened = await CohabitRepository.open(b, now: () => now);
    expect((await reopened.habit(id))!.isArchived, isTrue);
    expect(
      (await reopened.habit(id))!.scheduleHistory,
      (await source.habit(id))!.scheduleHistory,
    );
    final csv = await target.exportCsv();
    expect(csv, contains("'=雪"));
    expect(csv, contains('unknown'));
    expect(csv, contains('skipped'));
    expect(csv, contains('\r\n'));
    final malformed = jsonDecode(backup) as Map<String, dynamic>;
    malformed['version'] = 999;
    await expectLater(
      target.restoreBackup(jsonEncode(malformed)),
      throwsFormatException,
    );
    await target.setDayState(id, HabitDay(2026, 11, 1), DayState.done);
    expect(
      (await target.events()).last.hlc > (await source.events()).last.hlc,
      isTrue,
    );
  });
}
