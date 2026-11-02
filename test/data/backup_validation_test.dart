import 'dart:convert';

import 'package:cohabit/data/backup.dart';
import 'package:cohabit/data/database.dart';
import 'package:cohabit/data/repository.dart';
import 'package:cohabit/domain/day_state.dart';
import 'package:cohabit/domain/habit_day.dart';
import 'package:cohabit/domain/hlc.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 1, 2);
  final day = HabitDay(2026, 11, 1);
  Future<CohabitRepository> open() async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    return CohabitRepository.open(db, now: () => now);
  }

  Future<String> seed(CohabitRepository r) async {
    final id = await r.createHabit(
      name: '雪,"\r\n',
      polarity: HabitPolarity.negative,
      schedule: {1, 7},
    );
    await r.editHabit(id, schedule: {2});
    await r.setDayState(id, day, DayState.unknown);
    return id;
  }

  Map<String, dynamic> clone(String s) => jsonDecode(s) as Map<String, dynamic>;
  Map<String, dynamic> event(Map<String, dynamic> d, int i) =>
      (d['events'] as List)[i] as Map<String, dynamic>;
  test('malformed backup fields reject without writes', () async {
    final r = await open();
    await seed(r);
    final original = await r.exportBackup();
    final changes = <void Function(Map<String, dynamic>)>[
      (d) => d['version'] = 2,
      (d) => d['version'] = '1',
      (d) => d['format'] = 3,
      (d) => event(d, 0)['schemaVersion'] = 2,
      (d) => event(d, 0)['schemaVersion'] = '1',
      (d) => event(d, 0)['type'] = 'other',
      (d) => event(d, 0)['type'] = 2,
      (d) => event(d, 0)['hlc'] = '1-0',
      (d) => event(d, 0)['extra'] = true,
      (d) => event(d, 0)['payload']['createdDay'] = '2026-02-30',
      (d) => event(d, 0)['payload']['polarity'] = 'other',
      (d) => event(d, 2)['payload']['state'] = 'other',
      (d) => event(d, 2)['payload']['source'] = 'other',
      for (final schedule in [
        [],
        [1, 1],
        [0],
        [8],
      ])
        (d) => event(d, 0)['payload']['schedule'] = schedule,
      (d) => event(d, 2)['payload']['habitId'] = 'missing',
    ];
    for (final change in changes) {
      final d = clone(original);
      change(d);
      await expectLater(r.restoreBackup(jsonEncode(d)), throwsFormatException);
      expect(await r.exportBackup(), original);
    }
    final legacy = clone(original);
    event(legacy, 1)['payload'].remove('effectiveFrom');
    event(legacy, 2)['payload'].remove('source');
    final other = await open();
    await other.restoreBackup(jsonEncode(legacy));
    expect((await other.events()).length, 3);
  });
  test(
    'duplicate IDs compare structural content and reject conflicts',
    () async {
      final source = await open();
      final id = await seed(source);
      final d = clone(await source.exportBackup());
      final duplicate = clone(jsonEncode(event(d, 0)));
      duplicate['payload'] = Map.fromEntries(
        (duplicate['payload'] as Map<String, dynamic>).entries
            .toList()
            .reversed,
      );
      (d['events'] as List).add(duplicate);
      final r = await open();
      await r.restoreBackup(jsonEncode(d));
      expect((await r.events()).length, 3);
      final before = await r.exportBackup();
      final csv = await r.exportCsv();
      duplicate['payload']['name'] = 'conflict';
      await expectLater(r.restoreBackup(jsonEncode(d)), throwsFormatException);
      d['events'] = [duplicate];
      await expectLater(r.restoreBackup(jsonEncode(d)), throwsFormatException);
      expect(await r.exportBackup(), before);
      expect(await r.exportCsv(), csv);
      expect((await r.habit(id))!.name, '雪,"');
    },
  );
  test('populated merge respects local data and source priority', () async {
    final s = await open();
    final id = await seed(s);
    final r = await open();
    await r.restoreBackup(await s.exportBackup());
    final unrelated = await r.createHabit(
      name: 'local',
      polarity: HabitPolarity.positive,
      schedule: {1},
    );
    await r.setDayState(id, day, DayState.done);
    await s.setDayState(
      id,
      day,
      DayState.notDone,
      source: EventSource.healthConnect,
    );
    await s.setDayBoundaryMinutes(240);
    final d = clone(await s.exportBackup());
    d['events'] = (d['events'] as List).reversed.toList();
    final preview = await r.previewRestore(jsonEncode(d));
    expect(preview.newEvents, 1);
    expect(preview.duplicates, 3);
    expect(preview.logs, 1);
    await r.restoreBackup(jsonEncode(d));
    expect(await r.dayBoundaryMinutes(), 180);
    expect((await r.dayStates(day))[id]!.state, DayState.done);
    expect(await r.habit(unrelated), isNotNull);
    await r.restoreBackup(jsonEncode(d), restoreBoundary: true);
    expect(await r.dayBoundaryMinutes(), 240);
  });
  test('clock ordering survives failure and same-device restore', () async {
    final r = await open();
    final id = await seed(r);
    final d = clone(await r.exportBackup());
    final e = event(d, 2);
    e['id'] = 'incoming';
    e['deviceId'] = r.deviceId;
    e['hlc'] = Hlc(now.millisecondsSinceEpoch, 100).encoded;
    d['events'] = [e];
    await r.restoreBackup(jsonEncode(d));
    await r.setDayState(id, day, DayState.done);
    final last = (await r.events()).last.hlc;
    expect(last > Hlc(now.millisecondsSinceEpoch, 100), isTrue);
    await r.restoreBackup(jsonEncode(d));
    await r.setDayState(id, day, DayState.skipped);
    expect((await r.events()).last.hlc.counter, last.counter + 1);
    e['id'] = 'future';
    e['hlc'] = Hlc(now.millisecondsSinceEpoch + 300001, 0).encoded;
    await expectLater(
      r.restoreBackup(jsonEncode(d)),
      throwsA(isA<ClockDriftException>()),
    );
    await r.setDayState(id, day, DayState.done);
    expect((await r.events()).last.hlc.counter, last.counter + 2);
  });
  test('restore local writes and settings serialize', () async {
    final r = await open();
    final id = await seed(r);
    final backup = await r.exportBackup();
    await Future.wait([
      r.restoreBackup(backup),
      r.setDayState(id, day, DayState.done),
      r.setDayBoundaryMinutes(0),
    ]).timeout(const Duration(seconds: 5));
    expect((await r.events()).length, 4);
    expect((await r.dayStates(day))[id]!.state, DayState.done);
    final created = await r.createHabit(
      name: 'today',
      polarity: HabitPolarity.positive,
      schedule: {1},
    );
    expect((await r.habit(created))!.createdDay, day);
    await r.setDayBoundaryMinutes(180);
    await r.editHabit(created, schedule: {2});
    expect((await r.events()).last.payload['effectiveFrom'], '2026-10-31');
    final events = await r.events();
    for (var i = 1; i < events.length; i++) {
      expect(events[i].hlc > events[i - 1].hlc, isTrue);
    }
  });
  test('CSV and tied event ordering are deterministic', () async {
    final r = await open();
    expect(clone(await r.exportBackup())['events'], isEmpty);
    expect((await r.exportCsv()).split('\r\n').length, 2);
    for (final value in ['=x', ' +x', '-x', '\t@x']) {
      expect(csvCell(value), '"\'$value"');
    }
    expect(csvCell('雪,"\r\n'), '"雪,""\r\n"');
    final id = await seed(r);
    await r.setDayState(id, HabitDay(2026, 10, 30), DayState.skipped);
    await r.archiveHabit(id);
    final d = clone(await r.exportBackup());
    final list = d['events'] as List;
    for (var i = 0; i < list.length; i++) {
      list[i]['hlc'] = Hlc(now.millisecondsSinceEpoch, 0).encoded;
      list[i]['deviceId'] = i == 0 ? 'a' : 'b';
      list[i]['id'] = 'event-$i';
    }
    final target = await open();
    d['events'] = list.reversed.toList();
    await target.restoreBackup(jsonEncode(d));
    expect((await target.events()).map((e) => e.id), [
      'event-0',
      'event-1',
      'event-2',
      'event-3',
      'event-4',
    ]);
    final csv = await target.exportCsv();
    expect(csv, contains('"negative"'));
    expect(csv, contains('"unknown"'));
    expect(csv, contains('"skipped"'));
    expect(csv, isNot(contains('2026-10-29')));
    expect(csv, await target.exportCsv());
  });
}
