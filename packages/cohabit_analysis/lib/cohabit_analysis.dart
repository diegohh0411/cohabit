/// Phi and lagged correlation for yes/no habit series. See `docs/SPEC.md`,
/// "Analysis", for the methodology.
library;

export 'src/analyze.dart' show analyze;
export 'src/benjamini_hochberg.dart' show benjaminiHochberg;
export 'src/model.dart';
export 'src/pair_stats.dart' show PairStats, computePairStats;
export 'src/special.dart'
    show normalQuantile, studentTTwoSidedP, regularizedIncompleteBeta;
