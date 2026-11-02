import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/buttons.dart';
import '../design/page_scaffold.dart';
import '../design/section_label.dart';
import '../design/tokens.dart';
import '../domain/day_state.dart';
import '../domain/habit.dart';
import '../domain/habit_day.dart';
import '../graph/graph_model.dart';
import '../graph/graph_panel.dart';
import '../state/providers.dart';
import 'compare_page.dart';
import 'day_page.dart';
import 'labels.dart';
import 'navigation.dart';

/// The earliest habit day worth drawing: the oldest habit's first day.
HabitDay earliestDay(List<Habit> habits, HabitDay today) {
  var earliest = today;
  for (final h in habits) {
    if (h.createdDay < earliest) earliest = h.createdDay;
  }
  return earliest;
}

/// Overview graph, then one graph per habit.
class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final today = ref.watch(todayProvider).value;
    final habits = ref.watch(habitsProvider).value;
    final logged = ref.watch(loggedStatesProvider).value;

    void openDay(HabitDay day) =>
        openPage<void>(context, DayPage(initialDay: day));

    return PageScaffold(
      title: 'History',
      primaryAction: PageAction(
        label: 'Compare',
        desktopVariant: ButtonVariant.secondary,
        onPressed: () => openPage<void>(context, const ComparePage()),
      ),
      child: today == null || habits == null || logged == null
          ? const SizedBox.shrink()
          : PageBody(
              children: [
                if (habits.isEmpty)
                  Text(
                    'No habits yet. Add one to see its history.',
                    style: CohabitType.body(c).copyWith(color: c.muted),
                  )
                else ...[
                  const SectionLabel('Overview'),
                  const SizedBox(height: Space.s),
                  GraphPanel(
                    key: const ValueKey('overview-graph'),
                    today: today,
                    earliest: earliestDay(habits, today),
                    seriesBuilder: (range) => [
                      overviewSeries(habits, logged, range, today),
                    ],
                    onDayTap: (day, _) => openDay(day),
                  ),
                  for (final habit in habits) ...[
                    const SizedBox(height: Space.xl),
                    Text(habit.name, style: CohabitType.name(c)),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (habit.isNegative) 'avoid',
                        scheduleLabel(habit.schedule),
                      ].join(' · '),
                      style: CohabitType.meta(c),
                    ),
                    const SizedBox(height: Space.s),
                    GraphPanel(
                      key: ValueKey('graph-${habit.id}'),
                      today: today,
                      earliest: habit.createdDay,
                      seriesBuilder: (range) => [
                        habitSeries(
                          habit,
                          logged[habit.id] ?? const <HabitDay, DayState>{},
                          range,
                          today,
                        ),
                      ],
                      onDayTap: (day, _) => openDay(day),
                    ),
                  ],
                ],
              ],
            ),
    );
  }
}
