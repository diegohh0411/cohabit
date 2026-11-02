import 'dart:math' as math;

import 'package:cohabit/design/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _channel(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

/// WCAG 2.x contrast ratio.
double contrast(Color a, Color b) {
  final la = luminance(a);
  final lb = luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

String hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

void main() {
  test('contrast helper matches known WCAG values', () {
    expect(contrast(Colors.black, Colors.white), closeTo(21, 0.001));
    expect(contrast(Colors.white, Colors.white), closeTo(1, 0.001));
    // #767676 on white is the classic 4.54:1 AA threshold example.
    expect(
      contrast(const Color(0xFF767676), Colors.white),
      closeTo(4.54, 0.01),
    );
  });

  test(
    'palettes match the approved values, bar the two nudged light fills',
    () {
      const d = CohabitColors.dark;
      expect(
        [d.background, d.surface, d.hairline, d.text, d.muted, d.off].map(hex),
        ['#0B0E13', '#12161D', '#2A313C', '#E8ECF2', '#8C96A5', '#1B212B'],
      );
      expect([d.blue1, d.blue2, d.blue3, d.blue4, d.orange].map(hex), [
        '#16365C',
        '#1F5A96',
        '#3487D6',
        '#7CC0FF',
        '#F0883E',
      ]);
      const l = CohabitColors.light;
      expect(
        [l.background, l.surface, l.hairline, l.text, l.muted, l.off].map(hex),
        ['#F7F8FA', '#FFFFFF', '#D5DAE2', '#10151C', '#5D6776', '#E9ECF1'],
      );
      expect([l.blue1, l.blue2, l.blue4].map(hex), [
        '#C5DFF8',
        '#7DB6EC',
        '#0F4C8F',
      ]);
      // Approved #2F7FD1 / #C4560C gave 4.14:1 / 4.48:1 with white labels.
      expect(hex(l.blue3), '#2C78C7');
      expect(hex(l.orange), '#C3560C');
    },
  );

  for (final c in [CohabitColors.dark, CohabitColors.light]) {
    group('WCAG AA, ${c.brightness.name}', () {
      void text(String name, Color fg, Color bg) => test('$name text', () {
        expect(
          contrast(fg, bg),
          greaterThanOrEqualTo(4.5),
          reason: '$name = ${contrast(fg, bg).toStringAsFixed(2)}:1',
        );
      });

      void graphic(String name, Color fg, Color bg) =>
          test('$name graphic', () {
            expect(
              contrast(fg, bg),
              greaterThanOrEqualTo(3),
              reason: '$name = ${contrast(fg, bg).toStringAsFixed(2)}:1',
            );
          });

      // Body and label text.
      text('text on background', c.text, c.background);
      text('text on surface', c.text, c.surface);
      text('muted on background', c.muted, c.background);
      text('muted on surface', c.muted, c.surface);
      // Hover fills and the neutral selected segment.
      text('text on off', c.text, c.off);
      text('muted on off (ghost hover)', c.muted, c.off);
      text('text on hairline (selected neutral)', c.text, c.hairline);
      // Buttons.
      text('primary label (background on text fill)', c.background, c.text);
      text('selected Done/Clean label on blue3', c.onBlue3, c.blue3);
      text('selected Slipped label on orange', c.onOrange, c.orange);
      text('selected day toggle (background on text)', c.background, c.text);

      // Interactive and data shapes against the surfaces they sit on.
      graphic(
        'blue3 on surface (focus border, done cells)',
        c.blue3,
        c.surface,
      );
      graphic('blue3 on background', c.blue3, c.background);
      graphic('orange on surface (slipped cells)', c.orange, c.surface);
      graphic('orange on background', c.orange, c.background);
      graphic('blue4 on surface (focus ring)', c.blue4, c.surface);
      graphic('muted stripes on off (skipped hatch)', c.muted, c.off);
    });
  }

  test('documented exceptions: decorative fills are below 3:1 by design', () {
    // Hairlines, the off fill and the unknown outline are deliberately
    // quiet. They are never the only cue: each state also has a distinct
    // shape, a legend entry, hover or tap detail and a screen-reader label.
    for (final c in [CohabitColors.dark, CohabitColors.light]) {
      expect(contrast(c.hairline, c.surface), lessThan(3));
      expect(contrast(c.off, c.surface), lessThan(3));
    }
  });
}
