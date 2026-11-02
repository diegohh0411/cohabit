import '../domain/day_state.dart';
import '../domain/habit.dart';
import '../domain/habit_day.dart';
import '../ui/labels.dart';

/// Logged state by habit id and day, as stored. Anything absent is unlogged.
typedef LoggedStates = Map<String, Map<HabitDay, DayState>>;

/// How one cell is drawn. Colour is never the only cue: each style also has
/// a distinct shape (fill, hatch or hollow outline) and a text description.
enum CellStyle {
  /// Outside the habit's life or in the future: nothing is drawn.
  none,

  /// Positive habit done, or negative habit confirmed clean: blue3.
  done,

  /// Negative habit slipped: orange.
  slipped,

  /// Explicitly not done: the off fill.
  notDone,

  /// Deliberately excused or not scheduled: hatched.
  skipped,

  /// Nothing logged on a scheduled day: 1px hairline outline.
  unknown,

  // Overview scale, none to full.
  level0,
  level1,
  level2,
  level3,
  level4,
}

/// A run of whole weeks (Monday to Sunday), one column per week.
class GraphRange {
  const GraphRange({required this.first, required this.weeks})
    : assert(weeks > 0);

  /// Monday of the first column.
  final HabitDay first;
  final int weeks;

  static const int rows = 7;

  /// The range ending in the week of [today] that holds at least [minWeeks]
  /// columns and reaches back to the week of [earliest].
  factory GraphRange.covering({
    required HabitDay today,
    required HabitDay earliest,
    int minWeeks = 1,
  }) {
    final needed =
        today.weekStart.differenceInDays(earliest.weekStart) ~/ 7 + 1;
    final weeks = needed > minWeeks ? needed : minWeeks;
    return GraphRange(
      first: today.weekStart.addDays(-7 * (weeks - 1)),
      weeks: weeks < 1 ? 1 : weeks,
    );
  }

  int get length => weeks * rows;
  HabitDay get last => first.addDays(length - 1);

  HabitDay dayAt(int index) => first.addDays(index);
  int indexOf(HabitDay day) => day.differenceInDays(first);
  bool contains(HabitDay day) {
    final i = indexOf(day);
    return i >= 0 && i < length;
  }

  int columnOf(int index) => index ~/ rows;
  int rowOf(int index) => index % rows;

  @override
  bool operator ==(Object other) =>
      other is GraphRange && other.first == first && other.weeks == weeks;

  @override
  int get hashCode => Object.hash(first, weeks);
}

/// What the legend below a graph explains.
enum LegendKind { habit, overview }

/// One graph's worth of cells, aligned to a [GraphRange].
class GraphSeries {
  GraphSeries({
    required this.title,
    required this.range,
    required this.styles,
    required this.describe,
    required this.legend,
    required this.summary,
  }) : assert(styles.length == range.length);

  /// Habit name; "Overview" for the overview graph.
  final String title;
  final GraphRange range;

  /// One style per day, indexed from [GraphRange.first].
  final List<CellStyle> styles;

  /// Plain-text state of a day, for hover detail and screen readers.
  final String Function(HabitDay day) describe;
  final LegendKind legend;

  /// One sentence of counts for screen readers.
  final String summary;

  CellStyle styleOf(HabitDay day) =>
      range.contains(day) ? styles[range.indexOf(day)] : CellStyle.none;
}

/// Style and text for [habit] on [day].
///
/// Days before the habit existed (and unlogged) and days after [today] are
/// blank. Past that, an unlogged day is hollow when scheduled and hatched
/// when not; only an explicit log can make it done or not done.
({CellStyle style, String label}) habitCell(
  Habit habit,
  HabitDay day,
  DayState? logged,
  HabitDay today,
) {
  if (day > today) return (style: CellStyle.none, label: 'Upcoming');
  final isLogged = logged != null && logged != DayState.unknown;
  if (isLogged) {
    final style = switch (logged) {
      DayState.done => habit.isNegative ? CellStyle.slipped : CellStyle.done,
      DayState.notDone => habit.isNegative ? CellStyle.done : CellStyle.notDone,
      _ => CellStyle.skipped,
    };
    return (style: style, label: stateLabel(habit, logged));
  }
  if (day < habit.createdDay) {
    return (style: CellStyle.none, label: 'Before this habit started');
  }
  return habit.isScheduledOn(day)
      ? (style: CellStyle.unknown, label: 'Not logged')
      : (style: CellStyle.skipped, label: 'Skipped (not scheduled)');
}

