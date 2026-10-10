"""Verify an actual Windows package's isolated catalogue and all part textures.

Usage: python tools/parts/verify_packaged_catalogue.py --exe <candidate.exe>
       --qa-root <external GyroBrothers-QA>
Evidence and uniquely named fixtures remain outside the repository. No build
promotion, player-save reset, gameplay injection or existing-file overwrite.
"""
from __future__ import annotations

import argparse
from functools import lru_cache
import hashlib
from datetime import datetime, timezone
import json
import math
import os
import struct
import subprocess
from pathlib import Path
import sys
import uuid
import tempfile
import wave
import zlib
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
TASK = "002C.5.2"
UI_POLISH_LAYOUT = {
    "metal_plate": ([32, 32], 3),
    "inspection_frame": ([32, 32], 1),
    "button_caps": ([24, 24], 6),
    "merchant": ([48, 64], 14),
    "merchant_fixture": ([192, 64], 1),
    "credit_chip": ([16, 16], 4),
    "preview_station": ([160, 56], 1),
}
sys.path.insert(0, str(ROOT / "tools" / "workspace"))
import workspace
sys.path.insert(0, str(ROOT / "tools" / "build"))
import windows_checkpoint as pipeline

def check_engine_log(path: Path) -> dict:
    if not path.is_file():
        raise RuntimeError(f"Actual engine log was not produced: {path}")
    content = path.read_text(encoding="utf-8", errors="replace")
    if pipeline.ERRORS.search(content):
        raise RuntimeError(f"Engine errors in actual package log: {path}")
    if "PACKAGED_PART_ASSETS_PASS textures=42" not in content:
        raise RuntimeError(f"The actual compiled package probe did not complete: {path}")
    return {"path": str(path), "sha256": workspace.sha256(path)}


def verify_collection(path: Path, expected: set[str]) -> dict:
    if not path.is_file():
        raise RuntimeError("The actual package did not create its isolated QA collection")
    saved = json.loads(path.read_text(encoding="utf-8"))
    owned = saved.get("owned_part_ids")
    if (type(saved.get("schema_version")) is not int or saved.get("schema_version") != 3 or saved.get("starter_selected") != "breaker"
            or not isinstance(owned, list) or not all(isinstance(p, str) for p in owned)
            or len(owned) != len(expected) or set(owned) != expected):
        raise RuntimeError("Packaged QA collection does not own exactly the current 31 qualified part IDs")
    build = saved.get("equipped_build")
    if build != {"blade": "smash", "ratchet": "high", "bit": "flat"}:
        raise RuntimeError("The newly created QA collection changed its initial Breaker assembly")
    progression = saved.get("progression")
    empty_progression = {"credits":0,"salvage":0,"packet_serial":0,"pending_packet":{},
                         "last_packet":{},"run_serial":0,"active_run":"","last_reward":{}}
    if (not isinstance(progression, dict) or progression != empty_progression
            or any(type(progression.get(key)) is not int for key in ("credits","salvage","packet_serial","run_serial"))):
        raise RuntimeError("Packaged catalogue inspection must create zero economic state with no pending transactions or rewards")
    return {"path": str(path), "sha256": workspace.sha256(path), "owned_count": len(owned),
            "category_counts": {c: sum(p.startswith(c + ":") for p in owned)
                                for c in ("blade", "ratchet", "bit")},
            "owned_part_ids": sorted(owned), "equipped_build": build,
            "schema_version":3,"progression":progression,"qa_economy_empty":True}


def _visible_pixels(path: Path) -> tuple[list[int], str]:
    with Image.open(path) as image:
        size = list(image.size)
        data = bytearray(image.convert("RGBA").tobytes())
    for offset in range(0,len(data),4):
        if data[offset+3] == 0: data[offset:offset+3] = b"\0\0\0"
    return size,hashlib.sha256(data).hexdigest()


def verify_beast_assets(assets: dict, source_root: Path = ROOT) -> dict:
    """Prove actual imported beast colour and alpha against the native exports.

    Full visible RGBA comparison preserves every alpha byte, even where RGB is
    normalized only under alpha zero. The package's exact manifest also retains
    the native palette and named anatomy layers; a scalar runtime tint cannot
    substitute for source-authored colour.
    """
    source = source_root / "assets/powers/beasts_002c5_2/manifest.json"
    expected = json.loads(source.read_text(encoding="utf-8"))
    try:
        actual = json.loads(assets.get("beast_json", "null"))
    except (TypeError, ValueError) as error:
        raise RuntimeError("Packaged beast manifest is invalid") from error
    if actual != expected:
        raise RuntimeError("Packaged beast manifest differs from current source")
    rows = assets.get("beast_textures", [])
    identities = {"black_arrow", "iron_bull", "stone_tortoise", "coil_dragon"}
    if (not isinstance(rows, list) or len(rows) != 4 or not all(isinstance(row, dict) for row in rows)
            or {row.get("kind") for row in rows} != identities):
        raise RuntimeError("Actual package did not inspect all four beast sheets")
    for row in rows:
        kind = row["kind"]
        meta = expected["effects"][kind]
        expected_path = meta["texture"]
        if row.get("path") != expected_path:
            raise RuntimeError("Packaged beast texture path differs: " + kind)
        path = source_root / expected_path.removeprefix("res://")
        size, visible = _visible_pixels(path)
        if (row.get("valid") is not True or row.get("visible_pixels") is not True
                or row.get("size") != size or row.get("transparent_rgb_normalized") is not True
                or row.get("visible_rgba_sha256") != visible):
            raise RuntimeError("Packaged beast sheet colour/alpha pixels differ: " + expected_path)
        with Image.open(path) as image:
            alpha = image.convert("RGBA").getchannel("A").tobytes()
        visible_alpha = [value for value in alpha if value]
        if (not meta.get("colour_identity") or not isinstance(meta.get("native_palette"), dict)
                or len(meta["native_palette"]) != 6 or meta.get("colour_authored_in_native_layers") is not True
                or meta.get("runtime_colour_tint") is not False
                or meta.get("native_alpha_sha256") != hashlib.sha256(alpha).hexdigest()
                or meta.get("native_alpha_range") != [min(visible_alpha), max(visible_alpha)]
                or not any(value < 255 for value in visible_alpha)):
            raise RuntimeError("Native beast colour/transparency metadata differs: " + kind)
        if (pipeline.sha256(path) != meta.get("texture_sha256")
                or pipeline.sha256(source_root / meta["source"]) != meta.get("source_sha256")):
            raise RuntimeError("Native beast source/export fingerprint differs: " + kind)
    return {"beast_textures_verified": 4, "beast_manifest_matches_source": True,
            "beast_colour_identity_verified": True, "beast_visible_rgba_exact": True,
            "beast_transparency_alpha_exact": True, "beast_native_palette_metadata": True}


