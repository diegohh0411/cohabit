import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cohabit/design/tokens.dart';
import 'package:cohabit/domain/habit_day.dart';
import 'package:cohabit/graph/graph_model.dart';
import 'package:cohabit/graph/graph_painter.dart';
import 'package:flutter/material.dart';

/// A series where week `i` is entirely `styles[i]`, so each column of the
/// graph shows one style.
GraphSeries columnsOf(List<CellStyle> styles, {GraphRange? range}) {
  final r =
      range ?? GraphRange(first: HabitDay(2026, 10, 5), weeks: styles.length);
  return GraphSeries(
    title: 'Test',
    range: r,
    styles: [for (final s in styles) ...List.filled(GraphRange.rows, s)],
    describe: (_) => '',
    legend: LegendKind.habit,
    summary: '',
  );
}

class Pixels {
  Pixels(this.data, this.width);

  final ByteData data;
  final int width;

  Color at(int x, int y) {
    final o = (y * width + x) * 4;
    return Color.fromARGB(
      data.getUint8(o + 3),
      data.getUint8(o),
      data.getUint8(o + 1),
      data.getUint8(o + 2),
    );
  }
}

/// Renders [series] with the production painter at 1 pixel per logical pixel.
/// Call inside `tester.runAsync`.
Future<Pixels> renderSeries(GraphSeries series, CohabitColors colors) async {
  final width = GraphMetrics.widthFor(series.range.weeks).ceil();
  final height = GraphMetrics.height.ceil();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  CommitGraphPainter(
    series: series,
    colors: colors,
  ).paint(canvas, Size(width.toDouble(), height.toDouble()));
  final image = await recorder.endRecording().toImage(width, height);
  return Pixels((await image.toByteData())!, width);
}

/// Per-channel distance between two colours, 0 to 255.
int distance(Color a, Color b) {
  int d(double x, double y) => ((x - y).abs() * 255).round();
  return [
    d(a.r, b.r),
    d(a.g, b.g),
    d(a.b, b.b),
    d(a.a, b.a),
  ].reduce((m, v) => v > m ? v : m);
}
