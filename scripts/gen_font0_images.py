#!/usr/bin/env python3
"""Render Font0 preview PNGs (sample, glyph sheet, display mockups).

Uses the same proportional advances as gen_font0_ttf.py (ink width + 1px).
Requires: components/M5GFX (npm run deps). Stdlib only.

Usage: python3 scripts/gen_font0_images.py
"""

from __future__ import annotations

import re
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GLCD = ROOT / "components" / "M5GFX" / "src" / "lgfx" / "Fonts" / "glcdfont.h"

# Display mockup palette
PLAY_BG = (24, 0, 98)
PLAY_FG = (238, 238, 255)
PLAY_DIM = (123, 129, 213)
DISC_BG = (82, 0, 164)
DISC_FG = PLAY_FG
DISC_DIM = PLAY_DIM

# Glyph sheet palette
SHEET_PAGE = (18, 18, 22)
SHEET_CELL = (28, 28, 36)
SHEET_INK = (235, 235, 240)
SHEET_LABEL = (200, 200, 210)
SHEET_AXIS = (110, 110, 120)


def load_bytes(path: Path) -> list[int]:
    src = path.read_text()
    m = re.search(r"static const unsigned char font\[\] PROGMEM = \{(.*?)\};", src, re.S)
    if not m:
        raise SystemExit(f"font array not found in {path}")
    nums = [int(x, 16) for x in re.findall(r"0x([0-9A-Fa-f]{2})", m.group(1))]
    if len(nums) % 5:
        raise SystemExit(f"unexpected font byte count: {len(nums)}")
    return nums


def ink_cols(nums: list[int], code: int) -> tuple[int, int] | None:
    base = code * 5
    left = right = None
    for col in range(5):
        if nums[base + col]:
            if left is None:
                left = col
            right = col
    if left is None:
        return None
    return left, right


def advance_px(nums: list[int], code: int, mono: bool = False) -> int:
    if mono:
        return 6
    bounds = ink_cols(nums, code)
    if bounds is None:
        return 6
    left, right = bounds
    return right - left + 2


def write_png(path: Path, width: int, height: int, rgb: list[tuple[int, int, int]]) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(
            ">I", zlib.crc32(tag + data) & 0xFFFFFFFF
        )

    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            raw.extend(rgb[y * width + x])
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def scale_nearest(
    rgb: list[tuple[int, int, int]], w: int, h: int, n: int
) -> tuple[list[tuple[int, int, int]], int, int]:
    out = []
    for y in range(h):
        for _dy in range(n):
            for x in range(w):
                c = rgb[y * w + x]
                for _dx in range(n):
                    out.append(c)
    return out, w * n, h * n


class Canvas:
    def __init__(self, w: int, h: int, bg: tuple[int, int, int]):
        self.w, self.h = w, h
        self.px = [bg] * (w * h)

    def fill(self, color: tuple[int, int, int]) -> None:
        self.px = [color] * (self.w * self.h)

    def put(self, x: int, y: int, color: tuple[int, int, int]) -> None:
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y * self.w + x] = color

    def blit_glyph(
        self,
        nums: list[int],
        code: int,
        x: int,
        y: int,
        color: tuple[int, int, int],
        *,
        mono: bool = False,
        scale: int = 1,
        cell_bg: tuple[int, int, int] | None = None,
    ) -> int:
        """Draw glyph. Returns advance in destination pixels."""
        fixed_cell = mono or cell_bg is not None
        if cell_bg is not None:
            for dy in range(8 * scale):
                for dx in range(6 * scale):
                    self.put(x + dx, y + dy, cell_bg)

        bounds = ink_cols(nums, code)
        if bounds is None:
            return 6 * scale if fixed_cell else advance_px(nums, code) * scale

        # Fixed cell / mono: keep bitmap column positions. Proportional: left-trim.
        shift = 0 if fixed_cell else bounds[0]
        base = code * 5
        for col in range(5):
            byte = nums[base + col]
            for row in range(8):
                if not (byte & (1 << row)):
                    continue
                gx = col - shift
                for dy in range(scale):
                    for dx in range(scale):
                        self.put(x + gx * scale + dx, y + row * scale + dy, color)
        return 6 * scale if fixed_cell else advance_px(nums, code) * scale

    def text(
        self,
        nums: list[int],
        s: str,
        x: int,
        y: int,
        color: tuple[int, int, int],
        *,
        mono: bool = False,
        scale: int = 1,
    ) -> int:
        cx = x
        for ch in s:
            cx += self.blit_glyph(nums, ord(ch) & 0xFF, cx, y, color, mono=mono, scale=scale)
        return cx - x

    def measure(self, nums: list[int], s: str, *, mono: bool = False, scale: int = 1) -> int:
        return sum(advance_px(nums, ord(ch) & 0xFF, mono=mono) * scale for ch in s)

    def save(self, path: Path) -> None:
        write_png(path, self.w, self.h, self.px)
        print(f"wrote {path} ({self.w}x{self.h})")

    def save_scaled(self, path: Path, n: int) -> None:
        rgb, w, h = scale_nearest(self.px, self.w, self.h, n)
        write_png(path, w, h, rgb)
        print(f"wrote {path} ({w}x{h})")