def verify_pickup_assets(assets: dict, source_root: Path = ROOT) -> dict:
    """Read-only package evidence for actual floor receipt pixels and short PCM."""
    relative = "assets/powers/pickup_003a1/manifest.json"
    expected = json.loads((source_root / relative).read_text(encoding="utf-8"))
    try:
        actual = json.loads(assets.get("pickup_flair_json", "null"))
    except (TypeError, ValueError) as error:
        raise RuntimeError("Packaged pickup flair manifest is invalid") from error
    if actual != expected:
        raise RuntimeError("Packaged pickup flair manifest differs from current source")
    row = assets.get("pickup_flair_texture")
    if not isinstance(row, dict) or row.get("kind") != "collect":
        raise RuntimeError("Actual package did not inspect the authored pickup flair")
    if row.get("path") != expected["texture"] or row.get("metadata_path") != "res://"+relative:
        raise RuntimeError("Packaged pickup flair resource path differs")
    size, visible = _visible_pixels(source_root / expected["texture"].removeprefix("res://"))
    if (row.get("valid") is not True or row.get("visible_pixels") is not True
            or row.get("size") != size or row.get("transparent_rgb_normalized") is not True
            or row.get("visible_rgba_sha256") != visible):
        raise RuntimeError("Packaged pickup flair alpha/visible RGB pixels differ")
    topology = ("cell","pivot","columns","frame_count","durations_ms","tags","layers","source")
    if any(row.get(key) != expected[key] for key in topology):
        raise RuntimeError("Packaged pickup flair topology differs")
    source = source_root / expected["source"]
    if (pipeline.sha256(source) != expected.get("source_sha256")
            or pipeline.sha256(source_root / expected["texture"].removeprefix("res://")) != expected.get("texture_sha256")):
        raise RuntimeError("Pickup native master/export fingerprints differ")
    present = row.get("native_source_available")
    native_hash = row.get("native_source_sha256")
    if (type(present) is not bool or (present and native_hash != expected["source_sha256"])
            or (not present and native_hash != "")):
        raise RuntimeError("Packaged pickup flair native-source evidence is inconsistent")
    audio = assets.get("pickup_collect_audio")
    if not isinstance(audio, dict) or audio.get("kind") != "pickup_collect":
        raise RuntimeError("Actual package did not inspect the short pickup collection cue")
    path = "res://assets/audio/pickup_collect.wav"
    with wave.open(str(source_root / path.removeprefix("res://")),"rb") as sample:
        frames, rate, channels, width = sample.getnframes(),sample.getframerate(),sample.getnchannels(),sample.getsampwidth()
        digest = hashlib.sha256(sample.readframes(frames)).hexdigest()
    if (frames,rate,channels,width) != (8640,48000,1,2):
        raise RuntimeError("Source pickup cue is not the authored180ms mono16-bit PCM")
    if (audio.get("path") != path or audio.get("valid") is not True or audio.get("format") != 1
            or audio.get("stereo") is not False or audio.get("channels") != channels
            or audio.get("mix_rate") != rate or audio.get("loop_mode") != 0
            or audio.get("pcm_frames") != frames or audio.get("pcm_sha256") != digest
            or not isinstance(audio.get("duration_seconds"),(int,float))
            or isinstance(audio.get("duration_seconds"),bool) or not math.isfinite(audio["duration_seconds"]) or abs(audio["duration_seconds"]-.18) > .000001):
        raise RuntimeError("Packaged pickup collection PCM or one-shot timing differs")
    return {"pickup_flair_texture_verified":True,"pickup_flair_manifest_matches_source":True,"pickup_flair_visible_rgba_exact":True,
            "pickup_native_master_verified":True,"pickup_packaged_native_master_available":present,
            "pickup_collection_audio_pcm_exact":True,"pickup_collection_audio_seconds":.18}


def _source_economy_odds(source_root: Path) -> dict:
    """Require source identity for the real GDScript study's versioned odds."""
    summary_path = source_root / "tests/results/003a1_bulk_economy_odds.json"
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    required = ("scripts/packet_economy.gd","assets/data/packet_economy.json","assets/data/parts_catalogue.json")
    for path in required:
        if summary.get("source_hashes",{}).get(path) != workspace.sha256(source_root / path):
            raise RuntimeError("Source economy odds evidence is stale; rerun the production economy study: " + path)
    return summary["rarity_odds"]


