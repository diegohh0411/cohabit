import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/buttons.dart';
import '../design/confirm_dialog.dart';
import '../design/page_scaffold.dart';
import '../design/pressable.dart';
import '../design/section_label.dart';
import '../design/segmented_log_control.dart';
import '../design/text_field.dart';
import '../design/tokens.dart';
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
    final confirmed = await showConfirmDialog(
      context,
      title: 'Archive habit?',
      message: 'It leaves your lists. Its history is kept.',
      confirmLabel: 'Archive',
      confirmKey: const ValueKey('confirm-archive'),
    );
    if (!confirmed) return;
    await ref.read(repositoryProvider).archiveHabit(widget.habit!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PageScaffold(
      title: _isEdit ? 'Edit habit' : 'New habit',
      child: PageBody(
        children: [
          CohabitTextField(
            fieldKey: const ValueKey('habit-name'),
            label: 'Name',
            controller: _name,
            autofocus: !_isEdit,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.l),
          const SectionLabel('Type'),
          const SizedBox(height: Space.xs),
          SegmentedLogControl<HabitPolarity>(
            key: const ValueKey('habit-polarity'),
            semanticLabel: 'Habit type',
            selected: _polarity,
            onSelected: _isEdit ? null : (p) => setState(() => _polarity = p),
            options: const [
              LogOption(value: HabitPolarity.positive, label: 'Build'),
              LogOption(value: HabitPolarity.negative, label: 'Avoid'),
            ],
          ),
          if (_isEdit)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                'Type cannot change after creation.',
                style: CohabitType.meta(c),
              ),
            ),
          const SizedBox(height: Space.l),
          const SectionLabel('Days'),
          const SizedBox(height: Space.xs),
          Row(
            children: [
              for (var d = 1; d <= 7; d++) ...[
                if (d > 1) const SizedBox(width: Space.xs),
                Expanded(
                  child: _DayToggle(
                    key: ValueKey('weekday-$d'),
                    label: weekdayNames[d - 1].substring(0, 3),
                    selected: _schedule.contains(d),
                    onTap: () => setState(
                      () => _schedule.contains(d)
                          ? _schedule.remove(d)
                          : _schedule.add(d),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (_isEdit)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                'A new schedule applies from today. Earlier days keep the '
                'schedule they had.',
                style: CohabitType.meta(c),
              ),
            ),
          const SizedBox(height: Space.xl),
          Row(
            children: [
              CohabitButton.primary(
                key: const ValueKey('save-habit'),
                label: 'Save',
                onPressed: _valid ? _save : null,
              ),
              if (_isEdit) ...[
                const SizedBox(width: Space.s),
                CohabitButton.secondary(
                  key: const ValueKey('archive-habit'),
                  label: 'Archive',
                  onPressed: _archive,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _DayToggle extends StatelessWidget {
  const _DayToggle({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onPressed: onTap,
      selected: selected,
      builder: (context, s) => Container(
        height: ControlSize.of(context),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? c.text
              : s.hovered
              ? c.off
              : c.surface,
          border: Border.all(color: s.focused ? c.blue3 : c.hairline),
        ),
        foregroundDecoration: s.focused
            ? BoxDecoration(border: Border.all(color: c.blue3, width: 2))
            : null,
        child: Text(
          label,
          style: CohabitType.control(c).copyWith(
            color: selected ? c.background : c.text,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
