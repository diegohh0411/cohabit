import 'package:flutter/material.dart';

/// Colour tokens of the "precise instrument" design system.
///
/// Neutral surfaces carry the interface; blue and orange are reserved for
/// data. Both palettes follow the OS brightness.
@immutable
class CohabitColors extends ThemeExtension<CohabitColors> {
  const CohabitColors({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.hairline,
    required this.text,
    required this.muted,
    required this.off,
    required this.blue1,
    required this.blue2,
    required this.blue3,
    required this.blue4,
    required this.orange,
    required this.onBlue3,
    required this.onOrange,
  });

  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color hairline;
  final Color text;
  final Color muted;

  /// Fill for "not done" and the empty end of the overview scale.
  final Color off;

  /// Overview scale, weakest to strongest.
  final Color blue1;
  final Color blue2;

  /// Done and confirmed-clean fill; also the focus and accent colour.
  final Color blue3;
  final Color blue4;

  /// Slipped fill.
  final Color orange;

  /// Label colours on [blue3] and [orange] fills, chosen for WCAG AA (4.5:1).
  final Color onBlue3;
  final Color onOrange;

  /// Overview scale from none (index 0) to full (index 4).
  List<Color> get overviewScale => [off, blue1, blue2, blue3, blue4];

  /// Dark palette. White text fails AA on [blue3] (3.76:1) and [orange]
  /// (2.53:1), so labels on those fills use the page background instead.
  static const dark = CohabitColors(
    brightness: Brightness.dark,
    background: Color(0xFF0B0E13),
    surface: Color(0xFF12161D),
    hairline: Color(0xFF2A313C),
    text: Color(0xFFE8ECF2),
    muted: Color(0xFF8C96A5),
    off: Color(0xFF1B212B),
    blue1: Color(0xFF16365C),
    blue2: Color(0xFF1F5A96),
    blue3: Color(0xFF3487D6),
    blue4: Color(0xFF7CC0FF),
    orange: Color(0xFFF0883E),
    onBlue3: Color(0xFF0B0E13),
    onOrange: Color(0xFF0B0E13),
  );

  /// Light palette. [blue3] and [orange] are nudged darker than the approved
  /// values (#2F7FD1, #C4560C) so white labels reach 4.5:1.
  static const light = CohabitColors(
    brightness: Brightness.light,
    background: Color(0xFFF7F8FA),
    surface: Color(0xFFFFFFFF),
    hairline: Color(0xFFD5DAE2),
    text: Color(0xFF10151C),
    muted: Color(0xFF5D6776),
    off: Color(0xFFE9ECF1),
    blue1: Color(0xFFC5DFF8),
    blue2: Color(0xFF7DB6EC),
    blue3: Color(0xFF2C78C7),
    blue4: Color(0xFF0F4C8F),
    orange: Color(0xFFC3560C),
    onBlue3: Color(0xFFFFFFFF),
    onOrange: Color(0xFFFFFFFF),
  );

  static CohabitColors of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  @override
  CohabitColors copyWith() => this;

  @override
  CohabitColors lerp(CohabitColors? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

extension CohabitTheme on BuildContext {
  CohabitColors get colors => Theme.of(this).extension<CohabitColors>()!;
}

/// Spacing scale in logical pixels.
abstract final class Space {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Control heights: compact with a pointer, at least 44 for touch.
abstract final class ControlSize {
  static const double desktop = 30;
  static const double touch = 44;

  static double of(BuildContext context) =>
      isDesktopPlatform(context) ? desktop : touch;
}

/// macOS (and other desktop) adaptations apply when the theme platform is a
/// desktop one; tests drive this through `ThemeData.platform`.
bool isDesktopPlatform(BuildContext context) =>
    switch (Theme.of(context).platform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      _ => false,
    };

/// Layout breakpoints, in logical pixels of the window (not the screen).
abstract final class Breakpoints {
  /// At and above this width navigation moves to a side column: tablets and
  /// wide windows.
  static const double sidebar = 840;

  /// A phone turned on its side has little height, so it gets the side column
  /// too once it is at least this wide.
  static const double landscapeSidebar = 560;
}

/// Whether navigation is a side column rather than a bottom bar. Desktop
/// platforms always use it; touch platforms choose by window size.
bool usesSidebar(BuildContext context) {
  if (isDesktopPlatform(context)) return true;
  final size = MediaQuery.sizeOf(context);
  return size.width >= Breakpoints.sidebar ||
      (size.width > size.height && size.width >= Breakpoints.landscapeSidebar);
}

/// Typography: Inter for names and sentences; JetBrains Mono, with tabular
/// figures, for numbers and small uppercase labels.
abstract final class CohabitType {
  static const sans = 'Inter';
  static const mono = 'JetBrainsMono';

  static const _tabular = [FontFeature.tabularFigures()];

  static TextStyle body(CohabitColors c) => TextStyle(
    fontFamily: sans,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
    color: c.text,
  );

  /// Habit and item names.
  static TextStyle name(CohabitColors c) => TextStyle(
    fontFamily: sans,
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w500,
    color: c.text,
  );

  static TextStyle title(CohabitColors c) => TextStyle(
    fontFamily: sans,
    fontSize: 20,
    height: 26 / 20,
    fontWeight: FontWeight.w600,
    color: c.text,
  );

  static TextStyle control(CohabitColors c) => TextStyle(
    fontFamily: sans,
    fontSize: 13,
    height: 16 / 13,
    fontWeight: FontWeight.w500,
    color: c.text,
  );

  /// Metadata and numbers: 12px mono, tabular figures.
  static TextStyle meta(CohabitColors c) => TextStyle(
    fontFamily: mono,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
    fontFeatures: _tabular,
    color: c.muted,
  );

  /// Small uppercase section label: 11px, 0.08em tracking, muted. Pass the
  /// text already uppercased, or use `SectionLabel`.
  static TextStyle label(CohabitColors c) => TextStyle(
    fontFamily: mono,
    fontSize: 11,
    height: 14 / 11,
    letterSpacing: 11 * 0.08,
    fontWeight: FontWeight.w500,
    fontFeatures: _tabular,
    color: c.muted,
  );
}
