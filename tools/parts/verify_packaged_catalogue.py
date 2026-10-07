"""Verify an actual Windows package's isolated catalogue and all part textures.

Usage: python tools/parts/verify_packaged_catalogue.py --exe <candidate.exe>
       --qa-root <external GyroBrothers-QA>
Evidence and uniquely named fixtures remain outside the repository. No build
promotion, player-save reset, gameplay injection or existing-file overwrite.
"""
from __future__ import annotations

import argparse
import hashlib
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import sys
import uuid
import wave
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
    if (type(saved.get("schema_version")) is not int or saved.get("schema_version") != 2 or saved.get("starter_selected") != "breaker"
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
            "schema_version":2,"progression":progression,"qa_economy_empty":True}


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


def _source_economy_odds(source_root: Path) -> dict:
    """Require source identity for the real GDScript study's versioned odds."""
    summary_path = source_root / "tests/results/003a_economy_save_summary.json"
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
