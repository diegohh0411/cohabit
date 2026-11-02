import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/page_scaffold.dart';
import '../design/section_label.dart';
import '../design/select.dart';
import '../design/tokens.dart';
import '../domain/habit_day.dart';
import '../state/providers.dart';

String _clock(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final boundary =
        ref.watch(dayBoundaryProvider).value ?? defaultDayBoundaryMinutes;
    final options = {
      for (var h = 0; h <= maxDayBoundaryMinutes ~/ 60; h++) h * 60,
      boundary,
    }.toList()..sort();

    return PageScaffold(
      title: 'Settings',
      child: PageBody(
        children: [
          const SectionLabel('Day'),
          const SizedBox(height: Space.s),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: CohabitSelect<int>(
              fieldKey: const ValueKey('day-boundary'),
              label: 'Day starts at',
              value: boundary,
              items: {for (final m in options) m: _clock(m)},
              onChanged: (m) =>
                  ref.read(repositoryProvider).setDayBoundaryMinutes(m),
            ),
          ),
          const SizedBox(height: Space.s),
          Text(
            'Logging before this time counts toward the previous day. '
            'Existing logs keep their day.',
            style: CohabitType.meta(c),
          ),
          const SizedBox(height: Space.xl),
          const SectionLabel('About'),
          const SizedBox(height: Space.s),
          Text(
            'Typefaces: Inter and JetBrains Mono, bundled under the SIL Open '
            'Font License 1.1.',
            style: CohabitType.meta(c),
          ),
        ],
      ),
    );
  }
}
