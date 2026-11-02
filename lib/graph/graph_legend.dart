import 'package:flutter/material.dart';

import '../design/tokens.dart';
import 'graph_model.dart';
import 'graph_painter.dart';

/// Legend under a graph: every style it uses, drawn with the graph's own
/// painting code, plus its name in text.
class GraphLegend extends StatelessWidget {
  const GraphLegend({super.key, required this.kind});

  final LegendKind kind;

  static const _habit = [
    (CellStyle.done, 'Done or clean'),
    (CellStyle.slipped, 'Slipped'),
    (CellStyle.notDone, 'Not done'),
    (CellStyle.skipped, 'Skipped'),
    (CellStyle.unknown, 'Not logged'),
  ];

  static const _overview = [
    CellStyle.level0,
    CellStyle.level1,
    CellStyle.level2,
    CellStyle.level3,
    CellStyle.level4,
  ];

  /// Spoken once for the whole legend.
  String get semanticLabel => switch (kind) {
    LegendKind.habit =>
      'Legend: ${_habit.map((e) => e.$2.toLowerCase()).join(', ')}',
    LegendKind.overview =>
      'Legend: from less to more of the logged habits completed',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = CohabitType.label(c).copyWith(letterSpacing: 0.4);
    return Semantics(
      container: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: switch (kind) {
          LegendKind.habit => Wrap(
            spacing: Space.l,
            runSpacing: Space.xs,
            children: [
              for (final (style, text) in _habit)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Swatch(style),
                    const SizedBox(width: 6),
                    Text(text, style: label),
                  ],
                ),
            ],
          ),
          LegendKind.overview => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Less', style: label),
              const SizedBox(width: 6),
              for (final style in _overview) ...[
                _Swatch(style),
                const SizedBox(width: GraphMetrics.gap),
              ],
              const SizedBox(width: 4),
              Text('More', style: label),
            ],
          ),
        },
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.style);

  final CellStyle style;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(GraphMetrics.cell, GraphMetrics.cell),
    painter: _SwatchPainter(style, context.colors),
  );
}

class _SwatchPainter extends CustomPainter {
  const _SwatchPainter(this.style, this.colors);

  final CellStyle style;
  final CohabitColors colors;

  @override
  void paint(Canvas canvas, Size size) =>
      paintSwatch(canvas, Offset.zero, style, colors);

  @override
  bool shouldRepaint(_SwatchPainter oldDelegate) =>
      oldDelegate.style != style || oldDelegate.colors != colors;
}
