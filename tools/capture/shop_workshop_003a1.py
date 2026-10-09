"""Film exact frozen Shop/Workshop GUI flows with isolated declared fixtures."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT / "tools/workspace"))
sys.path.insert(0,str(ROOT / "tools/build"))
sys.path.insert(0,str(ROOT / "tools/capture"))
import workspace
import windows_checkpoint as pipeline
from presentation_showcase import movie_metadata
DRIVERS = ("test_shop_ux_003a1.gd","test_collection_ui.gd")

def hashes(project: Path) -> dict:
    paths = [project / "project.godot",project / "main.tscn"]
    paths += list((project / "scripts").rglob("*.gd"))
    paths += [p for p in (project / "assets").rglob("*") if p.is_file()]
    paths += [project / "tests" / name for name in DRIVERS]
    return {str(p.relative_to(project).as_posix()):pipeline.sha256(p) for p in sorted(paths)}

def player() -> dict:
    record = pipeline.production_profile(ROOT)
    directory = Path(record["directory"])
    record["recovery_backups"] = {str(p.relative_to(directory)):pipeline.sha256(p) for p in sorted((directory / "collection-backups").rglob("*")) if p.is_file()}
    return record

def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode",choices=("shop","workshop","all"),required=True)
    parser.add_argument("--diagnostic",action="store_true")
    parser.add_argument("--engine")
    parser.add_argument("--ffmpeg")
    parser.add_argument("--qa-root",type=Path)
    args=parser.parse_args()
    if args.mode=="all" and not args.diagnostic: parser.error("all is the automated contract study; film the separate shop/workshop clips")
    qa=workspace.create_task_workspace("003A.1",args.qa_root)
    identity="003a1_"+args.mode+"_ux_"+datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    snapshot=qa/"temp"/(identity+"_source")
    output=qa/"manifests"/(identity+".json")
    runtime_report=qa/"manifests"/(identity+"_runtime.json")
    profile=qa/"temp"/(identity+"_profile")/"collection.json"
    frames=qa/"frames"/identity
    raw=qa/"temp"/(identity+".avi")
    filename="003a1_bulk_shop_ux.mp4" if args.mode=="shop" else "003a1_workshop_route.mp4"
    video=qa/"video"/filename
    assert not snapshot.exists() and not output.exists() and not profile.exists()
    if not args.diagnostic: assert not video.exists(),"Never overwrite earlier QA evidence"
    before_player=player()
    source=hashes(ROOT)
    provenance={"validation":"started","scope":"Native production GUI input flow with disclosed initial economic/component fixtures; synthetic pad/touch events are not hardware acceptance.","source_git_sha":pipeline.git(ROOT,"rev-parse","HEAD"),"working_tree_at_freeze":pipeline.git(ROOT,"status","--porcelain"),"source_sha256":source,"real_player_before":before_player,"snapshot":str(snapshot),"profile":str(profile),"driver":"tests/test_shop_ux_003a1.gd","mode":args.mode,"diagnostic":args.diagnostic}
    pipeline.write_json(output,provenance)
    snapshot.mkdir()
    for family in ("scripts","assets",".godot"):
        shutil.copytree(ROOT/family,snapshot/family)
    for name in ("project.godot","main.tscn"):
        shutil.copy2(ROOT/name,snapshot/name)
    (snapshot/"tests").mkdir()
    for name in DRIVERS:
        shutil.copy2(ROOT/"tests"/name,snapshot/"tests"/name)
    assert hashes(snapshot)==source==hashes(ROOT),"Source changed during freeze; retained snapshot is excluded"
    profile.parent.mkdir()
    engine=workspace.find_tool("godot",args.engine)
    imported=pipeline.import_source([engine,"--headless","--path",str(snapshot),"--editor","--quit"],qa/"logs"/(identity+"_import"),600)
    after_import=hashes(snapshot)
    assert all(after_import.get(k)==v for k,v in source.items()),"Import cannot alter captured source bytes"
    added={k:v for k,v in after_import.items() if k not in source}
    assert all(k.endswith((".import",".uid")) for k in added),"Only generated import/UID metadata may be added"
    command=[engine,"--path",str(snapshot),"--script","res://tests/test_shop_ux_003a1.gd","--fixed-fps","60","--disable-vsync"]
    command+=(["--headless"] if args.diagnostic else ["--resolution","800x480","--write-movie",str(raw),"--audio-driver","Dummy"])
    command += ["--","--mode="+args.mode,"--report="+str(runtime_report),"--profile="+str(profile),"--frames="+str(frames)]
    if args.diagnostic:command += ["--diagnostic"]
    previous=os.environ.get("TOPGAME_QA_ROOT")
    os.environ["TOPGAME_QA_ROOT"]=str(qa.parent)
    try:process=pipeline.run_logged(command,qa/"logs"/(identity+".log"),900)
    finally:
        if previous is None:os.environ.pop("TOPGAME_QA_ROOT",None)
        else:os.environ["TOPGAME_QA_ROOT"]=previous
    data=json.loads(runtime_report.read_text(encoding="utf-8"))
    assert data["failures"]==0 and data["checks"]>100
    assert hashes(snapshot)==after_import and player()==before_player
    assert data["profile"]==str(profile) and pipeline.sha256(profile)==data["profile_sha256"]
    if args.mode in ("shop","all"):
        assert [(r["kind"],r["quantity"]) for r in data["receipts"]]==[("standard",3),("reclaimed",3)]
        assert data["final_wallet"]["credits"]==856
    if args.mode in ("workshop","all"):assert data["final_build"]["ratchet"]=="kickback"
    provenance.update(runtime_report=str(runtime_report),runtime_report_sha256=pipeline.sha256(runtime_report),runtime=data,imported=imported,process=process,source_unchanged=True,generated_import_metadata=added,real_player_after=player(),real_player_unchanged=True,validation="passed")
    if not args.diagnostic:
        ffmpeg=workspace.find_tool("ffmpeg",args.ffmpeg)
        metadata=movie_metadata(ffmpeg,raw)
        crop=next(iter(data["images"].values()))["crop"]
        assert all(image["crop"]==crop for image in data["images"].values())
        filters=[f"crop=640:360:{crop[0]}:{crop[1]}","scale=1280:720:flags=neighbor","pad=1280:760:0:0:color=0x10151f"]
        for phase in data["phases"]:
            text=phase["name"].replace("_"," ").upper()
            filters.append("drawtext=fontfile='C\\:/Windows/Fonts/consola.ttf':text='"+text+"':x=12:y=730:fontsize=18:fontcolor=0xd8e3dc:enable='between(t,"+f"{phase['from_frame']/60:.6f},{phase['to_frame']/60:.6f}"+")'")
        filters.append("drawtext=fontfile='C\\:/Windows/Fonts/consola.ttf':text='ISOLATED WALLET AND OWNERSHIP FIXTURES / AUTOMATED INPUTS':x=12:y=748:fontsize=10:fontcolor=0x81939c")
        command=[ffmpeg,"-v","error","-i",str(raw)]
        if not metadata["has_audio"]:command += ["-i",str(raw.with_suffix(".wav"))]
        command += ["-map","0:v:0","-map","0:a:0" if metadata["has_audio"] else "1:a:0","-vf",",".join(filters),"-c:v","libx264","-crf","18","-preset","fast","-pix_fmt","yuv420p","-c:a","aac","-b:a","160k","-movflags","+faststart",str(video)]
        encoded=pipeline.run_logged(command,qa/"logs"/(identity+"_encode.log"),600)
        decoded=pipeline.run_logged([ffmpeg,"-v","error","-i",str(video),"-f","null","-"],qa/"logs"/(identity+"_decode.log"),180)
        metadata=movie_metadata(ffmpeg,video)
        assert metadata["has_audio"] and abs(metadata["duration_seconds"]-data["seconds"])<.4
        for image in data["images"].values():
            result=pipeline.png_record(Path(image["path"]))
            assert result["width"]==640 and result["height"]==360
        provenance.update(video=str(video),video_sha256=pipeline.sha256(video),movie_metadata=metadata,encoded=encoded,decoded=decoded)
    pipeline.write_json(output,provenance)
    print(json.dumps({"passed":True,"manifest":str(output),"video":provenance.get("video"),"checks":data["checks"],"mode":args.mode},indent=2))

if __name__=="__main__":main()
