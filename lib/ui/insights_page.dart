import 'package:cohabit_analysis/cohabit_analysis.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analysis/insight_text.dart';
import '../design/buttons.dart';
import '../design/insight_card.dart';
import '../design/page_scaffold.dart';
import '../design/section_label.dart';
import '../design/tokens.dart';
import '../domain/habit.dart';
import '../state/analysis_providers.dart';
import '../state/providers.dart';
import 'navigation.dart';
import 'pairs_page.dart';

/// Most findings listed at once; the rest are in the All pairs view.
const int maxListedInsights = 20;

/// Patterns between habits, in plain sentences with their numbers. Runs the
/// analysis off the UI thread and refreshes when logs change.
class InsightsPage extends ConsumerWidget {
  const InsightsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habits = ref.watch(habitsProvider).value;
    final analysis = ref.watch(analysisProvider);
    final result = analysis.value;
    final canCompare = habits != null && habits.length >= 2;

    return PageScaffold(
      title: 'Insights',
      primaryAction: canCompare
          ? PageAction(
              key: const ValueKey('all-pairs'),
              label: 'All pairs',
              desktopVariant: ButtonVariant.secondary,
              onPressed: () => openPage<void>(context, const PairsPage()),
            )
          : null,
      child: habits == null
          ? const SizedBox.shrink()
          : PageBody(
              children: [
                if (!canCompare)
                  const _Message(
                    key: ValueKey('insights-empty-habits'),
                    title: 'Insights compare habits',
                    body:
                        'Add a second habit and log both for a few weeks. '
                        'Cohabit looks for habits that tend to go together '
                        'once two of them share at least '
                        '$_minDays logged days.',
                  )
                else if (analysis.hasError)
                  _Message(
                    key: const ValueKey('insights-error'),
                    title: 'Could not analyse your logs',
                    body: 'Your logs are safe. Try again to refresh insights.',
                    action: CohabitButton(
                      label: 'Try again',
                      onPressed: () => ref.invalidate(analysisProvider),
                    ),
                  )
                else if (result == null)
                  const _Message(
                    key: ValueKey('insights-loading'),
                    title: 'Analysing your logs',
                    body: 'This runs on your device and takes a moment.',
                    busy: true,
                  )
                else ...[
                  if (analysis.isLoading) const _Updating(),
                  _Findings(result: result, habits: habits),
                ],
              ],
            ),
    );
  }
}

const int _minDays = 30;

class _Findings extends StatelessWidget {
  const _Findings({required this.result, required this.habits});

  final AnalysisResult result;
  final List<Habit> habits;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final h in habits) h.id: h};
    final c = context.colors;
    final ranked = rankedInsights(result)
        .where((p) => byId.containsKey(p.fromId) && byId.containsKey(p.toId));
    final listed = ranked.take(maxListedInsights).toList();
    final hidden = ranked.length - listed.length;
    final minDays = result.config.minOverlapDays;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (result.maxOverlap < minDays)
          _Message(
            key: const ValueKey('insights-empty-data'),
            title: 'Not enough data yet',
            body:
                'A pair of habits needs at least $minDays days on which both '
                'were logged before Cohabit will say anything about them. '
                "Your closest pair has ${result.maxOverlap} so far. Days you "
                "skip or haven't logged don't count, and aren't counted "
                'as missed.',
          )
        else if (listed.isEmpty)
          _Message(
            key: const ValueKey('insights-empty-none'),
            title: 'Nothing stands out yet',
            body:
                'Cohabit compared ${result.testsRun} '
                '${result.testsRun == 1 ? 'pattern' : 'patterns'} across '
                '${result.days} days and none was strong enough to report '
                'with confidence. That is a normal result, and it can change '
                'as you log more.',
          )
        else ...[
          const SectionLabel('Patterns'),
          const SizedBox(height: Space.s),
          for (final p in listed) ...[
            _Finding(pair: p, from: byId[p.fromId]!, to: byId[p.toId]!),
            const SizedBox(height: Space.m),
          ],
          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.m),
              child: Text(
                '$hidden more in All pairs.',
                style: CohabitType.body(c).copyWith(color: c.muted),
              ),
            ),
        ],
        const SizedBox(height: Space.m),
        Text(
          'Based on ${result.days} days of logs, ${result.testsRun} '
          'comparisons, false discovery rate '
          '${(result.config.fdr * 100).round()}%. Patterns in what you '
          'logged, not causes.',
          key: const ValueKey('insights-footer'),
          style: CohabitType.meta(c),
        ),
      ],
    );
  }
}

class _Finding extends StatelessWidget {
  const _Finding({required this.pair, required this.from, required this.to});

  final PairResult pair;
  final Habit from;
  final Habit to;

  @override
  Widget build(BuildContext context) {
    final text = describeInsight(pair, from, to);
    return InsightCard(
      key: ValueKey('insight-${pair.fromId}-${pair.toId}-${pair.lag}'),
      sentence: text.sentence,
      stats: text.stats,
      semanticsLabel: text.semantics,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    super.key,
    required this.title,
    required this.body,
    this.busy = false,
    this.action,
  });

  final String title;
  final String body;
  final bool busy;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      liveRegion: busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: CohabitType.name(c)),
          const SizedBox(height: Space.xs),
          Text(body, style: CohabitType.body(c).copyWith(color: c.muted)),
          if (action != null) ...[const SizedBox(height: Space.s), action!],
        ],
      ),
    );
  }
}

/// Shown over the previous result while a newer analysis runs.
class _Updating extends StatelessWidget {
  const _Updating();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.s),
    child: Semantics(
      liveRegion: true,
      child: Text(
        'Updating…',
        key: const ValueKey('insights-updating'),
        style: CohabitType.meta(context.colors),
      ),
    ),
  );
}
