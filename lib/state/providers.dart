import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repository.dart';
import '../domain/day_state.dart';
import '../domain/habit.dart';
import '../domain/habit_day.dart';

/// Overridden at startup with an opened repository.
final repositoryProvider = Provider<CohabitRepository>(
  (ref) => throw UnimplementedError('repositoryProvider must be overridden'),
);

/// Clock used by the UI; overridden in tests.
final nowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// How often the current habit day is re-evaluated.
final dayTickProvider = Provider<Duration>((ref) => const Duration(minutes: 1));

final dayBoundaryProvider = StreamProvider<int>(
  (ref) => ref.watch(repositoryProvider).watchDayBoundaryMinutes(),
);

/// The current habit day, following the configured boundary.
final todayProvider = StreamProvider<HabitDay>((ref) async* {
  final now = ref.watch(nowProvider);
  final tick = ref.watch(dayTickProvider);
  final boundary = await ref.watch(dayBoundaryProvider.future);
  HabitDay compute() => habitDayFor(now(), boundaryMinutes: boundary);

  var current = compute();
  yield current;
  // A periodic stream (unlike a bare delayed future) is cancelled with the
  // provider, leaving no timer behind.
  await for (final _ in Stream<void>.periodic(tick)) {
    final next = compute();
    if (next != current) {
      current = next;
      yield current;
    }
  }
});

/// Active (non-archived) habits.
final habitsProvider = StreamProvider<List<Habit>>(
  (ref) => ref.watch(repositoryProvider).watchHabits(),
);

/// Archived habits, for the management screen.
final archivedHabitsProvider = StreamProvider<List<Habit>>(
  (ref) => ref
      .watch(repositoryProvider)
      .watchHabits(includeArchived: true)
      .map((all) => all.where((h) => h.isArchived).toList()),
);

/// Resolved day states for a habit day, keyed by habit id.
final dayStatesProvider =
    StreamProvider.family<Map<String, DayStateEntry>, HabitDay>(
      (ref, day) => ref.watch(repositoryProvider).watchDayStates(day),
    );

/// Day for which the user dismissed the review prompt (this session only).
class DismissedReviewDay extends Notifier<HabitDay?> {
  @override
  HabitDay? build() => null;

  void dismiss(HabitDay day) => state = day;
}

final dismissedReviewDayProvider =
    NotifierProvider<DismissedReviewDay, HabitDay?>(DismissedReviewDay.new);

/// Habits scheduled yesterday that were created by then and are still
/// unresolved. Empty when there is nothing to review.
final yesterdayReviewProvider = Provider<List<Habit>>((ref) {
  final today = ref.watch(todayProvider).value;
  final habits = ref.watch(habitsProvider).value;
  if (today == null || habits == null) return const [];
  final yesterday = today.addDays(-1);
  final states = ref.watch(dayStatesProvider(yesterday)).value;
  if (states == null) return const [];
  return [
    for (final h in habits)
      if (h.isScheduledOn(yesterday) &&
          h.createdDay <= yesterday &&
          h.effectiveState(yesterday, states[h.id]?.state) == DayState.unknown)
        h,
  ];
});
