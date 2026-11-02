import 'package:flutter/material.dart';

import 'tokens.dart';

/// A finding in one sentence with its numbers beneath: a 2px blue3 rule on
/// the left, a sentence in Inter, and a mono stats line such as
/// `2.3x  n=84  CI 1.6-3.2`.
///
/// Used for the findings on the Insights screen.
class InsightCard extends StatelessWidget {
  const InsightCard({
    super.key,
    required this.sentence,
    required this.stats,
    this.semanticsLabel,
  });

  final String sentence;

  /// What a screen reader says instead of the sentence and the raw stats,
  /// which are written for the eye (`->`, `CI`, `n=`).
  final String? semanticsLabel;

  /// Shown on one mono line, separated by two spaces.
  final List<String> stats;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      label: semanticsLabel ?? '$sentence ${stats.join(', ')}',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(
              top: BorderSide(color: c.hairline),
              right: BorderSide(color: c.hairline),
              bottom: BorderSide(color: c.hairline),
              left: BorderSide(color: c.blue3, width: 2),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.l,
              vertical: Space.m,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(sentence, style: CohabitType.body(c)),
                if (stats.isNotEmpty) ...[
                  const SizedBox(height: Space.xs),
                  Text(stats.join('  '), style: CohabitType.meta(c)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
