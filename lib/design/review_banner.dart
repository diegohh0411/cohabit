import 'package:flutter/material.dart';

import 'buttons.dart';
import 'section_label.dart';
import 'tokens.dart';

/// Prompt shown above the list: hairline above and below, no side borders.
/// Dismiss is ghost, Review is primary.
class ReviewBanner extends StatelessWidget {
  const ReviewBanner({
    super.key,
    required this.title,
    required this.detail,
    required this.onReview,
    required this.onDismiss,
    this.reviewKey,
    this.dismissKey,
  });

  final String title;
  final String detail;
  final VoidCallback onReview;
  final VoidCallback onDismiss;
  final Key? reviewKey;
  final Key? dismissKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final actions = Wrap(
      spacing: Space.s,
      runSpacing: Space.s,
      alignment: WrapAlignment.end,
      children: [
        CohabitButton.ghost(
          key: dismissKey,
          label: 'Dismiss',
          onPressed: onDismiss,
        ),
        CohabitButton.primary(
          key: reviewKey,
          label: 'Review',
          onPressed: onReview,
        ),
      ],
    );
    final message = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: CohabitType.name(c)),
        const SizedBox(height: 2),
        Text(detail, style: CohabitType.meta(c)),
      ],
    );
    return Semantics(
      container: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Hairline(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.m),
            child: LayoutBuilder(
              builder: (context, box) => box.maxWidth >= 480
                  ? Row(
                      children: [
                        Expanded(child: message),
                        const SizedBox(width: Space.l),
                        actions,
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        message,
                        const SizedBox(height: Space.m),
                        actions,
                      ],
                    ),
            ),
          ),
          const Hairline(),
        ],
      ),
    );
  }
}
