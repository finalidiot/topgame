"""Record the real input-only parts harness and encode a human review movie."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "workspace"))
import workspace
sys.path.insert(0, str(ROOT / "tools" / "build"))
import windows_checkpoint as pipeline

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--task", default="002C.5.2")
    parser.add_argument("--qa-root", type=Path)
    parser.add_argument("--engine")
    parser.add_argument("--ffmpeg")
    parser.add_argument("--diagnostic", action="store_true")
    args = parser.parse_args()
    task = workspace.create_task_workspace(args.task, args.qa_root)
    name = "002c5_2_assembly_showcase"
    manifest = task / "manifests" / (name + ("_diagnostic" if args.diagnostic else "") + ".json")
    avi = task / "temp" / (name + ".avi")
    output = task / "video" / (name + ".mp4")
    command = [workspace.find_tool("godot", args.engine), "--path", str(ROOT), "--script",
               "res://tests/capture_parts_catalogue.gd"]
    if args.diagnostic:
        command += ["--headless"]
    else:
        command += ["--write-movie", str(avi), "--fixed-fps", "60", "--disable-vsync"]
    command += ["--", "--seconds=6", "--manifest=" + str(manifest)]
    if args.diagnostic:
        command += ["--diagnostic"]
    else:
        command += ["--frames=" + str(task / "frames" / "assembly-showcase")]
    print("RECORD_REAL_PARTS_GAMEPLAY", flush=True)
    record = pipeline.run_logged(command, task / "logs" / (name + ("_diagnostic" if args.diagnostic else "") + ".log"), 600)
    result = json.loads(manifest.read_text(encoding="utf-8"))
    assert len(result["runs"]) == 7
    assert all(run["capture_frames"] == 360 for run in result["runs"])
    assert "PARTS_CAPTURE_PASS" in Path(record["log"]).read_text(encoding="utf-8", errors="replace")
    result["capture_process"] = record
    result["source_git_sha"] = pipeline.git(ROOT, "rev-parse", "HEAD")
    result["tracked_changes_at_capture"] = pipeline.git(ROOT, "status", "--porcelain", "--untracked-files=no")
    if not args.diagnostic:
        ffmpeg = workspace.find_tool("ffmpeg", args.ffmpeg)
        encoded = pipeline.run_logged([ffmpeg, "-y", "-v", "error", "-i", str(avi), "-an",
                                       "-c:v", "libx264", "-preset", "fast", "-crf", "18",
                                       "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(output)],
                                      task / "logs" / (name + "_encode.log"), 300)
        assert output.stat().st_size > 100_000
        # Decode the finished video, rather than trusting an encoder exit alone.
        decoded = pipeline.run_logged([ffmpeg, "-v", "error", "-i", str(output), "-f", "null", "-"],
                                      task / "logs" / (name + "_decode.log"), 300)
        result.update(video=str(output), video_sha256=pipeline.sha256(output),
                      editorial="Seven labelled 6-second real-combat segments, same seed/opponent. Integer 2x nearest gameplay; no visual edits, fake contacts or marketing cuts.",
                      nominal_seconds=42, encoder=encoded, decoder=decoded,
                      raw_movie=str(avi), raw_movie_sha256=pipeline.sha256(avi))
    manifest.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": True, "manifest": str(manifest), "video": result.get("video"),
                      "contacts": [r["actual_contacts"] for r in result["runs"]]}, indent=2))

if __name__ == "__main__":
    main()
