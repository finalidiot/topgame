"""Strict imported ecology RGBA/topology receipt against saved native sources.

Eight unique atlases contain eight card branches and eight icon states. Zero
alpha RGB padding is normalized; every alpha and every visible RGB is exact.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = "assets/powers/ecology003a2/manifest.json"
FAMILIES = {"iron_comet": ("wallbreaker", "ricochet_engine"), "orbit_drive": ("centrifuge", "perpetual_orbit"),
            "momentum_bank": ("flywheel_release", "countersteer"), "crash_guard": ("reactive_plating", "sacrificial_damper")}
CARD_LAYERS = ["01 sparse arena floor", "02 paid physical travel and shadows", "03 accepted rival native body", "04 accepted owner native body", "05 contact and finite follow-through"]
ICON_LAYERS = ["01 independently authored miniature tops", "02 branch travel and contact"]
TOPOLOGY = ("cell", "pivot", "layers", "tags", "durations_ms", "columns", "frame_count", "source", "source_sha256", "texture_sha256", "native_runtime_rgba_exact")


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def visible_bytes(image):
    data = bytearray(image.convert("RGBA").tobytes())
    for offset in range(0, len(data), 4):
        if data[offset + 3] == 0:
            data[offset:offset + 3] = b"\0\0\0"
    return bytes(data)


def verify_ecology_assets(assets: dict, source_root: Path = ROOT) -> dict:
    source_root = Path(source_root)
    manifest_path = source_root / MANIFEST
    expected = json.loads(manifest_path.read_text(encoding="utf-8"))
    try:
        actual = json.loads(assets.get("ecology_json", "null"))
    except (TypeError, ValueError) as error:
        raise RuntimeError("Packaged ecology manifest is invalid") from error
    require(actual == expected, "Packaged ecology manifest differs from saved source")
    require(expected.get("version") == 1 and expected.get("task") == "003A.2" and expected.get("filter") == "nearest" and expected.get("native_pixels") is True, "Invalid ecology source identity/filter")
    require(set(expected.get("families", {})) == set(FAMILIES) and set(expected.get("art", {})) == {branch for pair in FAMILIES.values() for branch in pair}, "Ecology must contain exactly four families/eight branches")
    rows = assets.get("ecology_textures")
    kinds = {family + "/" + group for family in FAMILIES for group in ("cards", "icons")}
    require(isinstance(rows, list) and len(rows) == 8 and all(isinstance(row, dict) for row in rows) and {row.get("kind") for row in rows} == kinds, "Actual package did not inspect eight unique ecology atlases")
    require(len({row.get("path") for row in rows}) == 8, "Duplicate compiled ecology texture path")
    sys.path.insert(0, str(ROOT / "tools"))
    from build_power_art import read_ase
    source_receipts, native_presence = {}, {}
    for row in rows:
        family, group = row["kind"].split("/")
        metadata = expected["families"][family][group]
        side, columns, count, layers = (64, 6, 12, CARD_LAYERS) if group == "cards" else (16, 2, 2, ICON_LAYERS)
        texture = "res://assets/powers/ecology003a2/" + family + "_" + group + ".png"
        native = "assets/source-art/ecology003a2/" + family + "_" + group + ".aseprite"
        require(row.get("family") == family and row.get("group") == group and row.get("path") == texture and row.get("metadata_path") == "res://" + MANIFEST, "Compiled ecology family/group/path mismatch")
        require(metadata.get("texture") == texture and metadata.get("source") == native and metadata.get("cell") == [side, side] and metadata.get("pivot") == [side // 2, side // 2]
                and metadata.get("columns") == columns and metadata.get("frame_count") == count and metadata.get("layers") == layers and metadata.get("native_runtime_rgba_exact") is True, "Ecology authored topology mismatch")
        durations = metadata.get("durations_ms")
        require(isinstance(durations, list) and len(durations) == count and all(type(value) is int and value > 0 for value in durations), "Invalid ecology frame durations")
        require(sha(source_root / native) == metadata.get("source_sha256"), "Saved ecology native master changed")
        try:
            frames, parsed = read_ase(source_root / native)
        except (AssertionError, ValueError, IndexError, OSError) as error:
            raise RuntimeError("Saved ecology native master is invalid") from error
        require(len(frames) == count, "Saved ecology native frame count changed")
        for key in ("cell", "pivot", "layers", "tags", "durations_ms"):
            require(parsed[key] == metadata.get(key), "Saved native ecology topology differs: " + key)
        for key in TOPOLOGY:
            require(row.get(key) == metadata.get(key), "Compiled ecology topology differs: " + key)
        with Image.open(source_root / texture.removeprefix("res://")) as image:
            image = image.convert("RGBA")
            visible = visible_bytes(image)
            size = list(image.size)
            require(image.getchannel("A").getbbox() is not None and size == [side * columns, side * ((count + columns - 1) // columns)], "Invalid ecology source atlas dimensions/visibility")
            require(sha(source_root / texture.removeprefix("res://")) == metadata.get("texture_sha256"), "Saved ecology PNG changed")
            for index, frame in enumerate(frames):
                cel = image.crop((index % columns * side, index // columns * side, (index % columns + 1) * side, (index // columns + 1) * side))
                require(visible_bytes(frame) == visible_bytes(cel), "Ecology native/runtime visible RGBA differs")
        require(row.get("valid") is True and row.get("visible_pixels") is True and row.get("transparent_rgb_normalized") is True and row.get("size") == size
                and row.get("visible_rgba_sha256") == hashlib.sha256(visible).hexdigest(), "Actual compiled ecology alpha/visible RGB differs")
        require(isinstance(row.get("rgba_sha256"), str) and re.fullmatch("[0-9a-f]{64}", row["rgba_sha256"]) is not None, "Missing actual compiled ecology raw RGBA digest")
        require(type(row.get("packaged_native_master_present")) is bool, "Missing packaged native presence declaration")
        native_presence[row["kind"]] = row["packaged_native_master_present"]
        source_receipts[row["kind"]] = {"master_sha256": metadata["source_sha256"], "png_sha256": metadata["texture_sha256"], "visible_rgba_sha256": hashlib.sha256(visible).hexdigest()}
        for index, branch in enumerate(FAMILIES[family]):
            art = expected["art"][branch]
            per_branch = 6 if group == "cards" else 1
            require(metadata["tags"].get(branch) == {"from": index * per_branch, "to": (index + 1) * per_branch - 1}, "Invalid ecology branch span")
            require(art.get("family") == family and art.get("art_id") == branch and art.get("source_tag") == branch, "Invalid ecology branch identity")
            if group == "cards":
                require(art.get("card_texture") == texture and art.get("card_row") == index and art.get("card_cell") == 64 and art.get("card_frames") == 6
                        and type(art.get("card_static_frame")) is int and art["card_static_frame"] in range(6) and art.get("card_durations_ms") == durations[index * 6:(index + 1) * 6], "Invalid ecology card source mapping")
            else:
                require(art.get("icon") == texture and art.get("icon_frame") == index, "Invalid ecology icon source mapping")
    return {"ecology_unique_atlases_verified": 8, "ecology_card_branches_verified": 8, "ecology_icon_states_verified": 8,
            "ecology_compiled_manifest_exact": True, "ecology_alpha_and_visible_rgb_exact": True, "ecology_native_topology_and_runtime_parity_exact": True,
            "ecology_transparent_rgb_normalized": True, "ecology_packaged_native_master_presence": native_presence, "ecology_source_receipts": source_receipts}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--source-root", type=Path, default=ROOT)
    args = parser.parse_args()
    print(json.dumps(verify_ecology_assets(json.loads(args.report.read_text(encoding="utf-8")), args.source_root), indent=2))


if __name__ == "__main__":
    main()
