"""Native beast colour identities and lossless RGBA-cel palette migration.

This tool changes RGB in native Aseprite palettes/cels only. All alpha bytes,
cel headers, layer chunks, tags, slices, durations and unknown chunks remain
unchanged. It never reconstructs anatomy or applies a runtime texture tint.
The explicit --apply operation preserves before masters and native exports in
external QA, proves current source/runtime parity first, then proves shape and
alpha preservation. Ordinary beast export is beast_manifestations.py.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import zlib

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from workspace.workspace import create_task_workspace, find_tool

PALETTE_ROLES = ("smoke", "shadow", "body", "plane", "silver", "light")
ORIGINAL_PALETTE = dict(zip(PALETTE_ROLES,
    ("#343434", "#414141", "#606060", "#808080", "#b4b4b4", "#dddddd")))
SPIRIT_PALETTES = {
    "black_arrow": dict(zip(PALETTE_ROLES,
        ("#2c2f33", "#292d32", "#454a50", "#686e75", "#b4b8bf", "#dde0e5"))),
    "iron_bull": dict(zip(PALETTE_ROLES,
        ("#392b2a", "#4b2b29", "#743f36", "#965b4b", "#b9b3ae", "#dfd7cc"))),
    "stone_tortoise": dict(zip(PALETTE_ROLES,
        ("#263526", "#2c482c", "#416b3e", "#608b53", "#a9bca6", "#d3e0c5"))),
    "coil_dragon": dict(zip(PALETTE_ROLES,
        ("#222c3b", "#2a3954", "#36627a", "#51849d", "#a6b9c8", "#cfe0e8"))),
}
COLOUR_IDENTITIES = {
    "black_arrow": "smoky charcoal with cool silver edges",
    "iron_bull": "deep rust and heated iron red with warm silver edges",
    "stone_tortoise": "earthy spectral green with pale sage silver edges",
    "coil_dragon": "muted cyan blue with blue violet shadow and ice silver edges",
}


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def rgb(value: str) -> bytes:
    return bytes.fromhex(value.removeprefix("#"))


def frames(data: bytes) -> list[tuple[bytes, list[tuple[int, bytes]]]]:
    size, magic, count, width, height, depth = struct.unpack_from("<IHHHHH", data)
    assert (size, magic, width, height, depth) == (len(data), 0xA5E0, 128, 128, 32)
    result = []
    offset = 128
    for _ in range(count):
        length, magic, old_count, _, new_count = struct.unpack_from("<IHHH2xI", data, offset)
        assert magic == 0xF1FA
        chunks = []
        position = offset + 16
        for _ in range(new_count or old_count):
            chunk_size, kind = struct.unpack_from("<IH", data, position)
            chunks.append((kind, data[position + 6:position + chunk_size]))
            position += chunk_size
        assert position == offset + length
        result.append((data[offset:offset + 16], chunks))
        offset += length
    assert offset == len(data)
    return result


def palette_entries(payload: bytes) -> list[tuple[str, int, bytes]]:
    size, first, last = struct.unpack_from("<III", payload)
    assert (size, first, last) == (6, 0, 5)
    result = []
    position = 20
    for _ in range(last - first + 1):
        flags = struct.unpack_from("<H", payload, position)[0]
        assert flags == 1
        rgba = payload[position + 2:position + 6]
        length = struct.unpack_from("<H", payload, position + 6)[0]
        name = payload[position + 8:position + 8 + length].decode("utf-8")
        result.append((name, position + 2, rgba))
        position += 8 + length
    assert position == len(payload)
    assert tuple(entry[0] for entry in result) == PALETTE_ROLES
    return result


def native_palette(data: bytes) -> dict[str, str]:
    palettes = [payload for _, chunks in frames(data) for kind, payload in chunks if kind == 0x2019]
    assert len(palettes) == 1
    return {name: "#" + rgba[:3].hex() for name, _, rgba in palette_entries(palettes[0])}


def cel_pixels(payload: bytes) -> bytes:
    assert struct.unpack_from("<H", payload, 7)[0] == 2, "Expected native compressed RGBA cel"
    width, height = struct.unpack_from("<HH", payload, 16)
    raw = zlib.decompress(payload[20:])
    assert len(raw) == width * height * 4
    return raw


def invariant_signature(data: bytes) -> dict:
    """Fingerprint every noncolour byte and the 80 native alpha/shape planes."""
    noncolour = [data[4:128]]
    alpha = []
    shape = []
    chunk_types = Counter()
    for header, chunks in frames(data):
        noncolour.append(header[4:])
        for kind, payload in chunks:
            chunk_types[kind] += 1
            noncolour.append(struct.pack("<H", kind))
            if kind == 0x2019:
                normalized = bytearray(payload)
                for _, position, _ in palette_entries(payload):
                    normalized[position:position + 3] = b"\0\0\0"
                noncolour.append(bytes(normalized))
            elif kind == 0x2005:
                raw = cel_pixels(payload)
                noncolour.append(payload[:20])
                alpha.append(raw[3::4])
                shape.append(bytes(1 if value else 0 for value in raw[3::4]))
                # RGB hidden under alpha zero is preserved too.
                noncolour.append(b"".join(raw[i:i + 3] for i in range(0, len(raw), 4) if raw[i + 3] == 0))
            else:
                noncolour.append(payload)
    return {"noncolour_native_sha256": sha(b"".join(noncolour)),
            "native_cel_alpha_sha256": sha(b"".join(alpha)),
            "native_cel_shape_sha256": sha(b"".join(shape)),
            "native_cels": len(alpha), "frame_count": len(frames(data)),
            "chunk_types": {hex(key): value for key, value in sorted(chunk_types.items())}}


def recolour_native(data: bytes, target: dict[str, str]) -> bytes:
    original = native_palette(data)
    assert original == ORIGINAL_PALETTE, "Refusing a second colour migration or unrecognised artist palette"
    mapping = {rgb(original[role]): rgb(target[role]) for role in PALETTE_ROLES}
    output = []
    for header, chunks in frames(data):
        updated = []
        for kind, payload in chunks:
            if kind == 0x2019:
                changed = bytearray(payload)
                for role, position, _ in palette_entries(payload):
                    changed[position:position + 3] = rgb(target[role])
                payload = bytes(changed)
            elif kind == 0x2005:
                raw = bytearray(cel_pixels(payload))
                for index in range(0, len(raw), 4):
                    if raw[index + 3]:
                        raw[index:index + 3] = mapping[bytes(raw[index:index + 3])]
                payload = payload[:20] + zlib.compress(bytes(raw), 9)
            updated.append(struct.pack("<IH", len(payload) + 6, kind) + payload)
        body = b"".join(updated)
        output.append(struct.pack("<I", len(body) + 16) + header[4:] + body)
    body = b"".join(output)
    result = struct.pack("<I", len(body) + 128) + data[4:128] + body
    assert invariant_signature(result) == invariant_signature(data)
    assert native_palette(result) == target
    return result


def colour_metadata(name: str, source: Path, native: Image.Image) -> dict:
    palette = native_palette(source.read_bytes())
    assert palette == SPIRIT_PALETTES[name], f"{name}: native colour identity changed"
    alpha = native.getchannel("A").tobytes()
    visible = [value for value in alpha if value]
    assert visible and any(value < 255 for value in visible)
    return {"colour_identity": COLOUR_IDENTITIES[name], "native_palette": palette,
            "colour_authored_in_native_layers": True, "runtime_colour_tint": False,
            "native_alpha_range": [min(visible), max(visible)],
            "native_translucent_pixel_fraction": sum(value < 255 for value in visible) / len(visible),
            "native_alpha_sha256": sha(alpha),
            "native_shape_sha256": sha(bytes(1 if value else 0 for value in alpha))}


def apply(aseprite: str, qa: Path) -> dict:
    evidence = qa / "manifests/beast-colour-identity"
    before_dir = qa / "temp/beast-colour-before"
    assert not evidence.exists() and not before_dir.exists(), "Preserve existing evidence; choose a fresh QA root"
    evidence.mkdir(parents=True)
    before_dir.mkdir(parents=True)
    manifest = json.loads((ROOT / "assets/powers/beasts_002c5_2/manifest.json").read_text(encoding="utf-8"))
    rows = []
    staged = []
    # Validate and preserve all four originals before any source mutation.
    for name, palette in SPIRIT_PALETTES.items():
        source = ROOT / f"assets/source-art/beasts_002c5_2/{name}.aseprite"
        runtime = ROOT / f"assets/powers/beasts_002c5_2/{name}.png"
        original = source.read_bytes()
        assert sha(original) == manifest["effects"][name]["source_sha256"]
        assert sha(runtime.read_bytes()) == manifest["effects"][name]["texture_sha256"]
        preserved = before_dir / source.name
        preserved.write_bytes(original)
        native_png = before_dir / f"{name}_native.png"
        native_json = evidence / f"{name}_baseline_native.json"
        command = [aseprite, "--batch", str(preserved), "--list-layers", "--list-tags", "--list-slices",
                   "--sheet", str(native_png), "--sheet-columns", "4", "--data", str(native_json), "--format", "json-array"]
        subprocess.run(command, capture_output=True, text=True, check=True)
        native = Image.open(native_png).convert("RGBA")
        assert native.tobytes() == Image.open(runtime).convert("RGBA").tobytes(), "Baseline native/runtime parity failed"
        changed = recolour_native(original, palette)
        rows.append({"beast": name, "before_source_sha256": sha(original),
                     "before_runtime_sha256": sha(runtime.read_bytes()), "after_source_sha256": sha(changed),
                     "baseline_native_runtime_rgba_exact": True, "baseline_native_command": command,
                     "before_palette": native_palette(original), "after_palette": palette,
                     "colour_identity": COLOUR_IDENTITIES[name], "invariants": invariant_signature(original),
                     "preserves_all_noncolour_bytes": True, "preserves_all_native_cel_alpha_and_shape": True,
                     "baseline_native_alpha_sha256": sha(native.getchannel("A").tobytes())})
        staged.append((source, changed))
    for source, changed in staged:
        source.write_bytes(changed)
    report = {"task": "003A", "operation": "native RGB palette and visible cel pixels only",
              "masters": 4, "layers_per_master": 4, "frames_per_master": 20,
              "tags_per_master": 5, "pivot": [64, 96], "runtime_tint": False,
              "baseline_parity_verified_before_changes": True, "geometry_alpha_timing_preserved": True,
              "checks": rows}
    (evidence / "003a_beast_colour_migration.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Explicitly migrate the four original native palettes")
    parser.add_argument("--aseprite")
    parser.add_argument("--qa-root", type=Path)
    args = parser.parse_args()
    if args.apply:
        report = apply(find_tool("aseprite", args.aseprite), create_task_workspace("003A", args.qa_root))
        print(json.dumps({key: value for key, value in report.items() if key != "checks"}))
    else:
        for name in SPIRIT_PALETTES:
            source = ROOT / f"assets/source-art/beasts_002c5_2/{name}.aseprite"
            print(json.dumps({"beast": name, "palette": native_palette(source.read_bytes()),
                              "invariants": invariant_signature(source.read_bytes())}))


if __name__ == "__main__":
    main()
