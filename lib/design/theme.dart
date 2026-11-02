import 'package:flutter/material.dart';

import 'tokens.dart';

/// Material is used only as plumbing (routes, text input, focus); every
/// visible surface comes from the design system: 0px corners, 1px hairlines,
/// no elevation, no ink effects.
ThemeData buildTheme(Brightness brightness, {TargetPlatform? platform}) {
  final c = CohabitColors.of(brightness);
  const square = RoundedRectangleBorder();
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.text,
    onPrimary: c.background,
    secondary: c.blue3,
    onSecondary: c.onBlue3,
    error: c.orange,
    onError: c.onOrange,
    surface: c.surface,
    onSurface: c.text,
    outline: c.hairline,
    outlineVariant: c.hairline,
    surfaceTint: Colors.transparent,
    shadow: Colors.transparent,
  );
  final body = CohabitType.body(c);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    platform: platform,
    colorScheme: scheme,
    fontFamily: CohabitType.sans,
    scaffoldBackgroundColor: c.background,
    canvasColor: c.surface,
    dividerColor: c.hairline,
    dividerTheme: DividerThemeData(color: c.hairline, thickness: 1, space: 1),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    focusColor: Colors.transparent,
    textTheme: TextTheme(
      displayLarge: CohabitType.title(c),
      displayMedium: CohabitType.title(c),
      displaySmall: CohabitType.title(c),
      headlineLarge: CohabitType.title(c),
      headlineMedium: CohabitType.title(c),
      headlineSmall: CohabitType.title(c),
      titleLarge: CohabitType.title(c),
      titleMedium: CohabitType.name(c),
      titleSmall: CohabitType.name(c),
      bodyLarge: body,
      bodyMedium: body,
      bodySmall: CohabitType.meta(c),
      labelLarge: CohabitType.control(c),
      labelMedium: CohabitType.control(c),
      labelSmall: CohabitType.label(c),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _QuietTransitions(),
        TargetPlatform.iOS: _QuietTransitions(),
        TargetPlatform.macOS: _QuietTransitions(),
        TargetPlatform.windows: _QuietTransitions(),
        TargetPlatform.linux: _QuietTransitions(),
        TargetPlatform.fuchsia: _QuietTransitions(),
      },
    ),
    extensions: [c],
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.blue3,
      selectionColor: c.blue3.withValues(alpha: 0.35),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(side: BorderSide(color: c.hairline)),
    ),
    datePickerTheme: DatePickerThemeData(
      shape: RoundedRectangleBorder(side: BorderSide(color: c.hairline)),
      backgroundColor: c.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      dayShape: const WidgetStatePropertyAll(square),
      yearShape: const WidgetStatePropertyAll(square),
      todayBorder: BorderSide(color: c.blue3),
      todayForegroundColor: WidgetStatePropertyAll(c.text),
      dayForegroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.onBlue3 : c.text,
      ),
      dayBackgroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.blue3 : Colors.transparent,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: square,
        foregroundColor: c.text,
        textStyle: CohabitType.control(c),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.hairline),
      ),
      textStyle: CohabitType.meta(c).copyWith(color: c.text),
    ),
    snackBarTheme: SnackBarThemeData(
      shape: RoundedRectangleBorder(side: BorderSide(color: c.hairline)),
      backgroundColor: c.surface,
      contentTextStyle: body,
      elevation: 0,
    ),
  );
}

/// Pages cross-fade briefly instead of sliding or zooming.
class _QuietTransitions extends PageTransitionsBuilder {
  const _QuietTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(opacity: animation, child: child);
}
