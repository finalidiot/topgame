"""Native accelerated density fixtures; independent Director study is separate."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[2]
for folder in ["tools/build","tools/workspace","tools/presentation","tools/capture"]:sys.path.insert(0,str(ROOT/folder))
import windows_checkpoint as pipeline
import workspace
from rpm_economy_study_003a1 import source, profile
from presentation_showcase import movie_metadata
from combat_art003a1 import frozen_project

def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--diagnostic",action="store_true")
    parser.add_argument("--engine");parser.add_argument("--ffmpeg")
    args=parser.parse_args()
    qa=workspace.create_task_workspace("003A.1")
    base="003a1_deep_run_escalation"
    stem=base+"_"+datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    report=qa/"manifests"/(stem+".json");raw=qa/"temp"/(stem+".avi");video=qa/"video"/(base+".mp4");frames=qa/"frames"/stem
    assert args.diagnostic or not video.exists(),"Preserve previous final movie"
    original_player=profile();stage,original,frozen=frozen_project(qa,stem)
    driver=stage/"tests/capture_deep_run_density_003a1.gd";driver_sha=pipeline.sha256(driver)
    command=[workspace.find_tool("godot",args.engine),"--path",str(stage),"--script","res://tests/capture_deep_run_density_003a1.gd"]
    command += ["--headless"] if args.diagnostic else ["--resolution","640x400","--fixed-fps","60","--disable-vsync","--write-movie",str(raw),"--audio-driver","Dummy"]
    command += ["--","--manifest="+str(report),"--frames="+str(frames)]
    if args.diagnostic:command += ["--diagnostic"]
    process=pipeline.run_logged(command,qa/"logs"/(stem+".log"),1200)
    data=json.loads(report.read_text());assert not data["failures"],data["failures"]
    assert data["movie_frames"]==1800+(0 if args.diagnostic else 36)
    assert len(data["scenes"])==5 and [s["peak_active_full"] for s in data["scenes"]]==[1,3,4,5,6]
    assert source(stage)==frozen and pipeline.sha256(driver)==driver_sha and profile()==original_player
    current=source(ROOT)
    assert current["scripts/threat_director.gd"]==original["scripts/threat_director.gd"],"Owned Director boundary changed"
    data.update(capture_process=process,frozen_project=str(stage),original_production_source=original,frozen_source=frozen,frozen_source_unchanged=True,production_source_unchanged=current==original,owned_director_unchanged=True,driver_sha256=driver_sha,player_before=original_player,player_after=profile(),player_and_backups_unchanged=True,source_git_sha=pipeline.git(ROOT,"rev-parse","HEAD"),source_boundary="Exact coherent capture snapshot; other agents may finish Ghost/UI source afterward. Director policy is frozen and separately measured. This movie is not final changed-Ghost validation.")
    if not args.diagnostic:
        ffmpeg=workspace.find_tool("ffmpeg",args.ffmpeg);info=movie_metadata(ffmpeg,raw)
        command=[ffmpeg,"-v","error","-i",str(raw)]
        if not info["has_audio"]:command += ["-i",str(raw.with_suffix(".wav"))]
        command += ["-map","0:v:0","-map","0:a:0" if info["has_audio"] else "1:a:0","-vf","scale=1280:800:flags=neighbor","-c:v","libx264","-crf","18","-preset","fast","-c:a","aac","-b:a","192k","-pix_fmt","yuv420p","-movflags","+faststart",str(video)]
        encode=pipeline.run_logged(command,qa/"logs"/(stem+"_encode.log"),600)
        decode=pipeline.run_logged([ffmpeg,"-v","error","-i",str(video),"-f","null","-"],qa/"logs"/(stem+"_decode.log"),180)
        metadata=movie_metadata(ffmpeg,video);assert metadata["has_audio"] and abs(metadata["duration_seconds"]-data["movie_frames"]/60)<0.3
        data.update(video=str(video),video_sha256=pipeline.sha256(video),raw_sha256=pipeline.sha256(raw),encoder=encode,decoder=decode,movie_metadata=metadata,editorial="Five labelled six-second scenarios, real fixed60Hz physics at normal playback speed. Native640x360 gameplay +40px outside-play caption strip, integer2x nearest presentation. Actual synchronized Godot music/SFX, no substitute soundtrack or staged activation/state/outcome.")
    pipeline.write_json(report,data)
    print(json.dumps({"passed":True,"manifest":str(report),"video":data.get("video"),"movie_frames":data["movie_frames"],"owned_director_unchanged":True,"player_unchanged":True},indent=2))

if __name__=="__main__":main()
