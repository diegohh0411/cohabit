import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/tokens.dart';
import '../domain/habit_day.dart';
import '../ui/labels.dart';
import 'graph_legend.dart';
import 'graph_model.dart';
import 'graph_painter.dart';

typedef SeriesBuilder = List<GraphSeries> Function(GraphRange range);

/// One or more graphs sharing a single horizontal scroll, so days line up
/// exactly. Stack two series to compare habits.
///
/// The range is chosen to fill the available width (at least [minWeeks]) and
/// to reach back to [earliest]. The view is anchored to today at the right
/// edge, and scrolls back in time.
///
/// Interaction: hover (pointer) or arrow keys (keyboard) show a day's detail
/// in a line below the graph; tapping or pressing Enter calls [onDayTap].
/// Every cell also has a semantics node, so screen readers get the same
/// detail without relying on colour.
class GraphPanel extends StatelessWidget {
  const GraphPanel({
    super.key,
    required this.today,
    required this.earliest,
    required this.seriesBuilder,
    this.onDayTap,
    this.minWeeks = 53,
  });

  final HabitDay today;
  final HabitDay earliest;
  final SeriesBuilder seriesBuilder;
  final int minWeeks;

  /// A past or present day was tapped (or activated from the keyboard).
  final void Function(HabitDay day, int seriesIndex)? onDayTap;

  static const double gutterWidth = 28;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final available = box.maxWidth - gutterWidth;
        final fit = ((available + GraphMetrics.gap) / GraphMetrics.pitch)
            .floor();
        final range = GraphRange.covering(
          today: today,
          earliest: earliest,
          minWeeks: math.max(minWeeks, fit),
        );
        return _GraphView(
          series: seriesBuilder(range),
          today: today,
          viewportWidth: available,
          onDayTap: onDayTap,
        );
      },
    );
  }
}

class _GraphView extends StatefulWidget {
  const _GraphView({
    required this.series,
    required this.today,
    required this.viewportWidth,
    required this.onDayTap,
  });

  final List<GraphSeries> series;
  final HabitDay today;
  final double viewportWidth;
  final void Function(HabitDay day, int seriesIndex)? onDayTap;

  @override
  State<_GraphView> createState() => _GraphViewState();
}

class _GraphViewState extends State<_GraphView> {
  static const double _monthRowHeight = 18;
  static const double _titleHeight = 20;
  static const double _blockGap = 10;

  final _focus = FocusNode(debugLabel: 'commit graph');
  final _scroll = ScrollController();
  HabitDay? _hover;
  HabitDay? _cursor;
  HabitDay? _selected;

  GraphRange get _range => widget.series.first.range;
  bool get _multi => widget.series.length > 1;
  double get _blockHeight => (_multi ? _titleHeight : 0) + GraphMetrics.height;
  double _blockTop(int i) => _monthRowHeight + i * (_blockHeight + _blockGap);
  double get _totalHeight => _blockTop(widget.series.length - 1) + _blockHeight;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  HabitDay? get _active =>
      _hover ?? (_focus.hasFocus ? _cursor : null) ?? _selected;