def gen_sample(nums: list[int]) -> None:
    lines = ["Alchemy", "0123", "ABC", "abc", "!@#$"]
    pad, line_h = 2, 9
    w = max(sum(advance_px(nums, ord(c)) for c in s) for s in lines) + pad * 2
    h = pad * 2 + line_h * len(lines) - 1
    c = Canvas(w, h, (0, 0, 0))
    y = pad
    for s in lines:
        c.text(nums, s, pad, y, (255, 255, 255))
        y += line_h
    c.save(ROOT / "font0_sample.png")


def gen_glyphs(nums: list[int]) -> None:
    scale, gap = 4, 4
    cw, ch = 6 * scale, 8 * scale
    pitch_x, pitch_y = cw + gap, ch + gap
    left, top = 56, 48
    w = left + 16 * pitch_x - gap + 4
    h = top + 16 * pitch_y - gap + 4
    c = Canvas(w, h, SHEET_PAGE)

    c.text(nums, "Font0 GLCD 5x7 / 6x8 256 glyphs", 4, 4, SHEET_LABEL, mono=True, scale=2)

    for col in range(16):
        label = f"{col:X}"
        x = left + col * pitch_x + (cw - c.measure(nums, label, mono=True, scale=2)) // 2
        c.text(nums, label, x, 20, SHEET_AXIS, mono=True, scale=2)
    for row in range(16):
        label = f"{row:X}0"
        c.text(nums, label, 4, top + row * pitch_y + (ch - 16) // 2, SHEET_AXIS, mono=True, scale=2)

    for code in range(256):
        row, col = divmod(code, 16)
        x = left + col * pitch_x
        y = top + row * pitch_y
        c.blit_glyph(nums, code, x, y, SHEET_INK, mono=True, scale=scale, cell_bg=SHEET_CELL)

    c.save(ROOT / "font0_glyphs.png")


def gen_play(nums: list[int]) -> None:
    c = Canvas(240, 135, PLAY_BG)
    pad = 4
    c.text(nums, "Alchemy", pad, 2, PLAY_FG)
    # right-ish counter
    counter = "12/220"
    cw = c.measure(nums, counter)
    c.text(nums, counter, 240 - pad - cw, 2, PLAY_FG)

    c.text(nums, "Fire + Water", pad, 14, PLAY_FG)

    items = ["Air", "Earth", "Energy", "Lava", "Steam", "Pressure", "Cloud", "Rain"]
    selected = 0
    y = 28
    for i, name in enumerate(items):
        if i == selected:
            c.text(nums, ">", pad, y, PLAY_FG)
            c.text(nums, name, 16, y, PLAY_FG)
        else:
            c.text(nums, name, 16, y, PLAY_DIM)
        y += 12

    c.text(nums, "ent pick  ^v move", pad, 125, PLAY_DIM)
    res = "240x135"
    c.text(nums, res, 240 - pad - c.measure(nums, res), 125, PLAY_DIM)

    path = ROOT / "font0_display_240x135.png"
    c.save(path)
    c.save_scaled(ROOT / "font0_display_240x135@3x.png", 3)


def gen_discover(nums: list[int]) -> None:
    c = Canvas(240, 135, DISC_BG)
    word = "Steam"
    scale = 2
    tw = c.measure(nums, word, scale=scale)
    th = 8 * scale
    c.text(nums, word, (240 - tw) // 2, (135 - th) // 2 - 2, DISC_FG, scale=scale)
    res = "240x135"
    c.text(nums, res, 240 - 4 - c.measure(nums, res), 125, DISC_DIM)
    c.save(ROOT / "font0_display_discover_240x135.png")
    c.save_scaled(ROOT / "font0_display_discover_240x135@3x.png", 3)


def main() -> None:
    if not GLCD.is_file():
        raise SystemExit(f"missing {GLCD} — run: npm run deps")
    nums = load_bytes(GLCD)
    gen_sample(nums)
    gen_glyphs(nums)
    gen_play(nums)
    gen_discover(nums)


if __name__ == "__main__":
    main()
