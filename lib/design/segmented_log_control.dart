import 'package:flutter/material.dart';

import 'pressable.dart';
import 'section_label.dart' show Hairline;
import 'tokens.dart';

/// How a selected segment is filled.
enum LogTone {
  /// Done / clean: blue3.
  positive,

  /// Slipped: orange.
  warning,

  /// Not done / skip: a quiet hairline fill.
  neutral,
}

class LogOption<T> {
  const LogOption({
    required this.value,
    required this.label,
    this.tone = LogTone.neutral,
    this.key,
  });

  final T value;
  final String label;
  final LogTone tone;
  final Key? key;
}

/// A row of mutually exclusive segments for logging a day.
///
/// 30px high with a pointer, 44px on touch. Selection is shown by fill and by
/// a heavier label, not by colour alone. Arrow keys move focus between
/// segments; Enter or Space selects.
class SegmentedLogControl<T> extends StatelessWidget {
  const SegmentedLogControl({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.semanticLabel,
  });

  final List<LogOption<T>> options;
  final T? selected;

  /// Called with the tapped option, including the already-selected one, so
  /// callers can treat a second tap as "clear". Null disables the control.
  final ValueChanged<T>? onSelected;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final height = ControlSize.of(context);
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Container(
        // Grows with the text scale; labels wrap rather than clip.
        constraints: BoxConstraints(minHeight: height),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.hairline),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < options.length; i++) ...[
                if (i > 0) const Hairline(vertical: true),
                Expanded(
                  child: _Segment<T>(
                    key: options[i].key,
                    option: options[i],
                    selected: options[i].value == selected,
                    onTap: onSelected == null
                        ? null
                        : () => onSelected!(options[i].value),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Segment<T> extends StatelessWidget {
  const _Segment({
    super.key,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final LogOption<T> option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onPressed: onTap,
      selected: selected,
      inGroup: true,
      builder: (context, s) {
        final (Color fill, Color fg) = selected
            ? switch (option.tone) {
                LogTone.positive => (c.blue3, c.onBlue3),
                LogTone.warning => (c.orange, c.onOrange),
                LogTone.neutral => (c.hairline, c.text),
              }
            : (s.hovered || s.pressed ? c.off : Colors.transparent, c.text);
        return Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s,
            vertical: Space.xs,
          ),
          decoration: BoxDecoration(color: fill),
          foregroundDecoration: s.focused
              ? BoxDecoration(border: Border.all(color: c.blue4, width: 2))
              : null,
          child: Text(
            option.label,
            maxLines: isDesktopPlatform(context) ? 1 : 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: CohabitType.control(c).copyWith(
              color: fg,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        );
      },
    );
  }
}
