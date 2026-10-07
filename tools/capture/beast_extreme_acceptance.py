"""Capture native 003A extreme-hit ladder and complete beast performances.

Every scene explicitly labels its deliberate physical collision pose fixture.
The canonical pair solver accepts the collision and production playback resolves
it; this evidence is separate from the natural frequency study.
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
sys.path.insert(0,str(ROOT / "tools/workspace"))
sys.path.insert(0,str(ROOT / "tools/build"))
import workspace
import windows_checkpoint as pipeline

NAMES = {"ladder":"003a_beast_extreme_hit_ladder", "completion":"003a_black_arrow_completion", "final":"003a_beast_final_acceptance"}


def dependencies() -> list[str]:
    paths = {"tools/capture/beast_extreme_acceptance.py","project.godot"}
    pending = ["tests/capture_beast_extreme_acceptance.gd"]
    while pending:
        relative = pending.pop()
        if relative in paths:
            continue
        paths.add(relative)
        code = (ROOT / relative).read_text(encoding="utf-8")
        for resource in re.findall(r'["\']res://([^"\']+)["\']',code):
            candidate = ROOT / resource
            if "%" in resource:
                candidate = ROOT / resource.split("%",1)[0]
                if not candidate.is_dir():
                    candidate = candidate.parent
            if candidate.is_dir():
                paths.update(str(p.relative_to(ROOT)).replace("\\","/") for p in candidate.rglob("*") if p.is_file() and p.suffix in {".png",".json",".import"})
            elif candidate.is_file():
                if candidate.suffix==".gd": pending.append(resource)
                else: paths.add(resource)
    for directory in ["assets/powers/beasts_002c5_2","assets/powers/feedback_002c5_2","assets/source-art/beasts_002c5_2"]:
        paths.update(str(p.relative_to(ROOT)).replace("\\","/") for p in (ROOT / directory).rglob("*") if p.is_file())
    return sorted(paths)


def validate(data: dict, rendered: bool) -> None:
    assert data["failures"]==[],data["failures"]
    assert data["native_view"]==[640,360] and data["fps"]==60 and data["slowdown"]==3
    assert not data["collection_opened"] and not data["main_created"]
    for run in data["runs"]:
        impact = run["actual_impact"]
        score = impact["impulse"]*impact["closing"]
        presentation = run["presentation"]
        assert impact["collision_id"]>0 and impact["first_entity_id"]==1 and impact["second_entity_id"]==2
        assert impact["impulse"]>0 and impact["closing"]>0
        assert presentation["peak_live"]<=1
        if run["target_multiplier"]>=1:
            assert run["phases"]==["prepare","travel","strike","recovery"]
            assert score>=presentation["extreme_threshold"]
            assert run["instance_id"]>0
            assert all(row["beast"].get("instance_id",run["instance_id"])==run["instance_id"] for row in run["rows"] if row["beast"])
            assert not run["rows"][-1]["beast"]
            if rendered:
                for phase in ["prepare","travel","strike","recovery"]:
                    image = pipeline.png_record(Path(run["feature_frames"][phase]["path"]))
                    assert image["width"]==640 and image["height"]==360
        else:
            assert score<presentation["extreme_threshold"] and run["instance_id"]==0
            assert all(not row["beast"] for row in run["rows"])
        if run["followup_impact"]:
            assert run["followup_impact"]["impulse"]*run["followup_impact"]["closing"]<presentation["extreme_threshold"]
            assert presentation["spawned"]==1


def capture(mode: str, args: argparse.Namespace, task: Path) -> dict:
    base=NAMES[mode]
    name=base+"_"+datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    output=task / "manifests" / (name+".json")
    raw=task / "temp" / (name+".avi")
    video=task / "video" / (base+".mp4")
    frames=task / "frames" / name
    assert not output.exists() and not raw.exists()
    if not args.diagnostic: assert not video.exists(),"Preserve existing final review media"
    paths=dependencies()
    before={path:pipeline.sha256(ROOT/path) for path in paths}
    profile_before=pipeline.production_profile(ROOT)
    command=[workspace.find_tool("godot",args.engine),"--path",str(ROOT),"--script","res://tests/capture_beast_extreme_acceptance.gd"]
    command += ["--headless"] if args.diagnostic else ["--fixed-fps","60","--disable-vsync","--write-movie",str(raw),"--audio-driver","Dummy"]
    command += ["--","--mode="+mode,"--manifest="+str(output)]
    command += ["--diagnostic"] if args.diagnostic else ["--frames="+str(frames)]
    print("BEAST_EXTREME_NATIVE_CAPTURE "+str(output),flush=True)
    process=pipeline.run_logged(command,task / "logs" / (name+".log"),900)
    data=json.loads(output.read_text(encoding="utf-8"))
    validate(data,rendered=not args.diagnostic)
    after={path:pipeline.sha256(ROOT/path) for path in paths}
    profile_after=pipeline.production_profile(ROOT)
    assert before==after,"Capture source changed during recording"
    assert profile_before==profile_after,"Battle-only capture modified player data"
    data.update(source_sha256=before,source_unchanged=True,source_git_sha=pipeline.git(ROOT,"rev-parse","HEAD"),profile_before=profile_before,profile_after=profile_after,profile_unchanged=True,capture_process=process,human_visual_status="PENDING HUMAN REVIEW",actual_audio="Native GameSound events connected to actual collision/controller output; accepted music assets preserved and no music regenerated.")
    if not args.diagnostic:
        ffmpeg=workspace.find_tool("ffmpeg",args.ffmpeg)
        encoded=pipeline.run_logged([ffmpeg,"-v","error","-i",str(raw),"-vf","scale=1280:720:flags=neighbor","-c:v","libx264","-crf","18","-preset","fast","-pix_fmt","yuv420p","-c:a","aac","-b:a","160k","-movflags","+faststart",str(video)],task / "logs" / (name+"_encode.log"),300)
        decoded=pipeline.run_logged([ffmpeg,"-v","error","-i",str(video),"-f","null","-"],task / "logs" / (name+"_decode.log"),120)
        metadata=subprocess.run([ffmpeg,"-hide_banner","-i",str(video)],capture_output=True,text=True)
        match=re.search(r"Duration: (\d+):(\d+):(\d+(?:\.\d+)?)",metadata.stderr)
        assert match
        duration=int(match[1])*3600+int(match[2])*60+float(match[3])
        expected=data["movie_frames"]/60
        assert abs(duration-expected)<.25 and video.stat().st_size>100_000
        assert "Audio:" in metadata.stderr,"Native captured effect audio missing"
        data.update(video=str(video),video_sha256=pipeline.sha256(video),raw_movie=str(raw),raw_sha256=pipeline.sha256(raw),actual_duration_seconds=duration,nominal_duration_seconds=expected,encoder=encoded,decoder=decoded,movie_metadata=metadata.stderr,editorial="Chronological native 640×360 battle scenes, integer2× nearest presentation. Simulation advances exactly once per three captured frames for 1/3-speed authored-pixel review. Declared collision fixtures remain visible in captions; normal steering/Brake continues the actual authored performance to recovery.")
    output.write_text(json.dumps(data,indent=2)+"\n",encoding="utf-8")
    result={"mode":mode,"passed":True,"manifest":str(output),"video":data.get("video"),"profile_unchanged":True,"scenes":len(data["runs"]),"frames":str(frames)}
    print(json.dumps(result,indent=2),flush=True)
    return result


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qa-root",type=Path)
    parser.add_argument("--engine")
    parser.add_argument("--ffmpeg")
    parser.add_argument("--mode",choices=["all",*NAMES],default="all")
    parser.add_argument("--diagnostic",action="store_true")
    args=parser.parse_args()
    task=workspace.create_task_workspace("003A",args.qa_root)
    for mode in NAMES if args.mode=="all" else [args.mode]: capture(mode,args,task)


if __name__=="__main__": main()
