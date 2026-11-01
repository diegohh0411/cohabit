import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/habit_day.dart';
import '../state/providers.dart';
import 'day_page.dart';
import 'habit_day_tile.dart';
import 'habit_form_page.dart';
import 'habits_page.dart';
import 'labels.dart';
import 'settings_page.dart';

class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider).value;
    final habits = ref.watch(habitsProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Today'),
            if (today != null)
              Text(
                formatDay(today),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Day view',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: today == null
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DayPage(initialDay: today),
                    ),
                  ),
          ),
          IconButton(
            tooltip: 'Habits',
            icon: const Icon(Icons.list_alt_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const HabitsPage())),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const HabitFormPage())),
        icon: const Icon(Icons.add),
        label: const Text('Add habit'),
      ),
      body: today == null || habits == null
          ? const Center(child: CircularProgressIndicator())
          : _TodayBody(today: today),
    );
  }
}

class _TodayBody extends ConsumerWidget {
  const _TodayBody({required this.today});

  final HabitDay today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habits = ref.watch(habitsProvider).value ?? const [];
    final states = ref.watch(dayStatesProvider(today)).value ?? const {};
    final scheduled = habits.where((h) => h.isScheduledOn(today)).toList();

    if (habits.isEmpty) {
      return const Center(child: Text('No habits yet. Add one to start.'));
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        _YesterdayReview(today: today),
        if (scheduled.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Nothing scheduled today.'),
          ),
        for (final habit in scheduled) ...[
          HabitDayTile(
            key: ValueKey('today-${habit.id}'),
            habit: habit,
            day: today,
            logged: states[habit.id]?.state,
          ),
          const Divider(),
        ],
      ],
    );
  }
}

/// Prompt for yesterday's unresolved habits. Unresolved days stay unknown
/// until the user resolves them; dismissing only hides the prompt.
class _YesterdayReview extends ConsumerWidget {
  const _YesterdayReview({required this.today});

  final HabitDay today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final yesterday = today.addDays(-1);
    final unresolved = ref.watch(yesterdayReviewProvider);
    final dismissed = ref.watch(dismissedReviewDayProvider) == yesterday;
    if (unresolved.isEmpty || dismissed) return const SizedBox.shrink();

    final count = unresolved.length;
    return Card(
      key: const ValueKey('yesterday-review'),
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Yesterday: $count ${count == 1 ? 'habit' : 'habits'} not logged',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(unresolved.map((h) => h.name).join(', ')),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton(
                  key: const ValueKey('review-yesterday'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DayPage(initialDay: yesterday),
                    ),
                  ),
                  child: const Text('Review'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  key: const ValueKey('dismiss-review'),
                  onPressed: () => ref
                      .read(dismissedReviewDayProvider.notifier)
                      .dismiss(yesterday),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
