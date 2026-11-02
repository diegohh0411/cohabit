import 'dart:math' as math;

import 'model.dart';
import 'special.dart';

/// Statistics of one association, before the false discovery correction.
class PairStats {
  const PairStats({
    required this.status,
    required this.n,
    this.rawPhi,
    this.phi,
    this.phiLow,
    this.phiHigh,
    this.nEff,
    this.p,
    this.ratio,
    this.ratioLow,
    this.ratioHigh,
  });

  final PairStatus status;
  final int n;
  final double? rawPhi;
  final double? phi;
  final double? phiLow;
  final double? phiHigh;
  final double? nEff;
  final double? p;
  final double? ratio;
  final double? ratioLow;
  final double? ratioHigh;
}

const double _varianceEpsilon = 1e-9;

/// Computes the association of [x] with [y] on the days both are observed.
///
/// [x] and [y] are aligned: `x[j]` and `y[j]` are compared, so for a lag the
/// caller passes `y` already shifted. [weekdays] holds each position's day of
/// the week of `x[j]` (1 to 7; with a fixed lag the day of `y[j]` is a
/// one-to-one function of it, so it defines the same strata). Entries are
/// [Observation] values.
///
/// See `docs/SPEC.md`, "Analysis", for the definitions.
PairStats computePairStats(
  List<int> x,
  List<int> y,
  List<int> weekdays,
  AnalysisConfig config,
) {
  assert(x.length == y.length && x.length == weekdays.length);
  final length = x.length;

  // Positions where both are observed.
  final idx = <int>[
    for (var j = 0; j < length; j++)
      if (x[j] >= 0 && y[j] >= 0) j,
  ];
  final n = idx.length;
  if (n < config.minOverlapDays) {
    return PairStats(status: PairStatus.tooFewDays, n: n);
  }

  // Unadjusted phi from the pooled 2x2 table.
  var n11 = 0, n10 = 0, n01 = 0, n00 = 0;
  for (final j in idx) {
    if (x[j] == 1) {
      y[j] == 1 ? n11++ : n10++;
    } else {
      y[j] == 1 ? n01++ : n00++;
    }
  }
  final row1 = n11 + n10, row0 = n01 + n00;
  final col1 = n11 + n01, col0 = n10 + n00;
  final rawDenominator = math.sqrt(
    row1.toDouble() * row0 * col1.toDouble() * col0,
  );
  final rawPhi = rawDenominator == 0
      ? null
      : (n11 * n00 - n10 * n01) / rawDenominator;

  // Remove day-of-week effects: subtract each weekday's mean (the residuals
  // of regressing on weekday indicators), which makes the correlation below
  // the partial correlation given the day of the week.
  final sumX = List<double>.filled(8, 0);
  final sumY = List<double>.filled(8, 0);
  final count = List<int>.filled(8, 0);
  for (final j in idx) {
    final w = weekdays[j];
    sumX[w] += x[j];
    sumY[w] += y[j];
    count[w]++;
  }
  final residualX = List<double>.filled(length, 0);
  final residualY = List<double>.filled(length, 0);
  var sxx = 0.0, syy = 0.0, sxy = 0.0;
  for (final j in idx) {
    final w = weekdays[j];
    final rx = x[j] - sumX[w] / count[w];
    final ry = y[j] - sumY[w] / count[w];
    residualX[j] = rx;
    residualY[j] = ry;
    sxx += rx * rx;
    syy += ry * ry;
    sxy += rx * ry;
  }
  if (sxx < _varianceEpsilon || syy < _varianceEpsilon) {
    return PairStats(status: PairStatus.constant, n: n, rawPhi: rawPhi);
  }
  final phi = (sxy / math.sqrt(sxx * syy)).clamp(-1.0, 1.0).toDouble();
  final ratio = _mantelHaenszel(x, y, weekdays, idx);

  // Too sparse for the test: some cell of the pooled table is expected to
  // hold fewer than a handful of days.
  final minExpected = math.min(row1, row0) * math.min(col1, col0) / n;
  if (minExpected < config.minExpectedCell) {
    return PairStats(status: PairStatus.sparse, n: n, rawPhi: rawPhi, phi: phi);
  }

  // Autocorrelation: Bartlett's variance of a cross-correlation between two
  // autocorrelated series, 1 + 2 * sum_k rho_x(k) rho_y(k), is the design
  // effect. The effective sample size is n divided by it (never above n).
  final present = List<bool>.filled(length, false);
  for (final j in idx) {
    present[j] = true;
  }
  final maxLag = math.min(config.maxAutocorrLag, n ~/ 4);
  var crossSum = 0.0;
  for (var h = 1; h <= maxLag; h++) {
    var pairs = 0;
    var px = 0.0, py = 0.0;
    for (final j in idx) {
      final k = j + h;
      if (k < length && present[k]) {
        pairs++;
        px += residualX[j] * residualX[k];
        py += residualY[j] * residualY[k];
      }
    }
    if (pairs < config.minAutocorrPairs) continue;
    final rhoX = (px / pairs) / (sxx / n);
    final rhoY = (py / pairs) / (syy / n);
    crossSum += rhoX.clamp(-1.0, 1.0) * rhoY.clamp(-1.0, 1.0);
  }
  final designEffect = math.max(1.0, 1 + 2 * crossSum);
  final nEff = n / designEffect;

  final controls = count.where((c) => c > 0).length - 1;
  final df = nEff - 2 - controls;
  double p;
  double low, high;
  if (df < 1) {
    p = 1;
    low = -1;
    high = 1;
  } else {
    final t = phi.abs() >= 1
        ? double.infinity
        : phi * math.sqrt(df / (1 - phi * phi));
    p = studentTTwoSidedP(t, df);
    final se = 1 / math.sqrt(nEff - 3 - controls);
    if (nEff - 3 - controls > 0 && phi.abs() < 1) {
      final z = normalQuantile(1 - (1 - config.confidence) / 2);
      final center = _atanh(phi);
      low = _tanh(center - z * se);
      high = _tanh(center + z * se);
    } else {
      low = -1;
      high = 1;
    }
  }

  double? ratioLow, ratioHigh;
  if (ratio != null && ratio.logVariance > 0) {
    final z = normalQuantile(1 - (1 - config.confidence) / 2);
    final se = math.sqrt(ratio.logVariance * designEffect);
    final lnRatio = math.log(ratio.value);
    ratioLow = math.exp(lnRatio - z * se);
    ratioHigh = math.exp(lnRatio + z * se);
  }

  return PairStats(
    status: PairStatus.tested,
    n: n,
    rawPhi: rawPhi,
    phi: phi,
    phiLow: low,
    phiHigh: high,
    nEff: nEff,
    p: p,
    ratio: ratio?.value,
    ratioLow: ratioLow,
    ratioHigh: ratioHigh,
  );
}

