import 'dart:async';
import 'dart:convert';

import 'package:cohabit/app.dart';
import 'package:cohabit/data/backup_files.dart';
import 'package:cohabit/data/database.dart';
import 'package:cohabit/data/repository.dart';
import 'package:cohabit/design/buttons.dart';
import 'package:cohabit/domain/day_state.dart';
import 'package:cohabit/domain/habit_day.dart';
import 'package:cohabit/state/providers.dart';
import 'package:cohabit/ui/app_shell.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class ControlledFiles extends BackupFiles {
  String? input;
  Object? openError;
  Object? saveError;
  Completer<bool>? pendingSave;
  Completer<String?>? pendingOpen;
  int opens = 0;
  int saves = 0;

  @override
  Future<String?> openJson() async {
    opens++;
    if (openError != null) throw openError!;
    return pendingOpen == null ? input : await pendingOpen!.future;
  }

  @override
  Future<bool> save(String contents, String extension) async {
    saves++;
    if (saveError != null) throw saveError!;
    return pendingSave == null ? true : await pendingSave!.future;
  }
}

void main() {
  late AppDatabase db;
  late CohabitRepository repo;
  late ControlledFiles files;
  late String backup;
  late String habitId;
  final now = DateTime(2026, 11, 1, 12);

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
    }
  }

  Future<void> start(
    WidgetTester tester, {
    double width = 360,
    double height = 900,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    files = ControlledFiles();
    await tester.runAsync(() async {
      final sourceDb = AppDatabase(NativeDatabase.memory());
      final source = await CohabitRepository.open(sourceDb, now: () => now);
      habitId = await source.createHabit(
        name: 'Walk outside',
        polarity: HabitPolarity.positive,
        schedule: {1, 2, 3, 4, 5, 6, 7},
      );
      await source.setDayState(habitId, HabitDay.fromDate(now), DayState.done);
      await source.setDayBoundaryMinutes(240);
      backup = await source.exportBackup();
      await source.close();
      db = AppDatabase(NativeDatabase.memory());
      repo = await CohabitRepository.open(db, now: () => now);
    });
    files.input = backup;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          backupFilesProvider.overrideWithValue(files),
          nowProvider.overrideWithValue(() => now),
        ],
        child: const CohabitApp(initialSection: Section.settings),
      ),
    );
    await drain(tester);
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 150);
    } else {
      await tester.ensureVisible(finder);
    }
    await tester.tap(finder);
    await drain(tester);
  }

  void verify(
    String name,
    Future<void> Function(WidgetTester) body, {
    TestVariant<dynamic>? variant,
  }) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(repo.close);
      }
    }, variant: variant ?? TargetPlatformVariant.only(TargetPlatform.android));
  }

  verify('restore preview cancels without writes and confirms merge', (
    tester,
  ) async {
    await start(tester);
    await tap(tester, 'Restore backup');
    expect(find.textContaining('1 habits · 1 day logs'), findsOneWidget);
    await tap(tester, 'cancel-restore');
    expect(await tester.runAsync(repo.events), isEmpty);
    await tap(tester, 'Restore backup');
    await tap(tester, 'confirm-restore');
    await tester.scrollUntilVisible(
      find.textContaining('Restore complete.'),
      100,
    );
    expect(find.textContaining('Restore complete.'), findsOneWidget);
    expect(await tester.runAsync(repo.dayBoundaryMinutes), 180);
    final before = await tester.runAsync(repo.events);
    await tap(tester, 'Restore backup');
    expect(find.textContaining('0 new events · 2 duplicates'), findsOneWidget);
    await tap(tester, 'restore-boundary');
    await tap(tester, 'confirm-restore');
    expect(await tester.runAsync(repo.dayBoundaryMinutes), 240);
    expect((await tester.runAsync(repo.events))!.length, before!.length);
  });

  verify('restore refreshes habit state and day boundary providers', (
    tester,
  ) async {
    await start(tester);
    final scope = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final habits = scope.listen(habitsProvider, (_, _) {});
    final states = scope.listen(
      dayStatesProvider(HabitDay.fromDate(now)),
      (_, _) {},
    );

    await drain(tester);
    expect(habits.read().value, isEmpty);
    await tap(tester, 'Restore backup');
    await tap(tester, 'restore-boundary');
    await tap(tester, 'confirm-restore');
    expect(habits.read().value!.single.name, 'Walk outside');
    expect(states.read().value![habitId]!.state, DayState.done);
    expect(scope.read(dayBoundaryProvider).value, 240);
    await tester.tap(find.text('Today').last);
    await drain(tester);
    expect(find.text('Walk outside'), findsOneWidget);
    await tester.tap(find.text('History').last);
    await drain(tester);
    expect(find.text('Walk outside'), findsOneWidget);
    habits.close();
    states.close();
    expect(tester.takeException(), isNull);
  });

  verify('busy operations ignore repeat taps and recover after errors', (
    tester,
  ) async {
    await start(tester);
    files.pendingSave = Completer<bool>();
    await tap(tester, 'Save backup (JSON)');
    expect(files.saves, 1);
    for (final label in [
      'Save backup (JSON)',
      'Export CSV',
      'Restore backup',
    ]) {
      expect(
        tester.widget<CohabitButton>(find.byKey(ValueKey(label))).onPressed,
        isNull,
      );
    }
    await tap(tester, 'Save backup (JSON)');
    expect(files.saves, 1);
    files.pendingSave!.complete(false);
    await drain(tester);
    expect(find.text('File saved.'), findsNothing);
    files.pendingSave = null;
    files.saveError = StateError('/private/path secret');
    await tap(tester, 'Export CSV');
    await tester.scrollUntilVisible(
      find.textContaining('Could not complete'),
      100,
    );
    expect(find.textContaining('Could not complete'), findsOneWidget);
    expect(find.textContaining('/private/path'), findsNothing);
    files.openError = StateError('read failed');
    await tap(tester, 'Restore backup');
    await tester.scrollUntilVisible(
      find.textContaining('Could not complete'),
      100,
    );
    expect(find.textContaining('Could not complete'), findsOneWidget);
    files.openError = null;
    files.pendingOpen = Completer<String?>();
    await tap(tester, 'Restore backup');
    final opens = files.opens;
    await tap(tester, 'Restore backup');
    expect(files.opens, opens);
    files.pendingOpen!.complete(null);
    await drain(tester);
    expect(find.byKey(const ValueKey('restore-preview')), findsNothing);
    expect(
      tester
          .widget<CohabitButton>(find.byKey(const ValueKey('Restore backup')))
          .onPressed,
      isNotNull,
    );
  });

  verify('clock and revalidation errors retain existing data', (tester) async {
    await start(tester);
    final future = jsonDecode(backup) as Map<String, dynamic>;
    final wall = now
        .add(const Duration(hours: 1))
        .millisecondsSinceEpoch
        .toRadixString(16)
        .padLeft(12, '0');
    future['events'][0]['hlc'] = '$wall-0000';
    files.input = jsonEncode(future);
    await tap(tester, 'Restore backup');
    expect(
      find.textContaining('Check your device date and time'),
      findsOneWidget,
    );
    expect(await tester.runAsync(repo.events), isEmpty);
    files.input = backup;
    await tap(tester, 'Restore backup');
    final conflicting = jsonDecode(backup) as Map<String, dynamic>;
    conflicting['events'][0]['payload']['name'] = 'Local changed name';
    await tester.runAsync(() => repo.restoreBackup(jsonEncode(conflicting)));
    await tap(tester, 'confirm-restore');
    await tester.scrollUntilVisible(
      find.textContaining('not a supported Cohabit backup'),
      100,
    );
    expect(
      find.textContaining('not a supported Cohabit backup'),
      findsOneWidget,
    );
    expect(
      (await tester.runAsync(() => repo.habit(habitId)))!.name,
      'Local changed name',
    );
    expect(await tester.runAsync(repo.dayBoundaryMinutes), 180);
  });

  verify('rotating with the preview open still restores', (tester) async {
    await start(tester, height: 800, width: 360);
    await tap(tester, 'Restore backup');
    tester.view.physicalSize = const Size(1200, 800);
    await drain(tester);
    await tap(tester, 'confirm-restore');
    expect(await tester.runAsync(repo.events), isNotEmpty);
    expect(find.textContaining('Restore complete.'), findsOneWidget);
  });

  for (final width in [320.0, 360.0, 1200.0]) {
    verify(
      'preview and feedback fit ${width.toInt()}px at double text size',
      (tester) async {
        await start(tester, width: width);
        await tap(tester, 'Restore backup');
        expect(find.byKey(const ValueKey('restore-preview')), findsOneWidget);
        await tap(tester, 'restore-boundary');
        await tap(tester, 'confirm-restore');
        await tester.scrollUntilVisible(
          find.textContaining('Restore complete.'),
          100,
        );
        expect(find.textContaining('Restore complete.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        files.input = 'invalid';
        await tap(tester, 'Restore backup');
        expect(find.textContaining('not a supported'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(
        width > 1000 ? TargetPlatform.macOS : TargetPlatform.android,
      ),
    );
  }
}
