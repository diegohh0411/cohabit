import 'package:cohabit/app.dart';
import 'package:cohabit/data/database.dart';
import 'package:cohabit/data/repository.dart';
import 'package:cohabit/domain/day_state.dart';
import 'package:cohabit/domain/habit_day.dart';
import 'package:cohabit/state/providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sunday 1 Nov 2026, 10:00 local: habit day is 2026-11-01.
final _now = DateTime(2026, 11, 1, 10, 0);
final _today = HabitDay(2026, 11, 1);
final _yesterday = HabitDay(2026, 10, 31);

void main() {
  late AppDatabase db;
  late CohabitRepository repo;

  /// Real SQLite needs real async, so repository calls run in `runAsync`.
  Future<T> db_<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  Future<void> settle(WidgetTester tester) async {
    // Provider chains (boundary -> today -> day states) take several rounds
    // of real async work to reach the widgets.
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  Future<void> start(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          nowProvider.overrideWithValue(() => _now),
          dayTickProvider.overrideWithValue(const Duration(days: 1)),
        ],
        child: const CohabitApp(),
      ),
    );
    await settle(tester);
  }

  /// testWidgets runs in a fake-async zone, so the real database is opened
  /// and closed inside runAsync.
  Future<void> open(WidgetTester tester) async {
    await db_(tester, () async {
      db = AppDatabase(NativeDatabase.memory());
      repo = await CohabitRepository.open(db, now: () => _now);
    });
    addTearDown(() => tester.runAsync(() => db.close()));
  }

  /// Creates a habit as if it had been made a month ago, so yesterday counts
  /// for it in the review prompt.
  Future<String> createOldHabit(WidgetTester tester, String name) =>
      db_(tester, () async {
        final earlier = await CohabitRepository.open(
          db,
          now: () => DateTime(2026, 10, 1, 10, 0),
        );
        return earlier.createHabit(
          name: name,
          polarity: HabitPolarity.positive,
          schedule: everyDayForTests,
        );
      });

  /// Unmounts the app and flushes the timers that Riverpod and drift leave
  /// behind on disposal, so the test ends with none pending.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('one tap logs a positive habit; tapping again clears it', (
    tester,
  ) async {
    await open(tester);
    final id = await db_(
      tester,
      () => repo.createHabit(
        name: 'Stretch',
        polarity: HabitPolarity.positive,
        schedule: everyDayForTests,
      ),
    );
    await start(tester);

    expect(find.text('Stretch'), findsOneWidget);
    expect(find.text('Not logged'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('$id-done')));
    await settle(tester);
    expect(find.text('Done'), findsNWidgets(2)); // status label + button
    expect(
      (await db_(tester, () => repo.dayStates(_today)))[id]!.state,
      DayState.done,
    );

    await tester.tap(find.byKey(ValueKey('$id-done')));
    await settle(tester);
    expect(find.text('Not logged'), findsOneWidget);
    expect(
      (await db_(tester, () => repo.dayStates(_today)))[id]!.state,
      DayState.unknown,
    );
    await finish(tester);
  });

  testWidgets('negative habit: record a slip, or confirm a clean day', (
    tester,
  ) async {
    await open(tester);
    final id = await db_(
      tester,
      () => repo.createHabit(
        name: 'Doomscroll',
        polarity: HabitPolarity.negative,
        schedule: everyDayForTests,
      ),
    );
    await start(tester);

    expect(find.byKey(ValueKey('$id-done')), findsOneWidget);
    expect(find.text('Slipped'), findsOneWidget);
    expect(find.text('Clean day'), findsOneWidget);
    // Nothing is assumed clean until confirmed.
    expect(find.text('Not logged'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('$id-notDone')));
    await settle(tester);
    var entry = (await db_(tester, () => repo.dayStates(_today)))[id]!;
    expect(entry.state, DayState.notDone); // clean day

    await tester.tap(find.byKey(ValueKey('$id-done')));
    await settle(tester);
    entry = (await db_(tester, () => repo.dayStates(_today)))[id]!;
    expect(entry.state, DayState.done); // slip
    expect(entry.source, EventSource.manual);
    await finish(tester);
  });

  testWidgets('today only lists habits scheduled for today', (tester) async {
    await open(tester);
    await db_(tester, () async {
      await repo.createHabit(
        name: 'Sunday run',
        polarity: HabitPolarity.positive,
        schedule: {DateTime.sunday},
      );
      await repo.createHabit(
        name: 'Monday gym',
        polarity: HabitPolarity.positive,
        schedule: {DateTime.monday},
      );
    });
    await start(tester);
    expect(find.text('Sunday run'), findsOneWidget);
    expect(find.text('Monday gym'), findsNothing);
    await finish(tester);
  });

  testWidgets('yesterday review prompt lists unresolved habits and opens '
      'that day', (tester) async {
    await open(tester);
    final id = await createOldHabit(tester, 'Read');
    await start(tester);

    expect(find.byKey(const ValueKey('yesterday-review')), findsOneWidget);
    expect(find.text('Yesterday: 1 habit not logged'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('review-yesterday')));
    await tester.pumpAndSettle();
    expect(find.text('Sat 31 Oct 2026'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('$id-done')));
    await settle(tester);
    expect(
      (await db_(tester, () => repo.dayStates(_yesterday)))[id]!.state,
      DayState.done,
    );
    // Today is untouched.
    expect(await db_(tester, () => repo.dayStates(_today)), isEmpty);

    await tester.pageBack();
    await settle(tester);
    expect(find.byKey(const ValueKey('yesterday-review')), findsNothing);
    await finish(tester);
  });

  testWidgets('review prompt can be dismissed without logging anything', (
    tester,
  ) async {
    await open(tester);
    await createOldHabit(tester, 'Read');
    await start(tester);

    await tester.tap(find.byKey(const ValueKey('dismiss-review')));
    await tester.pump();
    expect(find.byKey(const ValueKey('yesterday-review')), findsNothing);
    expect(await db_(tester, () => repo.dayStates(_yesterday)), isEmpty);
    await finish(tester);
  });

  testWidgets('a habit created today is not offered for yesterday review', (
    tester,
  ) async {
    await open(tester);
    await db_(
      tester,
      () => repo.createHabit(
        name: 'New',
        polarity: HabitPolarity.positive,
        schedule: everyDayForTests,
      ),
    );
    await start(tester);
    expect(find.byKey(const ValueKey('yesterday-review')), findsNothing);
    await finish(tester);
  });

  testWidgets('day view backfills a past day and navigates back and forward', (
    tester,
  ) async {
    await open(tester);
    final id = await db_(
      tester,
      () => repo.createHabit(
        name: 'Run',
        polarity: HabitPolarity.positive,
        schedule: everyDayForTests,
      ),
    );
    await start(tester);

    await tester.tap(find.byTooltip('Day view'));
    await tester.pumpAndSettle();
    expect(find.text('Sun 1 Nov 2026'), findsOneWidget);
    // Cannot go past today.
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.chevron_right),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byTooltip('Previous day'));
    await settle(tester);
    await tester.tap(find.byTooltip('Previous day'));
    await settle(tester);
    expect(find.text('Fri 30 Oct 2026'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('$id-notDone')));
    await settle(tester);
    final past = HabitDay(2026, 10, 30);
    expect(
      (await db_(tester, () => repo.dayStates(past)))[id]!.state,
      DayState.notDone,
    );

    // Edit the same past day again.
    await tester.tap(find.byKey(ValueKey('$id-done')));
    await settle(tester);
    expect(
      (await db_(tester, () => repo.dayStates(past)))[id]!.state,
      DayState.done,
    );
    await finish(tester);
  });

  testWidgets('create, edit and archive a habit through the forms', (
    tester,
  ) async {
    await open(tester);
    await start(tester);
    expect(find.text('No habits yet. Add one to start.'), findsOneWidget);

    await tester.tap(find.text('Add habit'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('save-habit')))
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const ValueKey('habit-name')),
      'Meditate',
    );
    await tester.tap(find.text('Avoid'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('weekday-6')));
    await tester.tap(find.byKey(const ValueKey('weekday-7')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-habit')));
    await settle(tester);
    await tester.pumpAndSettle();

    final habits = await db_(tester, () => repo.habits());
    expect(habits, hasLength(1));
    final habit = habits.single;
    expect(habit.name, 'Meditate');
    expect(habit.polarity, HabitPolarity.negative);
    expect(habit.schedule, {1, 2, 3, 4, 5});
    // Sunday is unscheduled, so it is not on today's list.
    expect(find.text('Nothing scheduled today.'), findsOneWidget);

    await tester.tap(find.byTooltip('Habits'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('habit-${habit.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('habit-name')),
      'Meditate daily',
    );
    await tester.tap(find.byKey(const ValueKey('weekday-7')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-habit')));
    await settle(tester);
    await tester.pumpAndSettle();
    final edited = (await db_(tester, () => repo.habit(habit.id)))!;
    expect(edited.name, 'Meditate daily');
    expect(edited.schedule, {1, 2, 3, 4, 5, 7});

    await tester.tap(find.byKey(ValueKey('habit-${habit.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('archive-habit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-archive')));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(await db_(tester, () => repo.habits()), isEmpty);
    expect((await db_(tester, () => repo.habit(habit.id)))!.isArchived, isTrue);
    await finish(tester);
  });

  testWidgets('day boundary setting changes the current habit day', (
    tester,
  ) async {
    await open(tester);
    await db_(tester, () => repo.setDayBoundaryMinutes(11 * 60));
    await start(tester);
    // 10:00 is before an 11:00 boundary, so it is still Saturday.
    expect(find.text('Sat 31 Oct 2026'), findsOneWidget);
    await finish(tester);
  });
}

const everyDayForTests = {1, 2, 3, 4, 5, 6, 7};