class _Ratio {
  const _Ratio(this.value, this.logVariance);
  final double value;
  final double logVariance;
}

/// Mantel-Haenszel risk ratio of `y == 1` given `x == 1` against `x == 0`,
/// stratified by weekday, with the Greenland-Robins variance of its log.
/// Null when a numerator or denominator sum is zero.
_Ratio? _mantelHaenszel(
  List<int> x,
  List<int> y,
  List<int> weekdays,
  List<int> idx,
) {
  final a = List<double>.filled(8, 0); // x=1, y=1
  final b = List<double>.filled(8, 0); // x=1, y=0
  final c = List<double>.filled(8, 0); // x=0, y=1
  final d = List<double>.filled(8, 0); // x=0, y=0
  for (final j in idx) {
    final w = weekdays[j];
    if (x[j] == 1) {
      y[j] == 1 ? a[w]++ : b[w]++;
    } else {
      y[j] == 1 ? c[w]++ : d[w]++;
    }
  }
  var r = 0.0, s = 0.0, v = 0.0;
  for (var w = 1; w <= 7; w++) {
    final total = a[w] + b[w] + c[w] + d[w];
    if (total == 0) continue;
    final exposed = a[w] + b[w];
    final unexposed = c[w] + d[w];
    final cases = a[w] + c[w];
    r += a[w] * unexposed / total;
    s += c[w] * exposed / total;
    v += (exposed * unexposed * cases - a[w] * c[w] * total) / (total * total);
  }
  if (r <= 0 || s <= 0) return null;
  return _Ratio(r / s, v / (r * s));
}

double _atanh(double x) => 0.5 * math.log((1 + x) / (1 - x));

double _tanh(double x) {
  if (x > 20) return 1;
  if (x < -20) return -1;
  final e = math.exp(2 * x);
  return (e - 1) / (e + 1);
}
