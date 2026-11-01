import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/habit.dart';
import '../state/providers.dart';
import 'habit_form_page.dart';
import 'labels.dart';

class HabitsPage extends ConsumerWidget {
  const HabitsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habits = ref.watch(habitsProvider).value ?? const <Habit>[];
    final archived = ref.watch(archivedHabitsProvider).value ?? const <Habit>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Habits')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add habit',
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const HabitFormPage())),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          if (habits.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No active habits.'),
            ),
          for (final habit in habits)
            ListTile(
              key: ValueKey('habit-${habit.id}'),
              title: Text(habit.name),
              subtitle: Text(
                '${habit.isNegative ? 'Avoid · ' : ''}'
                '${scheduleLabel(habit.schedule)}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => HabitFormPage(habit: habit),
                ),
              ),
            ),
          if (archived.isNotEmpty) ...[
            const Divider(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Archived'),
            ),
            for (final habit in archived)
              ListTile(
                title: Text(habit.name),
                subtitle: Text(
                  '${habit.isNegative ? 'Avoid · ' : ''}'
                  '${scheduleLabel(habit.schedule)}',
                ),
                enabled: false,
              ),
          ],
        ],
      ),
    );
  }
}
