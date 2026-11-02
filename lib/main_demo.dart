import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/database.dart';
import 'data/repository.dart';
import 'design/system_ui.dart';
import 'domain/day_state.dart';
import 'domain/habit_day.dart';
import 'state/providers.dart';
import 'ui/app_shell.dart';

/// Development entry point with a throwaway in-memory database holding about
/// fourteen months of generated history, so the graphs have something to
/// show. Nothing is written to disk.
///
///     flutter run -t lib/main_demo.dart -d macos
///
/// A built binary also reads `COHABIT_THEME` (light or dark) and
/// `COHABIT_SECTION` (today, history, habits or settings) from its
/// environment, which makes repeatable screenshots easy.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await enableEdgeToEdge();
  final repository = await _seed();
  final theme = Platform.environment['COHABIT_THEME'];
  final section = Platform.environment['COHABIT_SECTION'];
  runApp(
    ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repository)],
      child: CohabitApp(
        themeMode: switch (theme) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        },
        initialSection: Section.values.firstWhere(
          (s) => s.name == section,
          orElse: () => Section.today,
        ),
      ),
    ),
  );
}

Future<CohabitRepository> _seed() async {
  final real = DateTime.now();
  final start = DateTime(real.year, real.month, real.day - 420, 10);
  var now = start;
  final db = AppDatabase(NativeDatabase.memory());
  final repo = await CohabitRepository.open(db, now: () => now);

  const all = {1, 2, 3, 4, 5, 6, 7};
  final run = await repo.createHabit(
    name: 'Run',
    polarity: HabitPolarity.positive,
    schedule: {1, 2, 3, 4, 5, 6},
  );
  final read = await repo.createHabit(
    name: 'Read for 20 minutes',
    polarity: HabitPolarity.positive,
    schedule: all,
  );
  final sleep = await repo.createHabit(
    name: 'In bed before 23:00',
    polarity: HabitPolarity.positive,
    schedule: all,
  );
  final scroll = await repo.createHabit(
    name: 'Doomscrolling',
    polarity: HabitPolarity.negative,
    schedule: all,
  );
  final gym = await repo.createHabit(
    name: 'Gym',
    polarity: HabitPolarity.positive,
    schedule: {1, 3, 5},
  );

  // Deterministic pseudo-randomness, so screenshots are repeatable.
  var seed = 7;
  double next() {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed / 0x7fffffff;
  }

  final today = HabitDay.fromDate(real);
  var lastSleepDone = false;
  for (var offset = 0; offset < 420; offset++) {
    now = start.add(Duration(days: offset));
    final day = HabitDay.fromDate(now);
    if (offset == 280) await repo.editHabit(gym, schedule: {2, 4, 6});
    if (day >= today.addDays(-1)) break; // leave yesterday and today open

    Future<void> log(String id, DayState state) =>
        repo.setDayState(id, day, state);

    // Habits start out patchy and settle, with the odd gap left unlogged.
    final improving = offset / 420;
    final r = next();
    if (day.weekday != 7 && r < 0.45 + 0.4 * improving) {
      await log(run, DayState.done);
    } else if (day.weekday != 7 && r < 0.9) {
      await log(run, DayState.notDone);
    }
    // Reading follows a good night (the day before); that is the lagged
    // pattern the Insights screen should pick up.
    final r2 = next();
    final readChance = lastSleepDone ? 0.85 : 0.45;
    if (r2 < readChance) {
      await log(read, DayState.done);
    } else if (r2 < 0.92) {
      await log(read, DayState.notDone);
    }
    final r3 = next();
    final sleepDone = r3 < 0.35 + 0.5 * improving;
    lastSleepDone = sleepDone;
    if (sleepDone) {
      await log(sleep, DayState.done);
    } else if (r3 < 0.95) {
      await log(sleep, DayState.notDone);
    } else {
      await log(sleep, DayState.skipped);
    }
    // Slips on the same day as a bad night: a same-day link.
    final r4 = next();
    if (r4 < (sleepDone ? 0.1 : 0.45) - 0.05 * improving) {
      await log(scroll, DayState.done); // a slip
    } else if (r4 < 0.9) {
      await log(scroll, DayState.notDone); // confirmed clean
    }
    final gymDays = offset < 280 ? {1, 3, 5} : {2, 4, 6};
    if (gymDays.contains(day.weekday)) {
      final r5 = next();
      if (r5 < 0.6) await log(gym, DayState.done);
      if (r5 >= 0.6 && r5 < 0.85) await log(gym, DayState.notDone);
    }
  }
  // Reopen on the same database with the real clock.
  return CohabitRepository.open(db);
}
