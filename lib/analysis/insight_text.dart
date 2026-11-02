import 'package:cohabit_analysis/cohabit_analysis.dart';

import '../domain/habit.dart';

/// A finding ready to show: a plain sentence, the numbers beneath it and
/// what a screen reader says.
class InsightText {
  const InsightText({
    required this.sentence,
    required this.stats,
    required this.semantics,
  });

  final String sentence;
  final List<String> stats;
  final String semantics;
}

/// Formats a ratio such as `2.3x`'s number: more digits as it gets small.
String formatRatio(double v) {
  if (v >= 9.95) return v.toStringAsFixed(0);
  if (v >= 0.095) return v.toStringAsFixed(1);
  return v.toStringAsFixed(2);
}

/// Phi with an explicit sign, using a real minus.
String formatPhi(double v) {
  final text = v.abs().toStringAsFixed(2);
  if (v.abs() < 0.005) return text;
  return v < 0 ? '−$text' : '+$text';
}

/// What "done" means for [h] in a sentence: the habit's name, or a slip.
String eventPhrase(Habit h) => h.isNegative ? 'slipping on ${h.name}' : h.name;

String _capitalise(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String timingPhrase(int lag) => switch (lag) {
  0 => 'on the same day',
  1 => 'the next day',
  _ => '$lag days later',
};

String _timingShort(int lag) => lag == 0 ? 'same day' : '+${lag}d';

/// The wording of one pair. Always "tends to go with": these are patterns in
/// the logs, never causes.
InsightText describeInsight(PairResult p, Habit from, Habit to) {
  final positive = (p.phi ?? 0) >= 0;
  final sentence =
      '${_capitalise(eventPhrase(from))} tends to go with '
      '${positive ? '' : 'less '}${eventPhrase(to)} ${timingPhrase(p.lag)}.';

  final pair = '${from.name} ${p.lag == 0 ? '&' : '->'} ${to.name}';
  final stats = <String>[
    pair,
    if (p.lag > 0) _timingShort(p.lag),
    if (p.ratio != null) '${formatRatio(p.ratio!)}x',
    'n=${p.n}',
    if (p.ratioLow != null && p.ratioHigh != null)
      'CI ${formatRatio(p.ratioLow!)}-${formatRatio(p.ratioHigh!)}',
    if (p.phi != null) 'phi ${formatPhi(p.phi!)}',
  ];

  final ratioWords = p.ratio == null
      ? ''
      : '${formatRatio(p.ratio!)} times as likely, ';
  final interval = p.ratioLow != null && p.ratioHigh != null
      ? '95 percent confidence interval ${formatRatio(p.ratioLow!)} to '
            '${formatRatio(p.ratioHigh!)}, '
      : '';
  final semantics =
      '$sentence ${from.name} to ${to.name}, $ratioWords'
      '${p.n} days compared, $interval'
      'correlation ${formatPhi(p.phi ?? 0)}.';
  return InsightText(sentence: sentence, stats: stats, semantics: semantics);
}

/// Insights, strongest evidence first: lowest adjusted p, then largest
/// effect, then the earlier lag, so the order never depends on hash order.
List<PairResult> rankedInsights(AnalysisResult result) {
  final list = result.insights.toList();
  list.sort((a, b) {
    var c = a.q!.compareTo(b.q!);
    if (c != 0) return c;
    c = b.phi!.abs().compareTo(a.phi!.abs());
    if (c != 0) return c;
    c = a.lag.compareTo(b.lag);
    if (c != 0) return c;
    c = a.fromId.compareTo(b.fromId);
    return c != 0 ? c : a.toId.compareTo(b.toId);
  });
  return list;
}
