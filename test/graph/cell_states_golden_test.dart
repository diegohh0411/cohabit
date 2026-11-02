@Tags(['golden'])
library;

import 'package:cohabit/design/tokens.dart';
import 'package:cohabit/graph/graph_model.dart';
import 'package:cohabit/graph/graph_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Every cell state side by side, drawn by the production painter, at the
/// real 10px size (scaled up by the device pixel ratio) on the surface colour.
///
/// Skipped (striped) and unknown (hollow) sit next to each other on purpose:
/// they must stay distinguishable at this size. Regenerate with
/// `flutter test --update-goldens --tags golden`.
void main() {
  const styles = [
    CellStyle.done,
    CellStyle.slipped,
    CellStyle.notDone,
    CellStyle.skipped,
    CellStyle.unknown,
    CellStyle.none,
    CellStyle.level0,
    CellStyle.level1,
    CellStyle.level2,
    CellStyle.level3,
    CellStyle.level4,
  ];

  for (final colors in [CohabitColors.dark, CohabitColors.light]) {
    for (final ratio in [2.0, 8.0]) {
      testWidgets('cell states, ${colors.brightness.name} @${ratio}x', (
        tester,
      ) async {
        final series = columnsOf(styles);
        final width = GraphMetrics.widthFor(series.range.weeks) + 16;
        final height = GraphMetrics.height + 16;
        // Scale the drawing itself (as a higher-density screen would) and
        // capture it 1:1, so the image shows the real pixel pattern enlarged.
        tester.view
          ..devicePixelRatio = 1
          ..physicalSize = Size(width * ratio, height * ratio);
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: RepaintBoundary(
              key: const ValueKey('sheet'),
              child: ColoredBox(
                color: colors.surface,
                child: Center(
                  child: Transform.scale(
                    scale: ratio,
                    child: CustomPaint(
                      size: Size(
                        GraphMetrics.widthFor(series.range.weeks),
                        GraphMetrics.height,
                      ),
                      painter: CommitGraphPainter(
                        series: series,
                        colors: colors,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await expectLater(
          find.byKey(const ValueKey('sheet')),
          matchesGoldenFile(
            'goldens/cell_states_${colors.brightness.name}_${ratio.toInt()}x.png',
          ),
        );
      });
    }
  }
}
