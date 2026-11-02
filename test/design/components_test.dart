import 'package:cohabit/design/buttons.dart';
import 'package:cohabit/design/habit_row.dart';
import 'package:cohabit/design/insight_card.dart';
import 'package:cohabit/design/review_banner.dart';
import 'package:cohabit/design/section_label.dart';
import 'package:cohabit/design/segmented_log_control.dart';
import 'package:cohabit/design/text_field.dart';
import 'package:cohabit/design/theme.dart';
import 'package:cohabit/design/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(
  Widget child, {
  Brightness brightness = Brightness.dark,
  TargetPlatform platform = TargetPlatform.macOS,
  double width = 700,
}) => MaterialApp(
  key: ValueKey('$brightness-$platform'),
  debugShowCheckedModeBanner: false,
  theme: buildTheme(brightness, platform: platform),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: width, child: child),
    ),
  ),
);

/// Background colour of the first decorated container under [finder].
Color? fillOf(WidgetTester tester, Finder finder) {
  final box = tester.widget<Container>(
    find.descendant(of: finder, matching: find.byType(Container)).first,
  );
  return (box.decoration as BoxDecoration?)?.color;
}

TextStyle? labelStyleOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style;

void main() {
  group('theme', () {
    test('0px corners and no elevation anywhere', () {
      for (final b in Brightness.values) {
        final t = buildTheme(b);
        expect(
          (t.dialogTheme.shape! as RoundedRectangleBorder).borderRadius,
          BorderRadius.zero,
        );
        expect(t.dialogTheme.elevation, 0);
        expect(t.splashFactory, NoSplash.splashFactory);
        expect(t.snackBarTheme.elevation, 0);
      }
    });

    test('typography: Inter for text, JetBrains Mono tabular for numbers', () {
      final c = CohabitColors.dark;
      expect(CohabitType.body(c).fontFamily, 'Inter');
      expect(CohabitType.name(c).fontFamily, 'Inter');
      expect(CohabitType.meta(c).fontFamily, 'JetBrainsMono');
      expect(CohabitType.meta(c).fontFeatures, [
        const FontFeature.tabularFigures(),
      ]);
      final label = CohabitType.label(c);
      expect(label.fontFamily, 'JetBrainsMono');
      expect(label.fontSize, 11);
      expect(label.letterSpacing, closeTo(11 * 0.08, 1e-9));
      expect(label.color, c.muted);
      expect(label.fontFeatures, [const FontFeature.tabularFigures()]);
    });

    test('fonts and their OFL licences are bundled assets', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      for (final f in [
        'Inter-Regular',
        'Inter-Medium',
        'Inter-SemiBold',
        'JetBrainsMono-Regular',
        'JetBrainsMono-Medium',
        'JetBrainsMono-SemiBold',
      ]) {
        final data = await rootBundle.load('assets/fonts/$f.ttf');
        expect(data.lengthInBytes, greaterThan(100000), reason: f);
      }
      for (final f in ['OFL-Inter', 'OFL-JetBrainsMono']) {
        final text = await rootBundle.loadString('assets/fonts/$f.txt');
        expect(text, contains('SIL OPEN FONT LICENSE'), reason: f);
      }
    });

    testWidgets('follows the OS brightness', (tester) async {
      Brightness? seen;
      CohabitColors? colors;
      Widget app() => MaterialApp(
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: Builder(
          builder: (context) {
            seen = Theme.of(context).brightness;
            colors = context.colors;
            return const SizedBox();
          },
        ),
      );

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await tester.pumpWidget(app());
      expect(seen, Brightness.dark);
      expect(colors, CohabitColors.dark);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(seen, Brightness.light);
      expect(colors, CohabitColors.light);
    });
  });

  group('SectionLabel', () {
    testWidgets('uppercase 11px mono, muted, as a header', (tester) async {
      await tester.pumpWidget(host(const SectionLabel('Scheduled today')));
      final text = tester.widget<Text>(find.text('SCHEDULED TODAY'));
      expect(text.style!.fontSize, 11);
      expect(text.style!.fontFamily, 'JetBrainsMono');
      expect(text.style!.color, CohabitColors.dark.muted);
      expect(
        tester.getSemantics(find.text('SCHEDULED TODAY')),
        matchesSemantics(label: 'SCHEDULED TODAY', isHeader: true),
      );
    });
  });

  group('SegmentedLogControl', () {
    Widget control({
      String? selected,
      ValueChanged<String>? onSelected,
      TargetPlatform platform = TargetPlatform.macOS,
      Brightness brightness = Brightness.dark,
    }) => host(
      SegmentedLogControl<String>(
        selected: selected,
        onSelected: onSelected,
        options: const [
          LogOption(
            key: ValueKey('a'),
            value: 'done',
            label: 'Done',
            tone: LogTone.positive,
          ),
          LogOption(
            key: ValueKey('b'),
            value: 'slip',
            label: 'Slipped',
            tone: LogTone.warning,
          ),
          LogOption(key: ValueKey('c'), value: 'skip', label: 'Skip'),
        ],
      ),
      platform: platform,
      brightness: brightness,
    );

    testWidgets('30px high on desktop, 44px on touch', (tester) async {
      await tester.pumpWidget(control());
      expect(
        tester.getSize(find.byType(SegmentedLogControl<String>)).height,
        30,
      );
      await tester.pumpWidget(control(platform: TargetPlatform.android));
      expect(
        tester.getSize(find.byType(SegmentedLogControl<String>)).height,
        44,
      );
    });

    for (final brightness in Brightness.values) {
      final c = CohabitColors.of(brightness);
      testWidgets('selected Done uses blue3 and its label colour '
          '(${brightness.name})', (tester) async {
        await tester.pumpWidget(
          control(selected: 'done', brightness: brightness),
        );
        expect(fillOf(tester, find.byKey(const ValueKey('a'))), c.blue3);
        expect(labelStyleOf(tester, 'Done')!.color, c.onBlue3);
        expect(labelStyleOf(tester, 'Done')!.fontWeight, FontWeight.w600);
      });

      testWidgets('selected Slipped uses orange and its label colour '
          '(${brightness.name})', (tester) async {
        await tester.pumpWidget(
          control(selected: 'slip', brightness: brightness),
        );
        expect(fillOf(tester, find.byKey(const ValueKey('b'))), c.orange);
        expect(labelStyleOf(tester, 'Slipped')!.color, c.onOrange);
      });
    }

    testWidgets('unselected segments are transparent with plain text', (
      tester,
    ) async {
      await tester.pumpWidget(control(selected: 'done'));
      expect(
        fillOf(tester, find.byKey(const ValueKey('b'))),
        Colors.transparent,
      );
      expect(labelStyleOf(tester, 'Slipped')!.fontWeight, FontWeight.w500);
    });

    testWidgets('selected neutral option has a quiet fill', (tester) async {
      await tester.pumpWidget(control(selected: 'skip'));
      expect(
        fillOf(tester, find.byKey(const ValueKey('c'))),
        CohabitColors.dark.hairline,
      );
    });

    testWidgets('tap selects, including the already selected option', (
      tester,
    ) async {
      final taps = <String>[];
      await tester.pumpWidget(control(selected: 'done', onSelected: taps.add));
      await tester.tap(find.text('Slipped'));
      await tester.tap(find.text('Done'));
      expect(taps, ['slip', 'done']);
    });

    testWidgets('hover shows the off fill on an unselected segment', (
      tester,
    ) async {
      await tester.pumpWidget(control(onSelected: (_) {}));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('c'))));
      await tester.pump();
      expect(
        fillOf(tester, find.byKey(const ValueKey('c'))),
        CohabitColors.dark.off,
      );
    });

    testWidgets('keyboard: Tab focuses, arrows move, Enter selects', (
      tester,
    ) async {
      final taps = <String>[];
      await tester.pumpWidget(control(onSelected: taps.add));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(taps, ['slip', 'skip']);
    });

    testWidgets('semantics: buttons in a group, selection exposed', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(control(selected: 'slip', onSelected: (_) {}));
      debugPrint(
        tester.getSemantics(find.byKey(const ValueKey('b'))).toString(),
      );
      expect(
        tester.getSemantics(find.byKey(const ValueKey('b'))),
        matchesSemantics(
          label: 'Slipped',
          isButton: true,
          isSelected: true,
          isEnabled: true,
          hasEnabledState: true,
          hasSelectedState: true,
          isInMutuallyExclusiveGroup: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.byKey(const ValueKey('a'))),
        matchesSemantics(
          label: 'Done',
          isButton: true,
          isSelected: false,
          isEnabled: true,
          hasEnabledState: true,
          hasSelectedState: true,
          isInMutuallyExclusiveGroup: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('null callback disables it', (tester) async {
      await tester.pumpWidget(control(selected: 'done'));
      await tester.tap(find.text('Slipped'));
      await tester.pump(); // no exception, nothing to call
    });
  });

  group('buttons', () {
    testWidgets('primary: text-colour fill, background-colour label', (
      tester,
    ) async {
      for (final b in Brightness.values) {
        final c = CohabitColors.of(b);
        await tester.pumpWidget(
          host(
            CohabitButton.primary(
              key: const ValueKey('p'),
              label: 'Save',
              onPressed: () {},
            ),
            brightness: b,
          ),
        );
        expect(fillOf(tester, find.byKey(const ValueKey('p'))), c.text);
        expect(labelStyleOf(tester, 'Save')!.color, c.background);
      }
    });

    testWidgets('secondary: hairline border, no fill', (tester) async {
      final c = CohabitColors.dark;
      await tester.pumpWidget(
        host(
          CohabitButton.secondary(
            key: const ValueKey('s'),
            label: 'Cancel',
            onPressed: () {},
          ),
        ),
      );
      final box = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(const ValueKey('s')),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.color, Colors.transparent);
      expect((decoration.border! as Border).top.color, c.hairline);
      expect((decoration.border! as Border).top.width, 1);
      expect(decoration.borderRadius, isNull);
      expect(labelStyleOf(tester, 'Cancel')!.color, c.text);
    });

    testWidgets('ghost: muted label, no border', (tester) async {
      final c = CohabitColors.dark;
      await tester.pumpWidget(
        host(
          CohabitButton.ghost(
            key: const ValueKey('g'),
            label: 'Dismiss',
            onPressed: () {},
          ),
        ),
      );
      expect(labelStyleOf(tester, 'Dismiss')!.color, c.muted);
      expect(
        fillOf(tester, find.byKey(const ValueKey('g'))),
        Colors.transparent,
      );
    });

    testWidgets('heights: 30 with a pointer, at least 44 on touch', (
      tester,
    ) async {
      Widget button(TargetPlatform p) => host(
        CohabitButton.secondary(
          key: const ValueKey('s'),
          label: 'Go',
          onPressed: () {},
        ),
        platform: p,
      );
      await tester.pumpWidget(button(TargetPlatform.macOS));
      expect(tester.getSize(find.byKey(const ValueKey('s'))).height, 30);
      await tester.pumpWidget(button(TargetPlatform.android));
      expect(
        tester.getSize(find.byKey(const ValueKey('s'))).height,
        greaterThanOrEqualTo(44),
      );
    });

    testWidgets('tap and keyboard activate; disabled does nothing', (
      tester,
    ) async {
      var presses = 0;
      await tester.pumpWidget(
        host(
          CohabitButton.primary(
            label: 'Go',
            autofocus: true,
            onPressed: () => presses++,
          ),
        ),
      );
      await tester.tap(find.text('Go'));
      expect(presses, 1);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(presses, 2);

      await tester.pumpWidget(
        host(const CohabitButton.primary(label: 'Go', onPressed: null)),
      );
      await tester.tap(find.text('Go'));
      expect(presses, 2);
    });
  });

  group('CohabitTextField', () {
    testWidgets('hairline border, blue3 when focused, square', (tester) async {
      final c = CohabitColors.dark;
      await tester.pumpWidget(
        host(const CohabitTextField(label: 'Name', fieldKey: ValueKey('f'))),
      );
      final deco = tester
          .widget<TextField>(find.byKey(const ValueKey('f')))
          .decoration!;
      expect(
        (deco.enabledBorder! as OutlineInputBorder).borderSide.color,
        c.hairline,
      );
      expect(
        (deco.focusedBorder! as OutlineInputBorder).borderSide.color,
        c.blue3,
      );
      expect(
        (deco.enabledBorder! as OutlineInputBorder).borderRadius,
        BorderRadius.zero,
      );
      expect(find.text('NAME'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('f')));
      await tester.pump();
      final focused = tester.widget<InputDecorator>(
        find.byType(InputDecorator),
      );
      expect(focused.isFocused, isTrue);
    });

    testWidgets('passes text through', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      String? changed;
      await tester.pumpWidget(
        host(
          CohabitTextField(
            label: 'Name',
            controller: controller,
            onChanged: (v) => changed = v,
            fieldKey: const ValueKey('f'),
          ),
        ),
      );
      await tester.enterText(find.byKey(const ValueKey('f')), 'Read');
      expect(changed, 'Read');
      expect(controller.text, 'Read');
    });
  });

  group('HabitRow', () {
    Widget row(double width) => host(
      HabitRow(
        name: 'Doomscrolling',
        meta: 'Every day · avoid · Not logged',
        metaKey: const ValueKey('meta'),
        control: SegmentedLogControl<int>(
          key: const ValueKey('control'),
          selected: null,
          onSelected: (_) {},
          options: const [LogOption(value: 1, label: 'Slipped')],
        ),
      ),
      width: width,
    );

    testWidgets('surface with hairline border, name and mono meta line', (
      tester,
    ) async {
      final c = CohabitColors.dark;
      await tester.pumpWidget(row(700));
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(HabitRow),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final d = box.decoration as BoxDecoration;
      expect(d.color, c.surface);
      expect((d.border! as Border).top.color, c.hairline);
      expect(d.borderRadius, isNull);
      expect(d.boxShadow, isNull);
      expect(d.gradient, isNull);
      expect(
        tester.widget<Text>(find.text('Doomscrolling')).style!.fontFamily,
        'Inter',
      );
      final meta = tester.widget<Text>(find.byKey(const ValueKey('meta')));
      expect(meta.style!.fontFamily, 'JetBrainsMono');
    });

    testWidgets('control sits beside the name when wide, below when narrow', (
      tester,
    ) async {
      await tester.pumpWidget(row(700));
      final wideName = tester.getTopLeft(find.text('Doomscrolling'));
      final wideControl = tester.getTopLeft(
        find.byKey(const ValueKey('control')),
      );
      expect(wideControl.dx, greaterThan(wideName.dx + 100));

      await tester.pumpWidget(row(360));
      final narrowName = tester.getTopLeft(find.text('Doomscrolling'));
      final narrowControl = tester.getTopLeft(
        find.byKey(const ValueKey('control')),
      );
      expect(narrowControl.dy, greaterThan(narrowName.dy + 20));
      expect(narrowControl.dx, narrowName.dx);
    });
  });

  group('ReviewBanner', () {
    testWidgets('hairline above and below, Dismiss ghost, Review primary', (
      tester,
    ) async {
      final c = CohabitColors.dark;
      var reviewed = 0;
      var dismissed = 0;
      await tester.pumpWidget(
        host(
          ReviewBanner(
            title: 'Yesterday: 2 habits not logged',
            detail: 'Run, Read',
            onReview: () => reviewed++,
            onDismiss: () => dismissed++,
          ),
        ),
      );
      expect(find.byType(Hairline), findsNWidgets(2));
      expect(labelStyleOf(tester, 'Dismiss')!.color, c.muted);
      expect(labelStyleOf(tester, 'Review')!.color, c.background);

      await tester.tap(find.text('Review'));
      await tester.tap(find.text('Dismiss'));
      expect([reviewed, dismissed], [1, 1]);
    });

    testWidgets('stacks the actions under the message on a narrow screen', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          ReviewBanner(
            title: 'Yesterday: 2 habits not logged',
            detail: 'Run, Read',
            onReview: () {},
            onDismiss: () {},
          ),
          width: 340,
        ),
      );
      expect(
        tester.getTopLeft(find.text('Review')).dy,
        greaterThan(tester.getTopLeft(find.text('Run, Read')).dy),
      );
    });
  });

  group('InsightCard', () {
    testWidgets('2px blue3 rule on the left, sentence, mono stats', (
      tester,
    ) async {
      final c = CohabitColors.dark;
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          const InsightCard(
            sentence: 'Gym tends to follow good sleep.',
            stats: ['2.3x', 'n=84', 'CI 1.6-3.2'],
          ),
        ),
      );
      final deco =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: find.byType(InsightCard),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      final border = deco.border! as Border;
      expect(border.left.color, c.blue3);
      expect(border.left.width, 2);
      expect(border.top.width, 1);
      expect(deco.borderRadius, isNull);
      expect(deco.boxShadow, isNull);
      expect(
        tester
            .widget<Text>(find.text('Gym tends to follow good sleep.'))
            .style!
            .fontFamily,
        'Inter',
      );
      final stats = tester.widget<Text>(find.text('2.3x  n=84  CI 1.6-3.2'));
      expect(stats.style!.fontFamily, 'JetBrainsMono');
      expect(
        tester.getSemantics(find.byType(InsightCard)).label,
        'Gym tends to follow good sleep. 2.3x, n=84, CI 1.6-3.2',
      );
      handle.dispose();
    });

    testWidgets('renders in light mode too', (tester) async {
      await tester.pumpWidget(
        host(
          const InsightCard(sentence: 'A sentence.', stats: []),
          brightness: Brightness.light,
        ),
      );
      expect(find.text('A sentence.'), findsOneWidget);
    });
  });
}