def verify_shop_assets(assets: dict, source_root: Path = ROOT) -> dict:
    """Match imported packaged pixels/metadata and PCM against authored source."""
    packet_meta = assets.get("packet_json",{})
    texture_rows = assets.get("packet_textures",[])
    kinds = {"packet","reclaimed_packet","reveal_mat"}
    if (not isinstance(packet_meta,dict) or set(packet_meta) != kinds
            or not isinstance(texture_rows,list) or len(texture_rows) != 3
            or {row.get("kind") for row in texture_rows} != kinds):
        raise RuntimeError("Actual package did not inspect both packet sheets and the physical reveal mat")
    for row in texture_rows:
        kind = row["kind"]
        relative = "assets/ui/shop_003a/" + kind
        metadata = json.loads((source_root / (relative + ".json")).read_text(encoding="utf-8"))
        if json.loads(packet_meta[kind]) != metadata:
            raise RuntimeError("Packaged packet authored metadata differs: " + kind)
        if (row.get("path") != "res://" + relative + ".png"
                or row.get("metadata_path") != "res://" + relative + ".json"):
            raise RuntimeError("Packaged packet texture/metadata path differs: " + kind)
        size,visible = _visible_pixels(source_root / (relative + ".png"))
        if (row.get("valid") is not True or row.get("visible_pixels") is not True
                or row.get("transparent_rgb_normalized") is not True
                or row.get("size") != size or row.get("visible_rgba_sha256") != visible):
            raise RuntimeError("Actual packaged packet pixels differ: " + kind)
        for key in ("cell","pivot","tags","durations_ms","columns","frame_count"):
            if row.get(key) != metadata.get(key):
                raise RuntimeError("Actual imported packet topology differs: " + kind + "/" + key)
    config = json.loads((source_root / "assets/data/packet_economy.json").read_text(encoding="utf-8"))
    if (json.loads(assets.get("economy_json","null")) != config
            or assets.get("economy_config") != config or assets.get("economy_validation_errors") != []):
        raise RuntimeError("Packaged packet economy differs from production data")
    odds = assets.get("economy_odds",{})
    expected_odds = _source_economy_odds(source_root)
    if (not isinstance(odds,dict) or odds.get("kind") != "standard" or odds.get("guarantee") != "UNCOMMON+"
            or odds.get("new_guarantee") is not False or odds.get("rarity_weights") != config["rarity_weights"]
            or odds.get("categories") != expected_odds
            or odds.get("rules") != config["rules"]["standard"]
            or odds.get("missing_rarity_rule") != config["rules"]["missing_rarity"]):
        raise RuntimeError("Actual compiled packet odds differ from source production algorithm evidence")
    audio_path = source_root / "assets/audio/shop_003a/manifest.json"
    audio_manifest = json.loads(audio_path.read_text(encoding="utf-8"))
    if json.loads(assets.get("packet_audio_json","null")) != audio_manifest:
        raise RuntimeError("Packaged packet audio manifest differs from authored source")
    cues = {"packet_land","packet_crinkle","packet_tear","packet_spill","packet_clink","packet_new","packet_rare","packet_recycle"}
    rows = assets.get("packet_audio",[])
    if (set(audio_manifest.get("cues",{})) != cues or not isinstance(rows,list) or len(rows) != 8
            or {row.get("kind") for row in rows} != cues):
        raise RuntimeError("Actual package did not inspect all eight physical packet cues")
    for row in rows:
        kind = row["kind"]
        cue = audio_manifest["cues"][kind]
        expected_path = "res://assets/audio/shop_003a/" + cue["file"]
        with wave.open(str(source_root / expected_path.removeprefix("res://")),"rb") as sample:
            pcm = sample.readframes(sample.getnframes())
            frames,rate,channels,width = sample.getnframes(),sample.getframerate(),sample.getnchannels(),sample.getsampwidth()
        digest = hashlib.sha256(pcm).hexdigest()
        if (rate,channels,width) != (32000,1,2) or frames != cue["pcm_frames"] or digest != cue["pcm_sha256"]:
            raise RuntimeError("Packet source PCM no longer matches its authored manifest: " + kind)
        if (row.get("path") != expected_path or row.get("valid") is not True
                or row.get("mix_rate") != rate or row.get("channels") != channels
                or row.get("stereo") is not False or row.get("format") != 1 or row.get("loop_mode") != 0
                or row.get("pcm_frames") != frames or row.get("pcm_sha256") != digest):
            raise RuntimeError("Actual packaged packet PCM differs from authored source: " + kind)
    return {"packet_textures_verified":3,"packet_metadata_matches_source":True,"packet_pixels_exact":True,
            "packet_audio_cues_verified":8,"packet_audio_pcm_exact":True,"economy_matches_source":True,
            "production_odds_match":True,"odds_source":"tests/results/003a_economy_save_summary.json"}


def verify_ui_polish_assets(assets: dict, source_root: Path = ROOT) -> dict:
    """Require all seven actual imported UI atlases and exact authored metadata.

    Alpha and visible RGB are compared independently with the source PNGs.
    Only RGB under zero alpha is normalized, as with the retained packet and
    beast checks. Report flags or screenshot markers cannot replace this parity.
    """
    metadata_rows = assets.get("ui_polish_json", {})
    rows = assets.get("ui_polish_textures", [])
    kinds = set(UI_POLISH_LAYOUT)
    if (not isinstance(metadata_rows, dict) or set(metadata_rows) != kinds
            or not isinstance(rows, list) or len(rows) != len(kinds)
            or not all(isinstance(row, dict) for row in rows)
            or {row.get("kind") for row in rows} != kinds):
        raise RuntimeError("Actual package did not inspect all seven authored human-feedback UI sheets")
    for row in rows:
        kind = row["kind"]
        relative = "assets/ui/human_feedback003a/" + kind
        source_metadata = json.loads((source_root / (relative + ".json")).read_text(encoding="utf-8"))
        try:
            packaged_metadata = json.loads(metadata_rows[kind])
        except (TypeError, ValueError) as error:
            raise RuntimeError("Packaged UI authored metadata is invalid: " + kind) from error
        if packaged_metadata != source_metadata:
            raise RuntimeError("Packaged UI authored metadata differs: " + kind)
        if (row.get("path") != "res://" + relative + ".png"
                or row.get("metadata_path") != "res://" + relative + ".json"):
            raise RuntimeError("Packaged UI texture/metadata path differs: " + kind)
        cell, frames = UI_POLISH_LAYOUT[kind]
        size, visible = _visible_pixels(source_root / (relative + ".png"))
        with Image.open(source_root / (relative + ".png")) as image:
            source_visible = image.convert("RGBA").getchannel("A").getbbox() is not None
        if (not source_visible or row.get("valid") is not True or row.get("visible_pixels") is not True
                or row.get("transparent_rgb_normalized") is not True
                or row.get("size") != size or size != [cell[0] * frames, cell[1]]
                or row.get("visible_rgba_sha256") != visible):
            raise RuntimeError("Actual packaged UI pixels differ: " + kind)
        if (source_metadata.get("cell") != cell or source_metadata.get("columns") != frames
                or source_metadata.get("frame_count") != frames
                or source_metadata.get("texture") != kind + ".png"
                or source_metadata.get("filter") != "nearest" or source_metadata.get("native_pixels") is not True):
            raise RuntimeError("Authored UI native topology is invalid: " + kind)
        for key in ("cell", "pivot", "tags", "durations_ms", "layers", "columns", "frame_count"):
            if row.get(key) != source_metadata.get(key):
                raise RuntimeError("Actual imported UI topology differs: " + kind + "/" + key)
    return {"ui_polish_textures_verified": len(kinds), "ui_polish_metadata_matches_source": True,
            "ui_polish_pixels_exact": True, "ui_polish_native_topology_verified": True}


