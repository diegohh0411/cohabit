import 'benjamini_hochberg.dart';
import 'model.dart';
import 'pair_stats.dart';

/// Runs stages 1 and 2: the same-day (phi) and lagged correlation of every
/// pair of habits, with false discovery control across all of them.
///
/// Pure and deterministic, with no I/O, so it is safe to run in an isolate.
AnalysisResult analyze(AnalysisInput input) {
  final config = input.config;
  final series = input.series;
  final days = series.isEmpty ? 0 : series.first.values.length;
  for (final s in series) {
    if (s.values.length != days) {
      throw ArgumentError('All series must have the same length');
    }
  }

  // Day of the week of every position (Monday is 1). 1970-01-01 was a
  // Thursday.
  final weekdays = List<int>.generate(
    days,
    (j) => (input.startEpochDay + j + 3) % 7 + 1,
  );

  final raw = <({String from, String to, int lag, PairStats stats})>[];
  var maxOverlap = 0;

  void add(int i, int k, int lag) {
    final from = series[i].values;
    final to = series[k].values;
    // Align `to` by `lag` days: position j compares from[j] with to[j + lag].
    final span = days - lag;
    if (span <= 0) return;
    final x = from.sublist(0, span);
    final y = to.sublist(lag);
    final stats = computePairStats(x, y, weekdays.sublist(0, span), config);
    if (stats.n > maxOverlap) maxOverlap = stats.n;
    raw.add((from: series[i].id, to: series[k].id, lag: lag, stats: stats));
  }

  for (var i = 0; i < series.length; i++) {
    for (var k = i + 1; k < series.length; k++) {
      add(i, k, 0);
    }
  }
  for (final lag in config.lags) {
    if (lag <= 0) continue;
    for (var i = 0; i < series.length; i++) {
      for (var k = 0; k < series.length; k++) {
        if (i != k) add(i, k, lag);
      }
    }
  }

  // One false discovery family: every pair that could be tested.
  final testedIndexes = [
    for (var i = 0; i < raw.length; i++)
      if (raw[i].stats.status == PairStatus.tested) i,
  ];
  final adjusted = benjaminiHochberg([
    for (final i in testedIndexes) raw[i].stats.p!,
  ]);
  final qByIndex = <int, double>{
    for (var t = 0; t < testedIndexes.length; t++)
      testedIndexes[t]: adjusted[t],
  };

  final pairs = <PairResult>[
    for (var i = 0; i < raw.length; i++)
      () {
        final r = raw[i];
        final s = r.stats;
        final q = qByIndex[i];
        return PairResult(
          fromId: r.from,
          toId: r.to,
          lag: r.lag,
          status: s.status,
          n: s.n,
          rawPhi: s.rawPhi,
          phi: s.phi,
          phiLow: s.phiLow,
          phiHigh: s.phiHigh,
          nEff: s.nEff,
          p: s.p,
          q: q,
          ratio: s.ratio,
          ratioLow: s.ratioLow,
          ratioHigh: s.ratioHigh,
          isInsight:
              q != null && q <= config.fdr && s.phi!.abs() >= config.minAbsPhi,
        );
      }(),
  ];

  return AnalysisResult(
    habitIds: [for (final s in series) s.id],
    days: days,
    pairs: pairs,
    testsRun: testedIndexes.length,
    maxOverlap: maxOverlap,
    config: config,
  );
}
