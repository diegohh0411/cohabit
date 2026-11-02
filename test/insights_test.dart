import 'dart:async';

import 'package:cohabit/app.dart';
import 'package:cohabit/data/database.dart';
import 'package:cohabit/data/repository.dart';
import 'package:cohabit/design/insight_card.dart';
import 'package:cohabit/domain/day_state.dart';
import 'package:cohabit/domain/habit_day.dart';
import 'package:cohabit/state/analysis_providers.dart';
import 'package:cohabit/state/providers.dart';
import 'package:cohabit/ui/app_shell.dart';
import 'package:cohabit_analysis/cohabit_analysis.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sunday 1 Nov 2026, 10:00 local.
final _now = DateTime(2026, 11, 1, 10, 0);
final _today = HabitDay(2026, 11, 1);
const _every = {1, 2, 3, 4, 5, 6, 7};

/// Deterministic coin flips (xorshift32).
class _Rng {
  _Rng(this._s);
  int _s;
  double next() {
    _s ^= (_s << 13) & 0xFFFFFFFF;
    _s ^= _s >> 17;
    _s ^= (_s << 5) & 0xFFFFFFFF;
    _s &= 0xFFFFFFFF;
    return _s / 0x100000000;
  }
}

void main() {
  late AppDatabase db;
  late CohabitRepository repo;

  Future<T> run<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
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

  Future<String> habit(
    WidgetTester tester,
    String name, {
    HabitPolarity polarity = HabitPolarity.positive,
    Set<int> schedule = _every,
  }) => run(tester, () async {
    final earlier = await CohabitRepository.open(
      db,
      now: () => DateTime(2026, 7, 1, 10, 0),
    );
    return earlier.createHabit(
      name: name,
      polarity: polarity,
      schedule: schedule,
    );
  });

  /// Logs [values] (1 done, 0 not done, null left alone) ending the day
  /// before [end]; the first value is the oldest day.
  Future<void> log(
    WidgetTester tester,
    String id,
    List<int?> values, {
    HabitDay? end,
  }) => run(tester, () async {
    final last = (end ?? _today).addDays(-1);
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) continue;
      await repo.setDayState(
        id,
        last.addDays(i - (values.length - 1)),
        v == 1 ? DayState.done : DayState.notDone,
      );
    }
  });

  List<int> coin(int seed, int n) {
    final r = _Rng(seed);
    return [for (var i = 0; i < n; i++) r.next() < 0.5 ? 1 : 0];
  }

  List<int> copy(List<int> a, int seed, double keep) {
    final r = _Rng(seed);
    return [for (final v in a) r.next() < keep ? v : 1 - v];
  }

  /// The day after [a] drives [b]: done after a done day 85% of the time.
  List<int> follow(List<int> a, int seed) {
    final r = _Rng(seed);
    return [
      for (var i = 0; i < a.length; i++)
        r.next() < (i > 0 && a[i - 1] == 1 ? 0.85 : 0.15) ? 1 : 0,
    ];
  }

  late List<AnalysisInput> inputs;
  late List<Completer<AnalysisResult>> pending;

  Future<void> start(
    WidgetTester tester, {
    ThemeMode themeMode = ThemeMode.dark,
    Section section = Section.insights,
    AnalysisRunner? runner,
  }) async {
    inputs = [];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          nowProvider.overrideWithValue(() => _now),
          dayTickProvider.overrideWithValue(const Duration(days: 1)),
          analysisDebounceProvider.overrideWithValue(Duration.zero),
          analysisRunnerProvider.overrideWithValue(
            runner ??
                (input) async {
                  inputs.add(input);
                  return analyze(input);
                },
          ),
        ],
        child: CohabitApp(themeMode: themeMode, initialSection: section),
      ),
    );
    await settle(tester);
  }

  /// Completes every analysis still waiting. Runs started by early
  /// intermediate states are superseded, so only the latest one shows.
  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < pending.length; i++) {
      if (!pending[i].isCompleted) pending[i].complete(analyze(inputs[i]));
    }
    await settle(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  void phone(WidgetTester tester, {double width = 360, double scale = 1}) {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  /// Sleep and Gym done together on 90 days, 90% of the time.
  Future<(String, String)> togetherHabits(WidgetTester tester) async {
    final sleep = await habit(tester, 'Sleep');
    final gym = await habit(tester, 'Gym');
    final a = coin(11, 90);
    await log(tester, sleep, a);
    await log(tester, gym, copy(a, 12, 0.9));
    return (sleep, gym);
  }

  List<String> cardTexts(WidgetTester tester) => [
    for (final card in tester.widgetList<InsightCard>(find.byType(InsightCard)))
      card.sentence,
  ];

  group('empty states', () {
    testWidgets('one habit explains what insights need', (tester) async {
      phone(tester);
      await open(tester);
      await habit(tester, 'Sleep');
      await start(tester);

      expect(find.text('Insights compare habits'), findsOneWidget);
      expect(find.textContaining('Add a second habit'), findsOneWidget);
      expect(find.byType(InsightCard), findsNothing);
      expect(find.text('All pairs'), findsNothing);
      expect(inputs, isEmpty, reason: 'nothing to analyse yet');
      await finish(tester);
    });

    testWidgets('under 30 shared days is said plainly, with the count', (
      tester,
    ) async {
      phone(tester);
      await open(tester);
      final a = await habit(tester, 'Sleep');
      final b = await habit(tester, 'Gym');
      await log(tester, a, coin(1, 22));
      await log(tester, b, coin(2, 22));
      await start(tester);

      expect(find.text('Not enough data yet'), findsOneWidget);
      expect(find.textContaining('at least 30 days'), findsOneWidget);
      expect(find.textContaining('closest pair has 22 so far'), findsOneWidget);
      expect(find.byType(InsightCard), findsNothing);
      await finish(tester);
    });

    testWidgets('unlogged days never count as not done', (tester) async {
      phone(tester);
      await open(tester);
      final a = await habit(tester, 'Sleep');
      final b = await habit(tester, 'Gym');
      // 40 days each, but only 12 of them logged for both.
      await log(tester, a, coin(1, 40));
      await log(tester, b, [
        for (var i = 0; i < 40; i++) i % 40 >= 28 ? coin(2, 40)[i] : null,
      ]);
      await start(tester);

      expect(find.textContaining('closest pair has 12 so far'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('enough data but no pattern says so, without blame', (
      tester,
    ) async {
      phone(tester);
      await open(tester);
      final a = await habit(tester, 'Sleep');
      final b = await habit(tester, 'Gym');
      await log(tester, a, coin(21, 90));
      await log(tester, b, coin(22, 90));
      await start(tester);

      expect(find.text('Nothing stands out yet'), findsOneWidget);
      expect(find.textContaining('normal result'), findsOneWidget);
      expect(find.byType(InsightCard), findsNothing);
      expect(find.byKey(const ValueKey('insights-footer')), findsOneWidget);
      await finish(tester);
    });
  });

  group('findings', () {
    testWidgets('a same-day link reads as a plain sentence with its numbers', (
      tester,
    ) async {
      phone(tester);
      await open(tester);
      final (sleep, gym) = await togetherHabits(tester);
      await start(tester);

      final card = find.byKey(ValueKey('insight-$sleep-$gym-0'));
      expect(card, findsOneWidget);
      final widget = tester.widget<InsightCard>(card);
      expect(widget.sentence, 'Sleep tends to go with Gym on the same day.');
      // `Sleep & Gym  3.8x  n=90  CI 2.7-5.4  phi +0.78`
      expect(
        widget.stats.join('  '),
        matches(
          RegExp(
            r'^Sleep & Gym  \d+(\.\d+)?x  n=\d+  CI \d+(\.\d+)?-\d+(\.\d+)?  '
            r'phi \+0\.\d\d$',
          ),
        ),
      );
      // The statistics line is visible text, not just a label.
      expect(find.text(widget.stats.join('  ')), findsOneWidget);
      expect(
        find.textContaining('Patterns in what you logged'),
        findsOneWidget,
      );
      await finish(tester);
    });

    testWidgets('wording never claims a cause', (tester) async {
      phone(tester);
      await open(tester);
      await togetherHabits(tester);
      await start(tester);

      final sentences = cardTexts(tester);
      expect(sentences, isNotEmpty);
      for (final s in sentences) {
        expect(s, contains('tends to go with'));
        expect(
          s.toLowerCase(),
          isNot(matches(RegExp('caus|lead|because|makes'))),
        );
      }
      await finish(tester);
    });

    testWidgets('a lagged link names the earlier habit and the delay', (
      tester,
    ) async {
      phone(tester);
      await open(tester);
      final sleep = await habit(tester, 'Sleep');
      final read = await habit(tester, 'Read');
      final a = coin(31, 120);
      await log(tester, sleep, a);
      await log(tester, read, follow(a, 32));
      await start(tester);

      final card = find.byKey(ValueKey('insight-$sleep-$read-1'));
      expect(card, findsOneWidget);
      final widget = tester.widget<InsightCard>(card);
      expect(widget.sentence, 'Sleep tends to go with Read the next day.');
      expect(widget.stats.take(2), ['Sleep -> Read', '+1d']);
      // The reverse direction is not reported.
      expect(find.byKey(ValueKey('insight-$read-$sleep-1')), findsNothing);
      await finish(tester);
    });

    testWidgets('an opposing link says "less" and a ratio below 1', (
      tester,
    ) async {
      phone(tester);
      await open(tester);
      final a = await habit(tester, 'Early start');
      final b = await habit(tester, 'Snooze');
      final x = coin(41, 90);
      await log(tester, a, x);
      await log(tester, b, copy(x, 42, 0.12));
      await start(tester);

      final texts = cardTexts(tester);
      expect(
        texts,
        contains('Early start tends to go with less Snooze on the same day.'),
      );
      final stats = tester
          .widgetList<InsightCard>(find.byType(InsightCard))
          .first
          .stats;
      expect(stats[1], matches(RegExp(r'^0\.\d+x$')));
      await finish(tester);
    });

    testWidgets('screen readers get spoken numbers, not symbols', (
      tester,
    ) async {
      phone(tester);
      final handle = tester.ensureSemantics();
      await open(tester);
      await togetherHabits(tester);
      await start(tester);

      final label = tester.getSemantics(find.byType(InsightCard).first).label;
      expect(label, contains('tends to go with'));
      expect(label, contains('times as likely'));
      expect(label, contains('95 percent confidence interval'));
      expect(label, contains('days compared'));
      expect(label, isNot(contains('->')));
      expect(label, isNot(contains('CI ')));
      handle.dispose();
      await finish(tester);
    });
  });

  group('running in the background and refreshing', () {
    testWidgets('the UI stays usable while the analysis is running', (
      tester,
    ) async {
      phone(tester);
      await open(tester);
      final (sleep, gym) = await togetherHabits(tester);
      pending = [];
      await start(
        tester,
        runner: (input) {
          inputs.add(input);
          final c = Completer<AnalysisResult>();
          pending.add(c);
          return c.future;
        },
      );

      expect(find.text('Analysing your logs'), findsOneWidget);
      expect(pending, isNotEmpty);
      // Still responsive: switch to Today and back while it runs.
      await tester.tap(find.widgetWithText(GestureDetector, 'Today'));
      await settle(tester);
      expect(find.textContaining('SCHEDULED TODAY'), findsOneWidget);
      await tester.tap(find.widgetWithText(GestureDetector, 'Insights'));
      await settle(tester);
      expect(find.text('Analysing your logs'), findsOneWidget);

      await drain(tester);
      expect(find.text('Analysing your logs'), findsNothing);
      expect(find.byKey(ValueKey('insight-$sleep-$gym-0')), findsOneWidget);
      await finish(tester);
    });

    testWidgets('the default runner uses an isolate and agrees with analyze', (
      tester,
    ) async {
      final input = AnalysisInput(
        startEpochDay: 20731,
        series: [
          HabitSeries(id: 'a', values: coin(5, 80)),
          HabitSeries(id: 'b', values: coin(6, 80)),
        ],
      );
      final viaIsolate = await run(tester, () => runInIsolate(input));
      final direct = analyze(input);
      expect(viaIsolate.pairs.length, direct.pairs.length);
      for (var i = 0; i < direct.pairs.length; i++) {
        expect(viaIsolate.pairs[i].phi, direct.pairs[i].phi);
        expect(viaIsolate.pairs[i].q, direct.pairs[i].q);
      }
    });

    testWidgets('changing a log re-runs the analysis and updates the screen', (
      tester,
    ) async {
      phone(tester);
      await open(tester);
      final a = await habit(tester, 'Sleep');
      final b = await habit(tester, 'Gym');
      // 29 shared days: one short of the threshold.
      await log(tester, a, coin(51, 29));
      await log(tester, b, coin(52, 29));
      await start(tester);
      expect(find.textContaining('closest pair has 29 so far'), findsOneWidget);
      final runsBefore = inputs.length;

      // Log the 30th day for both, a day further back.
      // One write at a time, pumping in between: the database's stream
      // queries finish on the test clock.
      final day = _today.addDays(-30);
      await run(tester, () => repo.setDayState(a, day, DayState.done));
      await settle(tester);
      await run(tester, () => repo.setDayState(b, day, DayState.done));
      await settle(tester);

      expect(inputs.length, greaterThan(runsBefore));
      expect(find.textContaining('closest pair has'), findsNothing);
      expect(find.text('Not enough data yet'), findsNothing);
      await finish(tester);
    });

    testWidgets('the previous result stays up, marked, while it refreshes', (
      tester,
    ) async {
      phone(tester);
      await open(tester);
      final (sleep, gym) = await togetherHabits(tester);
      pending = [];
      await start(
        tester,
        runner: (input) {
          inputs.add(input);
          final c = Completer<AnalysisResult>();
          pending.add(c);
          return c.future;
        },
      );
      await drain(tester);
      expect(find.byKey(ValueKey('insight-$sleep-$gym-0')), findsOneWidget);
      expect(find.text('Updating…'), findsNothing);

      final before = pending.length;
      await run(tester, () => repo.setDayState(sleep, _today, DayState.done));
      await settle(tester);
      expect(pending.length, greaterThan(before));
      expect(find.text('Updating…'), findsOneWidget);
      expect(
        find.byKey(ValueKey('insight-$sleep-$gym-0')),
        findsOneWidget,
        reason: 'old result remains while the new one is computed',
      );

      await drain(tester);
      expect(find.text('Updating…'), findsNothing);
      await finish(tester);
    });
  });

  group('drill-down matrix', () {
    testWidgets(
      'the matrix opens from All pairs and cells show their numbers',
      (tester) async {
        phone(tester);
        await open(tester);
        final (sleep, gym) = await togetherHabits(tester);
        await start(tester);

        await tester.tap(find.text('All pairs'));
        await settle(tester);
        expect(find.byKey(const ValueKey('pairs-matrix')), findsOneWidget);
        expect(find.text('Select a cell to see its numbers.'), findsOneWidget);

        await tester.tap(find.byKey(ValueKey('cell-$sleep-$gym')));
        await settle(tester);
        expect(find.byKey(const ValueKey('pair-detail')), findsOneWidget);
        expect(find.text('Same day'), findsOneWidget);
        expect(find.text('Sleep then Gym, the next day'), findsOneWidget);
        expect(find.text('Gym then Sleep, 3 days later'), findsOneWidget);
        expect(find.textContaining('effective n='), findsWidgets);
        expect(find.textContaining('adjusted p '), findsWidgets);

        // Back returns to the findings.
        await tester.tap(find.byKey(const ValueKey('back')));
        await settle(tester);
        expect(find.byType(InsightCard), findsWidgets);
        await finish(tester);
      },
    );

    testWidgets('cells are labelled buttons', (tester) async {
      phone(tester);
      final handle = tester.ensureSemantics();
      await open(tester);
      await togetherHabits(tester);
      await start(tester);
      await tester.tap(find.text('All pairs'));
      await settle(tester);

      await tester.pump(const Duration(seconds: 1)); // finish the route
      expect(
        find.bySemanticsLabel(
          RegExp(r'^Sleep and Gym: correlation \+0\.\d\d, 90 days, a finding'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('^Gym and Sleep: correlation')),
        findsOneWidget,
      );
      handle.dispose();
      await finish(tester);
    });
  });

  testWidgets('analysis errors offer a retry that recovers', (tester) async {
    phone(tester);
    await open(tester);
    await habit(tester, 'Read');
    await habit(tester, 'Walk');
    var attempts = 0;
    await start(
      tester,
      runner: (input) async {
        if (++attempts == 1) throw StateError('Analysis failed');
        return analyze(input);
      },
    );
    expect(find.byKey(const ValueKey('insights-error')), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(find.byKey(const ValueKey('insights-error')), findsNothing);
    expect(find.byKey(const ValueKey('insights-empty-data')), findsOneWidget);
    await finish(tester);
  });

  group('layout', () {
    for (final mode in [ThemeMode.dark, ThemeMode.light]) {
      testWidgets('320px at double text size fits in $mode', (tester) async {
        phone(tester, width: 320, scale: 2);
        await open(tester);
        final sleep = await habit(tester, 'Read a book before sleeping');
        final gym = await habit(
          tester,
          'Doomscrolling before bed',
          polarity: HabitPolarity.negative,
        );
        final a = coin(61, 90);
        await log(tester, sleep, a);
        await log(tester, gym, copy(a, 62, 0.1));
        await start(tester, themeMode: mode);

        expect(tester.takeException(), isNull);
        expect(find.byType(InsightCard), findsWidgets);
        final rect = tester.getRect(find.byType(InsightCard).first);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
        // The floating action stays inside the screen above the bottom bar.
        final fab = tester.getRect(find.byKey(const ValueKey('all-pairs')));
        expect(fab.right, lessThanOrEqualTo(320));
        expect(fab.bottom, lessThanOrEqualTo(776));

        await tester.tap(find.byKey(const ValueKey('all-pairs')));
        await settle(tester);
        expect(tester.takeException(), isNull);
        // At double text size the intro pushes the matrix below the fold.
        await tester.scrollUntilVisible(
          find.byKey(ValueKey('cell-$sleep-$gym')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byKey(ValueKey('cell-$sleep-$gym')));
        await settle(tester);
        expect(tester.takeException(), isNull);
        final matrix = tester.getRect(
          find.byKey(const ValueKey('pairs-matrix')),
        );
        expect(matrix.right, lessThanOrEqualTo(320));
        await finish(tester);
      });

      testWidgets('all five tabs fit at 320px and double text in $mode', (
        tester,
      ) async {
        phone(tester, width: 320, scale: 2);
        await open(tester);
        await habit(tester, 'Read');
        await start(tester, themeMode: mode, section: Section.today);
        for (final label in [
          'Today',
          'History',
          'Insights',
          'Habits',
          'Settings',
        ]) {
          final rect = tester.getRect(
            find.widgetWithText(GestureDetector, label),
          );
          expect(rect.width, greaterThan(40), reason: label);
          expect(rect.height, greaterThanOrEqualTo(56), reason: label);
          expect(rect.right, lessThanOrEqualTo(320), reason: label);
        }
        expect(tester.takeException(), isNull);
        await finish(tester);
      });
    }
  });

  group('macOS', () {
    testWidgets('command-3 opens Insights beside the sidebar', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        tester.view.physicalSize = const Size(1100, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await open(tester);
        await togetherHabits(tester);
        await start(tester, section: Section.today);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await settle(tester);

        expect(find.byType(InsightCard), findsWidgets);
        expect(find.text('Cohabit'), findsOneWidget, reason: 'sidebar stays');
        expect(find.text('⌘3'), findsOneWidget);

        // All pairs is a header button on desktop and opens beside the
        // sidebar; Escape goes back.
        await tester.tap(find.text('All pairs'));
        await settle(tester);
        expect(find.byKey(const ValueKey('pairs-matrix')), findsOneWidget);
        expect(find.text('Cohabit'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(tester);
        await tester.pump(const Duration(seconds: 1)); // finish the route
        expect(find.byKey(const ValueKey('pairs-matrix')), findsNothing);
        await finish(tester);
      } finally {
        // Must be reset before the framework's end-of-test check.
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
