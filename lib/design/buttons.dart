import 'package:flutter/material.dart';

import 'pressable.dart';
import 'tokens.dart';

enum ButtonVariant { primary, secondary, ghost }

/// Primary (text-colour fill, background-colour label), secondary (hairline)
/// and ghost (muted) buttons.
class CohabitButton extends StatelessWidget {
  const CohabitButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = ButtonVariant.secondary,
    this.expand = false,
    this.autofocus = false,
  });

  const CohabitButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.expand = false,
    this.autofocus = false,
  }) : variant = ButtonVariant.primary;

  const CohabitButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.expand = false,
    this.autofocus = false,
  }) : variant = ButtonVariant.secondary;

  const CohabitButton.ghost({
    super.key,
    required this.label,
    required this.onPressed,
    this.expand = false,
    this.autofocus = false,
  }) : variant = ButtonVariant.ghost;

  final String label;
  final VoidCallback? onPressed;
  final ButtonVariant variant;
  final bool expand;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final height = ControlSize.of(context);
    return Pressable(
      onPressed: onPressed,
      autofocus: autofocus,
      builder: (context, s) {
        final (Color fill, Color fg, Color border) = switch (variant) {
          ButtonVariant.primary => (
            s.hovered || s.pressed ? c.text.withValues(alpha: 0.86) : c.text,
            c.background,
            c.text,
          ),
          ButtonVariant.secondary => (
            s.hovered || s.pressed ? c.off : Colors.transparent,
            c.text,
            c.hairline,
          ),
          ButtonVariant.ghost => (
            s.hovered || s.pressed ? c.off : Colors.transparent,
            c.muted,
            Colors.transparent,
          ),
        };
        final enabledOpacity = s.enabled ? 1.0 : 0.4;
        return Opacity(
          opacity: enabledOpacity,
          child: Container(
            constraints: BoxConstraints(minHeight: height, minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            alignment: expand ? Alignment.center : null,
            decoration: BoxDecoration(
              color: fill,
              border: Border.all(color: s.focused ? c.blue3 : border),
            ),
            foregroundDecoration: s.focused
                ? BoxDecoration(border: Border.all(color: c.blue3, width: 2))
                : null,
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CohabitType.control(c).copyWith(color: fg),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
