import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/pressable.dart';
import '../design/section_label.dart';
import '../design/tokens.dart';
import 'habit_form_page.dart';
import 'habits_page.dart';
import 'history_page.dart';
import 'insights_page.dart';
import 'navigation.dart';
import 'settings_page.dart';
import 'today_page.dart';

enum Section {
  today('Today'),
  history('History'),
  insights('Insights'),
  habits('Habits'),
  settings('Settings');

  const Section(this.label);
  final String label;

  Widget get page => switch (this) {
    today => const TodayPage(),
    history => const HistoryPage(),
    insights => const InsightsPage(),
    habits => const HabitsPage(),
    settings => const SettingsPage(),
  };
}

/// A side column on macOS and wide or landscape windows, a bottom bar on
/// phones. Detail pages open beside the sidebar on desktop and full-screen on
/// touch devices.
class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialSection = Section.today});

  final Section initialSection;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final _section = ValueNotifier<Section>(widget.initialSection);
  final _contentNavigator = GlobalKey<NavigatorState>();

  @override
  void dispose() {
    _section.dispose();
    super.dispose();
  }

  void _select(Section s) {
    _contentNavigator.currentState?.popUntil((r) => r.isFirst);
    _section.value = s;
  }

  Widget _sectionPage() => ValueListenableBuilder<Section>(
    valueListenable: _section,
    builder: (context, section, _) =>
        KeyedSubtree(key: ValueKey(section), child: section.page),
  );

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktopPlatform(context);
    if (!usesSidebar(context)) return _phone();

    // Command-1..5 switch sections, command-N adds a habit. Desktop only.
    final bindings = <ShortcutActivator, VoidCallback>{
      if (desktop) ...{
        for (final s in Section.values)
          SingleActivator(_digits[s.index], meta: true): () => _select(s),
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () {
          final nav = _contentNavigator.currentContext;
          if (nav != null) openPage<void>(nav, const HabitFormPage());
        },
      },
    };
    Widget layout = Scaffold(
      body: Row(
        children: [
          ValueListenableBuilder<Section>(
            valueListenable: _section,
            builder: (context, section, _) => _Sidebar(
              selected: section,
              onSelect: _select,
              showShortcuts: desktop,
            ),
          ),
          const Hairline(vertical: true),
          Expanded(
            child: Navigator(
              key: _contentNavigator,
              onGenerateRoute: (_) =>
                  MaterialPageRoute<void>(builder: (_) => _sectionPage()),
            ),
          ),
        ],
      ),
    );
    if (!desktop) layout = _backToToday(layout);
    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(autofocus: true, child: layout),
    );
  }

  /// Phones and other narrow windows: the sections fill the screen and a
  /// bottom bar switches between them.
  Widget _phone() => _backToToday(
    Scaffold(
      // The bar stays put behind the keyboard; no root section has a text
      // field, and detail pages with one cover the bar.
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          Expanded(child: _sectionPage()),
          ValueListenableBuilder<Section>(
            valueListenable: _section,
            builder: (context, section, _) =>
                _BottomBar(selected: section, onSelect: _select),
          ),
        ],
      ),
    ),
  );

  /// Back from a detail page returns to its section (Navigator does that
  /// before this is consulted). Back from another section returns to Today.
  /// Back from Today leaves the app.
  Widget _backToToday(Widget child) => ValueListenableBuilder<Section>(
    valueListenable: _section,
    child: child,
    builder: (context, section, child) => PopScope(
      canPop: section == Section.today,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(Section.today);
      },
      child: child!,
    ),
  );
}

const _digits = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
];

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.selected,
    required this.onSelect,
    required this.showShortcuts,
  });

  final Section selected;
  final ValueChanged<Section> onSelect;
  final bool showShortcuts;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: 200,
      color: c.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.l,
                Space.xl,
                Space.l,
                Space.l,
              ),
              child: Text(
                'Cohabit',
                style: CohabitType.name(c)
                    .copyWith(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
            const Hairline(),
            Semantics(
              container: true,
              label: 'Sections',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final s in Section.values)
                    _SidebarItem(
                      section: s,
                      selected: s == selected,
                      showShortcut: showShortcuts,
                      onTap: () => onSelect(s),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.section,
    required this.selected,
    required this.showShortcut,
    required this.onTap,
  });

  final Section section;
  final bool selected;
  final bool showShortcut;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onPressed: onTap,
      selected: selected,
      builder: (context, s) => Container(
        constraints: BoxConstraints(
          minHeight: isDesktopPlatform(context) ? 34 : ControlSize.touch,
        ),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: selected || s.hovered ? c.off : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: selected ? c.blue3 : Colors.transparent,
              width: 2,
            ),
          ),
          // Keyboard focus is shown on top of the selection rule.
        ),
        foregroundDecoration: s.focused
            ? BoxDecoration(border: Border.all(color: c.blue3, width: 2))
            : null,
        padding: const EdgeInsets.symmetric(horizontal: Space.l - 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                section.label,
                style: CohabitType.control(c).copyWith(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (showShortcut)
              ExcludeSemantics(
                child: Text(
                  '⌘${section.index + 1}',
                  style: CohabitType.meta(c),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Primary phone navigation. Each tab is the full width of a quarter of the
/// screen and at least 56px tall, so it is easy to hit with a thumb; the bar
/// paints under the gesture area, with its content inside the safe area.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.selected, required this.onSelect});

  final Section selected;
  final ValueChanged<Section> onSelect;

  /// Tabs stay a fixed width, so their labels stop growing here and shrink to
  /// fit instead.
  static const double maxLabelScale = 1.5;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Semantics(
          container: true,
          label: 'Sections',
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: maxLabelScale,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final s in Section.values)
                    Expanded(
                      child: Pressable(
                        onPressed: () => onSelect(s),
                        selected: s == selected,
                        inGroup: true,
                        builder: (context, state) => Container(
                          constraints: const BoxConstraints(minHeight: 56),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.xs,
                          ),
                          decoration: BoxDecoration(
                            color: state.pressed ? c.off : null,
                            border: Border(
                              top: BorderSide(
                                color: s == selected
                                    ? c.blue3
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          foregroundDecoration: state.focused
                              ? BoxDecoration(
                                  border: Border.all(color: c.blue3, width: 2),
                                )
                              : null,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              s.label,
                              maxLines: 1,
                              style: CohabitType.control(c).copyWith(
                                fontWeight: s == selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: s == selected ? c.text : c.muted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
