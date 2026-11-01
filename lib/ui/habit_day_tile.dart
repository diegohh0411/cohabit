import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/day_state.dart';
import '../domain/habit.dart';
import '../domain/habit_day.dart';
import '../state/providers.dart';
import 'labels.dart';

/// One habit on one day with one-tap logging.
///
/// Tapping an action logs that state; tapping the selected action again
/// clears it back to "not logged". Unlogged days are shown as such, never as
/// "not done".
class HabitDayTile extends ConsumerWidget {
  const HabitDayTile({
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
    final theme = Theme.of(context);
    final isLogged = logged != null && logged != DayState.unknown;
    final scheduled = habit.isScheduledOn(day);
    final status = isLogged
        ? stateLabel(habit, logged!)
        : scheduled
        ? 'Not logged'
        : 'Not scheduled';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(habit.name, style: theme.textTheme.titleMedium),
              ),
              if (habit.isNegative)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('avoid', style: theme.textTheme.labelSmall),
                ),
              Text(
                status,
                key: ValueKey('status-${habit.id}'),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: isLogged ? null : FontStyle.italic,
                  color: isLogged ? null : theme.hintColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final action in actionsFor(habit)) ...[
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: logged == action.state
                        ? FilledButton(
                            key: ValueKey('${habit.id}-${action.state.name}'),
                            onPressed: () => _tap(ref, action.state),
                            child: Text(action.label),
                          )
                        : OutlinedButton(
                            key: ValueKey('${habit.id}-${action.state.name}'),
                            onPressed: () => _tap(ref, action.state),
                            child: Text(action.label),
                          ),
                  ),
                ),
                if (action != actionsFor(habit).last) const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
