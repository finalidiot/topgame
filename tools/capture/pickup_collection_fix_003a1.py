"""Film all eight independently spawned pickups with actual fixed-solver steering."""
from __future__ import annotations

import argparse
from array import array
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import sys
import wave

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/workspace"))
sys.path.insert(0, str(ROOT / "tools/build"))
sys.path.insert(0, str(ROOT / "tools/capture"))
import workspace
import windows_checkpoint as pipeline
from presentation_showcase import movie_metadata
from pickup_feel_showcase import audible_receipt

DRIVERS = ["capture_pickup_collection_fix_003a1.gd", "test_pickup_positions_003a1.gd"]

def hashes(root: Path) -> dict:
    paths = list((root / "scripts").glob("*.gd")) + [p for p in (root / "assets").rglob("*") if p.is_file()]
    paths += [root / "tests" / name for name in DRIVERS]
    return {p.relative_to(root).as_posix(): pipeline.sha256(p) for p in sorted(paths)}

def player() -> dict:
    data = pipeline.production_profile(ROOT)
    directory = Path(data["directory"]) if data.get("directory") else None
    data["backups"] = ({str(p.relative_to(directory)):pipeline.sha256(p) for p in sorted((directory / "collection-backups").rglob("*")) if p.is_file()}
                       if directory is not None else {})
    return data

