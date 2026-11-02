import 'package:flutter/material.dart';

import 'tokens.dart';

/// One habit: surface with a hairline border, the name, a mono metadata
/// line and the log control. The control sits to the right when there is
/// room and below the name otherwise.
class HabitRow extends StatelessWidget {
  const HabitRow({
    super.key,
    required this.name,
    required this.meta,
    required this.control,
    this.metaKey,
    this.onNameTap,
  });

  final String name;

  /// e.g. `Mon Wed Fri · avoid · Not logged`.
  final String meta;
  final Key? metaKey;
  final Widget control;
  final VoidCallback? onNameTap;

  static const double wideBreakpoint = 560;
  static const double controlWidth = 300;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          style: CohabitType.name(c),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          meta,
          key: metaKey,
          style: CohabitType.meta(c),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.m),
        child: LayoutBuilder(
          builder: (context, box) {
            if (box.maxWidth >= wideBreakpoint) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: text),
                  const SizedBox(width: Space.l),
                  SizedBox(width: controlWidth, child: control),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                text,
                const SizedBox(height: Space.m),
                control,
              ],
            );
          },
        ),
      ),
    );
  }
}
