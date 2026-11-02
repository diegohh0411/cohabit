import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/pressable.dart';
import '../design/section_label.dart';
import '../design/tokens.dart';
import 'habit_form_page.dart';
import 'habits_page.dart';
import 'history_page.dart';
import 'navigation.dart';
import 'settings_page.dart';
import 'today_page.dart';

enum Section {
  today('Today'),
  history('History'),
  habits('Habits'),
  settings('Settings');

  const Section(this.label);
  final String label;

  Widget get page => switch (this) {
    today => const TodayPage(),
    history => const HistoryPage(),
    habits => const HabitsPage(),
    settings => const SettingsPage(),
  };
}

/// Sidebar on macOS, bottom bar on Android. Detail pages open beside the
/// sidebar on desktop and full-screen on phones.
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
    if (!desktop) {
      return Scaffold(
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
      );
    }

    // Command-1..4 switch sections, command-N adds a habit.
    final bindings = <ShortcutActivator, VoidCallback>{
      for (final s in Section.values)
        SingleActivator(_digits[s.index], meta: true): () => _select(s),
      const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () {
        final nav = _contentNavigator.currentContext;
        if (nav != null) openPage<void>(nav, const HabitFormPage());
      },
    };
    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            children: [
              ValueListenableBuilder<Section>(
                valueListenable: _section,
                builder: (context, section, _) =>
                    _Sidebar(selected: section, onSelect: _select),
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
        ),
      ),
    );
  }
}

const _digits = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
];

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selected, required this.onSelect});

  final Section selected;
  final ValueChanged<Section> onSelect;

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
    required this.onTap,
  });

  final Section section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onPressed: onTap,
      selected: selected,
      builder: (context, s) => Container(
        height: 34,
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
            ExcludeSemantics(
              child: Text('⌘${section.index + 1}', style: CohabitType.meta(c)),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.selected, required this.onSelect});

  final Section selected;
  final ValueChanged<Section> onSelect;

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
          child: Row(
            children: [
              for (final s in Section.values)
                Expanded(
                  child: Pressable(
                    onPressed: () => onSelect(s),
                    selected: s == selected,
                    builder: (context, state) => Container(
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: s == selected ? c.blue3 : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      foregroundDecoration: state.focused
                          ? BoxDecoration(
                              border: Border.all(color: c.blue3, width: 2),
                            )
                          : null,
                      child: Text(
                        s.label,
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
            ],
          ),
        ),
      ),
    );
  }
}
