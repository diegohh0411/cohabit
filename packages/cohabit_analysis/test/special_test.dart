import 'package:cohabit_analysis/cohabit_analysis.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final data = fixture('special.json');
  List<Map<String, Object?>> list(String key) =>
      (data[key]! as List).cast<Map<String, Object?>>();

  test('Student t p-values match scipy.stats.t', () {
    for (final c in list('tCases')) {
      final df = (c['df']! as num).toDouble();
      final t = (c['t']! as num).toDouble();
      expect(
        studentTTwoSidedP(t, df),
        closeTo9(c['p']! as num),
        reason: 't=$t df=$df',
      );
    }
  });

  test('normal quantiles match scipy.stats.norm.ppf', () {
    for (final c in list('quantiles')) {
      final p = (c['p']! as num).toDouble();
      expect(normalQuantile(p), closeTo9(c['z']! as num), reason: 'p=$p');
    }
    expect(normalQuantile(0.5), 0);
    expect(normalQuantile(0), double.negativeInfinity);
    expect(normalQuantile(1), double.infinity);
  });

  test('incomplete beta matches scipy.special.betainc', () {
    for (final c in list('betas')) {
      final a = (c['a']! as num).toDouble();
      final b = (c['b']! as num).toDouble();
      final x = (c['x']! as num).toDouble();
      expect(
        regularizedIncompleteBeta(a, b, x),
        closeTo9(c['value']! as num),
        reason: 'a=$a b=$b x=$x',
      );
    }
  });

  test('Benjamini-Hochberg matches scipy.stats.false_discovery_control', () {
    for (final c in list('bh')) {
      final p = [for (final v in c['p']! as List) (v as num).toDouble()];
      final expected = [for (final v in c['q']! as List) (v as num).toDouble()];
      final q = benjaminiHochberg(p);
      expect(q.length, expected.length);
      for (var i = 0; i < q.length; i++) {
        expect(q[i], closeTo9(expected[i]), reason: 'p=$p index $i');
      }
    }
  });

  test('Benjamini-Hochberg: adjusted values never fall below the p-values', () {
    final rng = Rng(5);
    final p = [for (var i = 0; i < 50; i++) rng.next()];
    final q = benjaminiHochberg(p);
    for (var i = 0; i < p.length; i++) {
      expect(q[i], greaterThanOrEqualTo(p[i]));
      expect(q[i], lessThanOrEqualTo(1));
    }
    expect(benjaminiHochberg([]), isEmpty);
  });
}
