import 'package:flutter/material.dart';

import 'section_label.dart';
import 'tokens.dart';

/// Input with a hairline border that turns blue3 on focus. The label is a
/// [SectionLabel] above the field, and is also the field's semantic label.
class CohabitTextField extends StatelessWidget {
  const CohabitTextField({
    super.key,
    required this.label,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.autofocus = false,
    this.hint,
    this.textCapitalization = TextCapitalization.none,
    this.fieldKey,
  });

  final String label;
  final String? hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;

  /// Key for the underlying [TextField], so tests can enter text.
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: color),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: SectionLabel(label)),
        const SizedBox(height: Space.xs),
        TextField(
          key: fieldKey,
          controller: controller,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          textInputAction: textInputAction,
          autofocus: autofocus,
          textCapitalization: textCapitalization,
          cursorColor: c.blue3,
          cursorWidth: 1.5,
          style: CohabitType.body(c),
          decoration: InputDecoration(
            // The visible label is the SectionLabel above; this one only
            // feeds the semantics tree.
            labelText: label,
            labelStyle: const TextStyle(color: Colors.transparent),
            floatingLabelBehavior: FloatingLabelBehavior.never,
            hintText: hint,
            hintStyle: CohabitType.body(c).copyWith(color: c.muted),
            isDense: true,
            filled: true,
            fillColor: c.surface,
            contentPadding: EdgeInsets.symmetric(
              horizontal: Space.m,
              vertical: (ControlSize.of(context) - 20) / 2,
            ),
            enabledBorder: border(c.hairline),
            border: border(c.hairline),
            focusedBorder: border(c.blue3),
          ),
        ),
      ],
    );
  }
}