def validate(data: dict, rendered: bool) -> dict:
    assert not data["failures"], data["failures"]
    assert data["radius"] == 18 and data["no_main_or_player_save_opened"] and data["native_view"] == [640,360]
    paths = [p for p in data["phases"] if p["case"] != "wallet_full"]
    assert len(paths) == 16 and all(sum(p["point_index"] == i for p in paths) == 2 for i in range(8))
    assert all(p["collection"] and p["nearest_world_distance"] > 18 for p in paths)
    assert all(p["collection"]["pickup"]["collection_flairs"] for p in paths)
    assert all(p["collection"]["pickup"]["draw_before_rigs"] for p in paths)
    full = [r for r in data["rows"] if r["case"] == "wallet_full"]
    assert full and all(not r["pickup"]["active"] and r["rerolls"] == 6 and r["collected"] == 0 for r in full)
    if rendered:
        assert data["sound_counts"].get("pickup_collect",0) == 16
        for p in paths:
            for suffix in ("before","receipt"):
                frame = data["feature_frames"][p["case"]+"_"+suffix]
                record = pipeline.png_record(Path(frame["path"]))
                assert (record["width"], record["height"]) == (640,360)
    return {"spawn_points":8,"actual_solver_traversals":16,"old_floor_only_misses":16,
            "world_radius_unchanged":18,"nearest_world_distance_min":min(p["nearest_world_distance"] for p in paths),
            "nearest_world_distance_max":max(p["nearest_world_distance"] for p in paths),
            "actual_collection_cues":data["sound_counts"].get("pickup_collect",0),"capacity_no_fake_drop":True}

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-snapshot", required=True, type=Path)
    parser.add_argument("--qa-root",type=Path)
    parser.add_argument("--engine")
    parser.add_argument("--ffmpeg")
    parser.add_argument("--diagnostic",action="store_true")
    args = parser.parse_args()
    qa = workspace.create_task_workspace("003A.1",args.qa_root)
    identity = "003a1_pickup_collection_fix_"+datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    report = qa / "manifests" / (identity+".json")
    raw, snapshot = qa / "temp" / (identity+".avi"), qa / "temp" / (identity+"_source")
    frames, video = qa / "frames" / identity, qa / "video" / "003a1_pickup_collection_fix.mp4"
    assert not report.exists() and not snapshot.exists() and not raw.exists()
    if not args.diagnostic: assert not video.exists(), "Preserve previous review videos; use a fresh required output only"
    before_player, source = player(), hashes(ROOT)
    shutil.copytree(args.base_snapshot,snapshot)
    for family in ("scripts","assets",".godot"):
        shutil.copytree(ROOT / family,snapshot / family,dirs_exist_ok=True)
    for name in DRIVERS:shutil.copy2(ROOT / "tests" / name,snapshot / "tests" / name)
    canonical_project = (ROOT / "project.godot").read_bytes()
    capture_project = canonical_project.decode("utf-8")
    for key,value in {"viewport_width":640,"viewport_height":360,"window_width_override":640,
                      "window_height_override":360,"min_width":640,"min_height":360}.items():
        capture_project = re.sub(r"^window/size/"+key+r"=.*$","window/size/"+key+"="+str(value),capture_project,flags=re.MULTILINE)
    (snapshot / "project.godot").write_bytes(capture_project.encode("utf-8"))
    assert hashes(snapshot) == source and hashes(ROOT) == source, "Source changed while freezing fixture; retry in a fresh directory"
    command = [workspace.find_tool("godot",args.engine),"--path",str(snapshot),"--script","res://tests/capture_pickup_collection_fix_003a1.gd"]
    command += (["--headless"] if args.diagnostic else ["--resolution","640x360","--fixed-fps","60","--disable-vsync","--write-movie",str(raw),"--audio-driver","Dummy"])
    command += ["--","--report="+str(report)]
    command += ["--diagnostic"] if args.diagnostic else ["--frames="+str(frames)]
    process = pipeline.run_logged(command,qa / "logs" / (identity+".log"),1200)
    data = json.loads(report.read_text(encoding="utf-8"))
    proof = validate(data,not args.diagnostic)
    assert hashes(snapshot) == source, "Frozen capture source changed"
    assert player() == before_player, "Native review changed actual player data"
    data.update(capture_process=process,content_proof=proof,source_sha256=source,
                source_git_sha=pipeline.git(ROOT,"rev-parse","HEAD"),captured_working_tree=pipeline.git(ROOT,"status","--porcelain"),
                frozen_source=str(snapshot),project_canonical_sha256=hashlib.sha256(canonical_project).hexdigest(),
                project_capture_sha256=hashlib.sha256(capture_project.encode("utf-8")).hexdigest(),native_fixture_display_override=True,
                real_player_before=before_player,real_player_unchanged=True,
                human_acceptance="Pending; automated actual-solver steering and explicit drop/starting-pose fixtures")
    if not args.diagnostic:
        ffmpeg = workspace.find_tool("ffmpeg",args.ffmpeg)
        raw_meta = movie_metadata(ffmpeg,raw)
        filters = ["scale=1280:720:flags=neighbor","pad=1280:768:0:0:color=0x10151f"]
        for p in data["phases"]:
            label = ("FULL WALLET 6/6 - NO IMPOSSIBLE FLOOR DROP" if p["case"] == "wallet_full" else
                     "SPAWN %d/8 %s - REAL STEERING / VISIBLE BLADE CONTACT / WORLD RADIUS 18" %
                     (p["point_index"]+1,"FORWARD" if p["case"].endswith("forward") else "REVERSE"))
            filters.append("drawtext=fontfile='C\\:/Windows/Fonts/consola.ttf':text='"+label+"':x=12:y=728:fontsize=16:fontcolor=0xd8e3dc:enable='between(t,"+
                           f"{p['from_frame']/60:.6f},{p['to_frame']/60:.6f}"+")'")
        filters.append("drawtext=fontfile='C\\:/Windows/Fonts/consola.ttf':text='EXPLICIT DROP + START POSE FIXTURES / FIXED SOLVER / NO PLAYER SAVE':x=12:y=749:fontsize=12:fontcolor=0x94a4ae")
        encode = [ffmpeg,"-v","error","-i",str(raw)]
        if not raw_meta["has_audio"]: encode += ["-i",str(raw.with_suffix(".wav"))]
        encode += ["-map","0:v:0","-map","0:a:0" if raw_meta["has_audio"] else "1:a:0","-vf",",".join(filters),
                   "-c:v","libx264","-crf","18","-preset","fast","-pix_fmt","yuv420p","-c:a","aac","-b:a","160k","-movflags","+faststart",str(video)]
        encoder = pipeline.run_logged(encode,qa / "logs" / (identity+"_encode.log"),600)
        decoder = pipeline.run_logged([ffmpeg,"-v","error","-i",str(video),"-f","null","-"],qa / "logs" / (identity+"_decode.log"),180)
        meta = movie_metadata(ffmpeg,video)
        assert meta["has_audio"] and abs(meta["duration_seconds"]-data["nominal_seconds"])<.3
        mix = qa / "temp" / (identity+"_actual_mix.wav")
        decoded_audio = pipeline.run_logged([ffmpeg,"-v","error","-i",str(video),"-map","0:a:0","-c:a","pcm_s16le",str(mix)],
                                           qa / "logs" / (identity+"_mix.log"),120)
        with wave.open(str(mix),"rb") as stream:
            pcm = array("h",stream.readframes(stream.getnframes()))
            audio_proof = audible_receipt(pcm,stream.getframerate(),stream.getnchannels(),data["phases"][0]["collection"]["movie_frame"]/60)
        data.update(video=str(video),video_sha256=pipeline.sha256(video),movie_metadata=meta,encoder=encoder,decoder=decoder,
                    raw_movie=str(raw),raw_sha256=pipeline.sha256(raw),
                    actual_mixed_audio=str(mix),mixed_audio_sha256=pipeline.sha256(mix),decoded_audio=decoded_audio,collection_audio_proof=audio_proof,
                    soundtrack="Actual native production Sound event route. No replacement audio/music.",
                    editorial="Native640x360 raster enlarged exactly2x nearest; captions in a separate48px lower strip, never over combat. Explicit independent fixtures, all8 points/both directions and full-capacity contrast. No natural drop-earning or human/controller acceptance claim.")
    report.write_text(json.dumps(data,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"passed":True,"manifest":str(report),"video":data.get("video"),"proof":proof},indent=2))

if __name__ == "__main__":main()
