import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design/system_ui.dart';
import 'design/theme.dart';
import 'design/tokens.dart';
import 'ui/app_shell.dart';
import 'ui/navigation.dart';

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
      navigatorKey: rootNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: themeMode,
      scrollBehavior: const CohabitScrollBehavior(),
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: systemUiStyleFor(context.colors),
        child: child!,
      ),
      home: AppShell(initialSection: initialSection),
    );
  }
}
