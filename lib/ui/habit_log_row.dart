import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/habit_row.dart';
import '../design/segmented_log_control.dart';
import '../domain/day_state.dart';
import '../domain/habit.dart';
import '../domain/habit_day.dart';
import '../state/providers.dart';
import 'labels.dart';

/// One habit on one day with one-tap logging.
///
/// Tapping an option logs that state; tapping the selected option again
/// clears it back to "not logged". Unlogged days are shown as such, never as
/// "not done".
class HabitLogRow extends ConsumerWidget {
  const HabitLogRow({
    super.key,
    required this.habit,
    required this.day,
    required this.logged,
  });

  final Habit habit;
  final HabitDay day;

  /// The resolved logged state for [day], if anything was logged.
  final DayState? logged;

  Future<void> _tap(WidgetRef ref, DayState target) {
    final next = logged == target ? DayState.unknown : target;
    return ref.read(repositoryProvider).setDayState(habit.id, day, next);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLogged = logged != null && logged != DayState.unknown;
    final status = isLogged
        ? stateLabel(habit, logged!)
        : habit.isScheduledOn(day)
        ? 'Not logged'
        : 'Not scheduled';
    final meta = [
      scheduleLabel(habit.scheduleOn(day)),
      if (habit.isNegative) 'avoid',
      status,
    ].join(' · ');

    return HabitRow(
      name: habit.name,
      meta: meta,
      metaKey: ValueKey('status-${habit.id}'),
      control: SegmentedLogControl<DayState>(
        semanticLabel: '${habit.name}, $status',
        selected: isLogged ? logged : null,
        onSelected: (s) => _tap(ref, s),
        options: [
          for (final action in actionsFor(habit))
            LogOption(
              key: ValueKey('${habit.id}-${action.state.name}'),
              value: action.state,
              label: action.label,
              tone: switch ((habit.isNegative, action.state)) {
                (false, DayState.done) => LogTone.positive,
                (true, DayState.notDone) => LogTone.positive,
                (true, DayState.done) => LogTone.warning,
                _ => LogTone.neutral,
              },
            ),
        ],
      ),
    );
  }
}
