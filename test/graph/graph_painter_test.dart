import 'package:cohabit/design/tokens.dart';
import 'package:cohabit/domain/habit_day.dart';
import 'package:cohabit/graph/graph_model.dart';
import 'package:cohabit/graph/graph_painter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  for (final colors in [CohabitColors.dark, CohabitColors.light]) {
    final name = colors.brightness.name;

    group('cell painting ($name)', () {
      // Column i covers x in [12 i, 12 i + 10).
      const styles = [
        CellStyle.none,
        CellStyle.done,
        CellStyle.slipped,
        CellStyle.notDone,
        CellStyle.skipped,
        CellStyle.unknown,
        CellStyle.level0,
        CellStyle.level1,
        CellStyle.level2,
        CellStyle.level3,
        CellStyle.level4,
      ];
      int cx(CellStyle s) => styles.indexOf(s) * 12 + 5;

      testWidgets('solid styles use their palette colour', (tester) async {
        final px = (await tester.runAsync(
          () => renderSeries(columnsOf(styles), colors),
        ))!;
        final expected = {
          CellStyle.done: colors.blue3,
          CellStyle.slipped: colors.orange,
          CellStyle.notDone: colors.off,
          CellStyle.level0: colors.off,
          CellStyle.level1: colors.blue1,
          CellStyle.level2: colors.blue2,
          CellStyle.level3: colors.blue3,
          CellStyle.level4: colors.blue4,
        };
        for (final e in expected.entries) {
          expect(
            distance(px.at(cx(e.key), 5), e.value),
            0,
            reason: '${e.key} centre',
          );
          // Square corners: the very first and last pixels are filled too.
          expect(distance(px.at(cx(e.key) - 5, 0), e.value), 0);
          expect(distance(px.at(cx(e.key) + 4, 9), e.value), 0);
        }
      });

      testWidgets('cells are 10px squares with a 2px gap', (tester) async {
        final px = (await tester.runAsync(
          () => renderSeries(columnsOf(styles), colors),
        ))!;
        final doneX = styles.indexOf(CellStyle.done) * 12;
        expect(px.at(doneX, 0).a, 1);
        expect(px.at(doneX + 9, 9).a, 1);
        expect(px.at(doneX + 10, 5).a, 0, reason: 'gap right of the cell');
        expect(px.at(doneX + 11, 5).a, 0, reason: 'gap right of the cell');
        // Rows: second row starts at y=12.
        expect(px.at(doneX + 5, 10).a, 0, reason: 'gap below the cell');
        expect(px.at(doneX + 5, 12).a, 1);
      });

      testWidgets('none draws nothing', (tester) async {
        final px = (await tester.runAsync(
          () => renderSeries(columnsOf(styles), colors),
        ))!;
        for (var y = 0; y < 10; y++) {
          for (var x = 0; x < 10; x++) {
            expect(px.at(x, y).a, 0);
          }
        }
      });

      testWidgets('unknown is a 1px hairline outline, hollow inside', (
        tester,
      ) async {
        final px = (await tester.runAsync(
          () => renderSeries(columnsOf(styles), colors),
        ))!;
        final x0 = styles.indexOf(CellStyle.unknown) * 12;
        for (var i = 0; i < 10; i++) {
          expect(distance(px.at(x0 + i, 0), colors.hairline), 0);
          expect(distance(px.at(x0 + i, 9), colors.hairline), 0);
          expect(distance(px.at(x0, i), colors.hairline), 0);
          expect(distance(px.at(x0 + 9, i), colors.hairline), 0);
        }
        for (var y = 1; y < 9; y++) {
          for (var x = 1; x < 9; x++) {
            expect(px.at(x0 + x, y).a, 0, reason: 'inside at $x,$y');
          }
        }
      });

      testWidgets('skipped is a filled, striped cell unlike the hollow '
          'unknown', (tester) async {
        final px = (await tester.runAsync(
          () => renderSeries(columnsOf(styles), colors),
        ))!;
        final skippedX = styles.indexOf(CellStyle.skipped) * 12;
        final unknownX = styles.indexOf(CellStyle.unknown) * 12;

        var opaqueSkipped = 0;
        var strokePixels = 0; // clearly the stripe colour
        var basePixels = 0; // clearly the base fill
        var opaqueUnknown = 0;
        for (var y = 0; y < 10; y++) {
          for (var x = 0; x < 10; x++) {
            final s = px.at(skippedX + x, y);
            if (s.a == 1) opaqueSkipped++;
            if (distance(s, colors.muted) < 40) strokePixels++;
            if (distance(s, colors.off) == 0) basePixels++;
            if (px.at(unknownX + x, y).a > 0) opaqueUnknown++;
          }
        }
        // Stripes are clipped to the cell: nothing leaks into the gap.
        for (var i = 0; i < 10; i++) {
          expect(px.at(skippedX + 10, i).a, 0);
          expect(px.at(skippedX + 11, i).a, 0);
          expect(px.at(skippedX + i, 10).a, 0);
        }
        expect(opaqueSkipped, 100, reason: 'skipped fills the whole cell');
        expect(opaqueUnknown, 36, reason: 'unknown is only the perimeter');
        // A strong hatch: a good share of the cell is stripe, and a good
        // share is base fill showing between stripes.
        expect(strokePixels, greaterThanOrEqualTo(30));
        expect(basePixels, greaterThanOrEqualTo(25));
      });
    });
  }

  group('geometry', () {
    final range = GraphRange(first: HabitDay(2026, 10, 5), weeks: 4);

    test('metrics', () {
      expect(GraphMetrics.cell, 10);
      expect(GraphMetrics.gap, 2);
      expect(GraphMetrics.rows, 7);
      expect(GraphMetrics.widthFor(4), 46);
      expect(GraphMetrics.height, 82);
    });

    test('originOf places one column per week, seven rows per column', () {
      expect(GraphMetrics.originOf(range, 0), const Offset(0, 0));
      expect(GraphMetrics.originOf(range, 6), const Offset(0, 72));
      expect(GraphMetrics.originOf(range, 7), const Offset(12, 0));
      expect(GraphMetrics.originOf(range, 27), const Offset(36, 72));
    });

    test('hitTest finds cells and ignores gaps and the outside', () {
      expect(GraphMetrics.hitTest(range, const Offset(5, 5)), 0);
      expect(GraphMetrics.hitTest(range, const Offset(17, 29)), 7 + 2);
      expect(GraphMetrics.hitTest(range, const Offset(10.5, 5)), isNull);
      expect(GraphMetrics.hitTest(range, const Offset(5, 11)), isNull);
      expect(GraphMetrics.hitTest(range, const Offset(-1, 5)), isNull);
      expect(GraphMetrics.hitTest(range, const Offset(500, 5)), isNull);
      expect(GraphMetrics.hitTest(range, const Offset(5, 500)), isNull);
    });
  });
}
