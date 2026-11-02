import 'package:flutter/material.dart';

import 'buttons.dart';
import 'tokens.dart';

/// Square, hairline-bordered confirmation. Returns true when confirmed.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  Key? confirmKey,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: context.colors.background.withValues(alpha: 0.7),
    builder: (context) {
      final c = context.colors;
      return Dialog(
        insetPadding: const EdgeInsets.all(Space.l),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(Space.l),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: CohabitType.name(c)),
                const SizedBox(height: Space.s),
                Text(message, style: CohabitType.body(c)),
                const SizedBox(height: Space.l),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    CohabitButton.ghost(
                      label: 'Cancel',
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                    const SizedBox(width: Space.s),
                    CohabitButton.primary(
                      key: confirmKey,
                      label: confirmLabel,
                      autofocus: true,
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return result ?? false;
}
