"""Editable native front-end art and original bitmap type for Task 002C.6.

Normal invocation exports the saved Aseprite masters. --author is the explicit
reconstruction operation; --check only reads production files and compares them
with the saved source and actual Aseprite CLI exports. No system font is used.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from build_power_art import read_ase, write_ase
sys.path.insert(0, str(ROOT / "tools/workspace"))
from workspace import create_task_workspace, find_tool

SOURCE = ROOT / "assets/source-art/ui"
OUT = ROOT / "assets/ui"
PALETTE = {
    "ink": "#10151f", "back wall": "#141e27", "bench": "#192832",
    "rubber": "#202b36", "seam": "#2c3d47", "steel": "#4c626e",
    "silver": "#abc0c7", "paper": "#e3e8dc", "oxide": "#a94c35",
    "amber": "#df8740", "brass": "#f3c36a", "font mask": "#ffffff",
}


def c(name: str):
    return tuple(bytes.fromhex(PALETTE.get(name, name).lstrip("#"))) + (255,)


def blank(size):
    return Image.new("RGBA", size)


# Explicit pixel rows, drawn for this project. Five columns retain an open
# counter at native scale. Lowercase has its own x-height and descenders.
PATTERNS = {
    "A": "01110/10001/10001/11111/10001/10001/10001",
    "B": "11110/10001/10001/11110/10001/10001/11110",
    "C": "01111/10000/10000/10000/10000/10000/01111",
    "D": "11110/10001/10001/10001/10001/10001/11110",
    "E": "11111/10000/10000/11110/10000/10000/11111",
    "F": "11111/10000/10000/11110/10000/10000/10000",
    "G": "01111/10000/10000/10111/10001/10001/01110",
    "H": "10001/10001/10001/11111/10001/10001/10001",
    "I": "01110/00100/00100/00100/00100/00100/01110",
    "J": "00111/00010/00010/00010/00010/10010/01100",
    "K": "10001/10010/10100/11000/10100/10010/10001",
    "L": "10000/10000/10000/10000/10000/10000/11111",
    "M": "10001/11011/10101/10101/10001/10001/10001",
    "N": "10001/11001/11001/10101/10011/10011/10001",
    "O": "01110/10001/10001/10001/10001/10001/01110",
    "P": "11110/10001/10001/11110/10000/10000/10000",
    "Q": "01110/10001/10001/10001/10101/10010/01101",
    "R": "11110/10001/10001/11110/10100/10010/10001",
    "S": "01111/10000/10000/01110/00001/00001/11110",
    "T": "11111/00100/00100/00100/00100/00100/00100",
    "U": "10001/10001/10001/10001/10001/10001/01110",
    "V": "10001/10001/10001/10001/10001/01010/00100",
    "W": "10001/10001/10001/10101/10101/11011/10001",
    "X": "10001/10001/01010/00100/01010/10001/10001",
    "Y": "10001/10001/01010/00100/00100/00100/00100",
    "Z": "11111/00001/00010/00100/01000/10000/11111",
    "0": "01110/10001/10011/10101/11001/10001/01110",
    "1": "00100/01100/00100/00100/00100/00100/01110",
    "2": "01110/10001/00001/00010/00100/01000/11111",
    "3": "11110/00001/00001/01110/00001/00001/11110",
    "4": "00010/00110/01010/10010/11111/00010/00010",
    "5": "11111/10000/10000/11110/00001/00001/11110",
    "6": "01110/10000/10000/11110/10001/10001/01110",
    "7": "11111/00001/00010/00100/01000/01000/01000",
    "8": "01110/10001/10001/01110/10001/10001/01110",
    "9": "01110/10001/10001/01111/00001/00001/01110",
    "a": "00000/00000/01110/00001/01111/10001/01111",
    "b": "10000/10000/10110/11001/10001/10001/11110",
    "c": "00000/00000/01111/10000/10000/10000/01111",
    "d": "00001/00001/01101/10011/10001/10001/01111",
    "e": "00000/00000/01110/10001/11111/10000/01111",
    "f": "00110/01001/01000/11100/01000/01000/01000",
    "g": "00000/00000/01111/10001/10001/01111/00001/10001/01110",
    "h": "10000/10000/10110/11001/10001/10001/10001",
    "i": "00100/00000/01100/00100/00100/00100/01110",
    "j": "00010/00000/00110/00010/00010/00010/00010/10010/01100",
    "k": "10000/10000/10001/10010/11100/10010/10001",
    "l": "01100/00100/00100/00100/00100/00100/01110",
    "m": "00000/00000/11010/10101/10101/10101/10101",
    "n": "00000/00000/10110/11001/10001/10001/10001",
    "o": "00000/00000/01110/10001/10001/10001/01110",
    "p": "00000/00000/11110/10001/10001/11110/10000/10000/10000",
    "q": "00000/00000/01111/10001/10001/01111/00001/00001/00001",
    "r": "00000/00000/10111/11000/10000/10000/10000",
    "s": "00000/00000/01111/10000/01110/00001/11110",
    "t": "01000/01000/11110/01000/01000/01001/00110",
    "u": "00000/00000/10001/10001/10001/10011/01101",
    "v": "00000/00000/10001/10001/10001/01010/00100",
    "w": "00000/00000/10001/10001/10101/10101/01010",
    "x": "00000/00000/10001/01010/00100/01010/10001",
    "y": "00000/00000/10001/10001/10001/01111/00001/10001/01110",
    "z": "00000/00000/11111/00010/00100/01000/11111",
    " ": "00000/00000/00000/00000/00000/00000/00000",
    "!": "00100/00100/00100/00100/00100/00000/00100",
    '"': "01010/01010/01010/00000/00000/00000/00000",
    "#": "01010/01010/11111/01010/11111/01010/01010",
    "$": "00100/01111/10100/01110/00101/11110/00100",
    "%": "11001/11010/00010/00100/01000/01011/10011",
    "&": "01100/10010/10100/01000/10101/10010/01101",
    "'": "00100/00100/01000/00000/00000/00000/00000",
    "(": "00010/00100/01000/01000/01000/00100/00010",
    ")": "01000/00100/00010/00010/00010/00100/01000",
    "*": "00000/10101/01110/11111/01110/10101/00000",
    "+": "00000/00100/00100/11111/00100/00100/00000",
    ",": "00000/00000/00000/00000/00000/00110/00110/00100/01000",
    "-": "00000/00000/00000/11111/00000/00000/00000",
    ".": "00000/00000/00000/00000/00000/00110/00110",
    "/": "00001/00010/00010/00100/01000/01000/10000",
    ":": "00000/00110/00110/00000/00110/00110/00000",
    ";": "00000/00110/00110/00000/00110/00110/00100/01000/00000",
    "<": "00001/00010/00100/01000/00100/00010/00001",
    "=": "00000/00000/11111/00000/11111/00000/00000",
    ">": "10000/01000/00100/00010/00100/01000/10000",
    "?": "01110/10001/00001/00010/00100/00000/00100",
    "@": "01110/10001/10111/10101/10111/10000/01111",
    "[": "01110/01000/01000/01000/01000/01000/01110",
    "\\": "10000/01000/01000/00100/00010/00010/00001",
    "]": "01110/00010/00010/00010/00010/00010/01110",
    "^": "00100/01010/10001/00000/00000/00000/00000",
    "_": "00000/00000/00000/00000/00000/00000/00000/11111",
    "`": "01000/00100/00010/00000/00000/00000/00000",
    "{": "00011/00100/00100/01000/00100/00100/00011",
    "|": "00100/00100/00100/00100/00100/00100/00100",
    "}": "11000/00100/00100/00010/00100/00100/11000",
    "~": "00000/00000/01001/10110/00000/00000/00000",
    "\u00a0": "00000/00000/00000/00000/00000/00000/00000",
    "\u00b0": "01100/10010/10010/01100/00000/00000/00000",
    "\u00b1": "00100/00100/11111/00100/00100/00000/11111",
    "\u00d7": "00000/10001/01010/00100/01010/10001/00000",
    "\u2013": "00000/00000/00000/01110/00000/00000/00000",
    "\u2014": "00000/00000/00000/11111/00000/00000/00000",
    "\u2018": "00010/00100/00100/00000/00000/00000/00000",
    "\u2019": "00100/00100/01000/00000/00000/00000/00000",
    "\u201c": "01010/10100/10100/00000/00000/00000/00000",
    "\u201d": "01010/01010/10100/00000/00000/00000/00000",
    "\u2022": "00000/00000/00100/01110/00100/00000/00000",
    "\u2026": "00000/00000/00000/00000/00000/00000/10101",
    "\u2190": "00000/00100/01000/11111/01000/00100/00000",
    "\u2191": "00100/01110/10101/00100/00100/00100/00000",
    "\u2192": "00000/00100/00010/11111/00010/00100/00000",
    "\u2193": "00000/00100/00100/00100/10101/01110/00100",
    "\u2160": "00100/00100/00100/00100/00100/00100/00100",
    "\u2161": "01010/01010/01010/01010/01010/01010/01010",
    "\u2162": "10101/10101/10101/10101/10101/10101/10101",
}
CODEPOINTS = list(range(32, 127)) + sorted(ord(ch) for ch in PATTERNS if ord(ch) > 126)


def draw_pattern(image, pattern, x=0, y=1, ink=(255, 255, 255, 255)):
    pixels = image.load()
    for row, bits in enumerate(pattern.split("/")):
        for column, bit in enumerate(bits):
            if bit == "1":
                pixels[x + column, y + row] = ink


def font_master():
    frames = []
    for code in CODEPOINTS:
        layer = blank((6, 10))
        draw_pattern(layer, PATTERNS[chr(code)])
        frames.append([layer])
    tags = [(f"U{code:04X}", i, i) for i, code in enumerate(CODEPOINTS)]
    return frames, ["original 5-column glyph mask"], tags, [100] * len(frames), (0, 8)


def bolt(d, x, y):
    d.rectangle((x - 2, y - 2, x + 2, y + 2), fill=c("ink"))
    d.rectangle((x - 1, y - 1, x + 1, y + 1), fill=c("steel"))
    d.line((x - 1, y, x + 1, y), fill=c("silver"))


def stepped_oval(cx, cy, rx, ry):
    return [(cx - rx, cy - ry // 3), (cx - rx * 3 // 4, cy - ry),
            (cx + rx * 3 // 4, cy - ry), (cx + rx, cy - ry // 3),
            (cx + rx, cy + ry // 3), (cx + rx * 3 // 4, cy + ry),
            (cx - rx * 3 // 4, cy + ry), (cx - rx, cy + ry // 3)]


def service_station(image, cx, cy, rx):
    """An empty rubber/steel top service tray: the live assembled top goes above."""
    d = ImageDraw.Draw(image)
    d.polygon(stepped_oval(cx + 2, cy + 14, rx + 10, 18), fill=c("ink"))
    d.polygon(stepped_oval(cx, cy + 6, rx, 16), fill=c("seam"))
    d.line([(cx - rx, cy + 1), (cx - rx * 3 // 4, cy + 13),
            (cx + rx * 3 // 4, cy + 13), (cx + rx, cy + 1)], fill=c("steel"), width=2)
    d.polygon(stepped_oval(cx, cy, rx, 16), fill=c("ink"))
    d.polygon(stepped_oval(cx, cy - 1, rx - 4, 13), fill=c("steel"))
    d.polygon(stepped_oval(cx, cy - 2, rx - 7, 11), fill=c("rubber"))
    d.line([(cx - rx + 9, cy - 8), (cx - rx * 3 // 4, cy - 12),
            (cx + rx * 3 // 4, cy - 12)], fill=c("silver"))
    # Lipped front and four load-bearing fasteners, all tied to the bench.
    d.rectangle((cx - 21, cy + 12, cx + 21, cy + 16), fill=c("ink"))
    d.line((cx - 15, cy + 14, cx + 15, cy + 14), fill=c("oxide"))
    for dx, dy in [(-rx + 9, -2), (rx - 9, -2), (-rx + 15, 6), (rx - 15, 6)]:
        bolt(d, cx + dx, cy + dy)
    # Short, deliberately placed chips; no random noisy texture.
    d.line((cx - rx + 15, cy + 11, cx - rx + 21, cy + 12), fill=c("amber"))
    d.line((cx + rx - 21, cy + 11, cx + rx - 17, cy + 10), fill=c("oxide"))


def _historical_background_master():
    frames = []
    for mode in ["title", "hub"]:
        plate, station, wear = [blank((640, 360)) for _ in range(3)]
        d = ImageDraw.Draw(plate)
        d.rectangle((0, 0, 639, 359), fill=c("ink"))
        d.rectangle((8, 34, 631, 319), fill=c("back wall"))
        d.rectangle((8, 252, 631, 319), fill=c("bench"))
        d.line((8, 251, 631, 251), fill=c("seam"))
        d.rectangle((8, 309, 631, 319), fill=c("rubber"))
        d.line((8, 309, 631, 309), fill=c("steel"))
        # Header and footer remain flat, giving the shared chrome clean space.
        d.line((12, 31, 627, 31), fill=c("seam"))
        d.line((12, 321, 627, 321), fill=c("seam"))
        d.line((12, 33, 72, 33), fill=c("oxide"))
        d.line((568, 319, 627, 319), fill=c("oxide"))
        if mode == "title":
            # A broad work bay on the right; the wordmark owns the quiet left.
            d.rectangle((385, 62, 612, 284), fill=c("bench"))
            d.line([(385, 284), (385, 62), (612, 62)], fill=c("seam"))
            d.line((612, 63, 612, 284), fill=c("ink"))
            d.rectangle((403, 80, 594, 254), fill=c("rubber"))
            for x, y in [(395, 72), (601, 72), (395, 272), (601, 272)]:
                bolt(d, x, y)
            service_station(station, 450, 226, 64)
            # Small mat corners orient the hero without an enclosing UI halo.
            w = ImageDraw.Draw(wear)
            for points in [[(402, 90), (402, 81), (415, 81)],
                           [(594, 90), (594, 81), (582, 81)],
                           [(402, 245), (402, 254), (415, 254)],
                           [(594, 245), (594, 254), (582, 254)]]:
                w.line(points, fill=c("oxide"), width=2)
        else:
            # The right is intentionally quiet under panels at x254..624.
            d.rectangle((27, 67, 232, 298), fill=c("bench"))
            d.rectangle((31, 72, 228, 290), fill=c("rubber"))
            d.line([(31, 290), (31, 72), (228, 72)], fill=c("seam"))
            for x, y in [(40, 81), (220, 81), (40, 281), (220, 281)]:
                bolt(d, x, y)
            service_station(station, 130, 198, 61)
            w = ImageDraw.Draw(wear)
            w.line([(47, 113), (47, 98), (61, 98)], fill=c("oxide"), width=2)
            w.line([(199, 98), (214, 98), (214, 113)], fill=c("oxide"), width=2)
            # Faint real bench scratches beside, never behind, the top station.
            w.line((63, 233, 80, 233), fill=c("seam"))
            w.line((61, 235, 68, 235), fill=c("seam"))
            w.line((184, 218, 200, 217), fill=c("seam"))
        ImageDraw.Draw(wear).line((18, 307, 29, 307), fill=c("oxide"))
        ImageDraw.Draw(wear).line((609, 305, 618, 305), fill=c("seam"))
        frames.append([plate, station, wear])
    return frames, ["quiet steel workbench", "physical rubber service station", "placed paint wear"], \
        [("title", 0, 0), ("hub", 1, 1), ("workshop", 1, 1)], [1000, 1000], (0, 0)


def background_master():
    """Quiet shared chrome; display fixtures are explicit screen-local assets.

    The old bay/pedestal and horizontal bench boundary were baked into frame1
    used by every menu, exposing partial boxes and slicing starter text.
    """
    frames = []
    for _ in range(2):
        plate, fixtures, wear = [blank((640, 360)) for _ in range(3)]
        d = ImageDraw.Draw(plate)
        d.rectangle((0, 0, 639, 359), fill=c("ink"))
        d.rectangle((8, 34, 631, 339), fill=c("back wall"))
        d.line((12, 31, 627, 31), fill=c("seam"))
        d.line((12, 33, 72, 33), fill=c("oxide"))
        frames.append([plate, fixtures, wear])
    return frames, ["quiet shared steel", "screen-local fixtures deliberately separate", "no leaked shared corner wear"], \
        [("title", 0, 0), ("hub", 1, 1), ("workshop", 1, 1)], [1000, 1000], (0, 0)


GLYPH_NAMES = ["key_enter", "key_escape", "pad_south", "pad_east", "dpad",
               "pad_back", "pad_start", "pad_cross", "pad_circle"]


def mini_text(im, text, x, y):
    small = {"E": ["111", "100", "110", "100", "111"],
             "S": ["111", "100", "111", "001", "111"],
             "C": ["111", "100", "100", "100", "111"]}
    for i, ch in enumerate(text):
        draw_pattern(im, "/".join(small[ch]), x + i * 4, y)


def glyph_master():
    frames = []
    for name in GLYPH_NAMES:
        key, symbol = [blank((16, 16)) for _ in range(2)]
        d = ImageDraw.Draw(key)
        s = ImageDraw.Draw(symbol)
        if name.startswith("key_"):
            d.polygon([(2, 2), (13, 2), (14, 3), (14, 12), (12, 14), (2, 14), (1, 13), (1, 3)], fill=c("ink"))
            d.line([(2, 2), (13, 2), (14, 3), (14, 12), (12, 14), (2, 14), (1, 13), (1, 3), (2, 2)], fill=c("silver"))
            d.line((3, 13, 11, 13), fill=c("steel"))
            if name == "key_enter":
                s.line([(11, 5), (11, 9), (5, 9)], fill=c("paper"))
                s.line([(7, 7), (5, 9), (7, 11)], fill=c("paper"))
            else:
                mini_text(symbol, "ESC", 3, 5)
        elif name == "dpad":
            points = [(5, 1), (10, 1), (10, 5), (14, 5), (14, 10),
                      (10, 10), (10, 14), (5, 14), (5, 10), (1, 10), (1, 5), (5, 5)]
            d.polygon(points, fill=c("ink"))
            d.line(points + [points[0]], fill=c("silver"))
            for triangle in [[(7, 3), (6, 4), (8, 4)], [(7, 12), (6, 11), (8, 11)],
                             [(3, 7), (4, 6), (4, 8)], [(12, 7), (11, 6), (11, 8)]]:
                s.polygon(triangle, fill=c("paper"))
        elif name in ("pad_back", "pad_start"):
            d.polygon([(3, 3), (12, 3), (14, 5), (14, 10), (12, 12), (3, 12), (1, 10), (1, 5)], fill=c("ink"))
            d.line([(3, 3), (12, 3), (14, 5), (14, 10), (12, 12), (3, 12), (1, 10), (1, 5), (3, 3)], fill=c("silver"))
            if name == "pad_back":
                s.rectangle((4, 5, 8, 8), outline=c("paper"))
                s.rectangle((7, 7, 11, 10), outline=c("paper"))
            else:
                for y in (5, 7, 9):
                    s.line((5, y, 10, y), fill=c("paper"))
        else:
            d.polygon([(5, 1), (10, 1), (14, 5), (14, 10), (10, 14), (5, 14), (1, 10), (1, 5)], fill=c("ink"))
            d.line([(5, 1), (10, 1), (14, 5), (14, 10), (10, 14), (5, 14), (1, 10), (1, 5), (5, 1)], fill=c("silver"))
            if name == "pad_south":
                draw_pattern(symbol, "010/101/111/101/101", 6, 5, c("paper"))
            elif name == "pad_east":
                draw_pattern(symbol, "110/101/110/101/110", 6, 5, c("paper"))
            elif name == "pad_cross":
                s.line((5, 5, 10, 10), fill=c("paper"))
                s.line((10, 5, 5, 10), fill=c("paper"))
            elif name == "pad_circle":
                s.line([(6, 4), (9, 4), (11, 6), (11, 9), (9, 11), (6, 11), (4, 9), (4, 6), (6, 4)], fill=c("paper"))
        frames.append([key, symbol])
    tags = [(name, i, i) for i, name in enumerate(GLYPH_NAMES)] + [("pad_bottom", 2, 2)]
    return frames, ["key or controller bezel", "native input symbol"], tags, [100] * len(frames), (8, 8)


SPECS = {
    "foundry_small": {"columns": 16, "factory": font_master, "cell": [6, 10]},
    "frontend_background": {"columns": 2, "factory": background_master, "cell": [640, 360]},
    "input_glyphs": {"columns": 9, "factory": glyph_master, "cell": [16, 16]},
}


def render_source(name):
    frames, meta = read_ase(SOURCE / f"{name}.aseprite")
    w, h = meta["cell"]
    columns = SPECS[name]["columns"]
    atlas = blank((w * columns, h * math.ceil(len(frames) / columns)))
    for i, frame in enumerate(frames):
        atlas.alpha_composite(frame, ((i % columns) * w, (i // columns) * h))
    meta.update({"version": 1, "texture": f"{name}.png", "columns": columns,
                 "frame_count": len(frames), "source": f"../source-art/ui/{name}.aseprite",
                 "native_pixels": True, "filter": "nearest", "task": "002C.6"})
    if name == "foundry_small":
        meta.update({"font_size": 10, "advance": 6, "line_height": 10,
                     "baseline": 8, "codepoints": CODEPOINTS,
                     "licence": "Original project-authored bitmap glyphs; repository licence."})
    return frames, atlas, meta


def bmfont(meta):
    w, h = meta["cell"]
    columns = meta["columns"]
    lines = ['info face="Foundry Small" size=10 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=0,0',
             f'common lineHeight=10 base=8 scaleW={w * columns} scaleH={h * math.ceil(len(CODEPOINTS) / columns)} pages=1 packed=0 alphaChnl=0 redChnl=4 greenChnl=4 blueChnl=4',
             'page id=0 file="foundry_small.png"', f"chars count={len(CODEPOINTS)}"]
    for i, code in enumerate(CODEPOINTS):
        lines.append(f"char id={code} x={(i % columns) * w} y={(i // columns) * h} width={w} height={h} xoffset=0 yoffset=0 xadvance=6 page=0 chnl=15")
    lines.append("kernings count=0")
    return "\n".join(lines) + "\n"


def author():
    SOURCE.mkdir(parents=True, exist_ok=True)
    for name, spec in SPECS.items():
        write_ase(SOURCE / f"{name}.aseprite", *spec["factory"](),
                  note="Task 002C.6 / original explicit pixel clusters / native editable UI / no licensed system fonts / integer coordinates / no resampling",
                  palette=PALETTE)


def export():
    OUT.mkdir(parents=True, exist_ok=True)
    for name in SPECS:
        frames, atlas, meta = render_source(name)
        atlas.save(OUT / f"{name}.png", optimize=True)
        (OUT / f"{name}.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        if name == "foundry_small":
            (OUT / "foundry_small.fnt").write_text(bmfont(meta), encoding="utf-8")
    print(f"Exported 3 saved native masters: {len(CODEPOINTS)} glyphs, 2 workbench states, 9 input glyphs.")


def check(aseprite=None):
    exe = find_tool("aseprite", aseprite)
    report = {"task": "002C.6", "aseprite_version": subprocess.check_output([exe, "--version"], text=True).strip(),
              "read_only": True, "native_runtime_parity": True, "masters": []}
    with tempfile.TemporaryDirectory(prefix="topgame-ui-native-") as directory:
        destination = Path(directory)
        for name, spec in SPECS.items():
            source = SOURCE / f"{name}.aseprite"
            frames, expected, meta = render_source(name)
            assert meta["cell"] == spec["cell"], f"{name}: changed native cell"
            assert Image.open(OUT / f"{name}.png").convert("RGBA").tobytes() == expected.tobytes(), f"{name}: saved-source/runtime pixel mismatch"
            saved_meta = json.loads((OUT / f"{name}.json").read_text(encoding="utf-8"))
            assert saved_meta == meta, f"{name}: metadata mismatch"
            if name == "foundry_small":
                assert (OUT / "foundry_small.fnt").read_text(encoding="utf-8") == bmfont(meta), "bitmap font metrics mismatch"
                assert set(range(32, 127)).issubset(meta["codepoints"]), "incomplete ASCII font"
                assert len(set(meta["codepoints"])) == len(meta["codepoints"]), "duplicate glyph"
                assert all(frame.getchannel("A").getextrema()[1] == 255 for code, frame in zip(CODEPOINTS, frames) if code not in (32, 160)), "empty printable glyph"
            native_png, native_json = destination / f"{name}.png", destination / f"{name}.json"
            subprocess.run([exe, "--batch", str(source), "--list-layers", "--list-tags", "--list-slices",
                            "--sheet-type", "horizontal", "--sheet", str(native_png),
                            "--data", str(native_json), "--format", "json-array"], check=True, capture_output=True, text=True)
            native = Image.open(native_png).convert("RGBA")
            horizontal = blank((meta["cell"][0] * len(frames), meta["cell"][1]))
            for i, frame in enumerate(frames):
                horizontal.alpha_composite(frame, (i * meta["cell"][0], 0))
            assert native.tobytes() == horizontal.tobytes(), f"{name}: actual Aseprite/native pixel mismatch"
            info = json.loads(native_json.read_text(encoding="utf-8"))
            assert [layer["name"] for layer in info["meta"]["layers"]] == meta["layers"], f"{name}: lost editable layers"
            native_tags = {tag["name"]: {"from": tag["from"], "to": tag["to"]} for tag in info["meta"]["frameTags"]}
            assert native_tags == meta["tags"], f"{name}: tag mismatch"
            assert [frame["duration"] for frame in info["frames"]] == meta["durations_ms"], f"{name}: timing mismatch"
            pivot = info["meta"]["slices"][0]["keys"][0]["pivot"]
            assert [pivot["x"], pivot["y"]] == meta["pivot"], f"{name}: pivot mismatch"
            report["masters"].append({"source": source.relative_to(ROOT).as_posix(), "frames": len(frames),
                                      "cell": meta["cell"], "layers": meta["layers"], "tags": len(meta["tags"]),
                                      "native_cli_parity": True, "source_runtime_parity": True,
                                      "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                                      "runtime_sha256": hashlib.sha256((OUT / f"{name}.png").read_bytes()).hexdigest()})
    return report


def preview(output):
    """Inspection sheet only, external QA; exact native images are inset at 1x."""
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet = Image.new("RGBA", (1280, 790), c("ink"))
    _, background, _ = render_source("frontend_background")
    sheet.alpha_composite(background, (0, 0))
    _, glyphs, _ = render_source("input_glyphs")
    sheet.alpha_composite(glyphs.resize((864, 96), Image.Resampling.NEAREST), (20, 382))
    for line, text in enumerate(["SPINNING METAL", "Collect parts. Build your top. Survive the arena.",
                                  "ABCDEFGHIJKLMNOPQRSTUVWXYZ  0123456789", "abcdefghijklmnopqrstuvwxyz  Clutch / Orbit Drive",
                                  "Chain Impact \u2014 High Gear \u00d7 3   RPM: 1,234!", "[](){}!? / +-= % @ # & : ; _ | < >"]):
        text_image = blank((len(text) * 6, 10))
        for i, character in enumerate(text):
            draw_pattern(text_image, PATTERNS[character], i * 6)
        scale = 4 if line == 0 else 2
        sheet.alpha_composite(text_image.resize((text_image.width * scale, 10 * scale), Image.Resampling.NEAREST), (20, 514 + line * 36))
        if line > 0:
            sheet.alpha_composite(text_image, (900, 480 + line * 28))
    sheet.convert("RGB").save(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--author", action="store_true", help="Explicitly overwrite these three UI masters with the original authored recipe")
    parser.add_argument("--check", action="store_true", help="Read-only saved master/runtime/native Aseprite parity")
    parser.add_argument("--aseprite", help="Native Aseprite executable override; otherwise TOPGAME_ASEPRITE/shared resolver")
    parser.add_argument("--report", type=Path, help="External QA JSON check report")
    parser.add_argument("--preview", type=Path, help="External QA inspection sheet")
    args = parser.parse_args()
    for destination in (args.report, args.preview):
        if destination and (destination.resolve() == ROOT or ROOT in destination.resolve().parents):
            raise ValueError("QA report/preview output must be outside the game repository")
    if args.check and args.author:
        parser.error("--check is read-only and cannot be combined with --author")
    if args.author:
        author()
    if args.check:
        report = check(args.aseprite)
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report, indent=2))
    else:
        export()
    if args.preview:
        preview(args.preview)


if __name__ == "__main__":
    main()
