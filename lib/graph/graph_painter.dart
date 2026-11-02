import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../design/tokens.dart';
import 'graph_model.dart';

/// Cell geometry: 10px squares with a 2px gap, no rounding, 7 rows.
abstract final class GraphMetrics {
  static const double cell = 10;
  static const double gap = 2;
  static const double pitch = cell + gap;
  static const int rows = GraphRange.rows;

  static double widthFor(int weeks) => weeks * pitch - gap;
  static const double height = rows * pitch - gap;

  /// Top-left corner of the cell at [index].
  static Offset originOf(GraphRange range, int index) =>
      Offset(range.columnOf(index) * pitch, range.rowOf(index) * pitch);

  /// Index of the cell under [position], or null in a gap or off the grid.
  static int? hitTest(GraphRange range, Offset position) {
    if (position.dx < 0 || position.dy < 0) return null;
    final col = position.dx ~/ pitch;
    final row = position.dy ~/ pitch;
    if (col >= range.weeks || row >= rows) return null;
    if (position.dx - col * pitch >= cell) return null;
    if (position.dy - row * pitch >= cell) return null;
    return col * rows + row;
  }
}

/// The skipped hatch in cell-local coordinates: 45-degree stripes about 2px
/// thick every 4.5px (measured across the stripes), geometrically clipped to
/// the cell so nothing spills into the gap.
///
/// A stripe at 45 degrees covers cells at a stair-step, which at 10px reads as
/// a clearly textured block, unlike the hollow outline of an unknown day. A
/// fainter, thinner hatch blurred into the off fill in the mockup.
final Path _hatchTile = () {
  const size = GraphMetrics.cell;
  const period = 4.5; // across the stripes
  const thickness = 2.0;
  final step = period * math.sqrt2; // along x + y
  final half = thickness * math.sqrt2 / 2;
  final stripes = Path();
  for (var k = step / 2; k < 2 * size + step; k += step) {
    // The band k - half <= x + y <= k + half, extended past the square.
    stripes
      ..moveTo(-size, k - half + size)
      ..lineTo(2 * size, k - half - 2 * size)
      ..lineTo(2 * size, k + half - 2 * size)
      ..lineTo(-size, k + half + size)
      ..close();
  }
  return Path.combine(
    PathOperation.intersect,
    stripes,
    Path()..addRect(const Rect.fromLTWH(0, 0, size, size)),
  );
}();

/// A 1px frame inside the cell, as four filled rectangles so every edge pixel
/// is exact (a stroked path antialiases the corners).
void _addOutline(Path path, Offset o) {
  const size = GraphMetrics.cell;
  path
    ..addRect(Rect.fromLTWH(o.dx, o.dy, size, 1))
    ..addRect(Rect.fromLTWH(o.dx, o.dy + size - 1, size, 1))
    ..addRect(Rect.fromLTWH(o.dx, o.dy + 1, 1, size - 2))
    ..addRect(Rect.fromLTWH(o.dx + size - 1, o.dy + 1, 1, size - 2));
}

/// Paints [styles] for [range] in one pass, batching cells of the same style
/// into a single path so a year of cells costs a handful of draw calls.
class CommitGraphPainter extends CustomPainter {
  CommitGraphPainter({
    required this.series,
    required this.colors,
    this.highlight,
    this.onTapDay,
    this.describeDay,
    this.textDirection = TextDirection.ltr,
  });

  final GraphSeries series;
  final CohabitColors colors;

  /// Index of a hovered or keyboard-focused cell to ring.
  final int? highlight;

  /// Tapping a cell's semantics node reports its day.
  final void Function(int index)? onTapDay;
  final String Function(int index)? describeDay;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final range = series.range;
    final fills = <Color, Path>{};
    final hatchBase = Path();
    final hatchLines = Path();
    final outlines = Path();

    for (var i = 0; i < range.length; i++) {
      final style = series.styles[i];
      if (style == CellStyle.none) continue;
      final o = GraphMetrics.originOf(range, i);
      final rect = Rect.fromLTWH(
        o.dx,
        o.dy,
        GraphMetrics.cell,
        GraphMetrics.cell,
      );
      switch (style) {
        case CellStyle.skipped:
          hatchBase.addRect(rect);
          hatchLines.addPath(_hatchTile, o);
        case CellStyle.unknown:
          _addOutline(outlines, o);
        default:
          (fills[fillColor(style, colors)!] ??= Path()).addRect(rect);
      }
    }

    final fill = Paint()..style = PaintingStyle.fill;
    fills.forEach((color, path) => canvas.drawPath(path, fill..color = color));
    canvas.drawPath(hatchBase, fill..color = colors.off);
    canvas
      ..drawPath(hatchLines, fill..color = colors.muted)
      ..drawPath(outlines, fill..color = colors.muted);

    final h = highlight;
    if (h != null && h >= 0 && h < range.length) {
      final o = GraphMetrics.originOf(range, h);
      canvas.drawRect(
        Rect.fromLTWH(
          o.dx,
          o.dy,
          GraphMetrics.cell,
          GraphMetrics.cell,
        ).inflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = colors.text,
      );
    }
  }

  @override
  bool shouldRepaint(CommitGraphPainter oldDelegate) =>
      oldDelegate.series != series ||
      oldDelegate.colors != colors ||
      oldDelegate.highlight != highlight;

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
    final range = series.range;
    return [
      for (var i = 0; i < range.length; i++)
        if (series.styles[i] != CellStyle.none)
          CustomPainterSemantics(
            rect: Rect.fromLTWH(
              GraphMetrics.originOf(range, i).dx,
              GraphMetrics.originOf(range, i).dy,
              GraphMetrics.cell,
              GraphMetrics.cell,
            ),
            properties: SemanticsProperties(
              label: describeDay?.call(i) ?? '',
              textDirection: textDirection,
              button: onTapDay != null,
              onTap: onTapDay == null ? null : () => onTapDay!(i),
            ),
          ),
    ];
  };

  @override
  bool shouldRebuildSemantics(CommitGraphPainter oldDelegate) =>
      oldDelegate.series != series;
}

/// Solid colour of a filled style, or null for hatch, outline and none.
Color? fillColor(CellStyle style, CohabitColors c) => switch (style) {
  CellStyle.done => c.blue3,
  CellStyle.slipped => c.orange,
  CellStyle.notDone => c.off,
  CellStyle.level0 => c.off,
  CellStyle.level1 => c.blue1,
  CellStyle.level2 => c.blue2,
  CellStyle.level3 => c.blue3,
  CellStyle.level4 => c.blue4,
  _ => null,
};

/// Paints a single cell of [style] at [origin]; used by the legend so swatches
/// match the graph exactly.
void paintSwatch(
  Canvas canvas,
  Offset origin,
  CellStyle style,
  CohabitColors colors,
) {
  final rect = Rect.fromLTWH(
    origin.dx,
    origin.dy,
    GraphMetrics.cell,
    GraphMetrics.cell,
  );
  switch (style) {
    case CellStyle.none:
      return;
    case CellStyle.skipped:
      canvas
        ..drawRect(rect, Paint()..color = colors.off)
        ..drawPath(_hatchTile.shift(origin), Paint()..color = colors.muted);
    case CellStyle.unknown:
      final outline = Path();
      _addOutline(outline, origin);
      canvas.drawPath(outline, Paint()..color = colors.muted);
    default:
      canvas.drawRect(rect, Paint()..color = fillColor(style, colors)!);
  }
}
