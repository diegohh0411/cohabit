import 'package:flutter/material.dart';

import 'design/theme.dart';
import 'ui/app_shell.dart';

class CohabitApp extends StatelessWidget {
  const CohabitApp({
    super.key,
    this.themeMode = ThemeMode.system,
    this.initialSection = Section.today,
  });

  /// Follows the OS by default; fixed only by demos and tests.
  final ThemeMode themeMode;
  final Section initialSection;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cohabit',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: themeMode,
      home: AppShell(initialSection: initialSection),
    );
  }
}
