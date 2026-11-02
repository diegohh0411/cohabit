/// Values of a [HabitSeries] cell.
abstract final class Observation {
  /// `done`, or a slip on a negative habit.
  static const int done = 1;

  /// `notDone`, or a confirmed clean day on a negative habit.
  static const int notDone = 0;

  /// `skipped` or `unknown`: left out of every comparison. Never `notDone`.
  static const int missing = -1;
}

/// One habit over a run of consecutive days.
class HabitSeries {
  const HabitSeries({
    required this.id,
    required this.values,
    this.negative = false,
  });

  final String id;

  /// One [Observation] per day, starting on [AnalysisInput.startEpochDay].
  final List<int> values;

  /// Whether the habit is a negative one (`1` means a slip). Carried for
  /// reporting only; the statistics treat both polarities the same way.
  final bool negative;

  @override
  bool operator ==(Object other) =>
      other is HabitSeries &&
      other.id == id &&
      other.negative == negative &&
      _sameInts(other.values, values);

  @override
  int get hashCode => Object.hash(id, negative, Object.hashAll(values));
}

bool _sameInts(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Tuning of an analysis. The defaults are the resolved thresholds from
/// `docs/SPEC.md`.
class AnalysisConfig {
  const AnalysisConfig({
    this.minOverlapDays = 30,
    this.lags = const [1, 2, 3],
    this.fdr = 0.05,
    this.confidence = 0.95,
    this.minAbsPhi = 0.1,
    this.minExpectedCell = 5,
    this.maxAutocorrLag = 14,
    this.minAutocorrPairs = 10,
  });

  /// A pair is not analysed below this many days on which both habits were
  /// observed.
  final int minOverlapDays;

  /// Positive lags to test, in days. Lag 0 (the same day) is always tested.
  final List<int> lags;

  /// Benjamini-Hochberg level.
  final double fdr;

  /// Level of the confidence intervals.
  final double confidence;

  /// An association must be at least this strong (absolute adjusted phi) to
  /// become an insight, however certain it is.
  final double minAbsPhi;

  /// Minimum expected count in every cell of the pooled 2x2 table; sparser
  /// pairs are described but not tested.
  final double minExpectedCell;

  /// Autocorrelation is estimated up to this lag, in days (or n/4 if less).
  final int maxAutocorrLag;

  /// Autocorrelation at a lag is ignored when fewer day pairs than this
  /// exist at that lag.
  final int minAutocorrPairs;

  @override
  bool operator ==(Object other) =>
      other is AnalysisConfig &&
      other.minOverlapDays == minOverlapDays &&
      _sameInts(other.lags, lags) &&
      other.fdr == fdr &&
      other.confidence == confidence &&
      other.minAbsPhi == minAbsPhi &&
      other.minExpectedCell == minExpectedCell &&
      other.maxAutocorrLag == maxAutocorrLag &&
      other.minAutocorrPairs == minAutocorrPairs;

  @override
  int get hashCode => Object.hash(
    minOverlapDays,
    Object.hashAll(lags),
    fdr,
    confidence,
    minAbsPhi,
    minExpectedCell,
    maxAutocorrLag,
    minAutocorrPairs,
  );
}

class AnalysisInput {
  const AnalysisInput({
    required this.startEpochDay,
    required this.series,
    this.config = const AnalysisConfig(),
  });

  /// Days since 1970-01-01 of the first cell of every series. Used only to
  /// find the day of the week.
  final int startEpochDay;

  /// All series must have the same length.
  final List<HabitSeries> series;
  final AnalysisConfig config;

  /// Equal inputs give equal results, so callers can skip repeating a run.
  @override
  bool operator ==(Object other) =>
      other is AnalysisInput &&
      other.startEpochDay == startEpochDay &&
      other.config == config &&
      other.series.length == series.length &&
      [for (var i = 0; i < series.length; i++) series[i] == other.series[i]]
          .every((same) => same);

  @override
  int get hashCode =>
      Object.hash(startEpochDay, config, Object.hashAll(series));
}

enum PairStatus {
  /// Fewer than [AnalysisConfig.minOverlapDays] days with both observed.
  tooFewDays,

  /// One habit never varies once day-of-week effects are removed, so there
  /// is nothing to correlate.
  constant,

  /// Enough days and variation, but cells too sparse for the significance
  /// test to be trusted. Effect size only.
  sparse,

  /// Tested, with a p-value that went into the false discovery correction.
  tested,
}

/// One association: [fromId] on a day against [toId] [lag] days later (the
/// same day when [lag] is 0).
class PairResult {
  const PairResult({
    required this.fromId,
    required this.toId,
    required this.lag,
    required this.status,
    required this.n,
    this.rawPhi,
    this.phi,
    this.phiLow,
    this.phiHigh,
    this.nEff,
    this.p,
    this.q,
    this.ratio,
    this.ratioLow,
    this.ratioHigh,
    this.isInsight = false,
  });

  /// The habit on the earlier day. For [lag] 0 this is the first of the two in
  /// input order, which only fixes which one the ratio is stated for.
  final String fromId;

  /// The habit [lag] days after [fromId]'s day.
  final String toId;
  final int lag;
  final PairStatus status;

  /// Days on which both habits were observed.
  final int n;

  /// Phi (Matthews correlation) before any adjustment, for reference.
  final double? rawPhi;

  /// Phi after removing day-of-week effects, with its confidence interval.
  /// Positive means `done` tends to go with `done`.
  final double? phi;
  final double? phiLow;
  final double? phiHigh;

  /// Sample size after discounting for autocorrelation.
  final double? nEff;

  /// Two-sided p-value, and its Benjamini-Hochberg adjusted value.
  final double? p;
  final double? q;

  /// How many times as likely [toId] is `done` on days [fromId] is `done`
  /// than on days it is not (Mantel-Haenszel, by day of week), with its
  /// confidence interval. Null if undefined.
  final double? ratio;
  final double? ratioLow;
  final double? ratioHigh;

  /// Whether the pair clears every bar (days, FDR, effect size) and may be
  /// shown as a finding.
  final bool isInsight;
}

class AnalysisResult {
  const AnalysisResult({
    required this.habitIds,
    required this.days,
    required this.pairs,
    required this.testsRun,
    required this.maxOverlap,
    required this.config,
  });

  /// Habits in input order.
  final List<String> habitIds;

  /// Length of the series.
  final int days;

  /// Every pair at lag 0 and at each lag, in a fixed order.
  final List<PairResult> pairs;

  /// Number of hypotheses in the false discovery family.
  final int testsRun;

  /// The largest overlap of any pair, so the app can tell how close it is to
  /// the threshold.
  final int maxOverlap;
  final AnalysisConfig config;

  Iterable<PairResult> get insights => pairs.where((p) => p.isInsight);
}
