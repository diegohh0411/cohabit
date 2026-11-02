#!/usr/bin/env python3
"""Generates the launcher icon from one grid definition.

A 3x3 commit-graph motif on the dark background: blue for done, one orange
cell for a slip, one quiet cell for nothing logged. Writes

  - the adaptive foreground and monochrome vector drawables (API 26+), and
  - legacy square PNGs for every density (API 24 and 25).

Run from the repository root; needs only the standard library:

    python3 tool/generate_launcher_icons.py
"""
import struct
import zlib
from pathlib import Path

RES = Path('android/app/src/main/res')
BG = (0x0B, 0x0E, 0x13)
OFF = (0x2A, 0x31, 0x3C)
B2, B3, B4 = (0x1F, 0x5A, 0x96), (0x34, 0x87, 0xD6), (0x7C, 0xC0, 0xFF)
ORANGE = (0xF0, 0x88, 0x3E)
GRID = [
    [B2, B3, B4],
    [B3, B4, B3],
    [OFF, B3, ORANGE],
]
ALPHA = {OFF: 0.35, B2: 0.6, B3: 0.8, B4: 1.0, ORANGE: 1.0}

# Adaptive layers are 108dp with a 66dp safe circle: the grid's corners
# (half-diagonal ~33dp) stay inside it.
CELL, GAP, CANVAS = 13, 4, 108


def hexcolor(c, alpha=1.0):
    a = round(alpha * 255)
    return '#%02X%02X%02X%02X' % ((a,) + tuple(c)) if alpha < 1 else '#%02X%02X%02X' % tuple(c)


def cells(size, cell, gap):
    total = 3 * cell + 2 * gap
    origin = (size - total) / 2
    for r in range(3):
        for c in range(3):
            x = origin + c * (cell + gap)
            y = origin + r * (cell + gap)
            yield x, y, cell, GRID[r][c]


def vector(path, mono):
    out = ['<?xml version="1.0" encoding="utf-8"?>',
           '<vector xmlns:android="http://schemas.android.com/apk/res/android"',
           f'    android:width="{CANVAS}dp" android:height="{CANVAS}dp"',
           f'    android:viewportWidth="{CANVAS}" android:viewportHeight="{CANVAS}">']
    for x, y, s, col in cells(CANVAS, CELL, GAP):
        fill = hexcolor((0, 0, 0), ALPHA[col]) if mono else hexcolor(col)
        out.append(f'    <path android:fillColor="{fill}" android:pathData='
                   f'"M{x:g},{y:g}h{s}v{s}h-{s}z" />')
    out.append('</vector>')
    path.write_text('\n'.join(out) + '\n')


def png(path, size):
    # Legacy icon: the grid fills about half the square.
    cell = size * 0.5 / 3.6
    gap = cell * 0.3
    rects = list(cells(size, cell, gap))
    rows = bytearray()
    for py in range(size):
        rows.append(0)
        for px in range(size):
            rgb = list(BG)
            for x, y, s, col in rects:
                w = max(0.0, min(px + 1, x + s) - max(px, x))
                h = max(0.0, min(py + 1, y + s) - max(py, y))
                cov = w * h
                if cov:
                    for i in range(3):
                        rgb[i] += (col[i] - rgb[i]) * cov
            rows.extend(round(v) for v in rgb)

    def chunk(tag, data):
        body = tag + data
        return struct.pack('>I', len(data)) + body + struct.pack('>I', zlib.crc32(body))

    path.write_bytes(
        b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(bytes(rows), 9))
        + chunk(b'IEND', b''))


def main():
    vector(RES / 'drawable/ic_launcher_foreground.xml', mono=False)
    vector(RES / 'drawable/ic_launcher_monochrome.xml', mono=True)
    for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                          ('xxhdpi', 144), ('xxxhdpi', 192)]:
        png(RES / f'mipmap-{density}/ic_launcher.png', size)


if __name__ == '__main__':
    main()
