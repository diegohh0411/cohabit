import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/page_scaffold.dart';
import '../design/pressable.dart';
import '../design/section_label.dart';
import '../design/tokens.dart';
import '../domain/habit.dart';
import '../state/providers.dart';
import 'habit_form_page.dart';
import 'labels.dart';
import 'navigation.dart';

class HabitsPage extends ConsumerWidget {
  const HabitsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final habits = ref.watch(habitsProvider).value ?? const <Habit>[];
    final archived = ref.watch(archivedHabitsProvider).value ?? const <Habit>[];

    return PageScaffold(
      title: 'Habits',
      primaryAction: PageAction(
        label: 'Add habit',
        onPressed: () => openPage<void>(context, const HabitFormPage()),
      ),
      child: PageBody(
        children: [
          const SectionLabel('Active'),
          const SizedBox(height: Space.s),
          if (habits.isEmpty)
            Text(
              'No active habits.',
              style: CohabitType.body(c).copyWith(color: c.muted),
            ),
          for (final habit in habits) ...[
            _HabitListRow(
              key: ValueKey('habit-${habit.id}'),
              habit: habit,
              onTap: () => openPage<void>(context, HabitFormPage(habit: habit)),
            ),
            const SizedBox(height: Space.s),
          ],
          if (archived.isNotEmpty) ...[
            const SizedBox(height: Space.l),
            const SectionLabel('Archived'),
            const SizedBox(height: Space.s),
            for (final habit in archived) ...[
              _HabitListRow(habit: habit),
              const SizedBox(height: Space.s),
            ],
          ],
        ],
      ),
    );
  }
}

class _HabitListRow extends StatelessWidget {
  const _HabitListRow({super.key, required this.habit, this.onTap});

  final Habit habit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final meta = [
      if (habit.isNegative) 'avoid',
      scheduleLabel(habit.schedule),
    ].join(' · ');
    return Pressable(
      onPressed: onTap,
      builder: (context, s) => Container(
        padding: const EdgeInsets.all(Space.m),
        constraints: BoxConstraints(minHeight: ControlSize.of(context)),
        decoration: BoxDecoration(
          color: s.hovered ? c.off : c.surface,
          border: Border.all(color: s.focused ? c.blue3 : c.hairline),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    habit.name,
                    style: CohabitType.name(c)
                        .copyWith(color: onTap == null ? c.muted : c.text),
                  ),
                  const SizedBox(height: 2),
                  Text(meta, style: CohabitType.meta(c)),
                ],
              ),
            ),
            if (onTap != null)
              ExcludeSemantics(child: Text('→', style: CohabitType.meta(c))),
          ],
        ),
      ),
    );
  }
}
