import 'package:flutter/material.dart';

const _square = RoundedRectangleBorder();

/// Plain functional theme with 0px corners. The design system is Milestone 2.
ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Colors.blueGrey,
    dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
  );
  const outline = OutlineInputBorder(borderRadius: BorderRadius.zero);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    cardTheme: const CardThemeData(shape: _square, elevation: 0),
    dialogTheme: const DialogThemeData(shape: _square),
    inputDecorationTheme: const InputDecorationTheme(border: outline),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: _square),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(shape: _square),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: _square),
    ),
    chipTheme: const ChipThemeData(shape: _square),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(shape: _square),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      shape: _square,
    ),
    snackBarTheme: const SnackBarThemeData(shape: _square),
    popupMenuTheme: const PopupMenuThemeData(shape: _square),
    dividerTheme: const DividerThemeData(thickness: 1, space: 1),
  );
}
