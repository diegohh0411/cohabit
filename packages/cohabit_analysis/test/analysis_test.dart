import 'package:cohabit_analysis/cohabit_analysis.dart';
import 'package:test/test.dart';

import 'support.dart';

const _monday = 20731; // 2026-10-05

AnalysisInput input(
  List<HabitSeries> series, {
  AnalysisConfig config = const AnalysisConfig(),
  int start = _monday,
}) => AnalysisInput(startEpochDay: start, series: series, config: config);

void main() {
  group('missing days', () {
    test('are excluded pairwise, so a third habit cannot change a pair', () {
      final rng = Rng(1);
      final a = [for (var i = 0; i < 90; i++) rng.chance(0.5) ? 1 : 0];
      final b = [for (var i = 0; i < 90; i++) rng.chance(0.5) ? 1 : 0];
      final c = [
        for (var i = 0; i < 90; i++) i % 3 == 0 ? Observation.missing : 1,
      ];
      final two = analyze(
        input([
          HabitSeries(id: 'a', values: a),
          HabitSeries(id: 'b', values: b),
        ]),
      );
      final three = analyze(
        input([
          HabitSeries(id: 'a', values: a),
          HabitSeries(id: 'b', values: b),
          HabitSeries(id: 'c', values: c),
        ]),
      );
      final ab2 = pair(two, 'a', 'b');
      final ab3 = pair(three, 'a', 'b');
      expect(ab3.n, 90);
      expect(ab3.phi, ab2.phi);
      expect(ab3.p, ab2.p);
      expect(pair(three, 'a', 'c').n, 60);
    });

    test('are not treated as notDone', () {
      // b is done whenever it is observed and a is done on the same days; if
      // the unobserved days counted as notDone for b they would be clearly
      // different from a. They must simply be left out.
      final rng = Rng(2);
      final a = [for (var i = 0; i < 100; i++) rng.chance(0.5) ? 1 : 0];
      final b = [
        for (var i = 0; i < 100; i++) i % 2 == 0 ? a[i] : Observation.missing,
      ];
      final asMissing = analyze(
        input([
          HabitSeries(id: 'a', values: a),
          HabitSeries(id: 'b', values: b),
        ]),
      );
      final asNotDone = analyze(
        input([
          HabitSeries(id: 'a', values: a),
          HabitSeries(
            id: 'b',
            values: [for (final v in b) v < 0 ? Observation.notDone : v],
          ),
        ]),
      );
      final p = pair(asMissing, 'a', 'b');
      expect(p.n, 50);
      expect(p.rawPhi, closeTo(1, 1e-12));
      expect(pair(asNotDone, 'a', 'b').rawPhi, lessThan(0.8));
    });

    test('a pair below 30 shared days gets no statistics at all', () {
      final rng = Rng(3);
      final a = [for (var i = 0; i < 60; i++) rng.chance(0.5) ? 1 : 0];
      final b = [
        for (var i = 0; i < 60; i++) i < 29 ? a[i] : Observation.missing,
      ];
      final p = pair(
        analyze(
          input([
            HabitSeries(id: 'a', values: a),
            HabitSeries(id: 'b', values: b),
          ]),
        ),
        'a',
        'b',
      );
      expect(p.n, 29);
      expect(p.status, PairStatus.tooFewDays);
      expect(p.phi, isNull);
      expect(p.p, isNull);
      expect(p.q, isNull);
      expect(p.isInsight, isFalse);
    });
  });

  group('day-of-week adjustment', () {
    test('two habits that only follow the weekday are not associated', () {
      final rng = Rng(4);
      List<int> weekdayHabit() => [
        for (var i = 0; i < 140; i++)
          rng.chance((i % 7) < 5 ? 0.9 : 0.1) ? 1 : 0,
      ];
      final r = analyze(
        input([
          HabitSeries(id: 'a', values: weekdayHabit()),
          HabitSeries(id: 'b', values: weekdayHabit()),
        ]),
      );
      final p = pair(r, 'a', 'b');
      expect(p.rawPhi, greaterThan(0.4));
      expect(p.phi!.abs(), lessThan(0.25));
      expect(p.isInsight, isFalse);
    });

    test(
      'a habit fully explained by the weekday is constant after adjusting',
      () {
        final rng = Rng(5);
        final r = analyze(
          input([
            HabitSeries(
              id: 'mondays',
              values: [for (var i = 0; i < 98; i++) i % 7 == 0 ? 1 : 0],
            ),
            HabitSeries(
              id: 'coin',
              values: [for (var i = 0; i < 98; i++) rng.chance(0.5) ? 1 : 0],
            ),
          ]),
        );
        final p = pair(r, 'mondays', 'coin');
        expect(p.status, PairStatus.constant);
        expect(p.rawPhi, isNotNull);
        expect(p.phi, isNull);
        expect(p.p, isNull);
      },
    );
  });

  group('degenerate series', () {
    test('a constant habit has no correlation and stays out of the family', () {
      final rng = Rng(6);
      final r = analyze(
        input([
          HabitSeries(id: 'always', values: List.filled(60, 1)),
          HabitSeries(id: 'never', values: List.filled(60, 0)),
          HabitSeries(
            id: 'coin',
            values: [for (var i = 0; i < 60; i++) rng.chance(0.5) ? 1 : 0],
          ),
        ]),
      );
      for (final id in ['always', 'never']) {
        final p = pair(r, id, 'coin');
        expect(p.status, PairStatus.constant);
        expect(p.rawPhi, isNull);
        expect(p.phi, isNull);
        expect(p.p, isNull);
        expect(p.q, isNull);
        expect(p.isInsight, isFalse);
      }
      expect(pair(r, 'always', 'never').status, PairStatus.constant);
      // Only the testable pairs count towards the correction.
      expect(r.testsRun, 0);
    });

    test('a very rare habit is described but not tested', () {
      final rng = Rng(7);
      final rare = List<int>.filled(90, 0)
        ..[10] = 1
        ..[40] = 1
        ..[77] = 1;
      final r = analyze(
        input([
          HabitSeries(id: 'rare', values: rare),
          HabitSeries(
            id: 'coin',
            values: [for (var i = 0; i < 90; i++) rng.chance(0.5) ? 1 : 0],
          ),
        ]),
      );
      final p = pair(r, 'rare', 'coin');
      expect(p.status, PairStatus.sparse);
      expect(p.phi, isNotNull);
      expect(p.p, isNull);
      expect(p.isInsight, isFalse);
    });

    test('empty and single-habit inputs produce no pairs', () {
      expect(analyze(input([])).pairs, isEmpty);
      final one = analyze(
        input([HabitSeries(id: 'a', values: List.filled(40, 1))]),
      );
      expect(one.pairs, isEmpty);
      expect(one.maxOverlap, 0);
    });

    test('series of different lengths are rejected', () {
      expect(
        () => analyze(
          input([
            const HabitSeries(id: 'a', values: [1, 0]),
            const HabitSeries(id: 'b', values: [1]),
          ]),
        ),
        throwsArgumentError,
      );
    });
  });

  group('direction and polarity', () {
    List<HabitSeries> followed({bool negative = false}) {
      final rng = Rng(8);
      final a = [for (var i = 0; i < 160; i++) rng.chance(0.5) ? 1 : 0];
      final b = [
        for (var i = 0; i < 160; i++)
          i == 0
              ? 0
              : rng.chance(a[i - 1] == 1 ? 0.8 : 0.15)
              ? 1
              : 0,
      ];
      return [
        HabitSeries(id: 'sleep', values: a),
        HabitSeries(id: 'gym', values: b, negative: negative),
      ];
    }

    test('a lag is reported from the earlier day to the later one', () {
      final r = analyze(input(followed()));
      final forward = pair(r, 'sleep', 'gym', 1);
      final backward = pair(r, 'gym', 'sleep', 1);
      expect(forward.isInsight, isTrue);
      expect(forward.phi, greaterThan(0.4));
      expect(forward.ratio, greaterThan(2));
      expect(forward.ratioLow, greaterThan(1));
      expect(backward.isInsight, isFalse);
      expect(backward.phi!.abs(), lessThan(0.25));
      // The same-day pair is reported once, in input order.
      expect(
        r.pairs.where((p) => p.lag == 0).map((p) => '${p.fromId}>${p.toId}'),
        ['sleep>gym'],
      );
      // Every ordered pair at every configured lag.
      expect(r.pairs.where((p) => p.lag > 0).length, 2 * 3);
    });

    test('same-day phi and p do not depend on the order of the habits', () {
      final s = followed();
      final ab = analyze(input([s[0], s[1]]));
      final ba = analyze(input([s[1], s[0]]));
      final x = pair(ab, 'sleep', 'gym');
      final y = pair(ba, 'gym', 'sleep');
      expect(x.phi, closeTo(y.phi!, 1e-12));
      expect(x.p, closeTo(y.p!, 1e-12));
      expect(x.nEff, closeTo(y.nEff!, 1e-12));
    });

    test('negative polarity changes only the label, not the statistics', () {
      final positive = analyze(input(followed()));
      final negative = analyze(input(followed(negative: true)));
      for (var i = 0; i < positive.pairs.length; i++) {
        expect(negative.pairs[i].phi, positive.pairs[i].phi);
        expect(negative.pairs[i].p, positive.pairs[i].p);
        expect(negative.pairs[i].ratio, positive.pairs[i].ratio);
      }
    });

    test('a negative association has a negative phi and a ratio below 1', () {
      final rng = Rng(9);
      final a = [for (var i = 0; i < 160; i++) rng.chance(0.5) ? 1 : 0];
      final b = [
        for (var i = 0; i < 160; i++) rng.chance(a[i] == 1 ? 0.2 : 0.8) ? 1 : 0,
      ];
      final p = pair(
        analyze(
          input([
            HabitSeries(id: 'a', values: a),
            HabitSeries(id: 'b', values: b),
          ]),
        ),
        'a',
        'b',
      );
      expect(p.phi, lessThan(-0.4));
      expect(p.ratio, lessThan(0.5));
      expect(p.ratioHigh, lessThan(1));
      expect(p.isInsight, isTrue);
    });
  });

  group('autocorrelation', () {
    test('streaks shrink the effective sample size', () {
      final rng = Rng(10);
      final r = analyze(
        input([
          HabitSeries(id: 'a', values: runs(rng, 150, 0.9)),
          HabitSeries(id: 'b', values: runs(rng, 150, 0.9)),
        ]),
      );
      final p = pair(r, 'a', 'b');
      expect(p.n, 150);
      expect(p.nEff, lessThan(100));
      expect(p.phiHigh! - p.phiLow!, greaterThan(0.25));
    });

    test('independent coin flips keep nearly the full sample size', () {
      final rng = Rng(11);
      final r = analyze(
        input([
          HabitSeries(
            id: 'a',
            values: [for (var i = 0; i < 300; i++) rng.chance(0.5) ? 1 : 0],
          ),
          HabitSeries(
            id: 'b',
            values: [for (var i = 0; i < 300; i++) rng.chance(0.5) ? 1 : 0],
          ),
        ]),
      );
      expect(pair(r, 'a', 'b').nEff, greaterThan(200));
    });
  });

  group('error control (simulation)', () {
    test('streaky, unrelated habits rarely look related at 5%', () {
      final rng = Rng(12345);
      var hits = 0;
      const trials = 600;
      for (var t = 0; t < trials; t++) {
        final r = analyze(
          input([
            HabitSeries(id: 'a', values: runs(rng, 60, 0.85)),
            HabitSeries(id: 'b', values: runs(rng, 60, 0.85)),
          ], config: const AnalysisConfig(lags: [])),
        );
        final p = pair(r, 'a', 'b').p;
        if (p != null && p < 0.05) hits++;
      }
      // Without the autocorrelation correction about a quarter of these
      // pairs would pass (measured: 26% at 60 days of streaks this long).
      // The correction is conservative: about 1.6% pass.
      expect(hits / trials, lessThan(0.09), reason: '$hits of $trials');
    });

    test('false discoveries stay controlled across a whole family', () {
      final rng = Rng(777);
      var runsWithFalseInsight = 0;
      const trials = 120;
      for (var t = 0; t < trials; t++) {
        final r = analyze(
          input([
            for (var h = 0; h < 5; h++)
              HabitSeries(id: 'h$h', values: runs(rng, 90, 0.8)),
          ]),
        );
        // Every pair is truly null, so any insight is a false discovery.
        if (r.insights.isNotEmpty) runsWithFalseInsight++;
      }
      expect(runsWithFalseInsight / trials, lessThan(0.12));
    });

    // Power of a strong link (done 90% of the days the other is, 10%
    // otherwise): about 0.65 at the 30-day threshold, near 1 from 45 days.
    // Weaker links need more days (see docs/SPEC.md).
    double power(int days, {required int trials}) {
      var found = 0;
      final rng = Rng(99);
      for (var t = 0; t < trials; t++) {
        final a = [for (var i = 0; i < days; i++) rng.chance(0.5) ? 1 : 0];
        final b = [
          for (var i = 0; i < days; i++)
            rng.chance(a[i] == 1 ? 0.9 : 0.1) ? 1 : 0,
        ];
        final r = analyze(
          input([
            HabitSeries(id: 'a', values: a),
            HabitSeries(id: 'b', values: b),
          ], config: const AnalysisConfig(lags: [])),
        );
        if (pair(r, 'a', 'b').isInsight) found++;
      }
      return found / trials;
    }

    test('a strong real link is found about half the time at 30 days', () {
      expect(power(30, trials: 100), inInclusiveRange(0.4, 0.9));
    });

    test('and almost always from 45 days', () {
      expect(power(45, trials: 60), greaterThan(0.9));
    });
  });

  test('results are deterministic', () {
    final rng = Rng(42);
    final series = [
      for (var h = 0; h < 4; h++)
        HabitSeries(id: 'h$h', values: runs(rng, 120, 0.8)),
    ];
    final first = analyze(input(series));
    final second = analyze(input(series));
    expect(first.pairs.length, second.pairs.length);
    for (var i = 0; i < first.pairs.length; i++) {
      final x = first.pairs[i];
      final y = second.pairs[i];
      expect(
        [x.fromId, x.toId, x.lag, x.n, x.phi, x.p, x.q, x.ratio, x.isInsight],
        [y.fromId, y.toId, y.lag, y.n, y.phi, y.p, y.q, y.ratio, y.isInsight],
      );
    }
  });
}
