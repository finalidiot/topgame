"""Fresh decorated client-fill evidence; no prior human footage is reused."""
from __future__ import annotations
from datetime import datetime, timezone
import argparse
import json
from pathlib import Path
import shutil
import sys
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "tools/build"), str(ROOT / "tools/workspace"), str(ROOT / "tools/capture")]
import workspace
import windows_checkpoint as pipeline
from native_window_003a1 import hashes, player, display_frame, PHASES, DRIVERS
from presentation_showcase import movie_metadata

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--revision",default="")
    parser.add_argument("--existing-capture",type=Path)
    args=parser.parse_args()
    assert not args.revision or args.revision.replace("_","").isalnum()
    suffix="_"+args.revision if args.revision else ""
    qa = workspace.create_task_workspace("003A.1")
    identity = "003a1_client_fill_" + datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    snapshot = qa / "temp" / (identity + "_source")
    manifest = qa / "manifests" / (identity + ".json")
    report = qa / "manifests" / (identity + "_runtime.json")
    frames = qa / "frames" / identity
    stop = qa / "temp" / (identity + ".stop")
    video = qa / ("video/003a1_maximized_client_fill"+suffix+".mp4")
    matrix = qa / ("images/003a1_window_fill_matrix"+suffix+".png")
    assert not any(p.exists() for p in (snapshot, manifest, report, frames, video, matrix)), "Preserve existing evidence"
    if args.existing_capture:
        original=args.existing_capture.resolve()
        assert original.parent==(qa/"manifests").resolve()
        record=json.loads(original.read_text(encoding="utf-8"))
        source=record["source_hashes"]; before=record["player_before"]
        snapshot=Path(record["snapshot"])
        assert snapshot.resolve().is_relative_to((qa/"temp").resolve())
        report=original.with_name(original.stem+"_runtime.json")
        imported=hashes(snapshot)
        record["reused_capture"]={"initial_manifest":str(original),"sha256":pipeline.sha256(original),
            "scope":"Only current-source raw guarded frames reused. An earlier postcondition demanded pixels in the optional sixth repeat-small stage. The five required resize/Maximise/Restore stages retain genuine native pixels; omitted repeats are declared below."}
    else:
        record, before, source, imported = capture(qa,identity,snapshot,manifest,report,frames,stop)
    assert all(imported.get(k)==v for k,v in source.items())
    assert all(k.endswith((".uid",".import")) for k in imported if k not in source)
    data = json.loads(report.read_text(encoding="utf-8"))
    assert data["world_unchanged"] and data["restore_verified"] and len(data["sequence_events"])==6
    assert data["native_client_pixel_guard"]["maximum_allowed_8bit_difference"]==1
    assert all(f["client_pixel_metrics"]["max"]<=1 for f in data["captured_frames"])
    groups = {phase:[f for f in data["captured_frames"] if f["phase"]==phase and f["phase_elapsed_msec"]>=250] for phase in PHASES}
    assert all(len(groups[phase])>=5 for phase in PHASES[:-1]), "Every required current stage needs real foreground pixels"
    assert all(f["mode"]==(2 if phase=="os_api_maximise" else 0) for phase, group in groups.items() for f in group)
    assert hashes(snapshot)==imported and player()==before
    record["stage_capture_counts"]={phase:len(group) for phase,group in groups.items()}
    record["optional_repeat_small_stage"]="Not required for review; its layout/world state is in the runtime report, and the first small stage supplies verified native pixels. Any omitted cursor/occluded frames are not interpolated or relabelled."
    edited = qa/"temp"/(identity+"_review"); edited.mkdir()
    concat = edited/"timeline.ffconcat"
    lines = ["ffconcat version 1.0"]
    timeline = []
    for index, frame in enumerate(data["captured_frames"]):
        output = edited/("frame_%05d.png"%index)
        display_frame(Path(frame["path"]),frame["phase"].replace("_"," ").upper(),
                      "CURRENT SOURCE / OS API ACTUATION / NATIVE WINDOWS CAPTION / PAUSED GAMEPLAY FIXTURE",output)
        following = data["captured_frames"][index+1] if index+1<len(data["captured_frames"]) else None
        duration = max(.04,min(.25,(following["time_msec"]-frame["time_msec"])/1000)) if following and following["phase"]==frame["phase"] else .12
        lines.extend(["file '"+output.as_posix()+"'","duration %.6f"%duration])
        timeline.append({"source":frame["path"],"sha256":pipeline.sha256(Path(frame["path"])),"seconds":duration,"phase":frame["phase"]})
    lines.append("file '"+output.as_posix()+"'")
    concat.write_text("\n".join(lines)+"\n",encoding="utf-8")
    ffmpeg = workspace.find_tool("ffmpeg")
    record["encode"] = pipeline.run_logged([ffmpeg,"-v","error","-f","concat","-safe","0","-i",str(concat),"-r","30","-c:v","libx264","-crf","17","-preset","fast","-pix_fmt","yuv420p","-movflags","+faststart",str(video)],qa/"logs"/(identity+"_encode.log"),600)
    record["decode"] = pipeline.run_logged([ffmpeg,"-v","error","-i",str(video),"-f","null","-"],qa/"logs"/(identity+"_decode.log"),180)
    selected = ["normal_800x480","larger_1280x800","os_api_maximise","os_api_restore"]
    sheet = Image.new("RGB",(3840,2304),(16,21,31))
    for index, phase in enumerate(selected):
        frame = groups[phase][-1]; tile = edited/("matrix_%d.png"%index)
        display_frame(Path(frame["path"]),phase.replace("_"," ").upper(),
                      "Current source / uniform nearest-neighbour640x360 / HUD outside arena / real OS caption",tile)
        sheet.paste(Image.open(tile),(1920*(index%2),1152*(index//2)))
    sheet.save(matrix)
    record.update(status="passed",runtime_report=str(report),runtime_report_sha256=pipeline.sha256(report),runtime=data,
                  video=str(video),video_sha256=pipeline.sha256(video),movie_metadata=movie_metadata(ffmpeg,video),
                  matrix=str(matrix),matrix_sha256=pipeline.sha256(matrix),timeline=timeline,
                  player_after=player(),player_unchanged=player()==before,frozen_source_unchanged=hashes(snapshot)==imported,
                  canonical_source_unchanged=hashes(ROOT)==source,physical_native_button_acceptance=False)
    pipeline.write_json(manifest,record)
    print(json.dumps({"status":record["status"],"manifest":str(manifest),"video":str(video),"matrix":str(matrix)},indent=2))

def capture(qa,identity,snapshot,manifest,report,frames,stop):
    before = player()
    source = hashes(ROOT)
    record = {"status":"started", "source_sha":pipeline.git(ROOT,"rev-parse","HEAD"),
              "working_tree":pipeline.git(ROOT,"status","--porcelain"), "source_hashes":source,
              "snapshot":str(snapshot), "player_before":before,
              "scope":"Current-source native decorated Windows. Paused legal four-power gameplay fixture. OS APIs actuate resize/Maximise/Restore; no physical button or phone acceptance claim. No historical frames reused."}
    pipeline.write_json(manifest, record)
    snapshot.mkdir()
    for family in ("scripts", "assets", ".godot"): shutil.copytree(ROOT/family, snapshot/family)
    for name in ("project.godot","main.tscn"): shutil.copy2(ROOT/name, snapshot/name)
    (snapshot/"tests").mkdir()
    for name in DRIVERS: shutil.copy2(ROOT/"tests"/name, snapshot/"tests"/name)
    assert hashes(snapshot) == source, "Snapshot must be byte-exact"
    engine = workspace.find_tool("godot")
    record["import"] = pipeline.import_source([engine,"--headless","--path",str(snapshot),"--editor","--quit"],qa/"logs"/(identity+"_import"),600)
    imported = hashes(snapshot)
    assert all(imported.get(k)==v for k,v in source.items())
    assert all(k.endswith((".uid",".import")) for k in imported if k not in source)
    command = [engine,"--path",str(snapshot),"--script","res://tests/"+DRIVERS[0],"--audio-driver","Dummy","--",
               "--auto-sequence","--report="+str(report),"--stop-file="+str(stop),"--frames="+str(frames)]
    record["capture"] = pipeline.run_logged(command,qa/"logs"/(identity+"_capture.log"),90)
    return record,before,source,imported

if __name__=="__main__": main()
