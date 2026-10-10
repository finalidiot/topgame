"""Export the editable 003A.1 floor collection keys; never regenerate implicitly.

--author writes the original six hand-placed pixel poses. Normal use exports the
artist's native master. --check verifies existing exact native/runtime RGBA,
layers, tags, pivot, timing and nearest-neighbour metadata without replacing it.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from build_power_art import read_ase, write_ase
from workspace.workspace import create_task_workspace, find_tool

SOURCE = ROOT / "assets/source-art/pickup_003a1/collection.aseprite"
OUT = ROOT / "assets/powers/pickup_003a1"
CELL = (40, 24)
PIVOT = (20, 12)
TIMINGS = [30, 35, 45, 55, 65, 80]
LAYERS = ["01 broken floor ring", "02 stamped chip glints", "03 short floor sparks"]
PALETTE = {"steel": "#4c626e", "silver": "#abc0c7", "cyan": "#69c2cf", "light": "#e3e8dc"}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def author() -> None:
    SOURCE.parent.mkdir(parents=True, exist_ok=True)
    frames = []
    # Explicit keyed broken octagons, with an open centre for the real machine.
    rings = [
        [(15, 12), (17, 10), (23, 10), (25, 12), (23, 14), (17, 14)],
        [(12, 12), (15, 9), (25, 9), (28, 12), (25, 15), (15, 15)],
        [(9, 12), (13, 8), (27, 8), (31, 12), (27, 16), (13, 16)],
        [(7, 12), (12, 7), (28, 7), (33, 12), (28, 17), (12, 17)],
        [(5, 12), (11, 6), (29, 6), (35, 12), (29, 18), (11, 18)],
        [(4, 12), (10, 6), (30, 6), (36, 12), (30, 18), (10, 18)],
    ]
    # One outward action with steadily falling alpha: no repeating flashes.
    alpha = [220, 205, 180, 140, 90, 36]
    for frame in range(6):
        images = [Image.new("RGBA", CELL) for _ in LAYERS]
        ring, glints, sparks = [ImageDraw.Draw(image) for image in images]
        points = rings[frame]
        ring.line(points[:3], fill=(105, 194, 207, alpha[frame]), width=1)
        ring.line(points[3:] + points[:1], fill=(171, 192, 199, alpha[frame]), width=1)
        if frame < 4:
            # Tiny opposing recycle-stamp highlights, confined to the floor.
            glints.line([(17-frame, 12), (19-frame, 11)], fill=(227, 232, 220, alpha[frame]), width=1)
            glints.line([(21+frame, 13), (23+frame, 12)], fill=(105, 194, 207, alpha[frame]), width=1)
        if frame > 0:
            sparks.line([(10-frame, 9-frame//2), (11-frame, 9-frame//2)], fill=(171, 192, 199, alpha[frame]), width=1)
            sparks.line([(29+frame, 14+frame//2), (30+frame, 14+frame//2)], fill=(105, 194, 207, alpha[frame]), width=1)
            if frame < 5: sparks.point((26+frame, 7-frame//2), fill=(227, 232, 220, alpha[frame]))
        frames.append(images)
    write_ase(SOURCE, frames, LAYERS, [("collect", 0, 5)], TIMINGS, PIVOT,
              note="003A.1 / short floor collection receipt / 310 ms / one outward fade / nearest / open centre / no attraction",
              palette=PALETTE)


def export(aseprite: str, qa: Path, check: bool) -> dict:
    cells, meta = read_ase(SOURCE)
    assert meta == {"cell": list(CELL), "pivot": list(PIVOT), "layers": LAYERS,
                    "tags": {"collect": {"from": 0, "to": 5}}, "durations_ms": TIMINGS}
    native_dir = qa / "temp" / ("pickup-flair-check" if check else "pickup-flair-export")
    native_dir.mkdir(parents=True, exist_ok=True)
    png, data = native_dir / "collection_native.png", native_dir / "collection_native.json"
    subprocess.run([aseprite, "--batch", str(SOURCE), "--list-layers", "--list-tags", "--list-slices",
                    "--sheet", str(png), "--sheet-columns", "6", "--data", str(data), "--format", "json-array"],
                   capture_output=True, text=True, check=True)
    native = Image.open(png).convert("RGBA")
    expected = Image.new("RGBA", (CELL[0]*6, CELL[1]))
    for i, cell in enumerate(cells): expected.alpha_composite(cell, (i*CELL[0], 0))
    assert native.size == expected.size
    a, b = native.tobytes(), expected.tobytes()
    assert all(a[i+3] == b[i+3] and max(abs(a[i+j]-b[i+j]) for j in range(3)) <= 1 for i in range(0, len(a), 4))
    native_meta = json.loads(data.read_text(encoding="utf-8"))
    assert [row["duration"] for row in native_meta["frames"]] == TIMINGS
    assert [layer["name"] for layer in native_meta["meta"]["layers"]] == LAYERS
    assert len(native_meta["meta"]["frameTags"]) == 1
    tag = native_meta["meta"]["frameTags"][0]
    assert tag["name"] == "collect" and tag["from"] == 0 and tag["to"] == 5 and tag["direction"] == "forward"
    assert native_meta["meta"]["slices"][0]["keys"][0]["pivot"] == {"x":20,"y":12}
    OUT.mkdir(parents=True, exist_ok=True)
    target = OUT / "collection.png"
    if check:
        assert Image.open(target).convert("RGBA").tobytes() == a, "Runtime must match the current editable native master"
    else: native.save(target, optimize=True)
    item = {"version":1,"task":"003A.1", **meta, "columns":6,"frame_count":6,
            "duration_ms":sum(TIMINGS),"filter":"nearest","floor_only":True,"loop":False,
            "reduced_flashing":"same one-way authored fade; no repeated brightness pulses",
            "source":SOURCE.relative_to(ROOT).as_posix(),"texture":"res://"+target.relative_to(ROOT).as_posix(),
            "source_sha256":sha(SOURCE),"texture_sha256":sha(target),"native_runtime_rgba_exact":True}
    manifest = OUT / "manifest.json"
    if check: assert json.loads(manifest.read_text(encoding="utf-8")) == item
    else: manifest.write_text(json.dumps(item, indent=2)+"\n", encoding="utf-8")
    return item


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--author", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--aseprite")
    parser.add_argument("--qa-root", type=Path)
    args = parser.parse_args()
    assert not (args.author and args.check)
    if args.author: author()
    item = export(find_tool("aseprite", args.aseprite), create_task_workspace("003A.1", args.qa_root), args.check)
    print(json.dumps({"passed":True,"check_only":args.check,"art":item}, indent=2))


if __name__ == "__main__": main()
