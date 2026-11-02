import 'package:flutter/material.dart';

import 'tokens.dart';

/// 1px rule in the hairline colour.
class Hairline extends StatelessWidget {
  const Hairline({super.key, this.vertical = false});

  final bool vertical;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: vertical ? 1 : null,
    height: vertical ? null : 1,
    child: ColoredBox(color: context.colors.hairline),
  );
}

/// Small uppercase mono label: 11px, 0.08em tracking, muted.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(text.toUpperCase(), style: CohabitType.label(context.colors)),
  );
}
