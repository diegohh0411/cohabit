import 'package:cohabit_analysis/cohabit_analysis.dart';
import 'package:test/test.dart';

import 'support.dart';

/// The Dart results must agree with the scikit-learn / SciPy values in
/// test/fixtures/analysis.json, produced by tool/generate_fixtures.py.
void main() {
  final data = fixture('analysis.json');
  final cfg = data['config']! as Map<String, Object?>;
  final config = AnalysisConfig(
    minOverlapDays: cfg['min_overlap_days']! as int,
    lags: [for (final l in cfg['lags']! as List) l as int],
    fdr: (cfg['fdr']! as num).toDouble(),
    confidence: (cfg['confidence']! as num).toDouble(),
    minAbsPhi: (cfg['min_abs_phi']! as num).toDouble(),
    minExpectedCell: (cfg['min_expected_cell']! as num).toDouble(),
    maxAutocorrLag: cfg['max_autocorr_lag']! as int,
    minAutocorrPairs: cfg['min_autocorr_pairs']! as int,
  );

  test('the default configuration is the one the fixtures were made with', () {
    const d = AnalysisConfig();
    expect(d.minOverlapDays, config.minOverlapDays);
    expect(d.lags, config.lags);
    expect(d.fdr, config.fdr);
    expect(d.confidence, config.confidence);
    expect(d.minAbsPhi, config.minAbsPhi);
    expect(d.minExpectedCell, config.minExpectedCell);
    expect(d.maxAutocorrLag, config.maxAutocorrLag);
    expect(d.minAutocorrPairs, config.minAutocorrPairs);
  });

  PairStatus status(String name) =>
      PairStatus.values.singleWhere((s) => s.name == name);

  for (final raw in data['cases']! as List) {
    final c = raw as Map<String, Object?>;
    final name = c['name']! as String;
    test(name, () {
      final input = AnalysisInput(
        startEpochDay: c['startEpochDay']! as int,
        series: [
          for (final s in c['series']! as List)
            HabitSeries(
              id: (s as Map<String, Object?>)['id']! as String,
              values: [for (final v in s['values']! as List) v as int],
            ),
        ],
        config: config,
      );
      final result = analyze(input);
      final expected = c['expected']! as Map<String, Object?>;
      final pairs = (expected['pairs']! as List).cast<Map<String, Object?>>();

      expect(result.testsRun, expected['testsRun']);
      expect(result.maxOverlap, expected['maxOverlap']);
      expect(result.pairs.length, pairs.length);

      void near(String field, double? actual, Object? want, String where) {
        if (want == null) {
          expect(actual, isNull, reason: '$where $field');
        } else {
          expect(actual, isNotNull, reason: '$where $field');
          expect(actual, closeTo9(want as num), reason: '$where $field');
        }
      }

      for (var i = 0; i < pairs.length; i++) {
        final e = pairs[i];
        final a = result.pairs[i];
        final where = '${e['fromId']}->${e['toId']} lag ${e['lag']}';
        expect(a.fromId, e['fromId'], reason: where);
        expect(a.toId, e['toId'], reason: where);
        expect(a.lag, e['lag'], reason: where);
        expect(a.status, status(e['status']! as String), reason: where);
        expect(a.n, e['n'], reason: where);
        expect(a.isInsight, e['isInsight'], reason: where);
        near('rawPhi', a.rawPhi, e['rawPhi'], where);
        near('phi', a.phi, e['phi'], where);
        near('phiLow', a.phiLow, e['phiLow'], where);
        near('phiHigh', a.phiHigh, e['phiHigh'], where);
        near('nEff', a.nEff, e['nEff'], where);
        near('p', a.p, e['p'], where);
        near('q', a.q, e['q'], where);
        near('ratio', a.ratio, e['ratio'], where);
        near('ratioLow', a.ratioLow, e['ratioLow'], where);
        near('ratioHigh', a.ratioHigh, e['ratioHigh'], where);
      }
    });
  }
}
