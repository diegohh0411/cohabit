import 'package:cohabit/design/theme.dart';
import 'package:cohabit/domain/day_state.dart';
import 'package:cohabit/domain/habit.dart';
import 'package:cohabit/domain/habit_day.dart';
import 'package:cohabit/graph/graph_model.dart';
import 'package:cohabit/graph/graph_painter.dart';
import 'package:cohabit/graph/graph_panel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final today = HabitDay(2026, 11, 1); // Sunday
final saturday = HabitDay(2026, 10, 31);
final friday = HabitDay(2026, 10, 30);

Habit habit(String id, String name, {bool negative = false}) => Habit(
  id: id,
  name: name,
  polarity: negative ? HabitPolarity.negative : HabitPolarity.positive,
  schedule: const {1, 2, 3, 4, 5, 6, 7},
  createdDay: HabitDay(2026, 8, 1),
);

final run = habit('run', 'Run');
final smoke = habit('smoke', 'Smoke', negative: true);

final logged = <String, Map<HabitDay, DayState>>{
  'run': {
    saturday: DayState.done,
    friday: DayState.notDone,
    HabitDay(2026, 10, 29): DayState.skipped,
  },
  'smoke': {saturday: DayState.done, friday: DayState.notDone},
};

Widget host(
  Widget child, {
  double width = 760,
  TargetPlatform platform = TargetPlatform.macOS,
}) => MaterialApp(
  theme: buildTheme(Brightness.dark, platform: platform),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: width, child: child),
    ),
  ),
);

GraphPanel panel({
  List<Habit> habits = const [],
  void Function(HabitDay, int)? onDayTap,
  bool overview = false,
}) {
  final hs = habits.isEmpty ? [run] : habits;
  return GraphPanel(
    today: today,
    earliest: HabitDay(2026, 8, 1),
    seriesBuilder: (range) => overview
        ? [overviewSeries(hs, logged, range, today)]
        : [
            for (final h in hs)
              habitSeries(h, logged[h.id] ?? {}, range, today),
          ],
    onDayTap: onDayTap,
  );
}

Finder canvases() => find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is CommitGraphPainter,
);

CommitGraphPainter painterAt(WidgetTester tester, [int i = 0]) =>
    tester.widget<CustomPaint>(canvases().at(i)).painter! as CommitGraphPainter;

/// Screen position of the centre of [day]'s cell in canvas [i].
Offset cellCenter(WidgetTester tester, HabitDay day, [int i = 0]) {
  final range = painterAt(tester, i).series.range;
  return tester.getTopLeft(canvases().at(i)) +
      GraphMetrics.originOf(range, range.indexOf(day)) +
      const Offset(5, 5);
}

String detail(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('graph-detail'))).data!;

