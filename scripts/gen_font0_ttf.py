#!/usr/bin/env python3
"""Build Cardputer Font0 desktop/web fonts from M5GFX glcdfont.h (fonts::Font0).

Outputs in fonts/:
  CardputerFont0.ttf   — TrueType (Figma / OS install; recommended default)
  CardputerFont0.otf   — CFF OpenType
  CardputerFont0.woff  — web
  CardputerFont0.woff2 — web (preferred for sites)

Requires: pip install fonttools brotli
Usage:    python3 scripts/gen_font0_ttf.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.t2CharStringPen import T2CharStringPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
GLCD = ROOT / "components" / "M5GFX" / "src" / "lgfx" / "Fonts" / "glcdfont.h"
OUT_DIR = ROOT / "fonts"
STEM = "CardputerFont0"

PIXEL = 100  # font units per bitmap pixel
CELL_W, CELL_H = 6, 8
UPM = CELL_H * PIXEL  # font-size 8 in Figma ≈ 1 Cardputer pixel per font pixel
ADVANCE = CELL_W * PIXEL
BASELINE_FROM_TOP = 7  # LovyanGFX Font0 baseline

NAME_TABLE = {
    "familyName": "Cardputer Font0",
    "styleName": "Regular",
    "uniqueFontIdentifier": "Cardputer Font0 Regular:Adafruit GLCD",
    "fullName": "Cardputer Font0 Regular",
    "psName": "CardputerFont0-Regular",
    "version": "Version 1.001",
    "description": (
        "Pixel font matching M5GFX/LovyanGFX fonts::Font0 bitmaps "
        "(Adafruit GLCD 5x7). Advances are proportional (ink width + 1px) "
        "so narrow glyphs like i/l are not padded to the 6px mono cell. "
        "For Cardputer ADV UI mockups."
    ),
    "manufacturer": "cardputer-alchemy (from Adafruit Industries bitmap)",
    "designer": "Adafruit Industries (bitmap); Cardputer Font0 packaging",
    "licenseDescription": "BSD License (Adafruit Industries). See fonts/LICENSE-Font0.txt",
}


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
    """Return inclusive [left, right] columns with ink, or None if empty."""
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


def glyph_advance(nums: list[int], code: int) -> int:
    """Ink width + 1px gap. Empty glyphs keep the classic 6px mono cell."""
    bounds = ink_cols(nums, code)
    if bounds is None:
        return ADVANCE
    left, right = bounds
    return (right - left + 1 + 1) * PIXEL


def draw_code(pen, nums: list[int], code: int) -> None:
    """Draw glyph left-trimmed so ink starts at x=0 (no empty left bearing)."""
    base = code * 5
    bounds = ink_cols(nums, code)
    shift = 0 if bounds is None else bounds[0]
    for col in range(5):
        byte = nums[base + col]
        for row in range(8):
            if not (byte & (1 << row)):
                continue
            x0 = (col - shift) * PIXEL
            y0 = (BASELINE_FROM_TOP - row - 1) * PIXEL
            pen.moveTo((x0, y0))
            pen.lineTo((x0 + PIXEL, y0))
            pen.lineTo((x0 + PIXEL, y0 + PIXEL))
            pen.lineTo((x0, y0 + PIXEL))
            pen.closePath()


def setup_common(fb: FontBuilder, glyph_order: list[str], advance: dict[str, int],
                 ascender: int, descender: int) -> None:
    nglyphs = len(glyph_order) - 1  # exclude .notdef
    fb.setupGlyphOrder(glyph_order)
    fb.setupCharacterMap({code: f"uni{code:04X}" for code in range(nglyphs)})
    fb.setupHorizontalMetrics({n: (advance[n], 0) for n in glyph_order})
    fb.setupHorizontalHeader(ascent=ascender, descent=descender)
    fb.setupOS2(
        sTypoAscender=ascender,
        sTypoDescender=descender,
        sTypoLineGap=0,
        usWinAscent=ascender,
        usWinDescent=abs(descender),
        achVendID="CPTR",
    )
    fb.setupPost()
    fb.setupNameTable(NAME_TABLE)
    fb.setupHead(unitsPerEm=UPM)


def build_ttf(nums: list[int], glyph_order: list[str], advance: dict[str, int],
              ascender: int, descender: int, path: Path) -> None:
    glyphs = {".notdef": TTGlyphPen(None).glyph()}
    for code in range(len(nums) // 5):
        pen = TTGlyphPen(None)
        draw_code(pen, nums, code)
        glyphs[f"uni{code:04X}"] = pen.glyph()

    fb = FontBuilder(UPM, isTTF=True)
    setup_common(fb, glyph_order, advance, ascender, descender)
    fb.setupGlyf(glyphs)
    fb.save(path)


def build_otf(nums: list[int], glyph_order: list[str], advance: dict[str, int],
              ascender: int, descender: int, path: Path) -> None:
    charstrings = {}
    pen = T2CharStringPen(advance[".notdef"], None)
    charstrings[".notdef"] = pen.getCharString()
    for code in range(len(nums) // 5):
        name = f"uni{code:04X}"
        pen = T2CharStringPen(advance[name], None)
        draw_code(pen, nums, code)
        charstrings[name] = pen.getCharString()

    fb = FontBuilder(UPM, isTTF=False)
    setup_common(fb, glyph_order, advance, ascender, descender)
    fb.setupCFF(
        NAME_TABLE["psName"],
        {"FullName": NAME_TABLE["fullName"], "FamilyName": NAME_TABLE["familyName"]},
        charstrings,
        {},
    )
    fb.save(path)


def write_flavors(ttf_path: Path, out_dir: Path) -> list[Path]:
    written = []
    for flavor, ext in (("woff", ".woff"), ("woff2", ".woff2")):
        font = TTFont(ttf_path)
        font.flavor = flavor
        dest = out_dir / f"{STEM}{ext}"
        font.save(dest)
        font.close()
        written.append(dest)
    return written


def main() -> None:
    if not GLCD.is_file():
        raise SystemExit(f"missing {GLCD} — run: npm run deps")

    nums = load_bytes(GLCD)
    nglyphs = len(nums) // 5
    glyph_order = [".notdef"] + [f"uni{code:04X}" for code in range(nglyphs)]
    advance = {".notdef": ADVANCE}
    advance.update({f"uni{code:04X}": glyph_advance(nums, code) for code in range(nglyphs)})
    ascender = BASELINE_FROM_TOP * PIXEL
    descender = -(CELL_H - BASELINE_FROM_TOP) * PIXEL

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    ttf_path = OUT_DIR / f"{STEM}.ttf"
    otf_path = OUT_DIR / f"{STEM}.otf"

    build_ttf(nums, glyph_order, advance, ascender, descender, ttf_path)
    build_otf(nums, glyph_order, advance, ascender, descender, otf_path)
    web = write_flavors(ttf_path, OUT_DIR)

    for path in (ttf_path, otf_path, *web):
        print(f"wrote {path} ({path.stat().st_size} bytes)")
    narrow = sum(1 for code in range(nglyphs) if advance[f"uni{code:04X}"] < ADVANCE)
    print(
        f"{nglyphs} glyphs ({narrow} narrower than 6px). "
        "Figma/desktop: prefer .ttf (size 8 = 1:1). Web: prefer .woff2."
    )


if __name__ == "__main__":
    main()
