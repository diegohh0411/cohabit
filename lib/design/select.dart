import 'package:flutter/material.dart';

import 'section_label.dart';
import 'tokens.dart';

/// Drop-down with a hairline border, square menu and no elevation.
class CohabitSelect<T> extends StatelessWidget {
  const CohabitSelect({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.fieldKey,
  });

  final String label;
  final T? value;

  /// Value to visible text.
  final Map<T, String> items;
  final ValueChanged<T>? onChanged;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: SectionLabel(label)),
        const SizedBox(height: Space.xs),
        Container(
          height: ControlSize.of(context),
          padding: const EdgeInsets.symmetric(horizontal: Space.m),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.hairline),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              key: fieldKey,
              value: value,
              isExpanded: true,
              isDense: true,
              elevation: 0,
              borderRadius: BorderRadius.zero,
              dropdownColor: c.surface,
              focusColor: Colors.transparent,
              iconEnabledColor: c.muted,
              style: CohabitType.body(c),
              hint: Text(label, style: CohabitType.body(c)),
              onChanged: onChanged == null
                  ? null
                  : (v) {
                      if (v != null) onChanged!(v);
                    },
              items: [
                for (final e in items.entries)
                  DropdownMenuItem<T>(
                    value: e.key,
                    child: Text(e.value, overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
