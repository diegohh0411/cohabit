import 'package:cohabit_analysis/cohabit_analysis.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analysis/insight_text.dart';
import '../design/page_scaffold.dart';
import '../design/pressable.dart';
import '../design/section_label.dart';
import '../design/tokens.dart';
import '../domain/habit.dart';
import '../state/analysis_providers.dart';
import '../state/providers.dart';

/// The drill-down behind the findings: the same-day phi matrix for every pair
/// of habits, and the numbers for any one pair, same day and lagged.
class PairsPage extends ConsumerStatefulWidget {
  const PairsPage({super.key});

  @override
  ConsumerState<PairsPage> createState() => _PairsPageState();
}

class _PairsPageState extends ConsumerState<PairsPage> {
  /// Selected pair, as habit ids in matrix order (row, column).
  (String, String)? _selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final habits = ref.watch(habitsProvider).value ?? const <Habit>[];
    final result = ref.watch(analysisProvider).value;

    return PageScaffold(
      title: 'All pairs',
      // Takes focus so Escape goes back without a click first.
      child: Focus(
        autofocus: true,
        child: PageBody(
          children: [
            if (result == null || habits.length < 2)
              Text(
                habits.length < 2
                    ? 'Add at least two habits to compare them.'
                    : 'Analysing your logs…',
                style: CohabitType.body(c).copyWith(color: c.muted),
              )
            else ...[
              Text(
                'Same-day phi for each pair, after removing day-of-week '
                'effects. +1 means done together, −1 means opposite. An '
                'outlined cell cleared the bar for a finding. Tap a cell for '
                'its numbers.',
                style: CohabitType.body(c).copyWith(color: c.muted),
              ),
              const SizedBox(height: Space.l),
              _Matrix(
                habits: habits,
                result: result,
                selected: _selected,
                onSelect: (pair) => setState(() => _selected = pair),
              ),
              const SizedBox(height: Space.xl),
              _Detail(habits: habits, result: result, selected: _selected),
            ],
          ],
        ),
      ),
    );
  }
}

PairResult? _lookup(AnalysisResult result, String from, String to, int lag) {
  for (final p in result.pairs) {
    if (p.lag == lag && p.fromId == from && p.toId == to) return p;
  }
  return null;
}

/// Same-day result for two habits, whichever way round the analysis stored
/// it.
PairResult? sameDay(AnalysisResult result, String a, String b) =>
    _lookup(result, a, b, 0) ?? _lookup(result, b, a, 0);

String _cellText(PairResult? p) {
  if (p == null) return '';
  return switch (p.status) {
    PairStatus.tooFewDays => '–',
    PairStatus.constant => '·',
    _ => p.phi == null ? '–' : formatPhi(p.phi!),
  };
}

String _cellSemantics(Habit a, Habit b, PairResult? p, int minDays) {
  final names = '${a.name} and ${b.name}';
  if (p == null) return names;
  return switch (p.status) {
    PairStatus.tooFewDays =>
      '$names: not enough data, ${p.n} of $minDays shared days',
    PairStatus.constant =>
      '$names: no variation to compare after removing day-of-week effects',
    PairStatus.sparse =>
      '$names: correlation ${formatPhi(p.phi!)}, too few days of one kind '
          'to test, ${p.n} days',
    PairStatus.tested =>
      '$names: correlation ${formatPhi(p.phi!)}, ${p.n} days'
          '${p.isInsight ? ', a finding' : ', not strong enough to report'}',
  };
}

class _Matrix extends StatelessWidget {
  const _Matrix({
    required this.habits,
    required this.result,
    required this.selected,
    required this.onSelect,
  });

  final List<Habit> habits;
  final AnalysisResult result;
  final (String, String)? selected;
  final ValueChanged<(String, String)> onSelect;

