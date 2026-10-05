"""Record labelled real human-feedback mechanics with the production HUD.

The harness supplies legal initial parts/powers and ordinary controls only.
Previous catalogue review output is never touched. Diagnostics and a decoded
50-second video retain actual effect counts, RPM, contacts and source hashes.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"tools/workspace"))
import workspace
sys.path.insert(0,str(ROOT/"tools/build"))
import windows_checkpoint as pipeline


def preserve(path: Path, task: Path):
    if not path.exists():return
    archive=task/"temp/feedback-review-revisions"
    archive.mkdir(parents=True,exist_ok=True)
    destination=archive/f"{path.stem}-{pipeline.sha256(path)[:16]}{path.suffix}"
    if not destination.exists():shutil.copy2(path,destination)


def validate(result):
    assert len(result["runs"])==7
    assert sum(run["capture_frames"] for run in result["runs"])==3000
    assert all(run["actual_battle_frames"]==run["capture_frames"] for run in result["runs"]),"A showcase segment ended early"
    drift,overdrive,route,anchor,impact,ramp,pickup=result["runs"]
    assert drift["drift_sparks_emitted"]>10 and drift["max_drift_intensity"]>0.2
    assert overdrive["max_rpm"]>1.02 and overdrive["actual_gains"].get("redline_motion",0)>0
    assert route["max_trace_age"]>4.0 and route["max_live_traces"]>=4
    assert anchor["max_anchor_maturity"]>0.99 and anchor["actual_gains"].get("dead_centre",0)>0
    assert anchor["max_pull_strength"]>=45.0 and anchor["actual_contacts"]>0
    assert impact["blast_tags"].get("impact_extreme",0)>0 and impact["actual_contacts"]>0
    assert ramp["blast_emissions"]>0 and ramp["actual_contacts"]>0
    assert pickup["pickups"]["created"]>=1 and pickup["pickups"]["collected"]>=1
    assert pickup["pickups"]["end_charges"]>pickup["pickups"]["start_charges"]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qa-root",type=Path)
    parser.add_argument("--engine")
    parser.add_argument("--ffmpeg")
    parser.add_argument("--diagnostic",action="store_true")
    args=parser.parse_args()
    task=workspace.create_task_workspace("002C.5.2",args.qa_root)
    name="002c5_2_feedback_showcase"
    suffix="_diagnostic" if args.diagnostic else ""
    manifest=task/"manifests"/(name+suffix+".json")
    movie=task/"temp"/(name+".avi")
    output=task/"video"/(name+".mp4")
    preserve(manifest,task)
    if not args.diagnostic:preserve(output,task)
    command=[workspace.find_tool("godot",args.engine),"--path",str(ROOT),"--script","res://tests/capture_playtest_feedback.gd"]
    if args.diagnostic:command += ["--headless"]
    else:command += ["--write-movie",str(movie),"--fixed-fps","60","--disable-vsync"]
    command += ["--","--manifest="+str(manifest)]
    if args.diagnostic:command += ["--diagnostic"]
    else:command += ["--frames="+str(task/"frames/feedback-showcase")]
    print("RECORD_REAL_FEEDBACK_GAMEPLAY",flush=True)
    record=pipeline.run_logged(command,task/"logs"/(name+suffix+".log"),600)
    result=json.loads(manifest.read_text(encoding="utf-8"))
    validate(result)
    assert "FEEDBACK_CAPTURE_PASS" in Path(record["log"]).read_text(encoding="utf-8",errors="replace")
    result["capture_process"]=record
    result["source_git_sha"]=pipeline.git(ROOT,"rev-parse","HEAD")
    result["tracked_changes_at_capture"]=pipeline.git(ROOT,"status","--porcelain","--untracked-files=no")
    result["source_sha256"]={name:pipeline.sha256(ROOT/name) for name in [
        "tests/capture_playtest_feedback.gd","scripts/battle.gd","scripts/power_runtime.gd",
        "scripts/power_visuals.gd","scripts/feedback_effects.gd","scripts/menus.gd",
        "scripts/run_pickups.gd","scripts/run_context.gd","assets/powers/feedback_002c5_2/manifest.json"]}
    result["automated_visible_mechanics_gate_passed"]=True
    if not args.diagnostic:
        ffmpeg=workspace.find_tool("ffmpeg",args.ffmpeg)
        encoded=pipeline.run_logged([ffmpeg,"-y","-v","error","-i",str(movie),"-an","-c:v","libx264",
            "-preset","fast","-crf","18","-pix_fmt","yuv420p","-movflags","+faststart",str(output)],task/"logs"/(name+"_encode.log"),300)
        assert output.stat().st_size>100_000
        decoded=pipeline.run_logged([ffmpeg,"-v","error","-i",str(output),"-f","null","-"],task/"logs"/(name+"_decode.log"),300)
        metadata=subprocess.run([ffmpeg,"-hide_banner","-i",str(output)],capture_output=True,text=True)
        match=re.search(r"Duration: (\d+):(\d+):(\d+(?:\.\d+)?)",metadata.stderr)
        assert match,"Finished movie duration unavailable"
        duration=int(match[1])*3600+int(match[2])*60+float(match[3])
        assert abs(duration-50)<0.20
        result.update(video=str(output),video_sha256=pipeline.sha256(output),actual_duration_seconds=duration,
            nominal_seconds=50,encoder=encoded,decoder=decoded,raw_movie=str(movie),raw_movie_sha256=pipeline.sha256(movie),
            editorial="Seven labelled real-physics segments with production Menus HUD. Controlled initial legal parts/powers, real omitted warmups, steering/burst/brake only. Native640x360 at integer2x nearest; no fake contacts, effects, recovery or target reactions.")
        for source,destination in [("01-overdrive.png","002c5_2_feedback_overdrive_native.png"),("03-anchor.png","002c5_2_feedback_anchor_native.png")]:
            frame=task/"frames/feedback-showcase"/source
            assert frame.exists(),f"Required actual gameplay review frame absent: {source}"
            image=task/"images"/destination
            preserve(image,task)
            shutil.copy2(frame,image)
    manifest.write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"passed":True,"manifest":str(manifest),"video":result.get("video"),
        "rpm_max":[r["max_rpm"] for r in result["runs"]],"contacts":[r["actual_contacts"] for r in result["runs"]]},indent=2))


if __name__=="__main__":main()
