import 'package:cohabit/app.dart';
import 'package:cohabit/data/database.dart';
import 'package:cohabit/data/repository.dart';
import 'package:cohabit/design/segmented_log_control.dart';
import 'package:cohabit/domain/day_state.dart';
import 'package:cohabit/domain/habit_day.dart';
import 'package:cohabit/graph/graph_painter.dart';
import 'package:cohabit/state/providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sunday 1 Nov 2026, 10:00 local.
final _now = DateTime(2026, 11, 1, 10, 0);
const _every = {1, 2, 3, 4, 5, 6, 7};

void main() {
  late AppDatabase db;
  late CohabitRepository repo;

  Future<T> run<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  Future<void> open(WidgetTester tester) async {
    await run(tester, () async {
      db = AppDatabase(NativeDatabase.memory());
      repo = await CohabitRepository.open(db, now: () => _now);
    });
    addTearDown(() => tester.runAsync(() => db.close()));
  }

  Future<void> start(
    WidgetTester tester, {
    ThemeMode themeMode = ThemeMode.dark,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          nowProvider.overrideWithValue(() => _now),
          dayTickProvider.overrideWithValue(const Duration(days: 1)),
        ],
        child: CohabitApp(themeMode: themeMode),
      ),
    );
    await settle(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));
  }

  /// Habit created a month ago, so its graph has history.
  Future<String> oldHabit(
    WidgetTester tester,
    String name, {
    HabitPolarity polarity = HabitPolarity.positive,
    Set<int> schedule = _every,
  }) => run(tester, () async {
    final earlier = await CohabitRepository.open(
      db,
      now: () => DateTime(2026, 10, 1, 10, 0),
    );
    return earlier.createHabit(
      name: name,
      polarity: polarity,
      schedule: schedule,
    );
  });

  Future<void> onPlatform(
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Finder sectionItem(String label) =>
      find.widgetWithText(GestureDetector, label);

  double controlHeight(WidgetTester tester) =>
      tester.getSize(find.byType(SegmentedLogControl<DayState>).first).height;

  group('Android: bottom bar and touch sizes', () {
    testWidgets('bottom bar switches sections; log control is 44px high', (
      tester,
    ) async {
      await open(tester);
      await oldHabit(tester, 'Read');
      await start(tester);

      for (final label in ['Today', 'History', 'Habits', 'Settings']) {
        expect(sectionItem(label), findsOneWidget, reason: label);
      }
      expect(find.text('Cohabit'), findsNothing, reason: 'no sidebar');
      expect(controlHeight(tester), 44);

      await tester.tap(sectionItem('History'));
      await settle(tester);
      expect(find.text('OVERVIEW'), findsOneWidget);

      await tester.tap(sectionItem('Habits'));
      await settle(tester);
      expect(find.text('ACTIVE'), findsOneWidget);

      await tester.tap(sectionItem('Settings'));
      await settle(tester);
      expect(find.text('Day starts at'.toUpperCase()), findsOneWidget);
      await finish(tester);
    });

    testWidgets('detail pages cover the bottom bar and go back', (
      tester,
    ) async {
      await open(tester);
      await oldHabit(tester, 'Read');
      await start(tester);
      await tester.tap(find.text('Day view'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('day-title')), findsOneWidget);
      expect(sectionItem('History'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('back')));
      await tester.pumpAndSettle();
      expect(sectionItem('History'), findsOneWidget);
      await finish(tester);
    });
  });

  group('macOS: sidebar, hover and keyboard', () {
    testWidgets('sidebar replaces the bottom bar; log control is 30px high', (
      tester,
    ) async {
      await onPlatform(TargetPlatform.macOS, () async {
        tester.view.physicalSize = const Size(1100, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await open(tester);
        final id = await oldHabit(tester, 'Read');
        await start(tester);

        expect(find.text('Cohabit'), findsOneWidget);
        for (final hint in ['⌘1', '⌘2', '⌘3', '⌘4']) {
          expect(find.text(hint), findsOneWidget);
        }
        expect(controlHeight(tester), 30);
        // The control sits beside the name at this width.
        expect(
          tester.getTopLeft(find.byType(SegmentedLogControl<DayState>)).dy,
          lessThan(
            tester
                    .getBottomLeft(
                      find.descendant(
                        of: find.byKey(ValueKey('today-$id')),
                        matching: find.text('Read'),
                      ),
                    )
                    .dy +
                20,
          ),
        );
        await finish(tester);
      });
    });

    testWidgets('command-number shortcuts switch sections', (tester) async {
      await onPlatform(TargetPlatform.macOS, () async {
        tester.view.physicalSize = const Size(1100, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await open(tester);
        await oldHabit(tester, 'Read');
        await start(tester);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
        await settle(tester);
        expect(find.text('OVERVIEW'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
        await settle(tester);
        expect(find.text('DAY STARTS AT'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
        await settle(tester);
        expect(find.text('Scheduled today · 1'.toUpperCase()), findsOneWidget);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await finish(tester);
      });
    });

    testWidgets('command-N adds a habit beside the sidebar; Escape goes back', (
      tester,
    ) async {
      await onPlatform(TargetPlatform.macOS, () async {
        tester.view.physicalSize = const Size(1100, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await open(tester);
        await start(tester);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();
        expect(find.text('New habit'), findsOneWidget);
        expect(find.text('Cohabit'), findsOneWidget, reason: 'sidebar stays');

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('New habit'), findsNothing);
        await finish(tester);
      });
    });

    testWidgets('detail pages open beside the sidebar', (tester) async {
      await onPlatform(TargetPlatform.macOS, () async {
        tester.view.physicalSize = const Size(1100, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await open(tester);
        await oldHabit(tester, 'Read');
        await start(tester);
        await tester.tap(find.text('Day view'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('day-title')), findsOneWidget);
        expect(find.text('Cohabit'), findsOneWidget);
        await finish(tester);
      });
    });

    testWidgets('light and dark both render the shell', (tester) async {
      await onPlatform(TargetPlatform.macOS, () async {
        tester.view.physicalSize = const Size(1100, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await open(tester);
        await oldHabit(tester, 'Read');
        for (final mode in [ThemeMode.light, ThemeMode.dark]) {
          await start(tester, themeMode: mode);
          expect(find.text('Read'), findsWidgets);
          await finish(tester);
        }
      });
    });
  });

  group('history, backfill and compare', () {
    Finder canvases() => find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is CommitGraphPainter,
    );

    testWidgets('history shows the overview then a graph per habit', (
      tester,
    ) async {
      await open(tester);
      await oldHabit(tester, 'Read');
      await oldHabit(tester, 'Doomscrolling', polarity: HabitPolarity.negative);
      await start(tester);
      await tester.tap(sectionItem('History'));
      await settle(tester);

      expect(canvases(), findsNWidgets(3)); // overview + two habits
      expect(find.text('Less'), findsOneWidget); // overview legend
      expect(find.text('Done or clean'), findsNWidgets(2));
      await finish(tester);
    });

    testWidgets('tapping a cell opens that day for backfill', (tester) async {
      await open(tester);
      final id = await oldHabit(tester, 'Read');
      await start(tester);
      await tester.tap(sectionItem('History'));
      await settle(tester);

      // Second canvas is Read's graph; tap Fri 30 Oct.
      final canvas = canvases().at(1);
      final painter =
          tester.widget<CustomPaint>(canvas).painter! as CommitGraphPainter;
      final range = painter.series.range;
      final cell =
          tester.getTopLeft(canvas) +
          GraphMetrics.originOf(range, range.indexOf(HabitDay(2026, 10, 30))) +
          const Offset(5, 5);
      await tester.tapAt(cell);
      await tester.pumpAndSettle();
      expect(find.text('Fri 30 Oct 2026'), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('$id-done')));
      await settle(tester);
      expect(
        (await run(
          tester,
          () => repo.dayStates(HabitDay(2026, 10, 30)),
        ))[id]!.state,
        DayState.done,
      );

      // Back on the graph, the cell is now filled.
      await tester.tap(find.byKey(const ValueKey('back')));
      await settle(tester);
      final after =
          tester.widget<CustomPaint>(canvases().at(1)).painter!
              as CommitGraphPainter;
      expect(after.series.styleOf(HabitDay(2026, 10, 30)), isNotNull);
      expect(after.series.describe(HabitDay(2026, 10, 30)), 'Done');
      await finish(tester);
    });

    testWidgets('compare stacks two habits; one habit explains itself', (
      tester,
    ) async {
      await open(tester);
      await oldHabit(tester, 'Read');
      await start(tester);
      await tester.tap(sectionItem('History'));
      await settle(tester);
      await tester.tap(find.text('Compare'));
      await tester.pumpAndSettle();
      expect(find.text('Add at least two habits to compare them.'), findsOne);
      await tester.tap(find.byKey(const ValueKey('back')));
      await tester.pumpAndSettle();
      await finish(tester);

      await run(
        tester,
        () => repo.createHabit(
          name: 'Gym',
          polarity: HabitPolarity.positive,
          schedule: _every,
        ),
      );
      await start(tester);
      await tester.tap(sectionItem('History'));
      await settle(tester);
      await tester.tap(find.text('Compare'));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(canvases(), findsNWidgets(2));
      expect(find.text('Top graph'.toUpperCase()), findsOneWidget);
      final a = tester.getRect(canvases().at(0));
      final b = tester.getRect(canvases().at(1));
      expect(a.left, b.left);
      expect(a.width, b.width);
      await finish(tester);
    });
  });

  group('schedule edits leave the past alone', () {
    testWidgets('a past unlogged day keeps the schedule it had', (
      tester,
    ) async {
      await open(tester);
      // Daily since a month ago.
      final id = await oldHabit(tester, 'Run');
      // Today (a Sunday) the schedule becomes weekdays only.
      await run(tester, () => repo.editHabit(id, schedule: {1, 2, 3, 4, 5}));
      await start(tester);

      // Today is no longer a scheduled day.
      expect(find.text('Nothing scheduled today.'), findsOneWidget);

      // Saturday and Sunday last week were scheduled when they happened.
      await tester.tap(find.text('Day view'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('previous-day')));
      await settle(tester); // Sat 31 Oct
      expect(find.text('Sat 31 Oct 2026'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(ValueKey('status-$id'))).data,
        endsWith('Not logged'),
      );
      await finish(tester);
    });

    testWidgets('the edit form says when a schedule starts to apply', (
      tester,
    ) async {
      await open(tester);
      await oldHabit(tester, 'Run');
      await start(tester);
      await tester.tap(sectionItem('Habits'));
      await settle(tester);
      await tester.tap(find.text('Run'));
      await tester.pumpAndSettle();
      expect(find.textContaining('applies from today'), findsOneWidget);
      await finish(tester);
    });
  });
}
