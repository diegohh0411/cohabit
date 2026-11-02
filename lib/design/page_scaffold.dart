import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'buttons.dart';
import 'section_label.dart';
import 'tokens.dart';

/// Maximum width of reading content; wider windows centre it.
const double contentMaxWidth = 760;

/// A page: header bar with title, optional back and actions, a hairline, and
/// a centred, width-limited body. Replaces the stock app bar.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.titleKey,
    this.actions = const [],
    this.showBack,
    this.floating,
  });

  final String title;
  final String? subtitle;
  final Key? titleKey;
  final List<Widget> actions;

  /// Defaults to showing Back whenever the page can be popped.
  final bool? showBack;
  final Widget child;

  /// Pinned bottom-right (an add action, for example).
  final Widget? floating;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final canBack = showBack ?? Navigator.of(context).canPop();
    Widget page = Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              title: title,
              subtitle: subtitle,
              titleKey: titleKey,
              actions: actions,
              showBack: canBack,
            ),
            const Hairline(),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: child),
                  if (floating != null)
                    Positioned(
                      right: Space.l,
                      bottom: Space.l,
                      child: floating!,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (canBack) {
      // Escape goes back on desktop.
      page = CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(context).maybePop(),
        },
        child: Focus(autofocus: false, child: page),
      );
    }
    return page;
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.titleKey,
    required this.actions,
    required this.showBack,
  });

  final String title;
  final String? subtitle;
  final Key? titleKey;
  final List<Widget> actions;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final height = isDesktopPlatform(context) ? 52.0 : 56.0;
    return Container(
      height: height,
      color: c.background,
      padding: const EdgeInsets.symmetric(horizontal: Space.l),
      child: Row(
        children: [
          if (showBack) ...[
            CohabitButton.ghost(
              key: const ValueKey('back'),
              label: '← Back',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: Space.s),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    key: titleKey,
                    style: CohabitType.name(c)
                        .copyWith(fontSize: 17, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: CohabitType.meta(c),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          for (final a in actions) ...[const SizedBox(width: Space.s), a],
        ],
      ),
    );
  }
}

/// Scrollable body column with the standard padding and max width.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.bottomInset = 0});

  final List<Widget> children;

  /// Extra space at the end, for floating actions.
  final double bottomInset;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: contentMaxWidth),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          Space.l,
          Space.l,
          Space.l,
          Space.l + bottomInset,
        ),
        children: children,
      ),
    ),
  );
}