GraphSeries habitSeries(
  Habit habit,
  Map<HabitDay, DayState> logged,
  GraphRange range,
  HabitDay today,
) {
  final styles = List<CellStyle>.filled(range.length, CellStyle.none);
  final labels = List<String>.filled(range.length, '');
  final counts = <CellStyle, int>{};
  for (var i = 0; i < range.length; i++) {
    final day = range.dayAt(i);
    final cell = habitCell(habit, day, logged[day], today);
    styles[i] = cell.style;
    labels[i] = cell.label;
    counts[cell.style] = (counts[cell.style] ?? 0) + 1;
  }
  final parts = [
    for (final (style, word) in [
      (CellStyle.done, habit.isNegative ? 'clean' : 'done'),
      (CellStyle.slipped, 'slipped'),
      (CellStyle.notDone, 'not done'),
      (CellStyle.skipped, 'skipped'),
      (CellStyle.unknown, 'not logged'),
    ])
      if (counts[style] != null) '${counts[style]} $word',
  ];
  final summary =
      '${habit.name}: ${parts.isEmpty ? 'no days yet' : parts.join(', ')}';
  return GraphSeries(
    title: habit.name,
    range: range,
    styles: styles,
    describe: (day) => range.contains(day) ? labels[range.indexOf(day)] : '',
    legend: LegendKind.habit,
    summary: summary,
  );
}

/// Whether a logged [state] counts as a completion for [habit]: a positive
/// habit done, or a negative habit confirmed clean.
bool isCompletion(Habit habit, DayState state) =>
    habit.isNegative ? state == DayState.notDone : state == DayState.done;

/// Overview scale index (0 to 4) for a completion [share] between 0 and 1.
int overviewLevel(double share) {
  if (share <= 0) return 0;
  if (share < 1 / 3) return 1;
  if (share < 2 / 3) return 2;
  if (share < 1) return 3;
  return 4;
}

/// Share of logged habits completed per day.
///
/// For each day, the habits that existed and were scheduled then (by the
/// schedule in force that day) count if they were logged and not deliberately
/// skipped. Done positive habits and confirmed-clean negative habits are
/// completions. Unlogged habits are unknown, so they never count against the
/// share. A day with scheduled habits but none measured shows as unknown;
/// a day with nothing scheduled is blank.
GraphSeries overviewSeries(
  List<Habit> habits,
  LoggedStates logged,
  GraphRange range,
  HabitDay today,
) {
  final styles = List<CellStyle>.filled(range.length, CellStyle.none);
  final labels = List<String>.filled(range.length, '');
  var measured = 0;
  var shareSum = 0.0;
  for (var i = 0; i < range.length; i++) {
    final day = range.dayAt(i);
    if (day > today) {
      labels[i] = 'Upcoming';
      continue;
    }
    var scheduled = 0;
    var measuredHabits = 0;
    var unlogged = 0;
    var completed = 0;
    for (final habit in habits) {
      if (day < habit.createdDay || !habit.isScheduledOn(day)) continue;
      scheduled++;
      final state = logged[habit.id]?[day];
      if (state == DayState.skipped) continue;
      if (state == null || state == DayState.unknown) {
        unlogged++;
        continue;
      }
      measuredHabits++;
      if (isCompletion(habit, state)) completed++;
    }
    if (scheduled == 0) {
      labels[i] = 'Nothing scheduled';
      continue;
    }
    if (measuredHabits == 0) {
      if (unlogged > 0) {
        styles[i] = CellStyle.unknown;
        labels[i] = 'Nothing logged';
      } else {
        labels[i] = 'All skipped';
      }
      continue;
    }
    final share = completed / measuredHabits;
    measured++;
    shareSum += share;
    styles[i] = CellStyle.values[CellStyle.level0.index + overviewLevel(share)];
    labels[i] =
        '$completed of $measuredHabits logged habits completed '
        '(${(share * 100).round()}%)'
        '${unlogged > 0 ? ', $unlogged not logged' : ''}';
  }
  return GraphSeries(
    title: 'Overview',
    range: range,
    styles: styles,
    describe: (day) => range.contains(day) ? labels[range.indexOf(day)] : '',
    legend: LegendKind.overview,
    summary: measured == 0
        ? 'Overview: no days to measure'
        : 'Overview: $measured ${measured == 1 ? 'day' : 'days'} measured, '
              'average completion '
              '${(shareSum / measured * 100).round()}%',
  );
}

/// Where month names go above a graph: the first column that starts in a new
/// month, skipping any that would crowd the previous name.
List<({int column, String label})> monthMarkers(GraphRange range) {
  final out = <({int column, String label})>[];
  var lastColumn = -100;
  int? lastMonth;
  for (var col = 0; col < range.weeks; col++) {
    final monday = range.first.addDays(col * 7);
    if (monday.month == lastMonth) continue;
    lastMonth = monday.month;
    if (col - lastColumn < 3) continue;
    lastColumn = col;
    out.add((column: col, label: monthShort[monday.month - 1]));
  }
  return out;
}
