import 'dart:math' as math;

/// Natural log of the gamma function (Lanczos, g=7, n=9). Absolute error
/// about 1e-15 for x > 0.
double logGamma(double x) {
  const g = 7.0;
  const c = <double>[
    0.99999999999980993,
    676.5203681218851,
    -1259.1392167224028,
    771.32342877765313,
    -176.61502916214059,
    12.507343278686905,
    -0.13857109526572012,
    9.9843695780195716e-6,
    1.5056327351493116e-7,
  ];
  if (x < 0.5) {
    // Reflection.
    return math.log(math.pi / math.sin(math.pi * x).abs()) - logGamma(1 - x);
  }
  final z = x - 1;
  var a = c[0];
  final t = z + g + 0.5;
  for (var i = 1; i < 9; i++) {
    a += c[i] / (z + i);
  }
  return 0.5 * math.log(2 * math.pi) +
      (z + 0.5) * math.log(t) -
      t +
      math.log(a);
}

/// Regularized incomplete beta function I_x(a, b), by continued fraction
/// (modified Lentz). Accurate to roughly 1e-13.
double regularizedIncompleteBeta(double a, double b, double x) {
  if (x.isNaN || a <= 0 || b <= 0) return double.nan;
  if (x <= 0) return 0;
  if (x >= 1) return 1;
  final lnFront =
      logGamma(a + b) -
      logGamma(a) -
      logGamma(b) +
      a * math.log(x) +
      b * math.log(1 - x);
  // The fraction converges quickly for x < (a+1)/(a+b+2); otherwise use the
  // symmetry I_x(a,b) = 1 - I_(1-x)(b,a).
  if (x < (a + 1) / (a + b + 2)) {
    return math.exp(lnFront) * _betaFraction(a, b, x) / a;
  }
  return 1 - math.exp(lnFront) * _betaFraction(b, a, 1 - x) / b;
}

double _betaFraction(double a, double b, double x) {
  const tiny = 1e-300;
  const eps = 1e-16;
  final qab = a + b;
  final qap = a + 1;
  final qam = a - 1;
  var c = 1.0;
  var d = 1 - qab * x / qap;
  if (d.abs() < tiny) d = tiny;
  d = 1 / d;
  var h = d;
  for (var m = 1; m <= 1000; m++) {
    final m2 = 2 * m;
    var aa = m * (b - m) * x / ((qam + m2) * (a + m2));
    d = 1 + aa * d;
    if (d.abs() < tiny) d = tiny;
    c = 1 + aa / c;
    if (c.abs() < tiny) c = tiny;
    d = 1 / d;
    h *= d * c;
    aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2));
    d = 1 + aa * d;
    if (d.abs() < tiny) d = tiny;
    c = 1 + aa / c;
    if (c.abs() < tiny) c = tiny;
    d = 1 / d;
    final delta = d * c;
    h *= delta;
    if ((delta - 1).abs() < eps) break;
  }
  return h;
}

/// Two-sided p-value of a Student t statistic with [df] degrees of freedom
/// (not necessarily an integer).
double studentTTwoSidedP(double t, double df) {
  if (t.isNaN || df.isNaN || df <= 0) return double.nan;
  if (t.isInfinite) return 0;
  final x = df / (df + t * t);
  return regularizedIncompleteBeta(df / 2, 0.5, x);
}

/// Inverse of the standard normal CDF (Wichura's AS 241, PPND16; relative
/// error about 1e-16).
double normalQuantile(double p) {
  if (p.isNaN || p < 0 || p > 1) return double.nan;
  if (p == 0) return double.negativeInfinity;
  if (p == 1) return double.infinity;
  final q = p - 0.5;
  if (q.abs() <= 0.425) {
    final r = 0.180625 - q * q;
    return q *
        (((((((2509.0809287301226727 * r + 33430.575583588128105) * r +
                                                    67265.770927008700853) *
                                                r +
                                            45921.953931549871457) *
                                        r +
                                    13731.693765509461125) *
                                r +
                            1971.5909503065514427) *
                        r +
                    133.14166789178437745) *
                r +
            3.387132872796366608) /
        (((((((5226.495278852545925 * r + 28729.085735721942674) * r +
                                                    39307.89580009271061) *
                                                r +
                                            21213.794301586595867) *
                                        r +
                                    5394.1960214247511077) *
                                r +
                            687.1870074920579083) *
                        r +
                    42.313330701600911252) *
                r +
            1);
  }
  var r = q < 0 ? p : 1 - p;
  r = math.sqrt(-math.log(r));
  double value;
  if (r <= 5) {
    r -= 1.6;
    value =
        (((((((7.7454501427834140764e-4 * r + 0.0227238449892691845833) * r +
                                                    0.24178072517745061177) *
                                                r +
                                            1.27045825245236838258) *
                                        r +
                                    3.64784832476320460504) *
                                r +
                            5.7694972214606914055) *
                        r +
                    4.6303378461565452959) *
                r +
            1.42343711074968357734) /
        (((((((1.05075007164441684324e-9 * r + 5.475938084995344946e-4) * r +
                                                    0.0151986665636164571966) *
                                                r +
                                            0.14810397642748007459) *
                                        r +
                                    0.68976733498510000455) *
                                r +
                            1.6763848301838038494) *
                        r +
                    2.05319162663775882187) *
                r +
            1);
  } else {
    r -= 5;
    value =
        (((((((2.01033439929228813265e-7 * r + 2.71155556874348757815e-5) * r +
                                                    0.0012426609473880784386) *
                                                r +
                                            0.026532189526576123093) *
                                        r +
                                    0.29656057182850489123) *
                                r +
                            1.7848265399172913358) *
                        r +
                    5.4637849111641143699) *
                r +
            6.6579046435011037772) /
        (((((((2.04426310338993978564e-15 * r + 1.4215117583164458887e-7) * r +
                                                    1.8463183175100546818e-5) *
                                                r +
                                            7.868691311456132591e-4) *
                                        r +
                                    0.0148753612908506148525) *
                                r +
                            0.13692988092273580531) *
                        r +
                    0.59983220655588793769) *
                r +
            1);
  }
  return q < 0 ? -value : value;
}
