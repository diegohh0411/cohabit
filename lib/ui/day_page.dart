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

    // Previous, next and the date picker: above the list with a pointer, and
    // pinned to the bottom edge on touch, where the thumb is.
    final desktop = isDesktopPlatform(context);
    final nav = _DayNav(
      expand: !desktop,
      canGoForward: canGoForward,
      onPrevious: () => setState(() => _day = _day.addDays(-1)),
      onNext: () => setState(() => _day = _day.addDays(1)),
      onPick: () => _pick(today),
    );

    return PageScaffold(
      title: formatDay(_day),
      titleKey: const ValueKey('day-title'),
      bottomBar: desktop ? null : nav,
      child: PageBody(
        children: [
          if (desktop) ...[nav, const SizedBox(height: Space.l)],
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

class _DayNav extends StatelessWidget {
  const _DayNav({
    required this.expand,
    required this.canGoForward,
    required this.onPrevious,
    required this.onNext,
    required this.onPick,
  });

  /// Fill the width, with arrow buttons either side of the date picker.
  final bool expand;
  final bool canGoForward;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final previous = CohabitButton.secondary(
      key: const ValueKey('previous-day'),
      label: expand ? '←' : '← Previous',
      semanticLabel: 'Previous day',
      expand: expand,
      onPressed: onPrevious,
    );
    final next = CohabitButton.secondary(
      key: const ValueKey('next-day'),
      label: expand ? '→' : 'Next →',
      semanticLabel: 'Next day',
      expand: expand,
      onPressed: canGoForward ? onNext : null,
    );
    final pick = CohabitButton.ghost(
      key: const ValueKey('pick-day'),
      label: 'Pick a date',
      expand: expand,
      onPressed: onPick,
    );
    if (!expand) {
      return Row(
        children: [
          previous,
          const SizedBox(width: Space.s),
          next,
          const SizedBox(width: Space.s),
          pick,
        ],
      );
    }
    return Row(
      children: [
        Expanded(flex: 2, child: previous),
        const SizedBox(width: Space.s),
        Expanded(flex: 3, child: pick),
        const SizedBox(width: Space.s),
        Expanded(flex: 2, child: next),
      ],
    );
  }
}