  static const double labelWidth = 128;
  static const double cellWidth = 64;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final minDays = result.config.minOverlapDays;
    return Semantics(
      container: true,
      label: 'Correlation matrix',
      child: SingleChildScrollView(
        key: const ValueKey('pairs-matrix'),
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Column numbers; the row labels carry the same numbers.
            ExcludeSemantics(
              child: Row(
                children: [
                  const SizedBox(width: labelWidth),
                  for (var j = 0; j < habits.length; j++)
                    SizedBox(
                      width: cellWidth,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: Space.xs),
                        child: Text(
                          '${j + 1}',
                          textAlign: TextAlign.center,
                          style: CohabitType.label(c),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            for (var i = 0; i < habits.length; i++)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: labelWidth,
                      child: Padding(
                        padding: const EdgeInsets.only(right: Space.s),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${i + 1}  ${habits[i].name}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: CohabitType.control(c),
                          ),
                        ),
                      ),
                    ),
                    for (var j = 0; j < habits.length; j++)
                      i == j
                          ? _Diagonal(c: c)
                          : _Cell(
                              key: ValueKey(
                                'cell-${habits[i].id}-${habits[j].id}',
                              ),
                              result: sameDay(
                                result,
                                habits[i].id,
                                habits[j].id,
                              ),
                              semantics: _cellSemantics(
                                habits[i],
                                habits[j],
                                sameDay(result, habits[i].id, habits[j].id),
                                minDays,
                              ),
                              selected:
                                  selected == (habits[i].id, habits[j].id),
                              onTap: () =>
                                  onSelect((habits[i].id, habits[j].id)),
                            ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Diagonal extends StatelessWidget {
  const _Diagonal({required this.c});

  final CohabitColors c;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: _Matrix.cellWidth,
      constraints: const BoxConstraints(minHeight: 44),
      margin: const EdgeInsets.all(1),
      color: c.off,
    ),
  );
}

class _Cell extends StatelessWidget {
  const _Cell({
    super.key,
    required this.result,
    required this.semantics,
    required this.selected,
    required this.onTap,
  });

  final PairResult? result;
  final String semantics;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final insight = result?.isInsight ?? false;
    return SizedBox(
      width: _Matrix.cellWidth,
      child: Pressable(
        onPressed: onTap,
        selected: selected,
        semanticLabel: semantics,
        builder: (context, s) => Container(
          constraints: const BoxConstraints(minHeight: 44),
          margin: const EdgeInsets.all(1),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: Space.xs),
          decoration: BoxDecoration(
            color: selected || s.hovered ? c.off : c.surface,
            border: Border.all(
              color: insight ? c.blue3 : c.hairline,
              width: insight ? 2 : 1,
            ),
          ),
          foregroundDecoration: s.focused
              ? BoxDecoration(border: Border.all(color: c.text, width: 2))
              : null,
          child: ExcludeSemantics(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _cellText(result),
                style: CohabitType.meta(c).copyWith(
                  color: c.text,
                  fontWeight: insight ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({
    required this.habits,
    required this.result,
    required this.selected,
  });

  final List<Habit> habits;
  final AnalysisResult result;
  final (String, String)? selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sel = selected;
    if (sel == null) {
      return Text(
        'Select a cell to see its numbers.',
        key: const ValueKey('pair-detail-empty'),
        style: CohabitType.meta(c),
      );
    }
    final byId = {for (final h in habits) h.id: h};
    final a = byId[sel.$1];
    final b = byId[sel.$2];
    if (a == null || b == null) return const SizedBox.shrink();

    final rows = <(String, PairResult?)>[
      ('Same day', sameDay(result, a.id, b.id)),
      for (final lag in result.config.lags) ...[
        (
          '${a.name} then ${b.name}, ${timingPhrase(lag)}',
          _lookup(result, a.id, b.id, lag),
        ),
        (
          '${b.name} then ${a.name}, ${timingPhrase(lag)}',
          _lookup(result, b.id, a.id, lag),
        ),
      ],
    ];
    return Column(
      key: const ValueKey('pair-detail'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel('${a.name} & ${b.name}'),
        const SizedBox(height: Space.s),
        for (final (label, p) in rows) ...[
          Text(label, style: CohabitType.name(c)),
          const SizedBox(height: 2),
          Text(_statsLine(p, result.config), style: CohabitType.meta(c)),
          const SizedBox(height: Space.m),
        ],
      ],
    );
  }
}

String _statsLine(PairResult? p, AnalysisConfig config) {
  if (p == null) return 'No data';
  switch (p.status) {
    case PairStatus.tooFewDays:
      return 'Not enough data: ${p.n} of ${config.minOverlapDays} shared days';
    case PairStatus.constant:
      return 'No variation left to compare after removing day-of-week '
          'effects (n=${p.n})';
    case PairStatus.sparse:
      return 'phi ${formatPhi(p.phi!)}  n=${p.n}  too few days of one kind '
          'to test';
    case PairStatus.tested:
      return [
        'phi ${formatPhi(p.phi!)}',
        'n=${p.n}',
        'effective n=${p.nEff!.round()}',
        if (p.phiLow != null)
          'CI ${formatPhi(p.phiLow!)} to ${formatPhi(p.phiHigh!)}',
        'adjusted p ${_formatP(p.q!)}',
        if (p.isInsight) 'finding',
      ].join('  ');
  }
}

String _formatP(double v) =>
    v < 0.001 ? '< 0.001' : '= ${v.toStringAsFixed(3)}';
