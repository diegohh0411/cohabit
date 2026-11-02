import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'buttons.dart';
import 'section_label.dart';
import 'tokens.dart';

/// Maximum width of reading content; wider windows centre it.
const double contentMaxWidth = 760;

/// The main action of a page.
///
/// With a pointer it is a button in the header. On touch it floats at the
/// bottom right, in thumb reach, above the bottom bar.
class PageAction {
  const PageAction({
    required this.label,
    required this.onPressed,
    this.key,
    this.desktopVariant = ButtonVariant.primary,
  });

  final String label;
  final VoidCallback? onPressed;
  final Key? key;

  /// How the button looks in the desktop header. On touch it is always
  /// primary, so it stands out from the content it floats over.
  final ButtonVariant desktopVariant;
}

/// A page: header bar with title, optional back and actions, a hairline, and
/// a centred, width-limited body. Replaces the stock app bar.
///
/// On touch, [primaryAction] floats at the bottom right and [bottomBar] is
/// pinned under the body, above the keyboard, so the main controls stay in
/// reach of one thumb.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.titleKey,
    this.actions = const [],
    this.primaryAction,
    this.bottomBar,
    this.showBack,
  });

  final String title;
  final String? subtitle;
  final Key? titleKey;

  /// Secondary header actions.
  final List<Widget> actions;

  /// The page's main action; see [PageAction].
  final PageAction? primaryAction;

  /// Pinned under the body on touch, for example Save. Pass it only for
  /// touch layouts; desktop pages keep their controls in the body.
  final Widget? bottomBar;

  /// Defaults to showing Back whenever the page can be popped.
  final bool? showBack;
  final Widget child;

  /// Space the body leaves at its end so the floating action never covers
  /// the last row.
  static double floatingInset(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return Space.l + scaler.scale(13) + 2 * Space.m + Space.l;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final desktop = isDesktopPlatform(context);
    final canBack = showBack ?? Navigator.of(context).canPop();
    final action = primaryAction;
    final floats = action != null && !desktop;
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
              actions: [
                ...actions,
                if (action != null && desktop)
                  _button(action, action.desktopVariant),
              ],
              showBack: canBack,
            ),
            const Hairline(),
            Expanded(
              child: _PageInsets(
                bottom: floats ? floatingInset(context) : 0,
                child: Stack(
                  children: [
                    Positioned.fill(child: child),
                    if (floats)
                      Positioned(
                        right: Space.l,
                        bottom: Space.l,
                        child: _button(action, ButtonVariant.primary),
                      ),
                  ],
                ),
              ),
            ),
            if (bottomBar != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border(top: BorderSide(color: c.hairline)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(Space.m),
                  child: bottomBar,
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

  Widget _button(PageAction a, ButtonVariant variant) => CohabitButton(
    key: a.key,
    label: a.label,
    variant: variant,
    onPressed: a.onPressed,
  );
}

/// Extra space the body must leave at its end; set by [PageScaffold].
class _PageInsets extends InheritedWidget {
  const _PageInsets({required this.bottom, required super.child});

  final double bottom;

  static double bottomOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PageInsets>()?.bottom ?? 0;

  @override
  bool updateShouldNotify(_PageInsets oldWidget) => bottom != oldWidget.bottom;
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
      // Grows with the text scale rather than clipping.
      constraints: BoxConstraints(minHeight: height),
      color: c.background,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.l,
        vertical: Space.xs,
      ),
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

  /// Extra space at the end on top of what the page already reserves for its
  /// floating action.
  final double bottomInset;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: contentMaxWidth),
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          Space.l,
          Space.l,
          Space.l,
          Space.l + bottomInset + _PageInsets.bottomOf(context),
        ),
        children: children,
      ),
    ),
  );
}
