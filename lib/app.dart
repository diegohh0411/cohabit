import 'package:flutter/material.dart';

import 'ui/theme.dart';
import 'ui/today_page.dart';

class CohabitApp extends StatelessWidget {
  const CohabitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cohabit',
      theme: buildTheme(),
      home: const TodayPage(),
    );
  }
}
