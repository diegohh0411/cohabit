import 'dart:async';
import 'dart:isolate';

import 'package:cohabit_analysis/cohabit_analysis.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analysis/analysis_input.dart';
import 'providers.dart';

/// Runs one analysis. The default uses a short-lived isolate, so the work
/// never blocks the UI thread; tests override it.
typedef AnalysisRunner = Future<AnalysisResult> Function(AnalysisInput input);

Future<AnalysisResult> runInIsolate(AnalysisInput input) =>
    Isolate.run(() => analyze(input));

final analysisRunnerProvider = Provider<AnalysisRunner>((ref) => runInIsolate);

/// A burst of taps (logging several habits in a row) starts one run, not one
/// per tap. Tests set this to zero.
final analysisDebounceProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 300),
);

/// The series to analyse, rebuilt whenever habits or logs change. Equal
/// inputs do not notify, so a log change that alters nothing in the analysed
/// window does not start a run.
final analysisInputProvider = Provider<AnalysisInput?>((ref) {
  final today = ref.watch(todayProvider).value;
  final habits = ref.watch(habitsProvider).value;
  final logged = ref.watch(loggedStatesProvider).value;
  if (today == null || habits == null || logged == null) return null;
  return buildAnalysisInput(habits: habits, logged: logged, today: today);
});

/// The latest analysis. Null while there are fewer than two habits. While a
/// newer run is in progress the previous result stays available as `value`.
final analysisProvider = FutureProvider<AnalysisResult?>((ref) async {
  final input = ref.watch(analysisInputProvider);
  if (input == null) return null;
  final debounce = ref.watch(analysisDebounceProvider);
  final runner = ref.watch(analysisRunnerProvider);
  if (debounce > Duration.zero) {
    // A newer input (or the end of the app) cancels the wait, so no timer
    // outlives the provider.
    final wait = Completer<void>();
    final timer = Timer(debounce, wait.complete);
    var cancelled = false;
    ref.onDispose(() {
      cancelled = true;
      timer.cancel();
      if (!wait.isCompleted) wait.complete();
    });
    await wait.future;
    // Superseded while waiting; the newer run owns the state.
    if (cancelled) return null;
  }
  return runner(input);
});
