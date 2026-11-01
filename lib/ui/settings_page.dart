import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/habit_day.dart';
import '../state/providers.dart';

String _clock(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boundary =
        ref.watch(dayBoundaryProvider).value ?? defaultDayBoundaryMinutes;
    final options = {
      for (var h = 0; h <= maxDayBoundaryMinutes ~/ 60; h++) h * 60,
      boundary,
    }.toList()..sort();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Day starts at'),
            subtitle: const Text(
              'Logging before this time counts toward the previous day. '
              'Existing logs keep their day.',
            ),
            trailing: DropdownButton<int>(
              key: const ValueKey('day-boundary'),
              value: boundary,
              items: [
                for (final m in options)
                  DropdownMenuItem(value: m, child: Text(_clock(m))),
              ],
              onChanged: (m) {
                if (m != null) {
                  ref.read(repositoryProvider).setDayBoundaryMinutes(m);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
