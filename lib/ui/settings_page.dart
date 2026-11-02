import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/page_scaffold.dart';
import '../design/buttons.dart';
import '../design/pressable.dart';
import '../data/repository.dart';
import '../design/section_label.dart';
import '../design/select.dart';
import '../design/tokens.dart';
import '../domain/habit_day.dart';
import '../state/backup_controller.dart';
import '../state/providers.dart';
import 'navigation.dart';

String _clock(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

Future<({bool restoreBoundary})?> _confirmRestore(
  RestorePreview preview,
  int current,
) async {
  final navigator = rootNavigatorKey.currentContext;
  if (navigator == null) return null;
  bool boundary = false;
  final confirm = await showDialog<bool>(
    context: navigator,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => Dialog(
        key: const ValueKey('restore-preview'),
        insetPadding: const EdgeInsets.all(Space.l),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.l),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Restore backup", style: CohabitType.name(context.colors)),
                const SizedBox(height: Space.s),
                Text(
                  '${preview.habits} habits · ${preview.logs} day logs\n'
                  '${preview.newEvents} new events · ${preview.duplicates} duplicates\n\n'
                  'Merge with your data. Nothing is deleted. Existing '
                  'event order resolves edits; duplicates are ignored.',
                  style: CohabitType.body(context.colors),
                ),
                const SizedBox(height: Space.l),
                Text(
                  'Backup: ${_clock(preview.boundary)} · Current: ${_clock(current)}',
                  style: CohabitType.meta(context.colors),
                ),
                Pressable(
                  key: const ValueKey('restore-boundary'),
                  semanticLabel: 'Restore day-start time',
                  selected: boundary,
                  onPressed: () => update(() => boundary = !boundary),
                  builder: (context, state) => Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(vertical: Space.s),
                    decoration: state.focused
                        ? BoxDecoration(
                            border: Border.all(color: context.colors.blue3),
                          )
                        : null,
                    child: Row(
                      children: [
                        ExcludeSemantics(child: Text(boundary ? '[x]' : '[ ]')),
                        const SizedBox(width: Space.s),
                        Expanded(
                          child: Text(
                            'Restore day-start time',
                            style: CohabitType.body(context.colors),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Space.l),
                Wrap(
                  spacing: Space.s,
                  runSpacing: Space.s,
                  children: [
                    CohabitButton.ghost(
                      key: const ValueKey('cancel-restore'),
                      onPressed: () => Navigator.pop(context, false),
                      label: "Cancel",
                    ),
                    CohabitButton.primary(
                      key: const ValueKey('confirm-restore'),
                      onPressed: () => Navigator.pop(context, true),
                      label: "Confirm restore",
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  return confirm == true ? (restoreBoundary: boundary) : null;
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _statusKey = GlobalKey();

  void _showStatus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _statusKey.currentContext;
      if (context != null) Scrollable.ensureVisible(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final backup = ref.watch(backupControllerProvider);
    ref.listen(backupControllerProvider, (_, next) {
      if (next.busy || next.message != null) _showStatus();
    });
    final controller = ref.read(backupControllerProvider.notifier);
    final status = backup.busy ? 'Working…' : backup.message;
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
          const SectionLabel('Data'),
          const Text(
            'JSON backups are unencrypted. Store them somewhere private. CSV is for spreadsheets, not a full backup.',
          ),
          if (status != null) ...[
            const SizedBox(height: Space.s),
            Semantics(
              key: _statusKey,
              liveRegion: true,
              container: true,
              child: Text(status, style: CohabitType.body(c)),
            ),
          ],
          for (final (label, action) in [
            ('Save backup (JSON)', () => controller.save(json: true)),
            ('Restore backup', () => controller.restore(_confirmRestore)),
            ('Export CSV', () => controller.save(json: false)),
          ])
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: CohabitButton(
                key: ValueKey(label),
                label: label,
                onPressed: backup.busy ? null : action,
              ),
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
