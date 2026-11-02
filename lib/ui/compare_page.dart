import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/page_scaffold.dart';
import '../design/select.dart';
import '../design/tokens.dart';
import '../domain/day_state.dart';
import '../domain/habit.dart';
import '../domain/habit_day.dart';
import '../graph/graph_model.dart';
import '../graph/graph_panel.dart';
import '../state/providers.dart';
import 'day_page.dart';
import 'history_page.dart' show earliestDay;
import 'navigation.dart';

/// Two habit graphs stacked with their days aligned, to see whether they
/// move together.
class ComparePage extends ConsumerStatefulWidget {
  const ComparePage({super.key});

  @override
  ConsumerState<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends ConsumerState<ComparePage> {
  String? _first;
  String? _second;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final today = ref.watch(todayProvider).value;
    final habits = ref.watch(habitsProvider).value ?? const <Habit>[];
    final logged = ref.watch(loggedStatesProvider).value;

    Habit? pick(String? id, int fallback) {
      for (final h in habits) {
        if (h.id == id) return h;
      }
      return fallback < habits.length ? habits[fallback] : null;
    }

    final a = pick(_first, 0);
    // Default the second graph to a different habit than the first.
    final b = _second == null && a != null && habits.length > 1
        ? habits.firstWhere((h) => h.id != a.id)
        : pick(_second, 1);

    final names = {for (final h in habits) h.id: h.name};
    return PageScaffold(
      title: 'Compare habits',
      child: PageBody(
        children: [
          if (habits.length < 2)
            Text(
              'Add at least two habits to compare them.',
              style: CohabitType.body(c).copyWith(color: c.muted),
            )
          else if (today != null &&
              logged != null &&
              a != null &&
              b != null) ...[
            LayoutBuilder(
              builder: (context, box) {
                final first = CohabitSelect<String>(
                  fieldKey: const ValueKey('compare-first'),
                  label: 'Top graph',
                  value: a.id,
                  items: names,
                  onChanged: (id) => setState(() => _first = id),
                );
                final second = CohabitSelect<String>(
                  fieldKey: const ValueKey('compare-second'),
                  label: 'Bottom graph',
                  value: b.id,
                  items: names,
                  onChanged: (id) => setState(() => _second = id),
                );
                // Side by side only when each gets room for a habit name.
                if (box.maxWidth < 480) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      first,
                      const SizedBox(height: Space.m),
                      second,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: first),
                    const SizedBox(width: Space.l),
                    Expanded(child: second),
                  ],
                );
              },
            ),
            const SizedBox(height: Space.xl),
            GraphPanel(
              key: const ValueKey('compare-graph'),
              today: today,
              earliest: earliestDay([a, b], today),
              seriesBuilder: (range) => [
                for (final h in [a, b])
                  habitSeries(
                    h,
                    logged[h.id] ?? const <HabitDay, DayState>{},
                    range,
                    today,
                  ),
              ],
              onDayTap: (day, _) =>
                  openPage<void>(context, DayPage(initialDay: day)),
            ),
          ],
        ],
      ),
    );
  }
}