def verify_final_acceptance_assets(assets: dict, source_root: Path = ROOT) -> dict:
    """Compare actual candidate-loaded defence/arena pixels with saved source.

    Editor existence and a self-reported valid flag cannot substitute for every
    alpha/visible RGB byte, topology and actual compiled metadata. Native masters
    are verified locally; their optional package presence is recorded explicitly.
    """
    defence_path = source_root / "assets/powers/defence003a/manifest.json"
    expected_defence = json.loads(defence_path.read_text(encoding="utf-8"))
    try:
        actual_defence = json.loads(assets.get("defence_json", "null"))
    except (TypeError, ValueError) as error:
        raise RuntimeError("Packaged defence metadata is invalid") from error
    if actual_defence != expected_defence:
        raise RuntimeError("Packaged defence metadata differs from saved source")
    expected_families = {"gyro_lock", "impact_sink", "anchor_exchange"}
    if set(expected_defence.get("families", {})) != expected_families or len(expected_defence.get("art", {})) != 12:
        raise RuntimeError("Defence source must contain three developed families and twelve card/icon states")
    metadata_rows = assets.get("arena_json", {})
    arena_kinds = {"display_panel", "machinery", "perimeter", "sparks", "vent", "warning_bank"}
    if not isinstance(metadata_rows, dict) or set(metadata_rows) != arena_kinds:
        raise RuntimeError("Actual package did not inspect all six arena metadata files")
    defence_rows = assets.get("defence_textures", [])
    arena_rows = assets.get("arena_textures", [])
    defence_keys = {family + "/" + group for family in expected_families for group in ("cards", "icons", "fx")}
    for rows, expected, label in [(defence_rows, defence_keys, "nine defence"), (arena_rows, arena_kinds, "six arena")]:
        if (not isinstance(rows, list) or len(rows) != len(expected) or not all(isinstance(r, dict) for r in rows)
                or {r.get("kind") for r in rows} != expected):
            raise RuntimeError("Actual package did not inspect all " + label + " sheets")
    sys.path.insert(0, str(source_root / "tools"))
    from build_power_art import read_ase
    native_presence = {}
    for row in defence_rows + arena_rows:
        kind = row["kind"]
        if "/" in kind:
            family, group = kind.split("/")
            metadata = expected_defence["families"][family][group]
            metadata_path = "res://assets/powers/defence003a/manifest.json"
            if row.get("family") != family or row.get("group") != group:
                raise RuntimeError("Actual defence family/group identity differs: " + kind)
        else:
            metadata_path = "res://assets/arena/escalation003a/" + kind + ".json"
            metadata = json.loads((source_root / metadata_path.removeprefix("res://")).read_text(encoding="utf-8"))
            try:
                actual = json.loads(metadata_rows[kind])
            except (TypeError, ValueError) as error:
                raise RuntimeError("Packaged arena metadata is invalid: " + kind) from error
            if actual != metadata:
                raise RuntimeError("Packaged arena metadata differs from saved source: " + kind)
            if metadata.get("presentation_only") is not True or metadata.get("native_pixels") is not True or metadata.get("filter") != "nearest":
                raise RuntimeError("Arena source must retain native presentation-only topology: " + kind)
        if row.get("path") != metadata.get("texture") or row.get("metadata_path") != metadata_path:
            raise RuntimeError("Actual packaged runtime/metadata path differs: " + kind)
        size, visible = _visible_pixels(source_root / metadata["texture"].removeprefix("res://"))
        if (row.get("valid") is not True or row.get("visible_pixels") is not True
                or row.get("transparent_rgb_normalized") is not True or row.get("size") != size
                or row.get("visible_rgba_sha256") != visible):
            raise RuntimeError("Actual packaged alpha/visible RGB pixels differ: " + kind)
        for key in ("cell", "pivot", "tags", "durations_ms", "layers", "columns", "frame_count", "source"):
            if row.get(key) != metadata.get(key):
                raise RuntimeError("Actual imported final-acceptance topology differs: " + kind + "/" + key)
        native = source_root / metadata["source"]
        if not native.is_file() or native.suffix != ".aseprite":
            raise RuntimeError("Saved editable native master is missing: " + kind)
        source_hash = hashlib.sha256(native.read_bytes()).hexdigest()
        if "source_sha256" in metadata and metadata["source_sha256"] != source_hash:
            raise RuntimeError("Defence manifest no longer matches its actual native master: " + kind)
        frames, native_metadata = read_ase(native)
        if len(frames) != metadata["frame_count"]:
            raise RuntimeError("Native authored frame count differs: " + kind)
        for key in ("cell", "pivot", "tags", "durations_ms", "layers"):
            if native_metadata.get(key) != metadata.get(key):
                raise RuntimeError("Native authored topology differs: " + kind + "/" + key)
        available = row.get("native_source_available")
        if type(available) is not bool or row.get("native_source_sha256") != (source_hash if available else ""):
            raise RuntimeError("Optional packaged native-source evidence is inconsistent: " + kind)
        native_presence[kind] = available
    return {"defence_textures_verified": 9, "arena_textures_verified": 6,
            "final_acceptance_metadata_matches_source": True, "final_acceptance_pixels_exact": True,
            "native_masters_verified": 15, "packaged_native_master_presence": native_presence}


def _compiled_metadata(assets, field, path, label):
    expected=json.loads(path.read_text(encoding="utf-8"))
    try:actual=json.loads(assets.get(field,"null"))
    except (TypeError,ValueError) as error:raise RuntimeError(f"Packaged {label} metadata is invalid") from error
    # These are raw packaged JSON files, so decoded canonical content (including
    # bool versus number types) agrees even if Git normalizes text newlines.
    if json.dumps(actual,sort_keys=True,separators=(",",":"))!=json.dumps(expected,sort_keys=True,separators=(",",":")):
        raise RuntimeError(f"Packaged {label} metadata differs from current source")
    return expected

