import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/buttons.dart';
import '../design/page_scaffold.dart';
import '../design/review_banner.dart';
import '../design/section_label.dart';
import '../design/tokens.dart';
import '../domain/habit_day.dart';
import '../state/providers.dart';
import 'day_page.dart';
import 'habit_form_page.dart';
import 'habit_log_row.dart';
import 'labels.dart';
import 'navigation.dart';

class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider).value;
    final habits = ref.watch(habitsProvider).value;

    return PageScaffold(
      title: 'Today',
      subtitle: today == null ? null : formatDay(today),
      actions: [
        CohabitButton.secondary(
          label: 'Day view',
          onPressed: today == null
              ? null
              : () => openPage<void>(context, DayPage(initialDay: today)),
        ),
        CohabitButton.primary(
          label: 'Add habit',
          onPressed: () => openPage<void>(context, const HabitFormPage()),
        ),
      ],
      child: today == null || habits == null
          ? const SizedBox.shrink()
          : _TodayBody(today: today),
    );
  }
}

class _TodayBody extends ConsumerWidget {
  const _TodayBody({required this.today});

  final HabitDay today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final habits = ref.watch(habitsProvider).value ?? const [];
    final states = ref.watch(dayStatesProvider(today)).value ?? const {};
    final scheduled = habits.where((h) => h.isScheduledOn(today)).toList();

    if (habits.isEmpty) {
      return PageBody(
        children: [
          Text(
            'No habits yet. Add one to start.',
            style: CohabitType.body(c).copyWith(color: c.muted),
          ),
        ],
      );
    }

    return PageBody(
      children: [
        _YesterdayReview(today: today),
        SectionLabel('Scheduled today · ${scheduled.length}'),
        const SizedBox(height: Space.s),
        if (scheduled.isEmpty)
          Text(
            'Nothing scheduled today.',
            style: CohabitType.body(c).copyWith(color: c.muted),
          ),
        for (final habit in scheduled) ...[
          HabitLogRow(
            key: ValueKey('today-${habit.id}'),
            habit: habit,
            day: today,
            logged: states[habit.id]?.state,
          ),
          const SizedBox(height: Space.s),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.l),
      child: ReviewBanner(
        key: const ValueKey('yesterday-review'),
        title:
            'Yesterday: $count ${count == 1 ? 'habit' : 'habits'} not logged',
        detail: unresolved.map((h) => h.name).join(', '),
        reviewKey: const ValueKey('review-yesterday'),
        dismissKey: const ValueKey('dismiss-review'),
        onReview: () => openPage<void>(context, DayPage(initialDay: yesterday)),
        onDismiss: () =>
            ref.read(dismissedReviewDayProvider.notifier).dismiss(yesterday),
      ),
    );
  }
}
