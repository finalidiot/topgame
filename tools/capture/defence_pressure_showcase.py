"""Capture declared invested defence against production AI and natural pressure.

Every skipped interval executes all intervening fixed solver ticks. The video
shows chronological excerpts, exact control policy and the honest AFK outcome.
No Main/profile, fake deaths, forced enemies, top-ups or threat-time jumps.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
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


def dependency_paths() -> list[str]:
    paths = {"tools/capture/defence_pressure_showcase.py"}
    pending = ["tests/capture_defence_pressure.gd"]
    while pending:
        relative = pending.pop()
        if relative in paths:
            continue
        paths.add(relative)
        code = (ROOT / relative).read_text(encoding="utf-8")
        for resource in re.findall(r'["\']res://([^"\']+)["\']', code):
            candidate = ROOT / resource
            if "%" in resource:
                candidate = ROOT / resource.split("%", 1)[0]
                if not candidate.is_dir():
                    candidate = candidate.parent
            if candidate.is_dir():
                paths.update(str(p.relative_to(ROOT)).replace("\\", "/") for p in candidate.rglob("*") if p.is_file() and p.suffix in {".png", ".json", ".wav", ".import"})
            elif candidate.is_file():
                if candidate.suffix == ".gd":
                    pending.append(resource)
                else:
                    paths.add(resource)
    for directory in ["assets/arena", "assets/top", "assets/powers", "assets/audio/music"]:
        paths.update(str(p.relative_to(ROOT)).replace("\\", "/") for p in (ROOT / directory).rglob("*") if p.is_file())
    paths.update(["assets/ui/foundry_small.fnt", "assets/ui/foundry_small.png", "assets/ui/foundry_small.png.import"])
    return sorted(paths)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qa-root", type=Path)
    parser.add_argument("--engine")
    parser.add_argument("--ffmpeg")
    parser.add_argument("--diagnostic", action="store_true")
    args = parser.parse_args()
    task = workspace.create_task_workspace("003A", args.qa_root)
    base = "003a_defence_pressure_acceptance"
    name = base + "_" + datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    manifest = task / "manifests" / (name + ".json")
    raw = task / "temp" / (name + ".avi")
    video = task / "video" / (base + ".mp4")
    frames = task / "frames" / name
    if not args.diagnostic:
        assert not video.exists(), "Preserve existing human-review movies"
    source_before = {relative: pipeline.sha256(ROOT / relative) for relative in dependency_paths()}
    profile_before = pipeline.production_profile(ROOT)
    measured = task / "manifests" / (name + "_afk_measurement.json")
    measure_command = [workspace.find_tool("godot", args.engine), "--headless", "--path", str(ROOT), "--script", "res://tests/observe_defence_pressure.gd", "--", "--seed=421", "--policy=zero_input", "--report=" + str(measured)]
    measurement = pipeline.run_logged(measure_command, task / "logs" / (name + "_afk_measurement.log"), 900)
    afk_measurement = json.loads(measured.read_text(encoding="utf-8"))["samples"][0]
    assert afk_measurement["director_investments"] == 15
    command = [workspace.find_tool("godot", args.engine), "--path", str(ROOT), "--script", "res://tests/capture_defence_pressure.gd"]
    command += ["--headless"] if args.diagnostic else ["--fixed-fps", "60", "--disable-vsync", "--write-movie", str(raw), "--audio-driver", "Dummy"]
    command += ["--", "--manifest=" + str(manifest), "--afk-end=" + str(afk_measurement["survival_seconds"])]
    command += ["--diagnostic"] if args.diagnostic else ["--frames=" + str(frames)]
    print("DEFENCE_NATIVE_CAPTURE " + str(manifest), flush=True)
    result = pipeline.run_logged(command, task / "logs" / (name + ".log"), 900)
    log = Path(result["log"]).read_text(encoding="utf-8", errors="replace")
    assert not any(marker in log for marker in ["SCRIPT ERROR:", "ERROR:", "ObjectDB instances were leaked"]), log
    data = json.loads(manifest.read_text(encoding="utf-8"))
    assert data["main_created"] is False and data["collection_accessed"] is False
    assert data["native_view"] == [640, 360]
    active, afk = data["summaries"]
    assert active["policy"] == "active_centre" and active["seconds"] >= 638.0
    assert afk["policy"] == "zero_input" and afk["reason"] in {"ring_out", "spin_out"}
    assert afk["seconds"] < 600.0
    assert abs(afk["seconds"] - afk_measurement["survival_seconds"]) < 0.001
    assert afk["economy"]["gains"]["combat_reclamation"] == 0.0
    assert all(afk["economy"]["gains"].get(source, 0) == 0 for source in ["elimination", "elite", "boss"])
    assert any(row["committed"] and row["time"] >= 360 for row in data["rows"] if row["policy"] == "active_centre")
    source_after = {relative: pipeline.sha256(ROOT / relative) for relative in source_before}
    assert source_before == source_after, "Capture dependencies changed while recording"
    assert profile_before == pipeline.production_profile(ROOT), "Capture touched the real profile"
    data.update(source_sha256=source_before, source_unchanged=True, source_git_sha=pipeline.git(ROOT, "rev-parse", "HEAD"), source_scope="Standalone transitive Battle/audio/art dependencies. Explicit native640x360nearest viewport settings; noMain/menus/projectconfigurationdependency.",real_profile_before=profile_before, real_profile_unchanged=True, capture_process=result, afk_prior_measurement=measurement, afk_prior_report=str(measured), afk_exact_replay=True, human_feel="Pending human review; automated sampled controls do not establish human feel acceptance.")
    # Retain verified source/profile evidence even if an encoder later fails.
    manifest.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    if not args.diagnostic:
        ffmpeg = workspace.find_tool("ffmpeg", args.ffmpeg)
        encode = pipeline.run_logged([ffmpeg, "-v", "error", "-i", str(raw), "-map", "0:v:0", "-map", "0:a:0", "-vf", "scale=1280:720:flags=neighbor", "-c:v", "libx264", "-crf", "18", "-preset", "fast", "-c:a", "aac", "-b:a", "192k", "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-shortest", str(video)], task / "logs" / (name + "_encode.log"), 300)
        decode = pipeline.run_logged([ffmpeg, "-v", "error", "-i", str(video), "-f", "null", "-"], task / "logs" / (name + "_decode.log"), 120)
        info = subprocess.run([ffmpeg, "-hide_banner", "-i", str(video)], capture_output=True, text=True)
        match = re.search(r"Duration: (\d+):(\d+):(\d+(?:\.\d+)?)", info.stderr)
        assert match
        seconds = int(match[1]) * 3600 + int(match[2]) * 60 + float(match[3])
        assert abs(seconds - data["nominal_seconds"]) < 0.25 and video.stat().st_size > 100_000
        data.update(video=str(video), video_sha256=pipeline.sha256(video), actual_duration_seconds=seconds, encoder=encode, decoder=decode, metadata=info.stderr, raw_movie=str(raw), raw_audio="Native PCM audio stream embedded by Godot Movie Maker in the AVI.", soundtrack="Actual unchanged accepted adaptive Run stems and ordinary combat SFX; skipped solver intervals emit no out-of-time sound.")
    manifest.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": True, "manifest": str(manifest), "video": data.get("video"), "seconds": data["nominal_seconds"], "observations": [{k: row[k] for k in ["policy", "seconds", "reason", "rpm", "hits"]} for row in data["summaries"]], "profile_unchanged": True}, indent=2))


if __name__ == "__main__":
    main()
