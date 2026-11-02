import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/page_scaffold.dart';
import '../design/buttons.dart';
import '../data/backup_files.dart';
import '../domain/hlc.dart';
import '../design/section_label.dart';
import '../design/select.dart';
import '../design/tokens.dart';
import '../domain/habit_day.dart';
import '../state/providers.dart';

String _clock(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool busy = false;
  String? feedback;

  Future<void> run(String operation) async {
    if (busy) return;
    setState(() {
      busy = true;
      feedback = null;
    });
    try {
      final repo = ref.read(repositoryProvider);
      final files = ref.read(backupFilesProvider);
      if (operation != "Restore backup") {
        final json = operation == "Save backup (JSON)";
        final contents = json
            ? await repo.exportBackup()
            : await repo.exportCsv();
        if (await files.save(contents, json ? "json" : "csv")) {
          if (mounted) setState(() => feedback = "File saved.");
        }
      } else {
        final input = await files.openJson();
        if (input == null) return;
        final preview = await repo.previewRestore(input);
        final current = await repo.dayBoundaryMinutes();
        if (!mounted) return;
        bool boundary = false;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
              shape: const RoundedRectangleBorder(),
              title: const Text("Restore backup"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "${preview.habits} habits · ${preview.logs} day logs\n${preview.newEvents} new events · ${preview.duplicates} duplicates\n\nMerge with your data. Nothing is deleted. Existing event order resolves edits; duplicates are ignored.",
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Restore day-start time"),
                      subtitle: Text(
                        "Backup: ${_clock(preview.boundary)} · Current: ${_clock(current)}",
                      ),
                      value: boundary,
                      onChanged: (value) => update(() => boundary = value!),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("Cancel"),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text("Confirm restore"),
                ),
              ],
            ),
          ),
        );
        if (confirm != true || !mounted) return;
        await repo.restoreBackup(input, restoreBoundary: boundary);
        if (mounted) {
          setState(
            () => feedback = "Restore complete. Backup merged with your data.",
          );
        }
      }
    } on ClockDriftException {
      if (mounted) {
        setState(
          () => feedback = "Check your device date and time, then try again. The backup contains events ahead of this device clock.",
        );
      }
    } on FormatException {
      if (mounted) {
        setState(
          () => feedback = "This file is not a supported Cohabit backup. Choose a valid JSON backup.",
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => feedback = "Could not complete the operation. Check the file and storage access, then try again.",
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          const SectionLabel('Data'),
          const Text(
            'JSON backups are unencrypted. Store them somewhere private. CSV is for spreadsheets, not a full backup.',
          ),
          for (final label in [
            'Save backup (JSON)',
            'Restore backup',
            'Export CSV',
          ])
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: CohabitButton(
                label: label,
                onPressed: busy ? null : () => run(label),
              ),
            ),
          if (busy) const Text('Working…'),
          if (feedback != null) Text(feedback!, semanticsLabel: feedback),
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
