import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Interaction state handed to a [Pressable] builder.
class PressState {
  const PressState({
    required this.hovered,
    required this.focused,
    required this.pressed,
    required this.enabled,
  });

  final bool hovered;
  final bool focused;
  final bool pressed;
  final bool enabled;
}

/// A focusable, hoverable, tappable region with button semantics. It is the
/// base of every interactive component: Enter and Space activate it, and a
/// pointer cursor appears on hover.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.onPressed,
    required this.builder,
    this.selected,
    this.semanticLabel,
    this.inGroup = false,
    this.autofocus = false,
    this.focusNode,
  });

  /// Null disables the region.
  final VoidCallback? onPressed;
  final Widget Function(BuildContext context, PressState state) builder;

  /// Non-null for toggle-like regions; exposed to assistive technology.
  final bool? selected;
  final String? semanticLabel;

  /// Part of a mutually exclusive group (a segmented control).
  final bool inGroup;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final state = PressState(
      hovered: _hovered && _enabled,
      focused: _focused && _enabled,
      pressed: _pressed && _enabled,
      enabled: _enabled,
    );
    // One merged node: button, selection, label and the focus action.
    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: _enabled,
        selected: widget.selected,
        inMutuallyExclusiveGroup: widget.inGroup ? true : null,
        label: widget.semanticLabel,
        onTap: widget.onPressed,
        child: FocusableActionDetector(
          enabled: _enabled,
          autofocus: widget.autofocus,
          focusNode: widget.focusNode,
          mouseCursor: _enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onShowFocusHighlight: (v) => setState(() => _focused = v),
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onPressed?.call();
                return null;
              },
            ),
          },
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: _enabled
                  ? (_) => setState(() => _pressed = true)
                  : null,
              onTapCancel: () => setState(() => _pressed = false),
              onTapUp: (_) => setState(() => _pressed = false),
              onTap: widget.onPressed,
              child: widget.builder(context, state),
            ),
          ),
        ),
      ),
    );
  }
}
