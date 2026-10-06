"""Record 003A discrete beast direction responses from actual Battle controls.

Every native blade starts with a labelled legal Iron Comet rank II loadout.
Countdown, wall charge, facing changes and expiration use the normal solver.
The fixed solver advances once per three movie frames for a clear 1/3-speed
review. There is no Main, menu, profile access or injected combat/avatar state.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/workspace"))
sys.path.insert(0, str(ROOT / "tools/build"))
import workspace
import windows_checkpoint as pipeline

IDENTITIES = ["black_arrow", "iron_bull", "stone_tortoise", "coil_dragon"]
BASELINE = "7c26ae7e949324bac8cff0707b2905af76a033c3"


def sources() -> list[str]:
    """Hash the actual dependency graph, independent of concurrent front ends."""
    paths = {"tools/capture/beast_direction_showcase.py", "project.godot"}
    pending = ["tests/capture_beast_direction_response.gd"]
    while pending:
        relative = pending.pop()
        if relative in paths:
            continue
        paths.add(relative)
        code = (ROOT / relative).read_text(encoding="utf-8")
        for resource in re.findall(r'["\']res://([^"\']+)["\']', code):
            candidate = ROOT / resource
            if "%" in resource:
                # Expand dynamic native atlas paths, such as all blade spins.
                candidate = ROOT / resource.split("%", 1)[0]
                if not candidate.is_dir():
                    candidate = candidate.parent
            if candidate.is_dir():
                paths.update(str(p.relative_to(ROOT)).replace("\\", "/") for p in candidate.rglob("*") if p.is_file() and p.suffix in {".png", ".json", ".import"})
            elif candidate.is_file():
                if candidate.suffix == ".gd":
                    pending.append(resource)
                else:
                    paths.add(resource)
    # Metadata references to native effect textures are data, not GDScript.
    for directory in ["assets/powers/beasts_002c5_2", "assets/powers/feedback_002c5_2", "assets/source-art/beasts_002c5_2"]:
        paths.update(str(p.relative_to(ROOT)).replace("\\", "/") for p in (ROOT / directory).rglob("*") if p.is_file())
    paths.update(["assets/ui/foundry_small.fnt", "assets/ui/foundry_small.png", "assets/ui/foundry_small.png.import"])
    return sorted(paths)


def validate(data: dict, rendered: bool) -> None:
    assert data["failures"] == []
    assert [run["identity"] for run in data["runs"]] == IDENTITIES
    assert data["native_view"] == [640, 360] and data["slowdown"] == 3
    assert not data["collection_opened"] and not data["main_created"]
    for run in data["runs"]:
        assert run["legal_initial_power_fixture"] == ["iron_comet", 2]
        assert run["movie_frames"] == 585 and run["simulation_ticks"] == 195
        proof = run["proof"]
        assert proof["steady_travel"] >= 4
        assert proof["left_response"] >= 6 and proof["left_settled"] >= 20
        assert proof["right_response"] >= 6 and proof["right_settled"] >= 20
        assert run["presentation"]["peak_live"] <= 3
        assert any(event["kind"] == "comet_charge" and event["owner"] == 1 for event in run["power_events"])
        travel = [row for row in run["rows"] if row["beast"].get("phase") == "travel"]
        # Each native avatar earns two facing changes, never a per-frame spin.
        transitions = [(row["tick"], row["mirror"]) for index, row in enumerate(travel) if index == 0 or row["mirror"] != travel[index-1]["mirror"]]
        assert [mirror for tick, mirror in transitions] == [False, True, False]
        assert len({row["beast"]["instance_id"] for row in travel}) == 1
        for row in run["rows"]:
            beast = row["beast"]
            if beast:
                assert beast["owner_entity_id"] == 1 and beast["beast"] == run["identity"]
                assert beast["age"] < 4.0 and beast["phase"] in {"prepare", "travel", "strike", "recovery"}
        if rendered:
            for key in ["steady_travel", "left_turn_response", "left_turn_settled", "right_turn_response", "settled_travel_settled"]:
                feature = run["feature_frames"][key]
                assert pipeline.png_record(Path(feature["path"]))["width"] == 640


def baseline_preservation(paths: list[str], starting_manifest: Path) -> dict:
    baseline = json.loads(starting_manifest.read_text(encoding="utf-8"))
    assert baseline["starting_sha"] == BASELINE and baseline["initial_working_tree_clean"]
    actual_before = dict(baseline["source"]["files"])
    actual_before.update({key.replace("\\", "/"): value for key, value in baseline["assets"].items()})
    native = [path for path in paths if path.startswith(("assets/powers/beasts_002c5_2/", "assets/source-art/beasts_002c5_2/"))]
    physics = [path for path in paths if path.startswith("scripts/") and path != "scripts/beast_manifestations.gd"]
    result = {}
    for path in native + physics:
        new_sha = pipeline.sha256(ROOT / path)
        if path in actual_before:
            old_sha = actual_before[path]
            assert old_sha == new_sha, f"Native beast art or gameplay dependency changed: {path}"
            result[path] = {"before": old_sha, "after": new_sha, "unchanged": True, "comparison": "Actual bytes captured before polish"}
        else:
            old = subprocess.check_output(["git", "show", f"{BASELINE}:{path}"], cwd=ROOT)
            old_sha = hashlib.sha256(old).hexdigest()
            current = (ROOT / path).read_bytes().replace(b"\r\n", b"\n")
            assert old_sha == hashlib.sha256(current).hexdigest(), f"Gameplay dependency changed: {path}"
            result[path] = {"baseline_git_blob_sha256": old_sha, "working_file_sha256": new_sha, "unchanged": True, "comparison": "Git-normalized text (Windows CRLF checkout)"}
    return {"baseline": BASELINE, "starting_manifest": str(starting_manifest), "files": result, "native_art_and_simulation_dependencies_unchanged": True}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qa-root", type=Path)
    parser.add_argument("--engine")
    parser.add_argument("--ffmpeg")
    parser.add_argument("--diagnostic", action="store_true")
    args = parser.parse_args()
    task = workspace.create_task_workspace("003A", args.qa_root)
    base = "003a_beast_direction_response"
    name = base + "_" + datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    output = task / "manifests" / (name + ".json")
    raw = task / "temp" / (name + ".avi")
    video = task / "video" / (base + ".mp4")
    frames = task / "frames" / name
    assert not any(p.exists() for p in [output, raw])
    if not args.diagnostic:
        assert not video.exists(), "Preserve earlier review media"
    paths = sources()
    before = {path: pipeline.sha256(ROOT / path) for path in paths}
    preservation = baseline_preservation(paths, task / "manifests/003a_human_feedback_start.json")
    profile_before = pipeline.production_profile(ROOT)
    command = [workspace.find_tool("godot", args.engine), "--path", str(ROOT), "--script", "res://tests/capture_beast_direction_response.gd"]
    if args.diagnostic:
        command += ["--headless"]
    else:
        command += ["--fixed-fps", "60", "--disable-vsync", "--write-movie", str(raw), "--audio-driver", "Dummy"]
    command += ["--", "--manifest=" + str(output)]
    command += ["--diagnostic"] if args.diagnostic else ["--frames=" + str(frames)]
    print("BEAST_DIRECTION_NATIVE_CAPTURE " + str(output), flush=True)
    process = pipeline.run_logged(command, task / "logs" / (name + ".log"), 600)
    data = json.loads(output.read_text(encoding="utf-8"))
    validate(data, rendered=not args.diagnostic)
    after = {path: pipeline.sha256(ROOT / path) for path in paths}
    profile_after = pipeline.production_profile(ROOT)
    assert before == after, "Battle dependencies changed during capture"
    assert profile_before == profile_after, "Read-only Battle capture changed the real profile"
    data.update(capture_process=process, source_sha256=before, source_unchanged=True, source_git_sha=pipeline.git(ROOT, "rev-parse", "HEAD"), source_dependency_scope="Transitive Battle/capture GDScript and native rendering resources only; no Main/Menus/FrontEnd/audio dependencies.", profile_before=profile_before, profile_after=profile_after, profile_unchanged=True, preserved_native_art_and_mechanics=preservation, automated_visible_response_gate_passed=True, human_visual_status="PENDING HUMAN REVIEW OF DISCRETE MIRROR RESPONSE AND JITTER")
    if not args.diagnostic:
        ffmpeg = workspace.find_tool("ffmpeg", args.ffmpeg)
        encoded = pipeline.run_logged([ffmpeg, "-v", "error", "-i", str(raw), "-an", "-vf", "scale=1280:720:flags=neighbor", "-c:v", "libx264", "-crf", "18", "-preset", "fast", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(video)], task / "logs" / (name + "_encode.log"), 300)
        decoded = pipeline.run_logged([ffmpeg, "-v", "error", "-i", str(video), "-f", "null", "-"], task / "logs" / (name + "_decode.log"), 120)
        metadata = subprocess.run([ffmpeg, "-hide_banner", "-i", str(video)], capture_output=True, text=True)
        match = re.search(r"Duration: (\d+):(\d+):(\d+(?:\.\d+)?)", metadata.stderr)
        assert match
        duration = int(match[1])*3600 + int(match[2])*60 + float(match[3])
        assert abs(duration-39.0)<0.20 and video.stat().st_size>100_000
        data.update(video=str(video), video_sha256=pipeline.sha256(video), raw_movie=str(raw), raw_sha256=pipeline.sha256(raw), actual_duration_seconds=duration, nominal_seconds=39, encoder=encoded, decoder=decoded, movie_metadata=metadata.stderr, editorial="Four chronological native 640x360 scenes, integer2x nearest export, 1/3-speed simulation review. Every blade displays real steady travel, sustained left response, settled left travel, sustained right response and settled right travel. Subsequent power expiration and authored recovery remain visible. No cuts, camera rotation or regenerated animation.")
    output.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": True, "manifest": str(output), "video": data.get("video"), "visible_simulation_frames": [run["visible_frames"] for run in data["runs"]], "proof": {run["identity"]: run["proof"] for run in data["runs"]}, "profile_unchanged": True}, indent=2))


if __name__ == "__main__":
    main()