def _visible_rgba_bytes(image):
    data=bytearray(image.convert("RGBA").tobytes())
    for offset in range(0,len(data),4):
        if data[offset+3]==0:data[offset:offset+3]=b"\0\0\0"
    return bytes(data)

def _native_base_layer(native,layer_index):
    # The venue is one normal RGBA frame. Extract its named actual cel rather
    # than incorrectly comparing each layer export to the flattened venue.
    data=native.read_bytes();width,height=struct.unpack_from("<HH",data,8)
    if struct.unpack_from("<H",data,6)[0]!=1:raise RuntimeError("Venue native master must retain its single authored frame")
    _,_,old,_,new=struct.unpack_from("<IHHH2xI",data,128);at=144
    for _ in range(new or old):
        length,kind=struct.unpack_from("<IH",data,at);payload=data[at+6:at+length]
        if kind==0x2005:
            layer,x,y,opacity,cel_type,z=struct.unpack_from("<HhhBHh",payload)
            if layer==layer_index:
                if opacity!=255 or cel_type not in (0,2) or z!=0:raise RuntimeError("Venue native cel topology changed")
                cw,ch=struct.unpack_from("<HH",payload,16);raw=zlib.decompress(payload[20:]) if cel_type==2 else payload[20:]
                image=Image.new("RGBA",(width,height));image.alpha_composite(Image.frombytes("RGBA",(cw,ch),raw),(x,y));return image
        at+=length
    raise RuntimeError("Venue native layer cel is missing")

@lru_cache(maxsize=16)
def _native_aseprite_pixels(native_path: str,native_hash: str,columns: int):
    # Native Aseprite is the compositing authority. Fractional-alpha spark
    # layers differ by one RGB rounding byte from Pillow; no tolerance is used
    # for the actual imported atlas or its authoritative native exported pixels.
    native=Path(native_path)
    if hashlib.sha256(native.read_bytes()).hexdigest()!=native_hash:raise RuntimeError("Native source changed during Aseprite parity inspection")
    qa=workspace.create_task_workspace("003A.1")
    with tempfile.TemporaryDirectory(prefix="package-native-parity-",dir=qa/"temp") as folder:
        out=Path(folder)/"native.png"
        process=subprocess.run([workspace.find_tool("aseprite"),"--batch",str(native),"--sheet-columns",str(columns),"--sheet",str(out)],capture_output=True,text=True,creationflags=subprocess.CREATE_NO_WINDOW if os.name=="nt" else 0)
        if process.returncode!=0:raise RuntimeError("Native Aseprite parity export failed: "+process.stderr)
        return _visible_pixels(out)

