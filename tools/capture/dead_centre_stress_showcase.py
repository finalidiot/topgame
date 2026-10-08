"""Film genuine mapped controls, physical contacts and production state meters."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import difflib
import json
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


def hashes(root: Path) -> dict[str,str]:
    files = list((root / "scripts").glob("*.gd")) + [p for p in (root / "assets").rglob("*") if p.is_file()]
    files += [root / "tests" / name for name in ("capture_dead_centre_stress.gd","observe_dead_centre_stress.gd","rpm_bot.gd")]
    return {p.relative_to(root).as_posix():pipeline.sha256(p) for p in sorted(files)}


def validate(data: dict, name: str) -> dict:
    assert data["native_view"] == [640,360] and data["movie_frames"] > 60
    assert data["mapped_controller_events"] >= data["movie_frames"] * 4
    assert not data["main_created"] and not data["collection_accessed"]
    rows = data["rows"]
    for row in rows:
        assert row["meters"], "Every visible meter must have an actual production diagnostic"
    proof = {"actual_full_top_contacts":len(data["filmed_impacts"]), "production_meter_snapshots":len(rows),
             "maximum_stress":max(r["powers"].get("anchor_stress",0.0) for r in rows),
             "maximum_redline_heat":max(r["powers"].get("redline_heat",0.0) for r in rows),
             "redline_active_samples":sum(r["powers"].get("redline_time",0.0) > 0.0 for r in rows),
             "anchor_redline_overlap_samples":sum(r["powers"].get("redline_time",0.0) > 0.0 and r["powers"].get("anchor_charge",0.0) >= .7 for r in rows),
             "actual_controlled_vent_samples":sum(bool(r["powers"].get("anchor_venting",False)) for r in rows)}
    assert proof["actual_full_top_contacts"] > 0
    if name == "003a1_dead_center_stress":
        assert proof["maximum_stress"] >= .8 and proof["actual_controlled_vent_samples"] > 0
        assert any(r["powers"].get("anchor_strength",1.0) < .5 for r in rows)
        assert any(r["powers"].get("anchor_stress",1.0) < .2 and r["powers"].get("anchor_charge",0.0) >= .7 for r in rows)
    if name == "003a1_redline_dead_center":
        assert proof["redline_active_samples"] > 0 and proof["anchor_redline_overlap_samples"] > 0
        assert proof["actual_controlled_vent_samples"] > 0
    if name == "003a1_state_meters":
        assert data["full_production_hud"]
        assert max(r["powers"].get("orbit_charge",0.0) for r in rows) >= .7
        assert any(r["powers"].get("drift_active",False) for r in rows)
        assert max(r["powers"].get("sink_charge",0.0) for r in rows) >= 15.0
        assert any(c["end"]["defence"].get("vents",0) > 0 for c in data["cases"])
        assert proof["redline_active_samples"] > 0 and any(r["powers"].get("redline_time",0.0) == 0 for r in rows)
        assert proof["maximum_stress"] >= .35 and proof["actual_controlled_vent_samples"] > 0
    return proof


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan",type=Path,required=True)
    parser.add_argument("--name",required=True)
    parser.add_argument("--base-snapshot",type=Path,required=True)
    parser.add_argument("--qa-root",type=Path)
    parser.add_argument("--engine")
    parser.add_argument("--ffmpeg")
    parser.add_argument("--diagnostic",action="store_true")
    args=parser.parse_args()
    task=workspace.create_task_workspace("003A.1",args.qa_root)
    identity=args.name+"_"+datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    manifest=task / "manifests" / (identity+".json")
    raw=task / "temp" / (identity+".avi")
    frames=task / "frames" / identity
    video=task / "video" / (args.name+".mp4")
    assert args.plan.is_file() and not manifest.exists()
    if not args.diagnostic: assert not video.exists(), "Preserve previous final review movies"
    source=hashes(ROOT)
    profile=pipeline.production_profile(ROOT)
    capture_root=task / "temp" / (identity+"_source")
    shutil.copytree(args.base_snapshot,capture_root)
    for directory in ("scripts","assets"):
        shutil.copytree(ROOT / directory,capture_root / directory,dirs_exist_ok=True)
    # The canonical import was completed after the authored PNG exports.
    # Copy those exact resource caches rather than the historical cache pixels.
    shutil.copytree(ROOT / ".godot",capture_root / ".godot",dirs_exist_ok=True)
    cache_hashes = {p.relative_to(ROOT).as_posix():pipeline.sha256(p) for p in (ROOT / ".godot/imported").glob("*") if p.is_file()}
    assert all(pipeline.sha256(capture_root / name) == value for name,value in cache_hashes.items()), "Imported native asset pixels must match the canonical post-art import"
    for name in ("capture_dead_centre_stress.gd","observe_dead_centre_stress.gd","rpm_bot.gd"):
        shutil.copy2(ROOT / "tests" / name,capture_root / "tests" / name)
    original=(ROOT / "project.godot").read_bytes()
    adjusted=original.replace(b"window/size/window_width_override=1280",b"window/size/window_width_override=640").replace(b"window/size/window_height_override=720",b"window/size/window_height_override=360")
    assert original != adjusted
    (capture_root / "project.godot").write_bytes(adjusted)
    assert hashes(capture_root) == source
    snapshot={"root":str(capture_root),"source_sha256":source,"source_matches_canonical":True,
              "canonical_imported_cache_sha256":cache_hashes,"cache_matches_canonical":True,
              "canonical_project_sha256":pipeline.sha256(ROOT / "project.godot"), "capture_project_sha256":pipeline.sha256(capture_root / "project.godot"),
              "display_only_project_diff":"".join(difflib.unified_diff(original.decode().splitlines(True),adjusted.decode().splitlines(True),fromfile="canonical/project.godot",tofile="QA-native/project.godot"))}
    command=[workspace.find_tool("godot",args.engine),"--path",str(capture_root),"--script","res://tests/capture_dead_centre_stress.gd"]
    command += ["--headless"] if args.diagnostic else ["--resolution","640x360","--fixed-fps","60","--disable-vsync","--write-movie",str(raw),"--audio-driver","Dummy"]
    command += ["--","--manifest="+str(manifest),"--plan="+str(args.plan)]
    command += ["--diagnostic"] if args.diagnostic else ["--frames="+str(frames)]
    process=pipeline.run_logged(command,task / "logs" / (identity+".log"),2400)
    log=Path(process["log"]).read_text(encoding="utf-8",errors="replace")
    assert not any(s in log for s in ("SCRIPT ERROR:","ERROR:","ObjectDB instances were leaked")),log[-5000:]
    data=json.loads(manifest.read_text(encoding="utf-8"))
    proof=validate(data,args.name)
    assert hashes(capture_root) == source, "Frozen gameplay changed during the capture"
    assert profile == pipeline.production_profile(ROOT), "Real player profile changed"
    data.update(native_snapshot=snapshot, capture_process=process, content_proof=proof,
                real_profile_before=profile, real_profile_unchanged=True,
                source_git_sha=pipeline.git(ROOT,"rev-parse","HEAD"),
                working_tree=pipeline.git(ROOT,"status","--porcelain"),
                human_acceptance="Pending review; synthetic mapped pad events do not establish physical controller or phone acceptance.")
    if not args.diagnostic:
        ffmpeg=workspace.find_tool("ffmpeg",args.ffmpeg)
        raw_info=movie_metadata(ffmpeg,raw)
        assert "640x360" in raw_info["metadata"]
        encode=[ffmpeg,"-v","error","-i",str(raw)]
        if not raw_info["has_audio"]: encode += ["-i",str(raw.with_suffix(".wav"))]
        encode += ["-map","0:v:0","-map","0:a:0" if raw_info["has_audio"] else "1:a:0","-vf","scale=1280:720:flags=neighbor",
                   "-c:v","libx264","-crf","18","-preset","fast","-c:a","aac","-b:a","160k","-pix_fmt","yuv420p","-movflags","+faststart",str(video)]
        encoder=pipeline.run_logged(encode,task / "logs" / (identity+"_encode.log"),600)
        decoder=pipeline.run_logged([ffmpeg,"-v","error","-i",str(video),"-f","null","-"],task / "logs" / (identity+"_decode.log"),180)
        info=movie_metadata(ffmpeg,video)
        assert info["has_audio"] and abs(info["duration_seconds"]-data["nominal_seconds"]) < .3
        data.update(video=str(video),video_sha256=pipeline.sha256(video),movie_metadata=info,encoder=encoder,decoder=decoder,raw_movie=str(raw),soundtrack="Unchanged Run music and ordinary actual contact SFX")
    manifest.write_text(json.dumps(data,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"passed":True,"manifest":str(manifest),"video":data.get("video"),"seconds":data["nominal_seconds"],"proof":proof},indent=2))


if __name__ == "__main__": main()