void main() {
  group('layout', () {
    testWidgets('one column per week, 7 rows, anchored to today at the right', (
      tester,
    ) async {
      await tester.pumpWidget(host(panel()));
      final range = painterAt(tester).series.range;
      expect(range.first.weekday, DateTime.monday);
      expect(range.last, today);
      final canvas = tester.getRect(canvases().first);
      expect(canvas.height, GraphMetrics.height);
      expect(canvas.width, GraphMetrics.widthFor(range.weeks));
      // Today's cell is the last column, bottom row, at the right edge.
      final todayCell = cellCenter(tester, today);
      expect(todayCell.dx, closeTo(canvas.right - 5, 0.01));
      expect(todayCell.dy, closeTo(canvas.bottom - 5, 0.01));
    });

    testWidgets('fills a wide window with at least a year of weeks', (
      tester,
    ) async {
      await tester.pumpWidget(host(panel(), width: 1000));
      final weeks = painterAt(tester).series.range.weeks;
      expect(weeks, greaterThanOrEqualTo(53));
      // 12px per week fits the window without scrolling.
      expect(GraphMetrics.widthFor(weeks), lessThanOrEqualTo(1000 - 28));
    });

    testWidgets('on a phone it scrolls back in time from today', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(panel(), width: 360, platform: TargetPlatform.android),
      );
      final scroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(scroll.reverse, isTrue);
      expect(scroll.scrollDirection, Axis.horizontal);
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      expect(position.pixels, 0, reason: 'starts at today');
      expect(position.maxScrollExtent, greaterThan(0));
      // Today is visible at the right edge before any scrolling.
      expect(cellCenter(tester, today).dx, lessThanOrEqualTo(360));

      // Dragging right moves back in time.
      final range = painterAt(tester).series.range;
      final earlier = range.first.addDays(7);
      expect(cellCenter(tester, earlier).dx, lessThan(0), reason: 'off-screen');
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(3000, 0),
      );
      await tester.pump();
      expect(cellCenter(tester, earlier).dx, greaterThan(0));
    });

    testWidgets('month names sit above the graph', (tester) async {
      await tester.pumpWidget(host(panel()));
      expect(find.text('OCT'), findsWidgets);
      expect(find.text('SEP'), findsWidgets);
    });
  });

  group('legend', () {
    testWidgets('per-habit legend names every state', (tester) async {
      await tester.pumpWidget(host(panel()));
      for (final t in [
        'Done or clean',
        'Slipped',
        'Not done',
        'Skipped',
        'Not logged',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
    });

    testWidgets('overview legend runs from less to more', (tester) async {
      await tester.pumpWidget(host(panel(overview: true)));
      expect(find.text('Less'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
      expect(find.text('Skipped'), findsNothing);
    });

    testWidgets('legend is announced once, not swatch by swatch', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(panel()));
      expect(
        find.bySemanticsLabel(RegExp(r'^Legend: done or clean, slipped')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('day detail', () {
    testWidgets('hover (pointer) shows the day and its state', (tester) async {
      await tester.pumpWidget(host(panel()));
      expect(detail(tester), startsWith('Hover a day'));

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(cellCenter(tester, saturday));
      await tester.pump();
      expect(detail(tester), 'Sat 31 Oct 2026 · Done');

      await mouse.moveTo(cellCenter(tester, friday));
      await tester.pump();
      expect(detail(tester), 'Fri 30 Oct 2026 · Not done');

      await mouse.moveTo(cellCenter(tester, HabitDay(2026, 10, 29)));
      await tester.pump();
      expect(detail(tester), 'Thu 29 Oct 2026 · Skipped');

      await mouse.moveTo(cellCenter(tester, HabitDay(2026, 10, 28)));
      await tester.pump();
      expect(detail(tester), 'Wed 28 Oct 2026 · Not logged');

      await mouse.moveTo(const Offset(5, 500));
      await tester.pump();
      expect(detail(tester), startsWith('Hover a day'));
    });

    testWidgets('negative habit hover words slips and clean days', (
      tester,
    ) async {
      await tester.pumpWidget(host(panel(habits: [smoke])));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(cellCenter(tester, saturday));
      await tester.pump();
      expect(detail(tester), 'Sat 31 Oct 2026 · Slipped');
      await mouse.moveTo(cellCenter(tester, friday));
      await tester.pump();
      expect(detail(tester), 'Fri 30 Oct 2026 · Clean day');
    });

    testWidgets('overview detail gives the completed share', (tester) async {
      await tester.pumpWidget(
        host(panel(overview: true, habits: [run, smoke])),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(cellCenter(tester, saturday));
      await tester.pump();
      // Run done, Smoke slipped: one of two.
      expect(detail(tester), 'Sat 31 Oct 2026 · 1 of 2 habits completed (50%)');
      await mouse.moveTo(cellCenter(tester, friday));
      await tester.pump();
      expect(detail(tester), 'Fri 30 Oct 2026 · 1 of 2 habits completed (50%)');
    });

    testWidgets('tap (touch) shows detail and opens the day', (tester) async {
      final taps = <(HabitDay, int)>[];
      await tester.pumpWidget(
        host(
          panel(onDayTap: (d, i) => taps.add((d, i))),
          platform: TargetPlatform.android,
        ),
      );
      expect(detail(tester), startsWith('Tap a day'));
      await tester.tapAt(cellCenter(tester, saturday));
      await tester.pump();
      expect(taps, [(saturday, 0)]);
      expect(detail(tester), 'Sat 31 Oct 2026 · Done');
    });

    testWidgets('gaps and future days do not open anything', (tester) async {
      final taps = <HabitDay>[];
      await tester.pumpWidget(host(panel(onDayTap: (d, _) => taps.add(d))));
      // The gap between two cells.
      await tester.tapAt(cellCenter(tester, saturday) + const Offset(6, 0));
      // The future: Monday after today is in no column, but a day later in the
      // same range column does not exist either; tap beyond the last column.
      await tester.tapAt(
        tester.getTopRight(canvases().first) + const Offset(5, 5),
      );
      expect(taps, isEmpty);
    });
  });

  group('keyboard', () {
    testWidgets('arrows move a cursor, Enter opens the day', (tester) async {
      final taps = <HabitDay>[];
      await tester.pumpWidget(host(panel(onDayTap: (d, _) => taps.add(d))));
      final focus = Focus.of(tester.element(canvases().first));
      focus.requestFocus();
      await tester.pump();
      // Cursor starts on today.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(detail(tester), startsWith('Sat 31 Oct 2026'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(detail(tester), startsWith('Sat 24 Oct 2026'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      // Cannot move into the future.
      expect(
        detail(tester),
        startsWith('Sun 25 Oct 2026'.replaceFirst('25 Oct', '1 Nov')),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(taps, [today]);
    });
  });

  group('semantics', () {
    testWidgets('every drawn cell is a labelled button; summary on the panel', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(panel()));
      expect(
        find.semantics.byLabel('Sat 31 Oct 2026, Run: Done'),
        findsOneWidget,
      );
      expect(
        find.semantics.byLabel('Fri 30 Oct 2026, Run: Not done'),
        findsOneWidget,
      );
      expect(
        find.semantics.byLabel('Thu 29 Oct 2026, Run: Skipped'),
        findsOneWidget,
      );
      expect(
        find.semantics.byLabel('Wed 28 Oct 2026, Run: Not logged'),
        findsOneWidget,
      );
      expect(
        find.semantics.byLabel(
          RegExp(r'^Run: \d+ done, 1 not done, 1 skipped'),
        ),
        findsOneWidget,
      );
      // Blank cells (before the habit, or in the future) are not announced.
      expect(
        find.semantics.byLabel(RegExp(r'Before this habit started')),
        findsNothing,
      );
      handle.dispose();
    });

    testWidgets('a cell\'s semantic tap opens the day', (tester) async {
      final handle = tester.ensureSemantics();
      final taps = <HabitDay>[];
      await tester.pumpWidget(host(panel(onDayTap: (d, _) => taps.add(d))));
      final node = find.semantics
          .byLabel('Sat 31 Oct 2026, Run: Done')
          .evaluate()
          .single;
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      tester.semantics.tap(
        find.semantics.byLabel('Sat 31 Oct 2026, Run: Done'),
      );
      await tester.pump();
      expect(taps, [saturday]);
      handle.dispose();
    });
  });

  group('comparison', () {
    testWidgets('two graphs stack with days aligned', (tester) async {
      await tester.pumpWidget(host(panel(habits: [run, smoke])));
      expect(canvases(), findsNWidgets(2));
      final a = tester.getRect(canvases().at(0));
      final b = tester.getRect(canvases().at(1));
      expect(a.left, b.left);
      expect(a.width, b.width);
      expect(b.top, greaterThan(a.bottom));
      expect(
        painterAt(tester, 0).series.range,
        painterAt(tester, 1).series.range,
      );
      // The same day is the same x in both.
      expect(
        cellCenter(tester, saturday, 0).dx,
        cellCenter(tester, saturday, 1).dx,
      );
      // Titles are drawn once each.
      expect(find.text('Run'), findsOneWidget);
      expect(find.text('Smoke'), findsOneWidget);
    });

    testWidgets('hovering a day highlights it in both and details both', (
      tester,
    ) async {
      await tester.pumpWidget(host(panel(habits: [run, smoke])));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(cellCenter(tester, saturday, 1));
      await tester.pump();
      final range = painterAt(tester).series.range;
      expect(painterAt(tester, 0).highlight, range.indexOf(saturday));
      expect(painterAt(tester, 1).highlight, range.indexOf(saturday));
      expect(detail(tester), 'Sat 31 Oct 2026 · Run: Done · Smoke: Slipped');
    });

    testWidgets('both graphs scroll together', (tester) async {
      await tester.pumpWidget(
        host(
          panel(habits: [run, smoke]),
          width: 300,
          platform: TargetPlatform.android,
        ),
      );
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });
}