def verify_combat_presentation_assets(assets: dict,source_root: Path=ROOT) -> dict:
    """Actual imported new/changed venue, power/card and contact-spark RGBA.

    Exact native topology and native visible RGBA bind every sheet to its saved
    editable Aseprite master. Native source inclusion in the package stays an
    explicit optional fact; the verifier always checks the local source master.
    """
    art=_compiled_metadata(assets,"combat_art_json",source_root/"assets/powers/combat_003a1/manifest.json","combat art")
    identity=_compiled_metadata(assets,"combat_identity_json",source_root/"assets/powers/identity_manifest.json","combat identity")
    sparks=_compiled_metadata(assets,"combat_spark_json",source_root/"assets/powers/impact_003a1/manifest.json","contact sparks")
    cracks=_compiled_metadata(assets,"combat_crack_json",source_root/"assets/powers/impact_003a1/crack_manifest.json","contact crack")
    _compiled_metadata(assets,"combat_arena_geometry_json",source_root/"assets/arena/manifest.json","fixed arena geometry")
    if art.get("filter")!="nearest" or art.get("presentation_only") is not True or sparks.get("native_runtime_rgba_exact") is not True or cracks.get("filter")!="nearest" or cracks.get("native_runtime_rgba_exact") is not True:
        raise RuntimeError("Combat art source must retain native nearest pixel/parity metadata")
    wanted={}
    for name in ("backdrop","structure","surface","markings","rear_rim","front_rim"):
        item=deepcopy_metadata(art["base_arena"]);item["texture"]=item["textures"][name]
        wanted["arena_base/"+name]=(item,"res://assets/powers/combat_003a1/manifest.json",name)
    for name in ("venue_lights","power_motion","redline_ring"):
        wanted["combat/"+name]=(art["families"][name],"res://assets/powers/combat_003a1/manifest.json",None)
    for family in ("redline","afterimage","orbit_drive","predator_line"):
        wanted["card/"+family]=(identity["families"][family]["cards"],"res://assets/powers/identity_manifest.json",None)
    wanted["combat/contact_sparks"]=(sparks,"res://assets/powers/impact_003a1/manifest.json",None)
    wanted["combat/contact_crack"]=(cracks,"res://assets/powers/impact_003a1/crack_manifest.json",None)
    rows=assets.get("combat_art_textures")
    if not isinstance(rows,list) or len(rows)!=15 or not all(isinstance(r,dict) for r in rows) or {r.get("kind") for r in rows}!=set(wanted):
        raise RuntimeError("Actual package did not inspect all fifteen combat art sheets exactly once")
    sys.path.insert(0,str(source_root/"tools"));from build_power_art import read_ase
    native_presence={};masters={}
    for row in rows:
        kind=row["kind"];meta,metadata_path,layer=wanted[kind]
        if row.get("path")!=meta["texture"] or row.get("metadata_path")!=metadata_path or (layer is not None and row.get("native_layer")!=layer):
            raise RuntimeError("Actual combat resource/layer path differs: "+kind)
        png=source_root/meta["texture"].removeprefix("res://");size,digest=_visible_pixels(png)
        if row.get("valid") is not True or row.get("visible_pixels") is not True or row.get("transparent_rgb_normalized") is not True or row.get("size")!=size or row.get("visible_rgba_sha256")!=digest:
            raise RuntimeError("Actual imported combat alpha/visible RGBA differs: "+kind)
        for key in ("cell","pivot","columns","frame_count","tags","durations_ms","layers","source"):
            if row.get(key)!=meta.get(key):raise RuntimeError("Actual combat native topology differs: "+kind+"/"+key)
        for key in ("columns","frame_count"):
            if isinstance(row[key],bool) or not isinstance(row[key],(int,float)) or not math.isfinite(row[key]):raise RuntimeError("Actual combat native topology differs: "+kind+"/"+key)
        native=source_root/meta["source"]
        if not native.is_file() or native.suffix!=".aseprite":raise RuntimeError("Combat native editable master is missing: "+kind)
        native_hash=hashlib.sha256(native.read_bytes()).hexdigest()
        if "source_sha256" in meta and meta["source_sha256"]!=native_hash:raise RuntimeError("Combat source/master fingerprint differs: "+kind)
        frames,native_meta=read_ase(native)
        if len(frames)!=meta["frame_count"]:raise RuntimeError("Combat native frame count differs: "+kind)
        for key in ("cell","pivot","tags","durations_ms","layers"):
            if native_meta.get(key)!=meta.get(key):raise RuntimeError("Combat saved native topology differs: "+kind+"/"+key)
        if layer is not None:derived=_native_base_layer(native,native_meta["layers"].index(layer))
        else:
            width,height=meta["cell"];columns=meta["columns"];derived=Image.new("RGBA",(width*columns,height*math.ceil(len(frames)/columns)))
            for index,frame in enumerate(frames):derived.alpha_composite(frame,(index%columns*width,index//columns*height))
        derived_size,derived_digest=(list(derived.size),hashlib.sha256(_visible_rgba_bytes(derived)).hexdigest())
        if kind in ("combat/contact_sparks","combat/contact_crack"):derived_size,derived_digest=_native_aseprite_pixels(str(native.resolve()),native_hash,int(meta["columns"]))
        if derived_size!=size or derived_digest!=digest:
            raise RuntimeError("Combat runtime export differs from saved native RGBA: "+kind)
        available=row.get("native_source_available")
        if type(available) is not bool or row.get("native_source_sha256")!=(native_hash if available else ""):
            raise RuntimeError("Combat optional packaged native-source evidence is inconsistent: "+kind)
        native_presence[kind]=available;masters[meta["source"]]=native_hash
    return {"combat_art_sheets_verified":15,"combat_native_master_count":len(masters),"combat_art_metadata_exact":True,"combat_art_visible_rgba_exact":True,"combat_native_runtime_parity_exact":True,"combat_packaged_native_master_presence":native_presence,"combat_native_master_sha256":masters}

def deepcopy_metadata(value):return json.loads(json.dumps(value))

def _pcm_receipt(row,path,source_root,looping,stereo,label):
    if not isinstance(row,dict):raise RuntimeError(label+" PCM receipt is missing")
    with wave.open(str(source_root/path.removeprefix("res://")),"rb") as sample:
        channels=sample.getnchannels();rate=sample.getframerate();frames=sample.getnframes();width=sample.getsampwidth();pcm=sample.readframes(frames)
    if channels!=(2 if stereo else 1) or rate!=32000 or width!=2:raise RuntimeError(label+" source WAV format differs")
    duration=row.get("duration_seconds")
    if row.get("path")!=path or row.get("valid") is not True or row.get("format")!=1 or type(row.get("stereo")) is not bool or row.get("stereo")!=stereo or row.get("channels")!=channels or row.get("mix_rate")!=rate or row.get("pcm_frames")!=frames or row.get("pcm_sha256")!=hashlib.sha256(pcm).hexdigest() or row.get("loop_mode")!=(1 if looping else 0):
        raise RuntimeError(label+" actual imported PCM/format/loop differs")
    if type(duration) not in (int,float) or not math.isfinite(duration) or abs(duration-frames/rate)>1e-6:
        raise RuntimeError(label+" actual imported PCM duration differs")
    if looping and (row.get("loop_begin")!=0 or row.get("loop_end")!=frames):raise RuntimeError(label+" loop bounds differ")
    for key in ("format","channels","mix_rate","pcm_frames","loop_mode"):
        if isinstance(row.get(key),bool):raise RuntimeError(label+" actual imported PCM scalar type differs")
    return {"frames":frames,"duration_seconds":frames/rate,"pcm_sha256":hashlib.sha256(pcm).hexdigest(),"channels":channels,"sample_rate":rate}

def verify_combat_audio_assets(assets: dict,source_root: Path=ROOT) -> dict:
    manifest=_compiled_metadata(assets,"combat_audio_json",source_root/"assets/audio/impact_003a1/manifest.json","metal audio")
    kinds={"metal_light","metal_normal","metal_clang","metal_edge","metal_scrape","metal_massive","metal_extreme","metal_crack","metal_grind","metal_wall","metal_takedown"}
    rows=assets.get("combat_audio")
    if set(manifest.get("sounds",{}))!=kinds or not isinstance(rows,list) or len(rows)!=11 or not all(isinstance(r,dict) for r in rows) or {r.get("kind") for r in rows}!=kinds:
        raise RuntimeError("Actual package did not inspect all eleven metal PCM cues exactly once")
    verified={}
    for row in rows:
        kind=row["kind"];path="res://assets/audio/impact_003a1/"+kind+".wav";meta=manifest["sounds"][kind]
        verified[kind]=_pcm_receipt(row,path,source_root,False,False,"Metal "+kind)
        if meta.get("file")!=kind+".wav" or meta.get("frames")!=verified[kind]["frames"] or meta.get("pcm_sha256")!=verified[kind]["pcm_sha256"] or meta.get("sha256")!=hashlib.sha256((source_root/path.removeprefix("res://")).read_bytes()).hexdigest():
            raise RuntimeError("Metal authored source metadata/PCM differs: "+kind)
    return {"metal_audio_cues_verified":11,"metal_audio_pcm_exact":True,"metal_audio_metadata_exact":True,"metal_audio_receipts":verified}

def _metadata_equal(actual,expected):
    if isinstance(expected,dict):return isinstance(actual,dict) and set(actual)==set(expected) and all(_metadata_equal(actual[k],v) for k,v in expected.items())
    if isinstance(expected,list):return isinstance(actual,list) and len(actual)==len(expected) and all(_metadata_equal(a,b) for a,b in zip(actual,expected))
    if type(expected) in (int,float):return type(actual) in (int,float) and math.isfinite(actual) and math.isclose(actual,expected,rel_tol=1e-13,abs_tol=1e-14)
    return type(actual) is type(expected) and actual==expected

def verify_music_variation_assets(assets: dict,source_root: Path=ROOT) -> dict:
    manifest=_compiled_metadata(assets,"music_variation_json",source_root/"assets/audio/music/run_arrangement_003a1_manifest.json","Run music variation")
    score_path=source_root/"assets/audio/music/run_arrangement_003a1.json"
    _compiled_metadata(assets,"music_variation_score_json",score_path,"Run music score")
    if manifest.get("score_sha256")!=hashlib.sha256(score_path.read_bytes()).hexdigest():raise RuntimeError("Run music authored score fingerprint differs")
    kinds={"run_opening","run_motion"};rows=assets.get("music_variation_stems")
    if set(manifest.get("stems",{}))!=kinds or not isinstance(rows,list) or len(rows)!=2 or not all(isinstance(r,dict) for r in rows) or {r.get("kind") for r in rows}!=kinds:
        raise RuntimeError("Actual package did not inspect both new Run music stems exactly once")
    verified={}
    for row in rows:
        kind=row["kind"];path="res://assets/audio/music/"+kind+".wav";meta=manifest["stems"][kind]
        verified[kind]=_pcm_receipt(row,path,source_root,False,True,"Run music "+kind)
        if meta.get("frames")!=verified[kind]["frames"] or meta.get("channels")!=2 or meta.get("sample_rate")!=32000 or meta.get("sample_width_bytes")!=2 or meta.get("sha256")!=hashlib.sha256((source_root/path.removeprefix("res://")).read_bytes()).hexdigest():
            raise RuntimeError("Run music authored stem metadata differs: "+kind)
    original_path=source_root/"assets/audio/music/manifest.json";original=json.loads(original_path.read_text())
    if manifest.get("original_music_manifest_sha256")!=hashlib.sha256(original_path.read_bytes()).hexdigest():raise RuntimeError("Accepted original music manifest fingerprint differs")
    for kind in ("title","workshop","run_base","run_pressure","run_boss"):
        if manifest.get("preserved_music_sha256",{}).get(kind)!=hashlib.sha256((source_root/f"assets/audio/music/{kind}.wav").read_bytes()).hexdigest():raise RuntimeError("Accepted original music source bytes changed: "+kind)
    combined=deepcopy_metadata(original);combined["stems"].update(manifest["stems"]);combined["run_variation"]=manifest
    if not _metadata_equal(assets.get("music_asset_metadata"),combined):raise RuntimeError("Actual Music.asset_metadata does not expose all seven synchronized original/variation stems")
    return {"music_variation_stems_verified":2,"music_variation_pcm_exact":True,"music_variation_metadata_exact":True,"music_seven_stem_asset_metadata_verified":True,"original_five_music_bytes_preserved":True,"music_variation_import_loop_mode":0,"music_variation_runtime_loop_owner":"Music._ready sets exact shared PCM bounds on duplicated resources","music_variation_receipts":verified}


def verify_optional_ecology_assets(assets: dict, source_root: Path=ROOT) -> dict:
    # Historical/minimal source fixtures without this new family retain their
    # existing contracts. Current source requires the actual compiled receipt.
    if not (source_root / "assets/powers/ecology003a2/manifest.json").is_file():
        return {}
    sys.path.insert(0, str(ROOT / "tools/art"))
    from verify_ecology_package import verify_ecology_assets
    return verify_ecology_assets(assets, source_root)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", type=Path, required=True, help="Explicit candidate or latest Windows executable")
    parser.add_argument("--qa-root", type=Path, help="External QA root; defaults to the workspace convention")
    parser.add_argument("--task", default=TASK, help="Task QA workspace; preserved default for older checkpoint tooling")
    args = parser.parse_args()
    exe = args.exe.expanduser().resolve(strict=True)
    if not exe.is_file() or exe.suffix.lower() != ".exe":
        parser.error("--exe must identify an existing Windows executable")
    qa_root = workspace.qa_root(args.qa_root)
    before = pipeline.production_profile(ROOT)
    if not before.get("available"):
        parser.error("The real player profile cannot be fingerprinted on this host; no package was launched")
    if before.get("available"):
        user_directory = Path(before["directory"]).resolve()
        if qa_root == user_directory or user_directory in qa_root.parents:
            parser.error("The external QA root must be outside the player's user-data directory")
    workspace.valid_task(args.task)
    task = workspace.create_task_workspace(args.task, qa_root)
    run_id = uuid.uuid4().hex
    stem = ("002c5_2" if args.task == TASK else args.task.lower().replace(".", "")) + "_packaged_catalogue_" + run_id
    collection = task / "temp" / (stem + "_collection.json")
    asset_report = task / "manifests" / (stem + "_assets.json")
    manifest = task / "manifests" / (stem + ".json")
    if any(path.exists() for path in (collection, asset_report, manifest)):
        raise RuntimeError("Unique QA fixture unexpectedly already exists; no files were overwritten")
    source = ROOT / "assets/data/parts_catalogue.json"
    source_data = json.loads(source.read_text(encoding="utf-8"))
    catalogue = source_data["categories"]
    expected = {category + ":" + id for category, parts in catalogue.items() for id in parts}
    expected_textures = {str(part["visual"][field]) for category, parts in catalogue.items()
                         for part in parts.values() for field in (["sprite", "spin"] if category == "blade" else ["sprite"])}
    if len(expected) != 31 or len(expected_textures) != 42:
        raise RuntimeError("This task's package check requires the final 31-part / 42-texture catalogue")
    report = {"task": args.task, "run_id": run_id, "status": "running",
              "started_utc": datetime.now(timezone.utc).isoformat(), "exe": str(exe),
              "exe_sha256": workspace.sha256(exe), "source_catalogue_sha256": workspace.sha256(source),
              "profile_before": before, "child_environment": {"TOPGAME_QA_ROOT": str(qa_root)},
              "evidence_scope": "Actual packaged isolated ownership and compiled read-only catalogue/texture probe; no gameplay outcomes injected"}
    prior_qa_root = os.environ.get("TOPGAME_QA_ROOT")
    try:
        # run_logged launches hidden Windows children. Its inherited environment
        # is explicitly scoped here, then restored even if package validation fails.
        os.environ["TOPGAME_QA_ROOT"] = str(qa_root)
        engine_log = task / "logs" / (stem + "_engine.log")
        command = [str(exe), "--headless", "--quit-after", "120", "--log-file", str(engine_log),
                   "--", "--qa-catalogue", "--qa-task=" + args.task, "--collection-path=" + str(collection),
                   "--qa-assets-report=" + str(asset_report)]
        report["collection_process"] = pipeline.run_logged(command, task / "logs" / (stem + "_process.log"), 180)
        report["collection_engine_log"] = check_engine_log(engine_log)
        report["collection"] = verify_collection(collection, expected)
        assets = json.loads(asset_report.read_text(encoding="utf-8"))
        rows = assets.get("textures", [])
        # Git's clean snapshot may normalise text newlines. Compare decoded
        # catalogue content, while retaining both raw file hashes as evidence.
        if (json.loads(assets.get("catalogue_json", "null")) != source_data
                or assets.get("failures") != [] or assets.get("read_only_asset_inspection") is not True
                or len(rows) != len(expected_textures)
                or {row["path"] for row in rows} != expected_textures
                or not all(row.get("valid") is True and row.get("visible_pixels") is True
                           and row.get("size") == ([384, 48] if row["path"].endswith("_spin.png") else [48, 48])
                           for row in rows)):
            raise RuntimeError("Actual package JSON or all 42 visible component textures differ from current source")
        report["assets"] = {"path": str(asset_report), "sha256": workspace.sha256(asset_report),
                            "textures_verified": len(rows), "catalogue_matches_source": True,
                            "packaged_catalogue_sha256": assets["catalogue_sha256"]}
        # New runtime feedback sheets must survive the clean release export with
        # exact alpha and visible RGB; Godot fills RGB behind alpha-zero borders.
        feedback_source = ROOT / "assets/powers/feedback_002c5_2/manifest.json"
        expected_feedback = json.loads(feedback_source.read_text(encoding="utf-8"))
        if json.loads(assets.get("feedback_json", "null")) != expected_feedback:
            raise RuntimeError("Packaged feedback manifest differs from current source")
        feedback_rows = assets.get("feedback_textures", [])
        if len(feedback_rows) != 3 or {r.get("kind") for r in feedback_rows} != {"centre", "impact", "pickup"}:
            raise RuntimeError("Actual package did not inspect all three feedback sheets")
        for row in feedback_rows:
            path = ROOT / row["path"].removeprefix("res://")
            with Image.open(path) as image:
                size = list(image.size)
                data = bytearray(image.convert("RGBA").tobytes())
                for offset in range(0, len(data), 4):
                    if data[offset + 3] == 0:
                        data[offset:offset + 3] = b"\0\0\0"
                rgba = hashlib.sha256(data).hexdigest()
            if (not row.get("valid") or not row.get("visible_pixels") or row.get("size") != size
                    or row.get("transparent_rgb_normalized") is not True or row.get("visible_rgba_sha256") != rgba):
                raise RuntimeError("Packaged feedback sheet pixels differ: " + row["path"])
        report["assets"]["feedback_textures_verified"] = 3
        report["assets"]["feedback_manifest_matches_source"] = True
        report["assets"].update(verify_pickup_assets(assets))
        report["assets"].update(verify_beast_assets(assets))
        music_source = json.loads((ROOT / "assets/audio/music/manifest.json").read_text(encoding="utf-8"))
        music_rows = assets.get("music_stems", [])
        music_ids = {"title", "workshop", "run_base", "run_pressure", "run_boss"}
        if json.loads(assets.get("music_json", "null")) != music_source or len(music_rows) != 5 or {row.get("kind") for row in music_rows} != music_ids:
            raise RuntimeError("Actual package does not contain the five current original synchronized music stems")
        for row in music_rows:
            expected_path = "res://assets/audio/music/" + row["kind"] + ".wav"
            with wave.open(str(ROOT / expected_path.removeprefix("res://")), "rb") as sample:
                pcm = sample.readframes(sample.getnframes())
                if (row.get("path") != expected_path or not row.get("valid") or row.get("pcm_frames") != sample.getnframes()
                        or row.get("mix_rate") != sample.getframerate() or row.get("pcm_sha256") != hashlib.sha256(pcm).hexdigest()):
                    raise RuntimeError("Packaged imported PCM differs from original composition: " + expected_path)
        report["assets"]["music_stems_verified"] = 5
        report["assets"]["music_pcm_exact"] = True
        report["assets"].update(verify_shop_assets(assets))
        report["assets"].update(verify_ui_polish_assets(assets))
        report["assets"].update(verify_final_acceptance_assets(assets))
        report["assets"].update(verify_combat_presentation_assets(assets))
        report["assets"].update(verify_combat_audio_assets(assets))
        report["assets"].update(verify_music_variation_assets(assets))
        report["assets"].update(verify_optional_ecology_assets(assets))
        report["status"] = "passed"
    except Exception as error:
        report.update(status="failed", error=str(error))
        if isinstance(error, pipeline.ProcessValidationError): report["failed_process"] = error.record
        raise
    finally:
        if prior_qa_root is None: os.environ.pop("TOPGAME_QA_ROOT", None)
        else: os.environ["TOPGAME_QA_ROOT"] = prior_qa_root
        report["profile_after"] = pipeline.production_profile(ROOT)
        report["profile_unchanged"] = report["profile_before"] == report["profile_after"]
        if not report["profile_unchanged"]:
            report.update(status="failed", error="The real player profile changed; preserve it and investigate")
        report["finished_utc"] = datetime.now(timezone.utc).isoformat()
        manifest.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    if not report["profile_unchanged"]: raise RuntimeError(report["error"])
    print(json.dumps({"passed": True, "owned_parts": 31, "textures_verified": 42,
                      "profile_unchanged": True, "manifest": str(manifest)}, indent=2))


if __name__ == "__main__":
    main()
