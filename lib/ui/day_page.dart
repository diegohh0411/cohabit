import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/buttons.dart';
import '../design/page_scaffold.dart';
import '../design/tokens.dart';
import '../domain/habit_day.dart';
import '../state/providers.dart';
import 'habit_log_row.dart';
import 'labels.dart';

/// Backfill and edit any past day.
class DayPage extends ConsumerStatefulWidget {
  const DayPage({super.key, required this.initialDay});

  final HabitDay initialDay;

  @override
  ConsumerState<DayPage> createState() => _DayPageState();
}

class _DayPageState extends ConsumerState<DayPage> {
  late HabitDay _day = widget.initialDay;

  Future<void> _pick(HabitDay today) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day.toLocalDate(),
      firstDate: DateTime(2000),
      lastDate: today.toLocalDate(),
    );
    if (picked != null) setState(() => _day = HabitDay.fromDate(picked));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final today = ref.watch(todayProvider).value ?? widget.initialDay;
    final habits = ref.watch(habitsProvider).value ?? const [];
    final states = ref.watch(dayStatesProvider(_day)).value ?? const {};
    final canGoForward = _day < today;

    return PageScaffold(
      title: formatDay(_day),
      titleKey: const ValueKey('day-title'),
      child: PageBody(
        children: [
          Row(
            children: [
              CohabitButton.secondary(
                key: const ValueKey('previous-day'),
                label: '← Previous',
                onPressed: () => setState(() => _day = _day.addDays(-1)),
              ),
              const SizedBox(width: Space.s),
              CohabitButton.secondary(
                key: const ValueKey('next-day'),
                label: 'Next →',
                onPressed: canGoForward
                    ? () => setState(() => _day = _day.addDays(1))
                    : null,
              ),
              const SizedBox(width: Space.s),
              CohabitButton.ghost(
                key: const ValueKey('pick-day'),
                label: 'Pick a date',
                onPressed: () => _pick(today),
              ),
            ],
          ),
          const SizedBox(height: Space.l),
          if (habits.isEmpty)
            Text(
              'No habits yet.',
              style: CohabitType.body(c).copyWith(color: c.muted),
            ),
          for (final habit in habits) ...[
            HabitLogRow(
              key: ValueKey('$_day-${habit.id}'),
              habit: habit,
              day: _day,
              logged: states[habit.id]?.state,
            ),
            const SizedBox(height: Space.s),
          ],
        ],
      ),
    );
  }
}