  void _tapDay(HabitDay day, int seriesIndex) {
    if (day > widget.today) return;
    setState(() => _selected = day);
    widget.onDayTap?.call(day, seriesIndex);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final cursor = _cursor ?? widget.today;
    final key = event.logicalKey;
    final delta = key == LogicalKeyboardKey.arrowLeft
        ? -7
        : key == LogicalKeyboardKey.arrowRight
        ? 7
        : key == LogicalKeyboardKey.arrowUp
        ? -1
        : key == LogicalKeyboardKey.arrowDown
        ? 1
        : null;
    if (delta != null) {
      var next = cursor.addDays(delta);
      if (next > widget.today || next < _range.first) next = cursor;
      setState(() => _cursor = next);
      _reveal(next);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      _tapDay(cursor, 0);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Scrolls so the cursor's column is on screen. The view is reversed, so
  /// offset 0 is the right edge.
  void _reveal(HabitDay day) {
    if (!_scroll.hasClients) return;
    final x = GraphMetrics.originOf(_range, _range.indexOf(day)).dx;
    final content = GraphMetrics.widthFor(_range.weeks);
    final viewport = _scroll.position.viewportDimension;
    final offset = _scroll.offset;
    final visibleLeft = content - offset - viewport;
    final visibleRight = content - offset;
    double? target;
    if (x < visibleLeft) {
      target = content - viewport - x;
    } else if (x + GraphMetrics.cell > visibleRight) {
      target = content - x - GraphMetrics.cell;
    }
    if (target != null) {
      _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
    }
  }

  String _detail(HabitDay day) {
    final parts = [
      for (final s in widget.series)
        _multi ? '${s.title}: ${s.describe(day)}' : s.describe(day),
    ];
    return '${formatDay(day)} · ${parts.join(' · ')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final desktop = isDesktopPlatform(context);
    final range = _range;
    final contentWidth = math.max(
      GraphMetrics.widthFor(range.weeks),
      widget.viewportWidth,
    );
    final active = _active;
    final highlight = active != null && range.contains(active)
        ? range.indexOf(active)
        : null;
    final labelStyle = CohabitType.label(c).copyWith(letterSpacing: 0.4);

    final scrollContent = SizedBox(
      width: contentWidth,
      height: _totalHeight,
      child: Stack(
        children: [
          for (final m in monthMarkers(range))
            Positioned(
              left: m.column * GraphMetrics.pitch,
              top: 0,
              child: ExcludeSemantics(
                child: Text(m.label.toUpperCase(), style: labelStyle),
              ),
            ),
          for (var i = 0; i < widget.series.length; i++)
            Positioned(
              left: 0,
              top: _blockTop(i) + (_multi ? _titleHeight : 0),
              width: GraphMetrics.widthFor(range.weeks),
              height: GraphMetrics.height,
              child: _SeriesCanvas(
                series: widget.series[i],
                colors: c,
                highlight: highlight,
                today: widget.today,
                onHover: (day) {
                  if (day != _hover) setState(() => _hover = day);
                },
                onTap: (day) => _tapDay(day, i),
              ),
            ),
        ],
      ),
    );

    // The grid is fixed-pitch, so its month, weekday and series labels stop
    // growing at 1.3x. The detail line and legend below keep the full scale.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: Semantics(
            container: true,
            label: widget.series.map((s) => s.summary).join('. '),
            child: Focus(
              focusNode: _focus,
              onKeyEvent: _onKey,
              onFocusChange: (focused) {
                if (focused) _cursor ??= widget.today;
              },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: SizedBox(
                      width: GraphPanel.gutterWidth,
                      height: _totalHeight,
                      child: Stack(
                        children: [
                          for (var i = 0; i < widget.series.length; i++)
                            for (final row in const [0, 2, 4])
                              Positioned(
                                top:
                                    _blockTop(i) +
                                    (_multi ? _titleHeight : 0) +
                                    row * GraphMetrics.pitch -
                                    2,
                                child: Text(
                                  weekdayLetters[row],
                                  style: labelStyle,
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: widget.viewportWidth,
                    height: _totalHeight,
                    child: Stack(
                      children: [
                        SingleChildScrollView(
                          controller: _scroll,
                          scrollDirection: Axis.horizontal,
                          reverse: true,
                          child: scrollContent,
                        ),
                        if (_multi)
                          for (var i = 0; i < widget.series.length; i++)
                            Positioned(
                              left: 0,
                              top: _blockTop(i) + 1,
                              child: IgnorePointer(
                                child: ExcludeSemantics(
                                  child: Text(
                                    widget.series[i].title,
                                    style: CohabitType.control(c),
                                  ),
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.s),
        Padding(
          padding: const EdgeInsets.only(left: GraphPanel.gutterWidth),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 16),
            child: Text(
              active != null
                  ? _detail(active)
                  : desktop
                  ? 'Hover a day for detail. Click to open it.'
                  : 'Tap a day to open it.',
              key: const ValueKey('graph-detail'),
              style: CohabitType.meta(c)
                  .copyWith(color: active != null ? c.text : c.muted),
            ),
          ),
        ),
        const SizedBox(height: Space.s),
        Padding(
          padding: const EdgeInsets.only(left: GraphPanel.gutterWidth),
          child: GraphLegend(kind: widget.series.first.legend),
        ),
      ],
    );
  }
}

class _SeriesCanvas extends StatelessWidget {
  const _SeriesCanvas({
    required this.series,
    required this.colors,
    required this.highlight,
    required this.today,
    required this.onHover,
    required this.onTap,
  });

  final GraphSeries series;
  final CohabitColors colors;
  final int? highlight;
  final HabitDay today;
  final ValueChanged<HabitDay?> onHover;
  final ValueChanged<HabitDay> onTap;

  HabitDay? _dayAt(Offset position, {bool snapGaps = false}) {
    final i = GraphMetrics.hitTest(series.range, position, snapGaps: snapGaps);
    return i == null ? null : series.range.dayAt(i);
  }

  @override
  Widget build(BuildContext context) {
    final range = series.range;
    return MouseRegion(
      onHover: (e) => onHover(_dayAt(e.localPosition)),
      onExit: (_) => onHover(null),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final day = _dayAt(d.localPosition, snapGaps: true);
          if (day != null) onTap(day);
        },
        child: CustomPaint(
          size: Size(GraphMetrics.widthFor(range.weeks), GraphMetrics.height),
          painter: CommitGraphPainter(
            series: series,
            colors: colors,
            highlight: highlight,
            textDirection: Directionality.of(context),
            onTapDay: (i) {
              final day = range.dayAt(i);
              if (day <= today) onTap(day);
            },
            describeDay: (i) {
              final day = range.dayAt(i);
              return '${formatDay(day)}, ${series.title}: '
                  '${series.describe(day)}';
            },
          ),
        ),
      ),
    );
  }
}
