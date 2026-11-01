import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show setEquals;

import '../domain/day_state.dart';
import '../domain/habit.dart';
import '../state/providers.dart';
import 'labels.dart';

/// Create a habit, or edit / archive an existing one. Polarity is fixed once
/// a habit exists.
class HabitFormPage extends ConsumerStatefulWidget {
  const HabitFormPage({super.key, this.habit});

  final Habit? habit;

  @override
  ConsumerState<HabitFormPage> createState() => _HabitFormPageState();
}

class _HabitFormPageState extends ConsumerState<HabitFormPage> {
  late final TextEditingController _name = TextEditingController(
    text: widget.habit?.name ?? '',
  );
  late HabitPolarity _polarity =
      widget.habit?.polarity ?? HabitPolarity.positive;
  late final Set<int> _schedule = {...(widget.habit?.schedule ?? everyDay)};

  bool get _isEdit => widget.habit != null;
  bool get _valid => _name.text.trim().isNotEmpty && _schedule.isNotEmpty;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final repo = ref.read(repositoryProvider);
    final habit = widget.habit;
    if (habit == null) {
      await repo.createHabit(
        name: _name.text,
        polarity: _polarity,
        schedule: _schedule,
      );
    } else {
      final name = _name.text.trim();
      await repo.editHabit(
        habit.id,
        name: name == habit.name ? null : name,
        schedule: setEquals(_schedule, habit.schedule) ? null : _schedule,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _archive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive habit?'),
        content: const Text('It leaves your lists. Its history is kept.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-archive'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(repositoryProvider).archiveHabit(widget.habit!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit habit' : 'New habit')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const ValueKey('habit-name'),
            controller: _name,
            autofocus: !_isEdit,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          SegmentedButton<HabitPolarity>(
            key: const ValueKey('habit-polarity'),
            segments: const [
              ButtonSegment(
                value: HabitPolarity.positive,
                label: Text('Build'),
              ),
              ButtonSegment(
                value: HabitPolarity.negative,
                label: Text('Avoid'),
              ),
            ],
            selected: {_polarity},
            onSelectionChanged: _isEdit
                ? null
                : (s) => setState(() => _polarity = s.first),
          ),
          if (_isEdit)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Type cannot change after creation.'),
            ),
          const SizedBox(height: 16),
          const Text('Days'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  key: ValueKey('weekday-$d'),
                  label: Text(weekdayNames[d - 1].substring(0, 3)),
                  selected: _schedule.contains(d),
                  onSelected: (on) => setState(
                    () => on ? _schedule.add(d) : _schedule.remove(d),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const ValueKey('save-habit'),
            onPressed: _valid ? _save : null,
            child: const Text('Save'),
          ),
          if (_isEdit) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('archive-habit'),
              onPressed: _archive,
              child: const Text('Archive'),
            ),
          ],
        ],
      ),
    );
  }
}
