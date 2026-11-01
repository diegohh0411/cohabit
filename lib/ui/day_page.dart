import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/habit_day.dart';
import '../state/providers.dart';
import 'habit_day_tile.dart';
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
    final today = ref.watch(todayProvider).value ?? widget.initialDay;
    final habits = ref.watch(habitsProvider).value ?? const [];
    final states = ref.watch(dayStatesProvider(_day)).value ?? const {};
    final canGoForward = _day < today;

    return Scaffold(
      appBar: AppBar(
        title: Text(formatDay(_day), key: const ValueKey('day-title')),
        actions: [
          IconButton(
            tooltip: 'Previous day',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => _day = _day.addDays(-1)),
          ),
          IconButton(
            tooltip: 'Next day',
            icon: const Icon(Icons.chevron_right),
            onPressed: canGoForward
                ? () => setState(() => _day = _day.addDays(1))
                : null,
          ),
          IconButton(
            tooltip: 'Pick a date',
            icon: const Icon(Icons.edit_calendar_outlined),
            onPressed: () => _pick(today),
          ),
        ],
      ),
      body: habits.isEmpty
          ? const Center(child: Text('No habits yet.'))
          : ListView(
              children: [
                for (final habit in habits) ...[
                  HabitDayTile(
                    key: ValueKey('${_day}-${habit.id}'),
                    habit: habit,
                    day: _day,
                    logged: states[habit.id]?.state,
                  ),
                  const Divider(),
                ],
              ],
            ),
    );
  }
}
