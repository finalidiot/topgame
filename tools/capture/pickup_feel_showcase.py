"""Freeze current production source and film actual Main pickup contacts/audio."""
from __future__ import annotations

import argparse
from array import array
from datetime import datetime, timezone
import hashlib
import json
import math
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

DRIVERS = ["capture_pickup_feel_003a1.gd", "test_rpm_playthrough.gd", "rpm_bot.gd"]


def hashes(root: Path) -> dict:
    paths = list((root / "scripts").glob("*.gd")) + [p for p in (root / "assets").rglob("*") if p.is_file()]
    paths += [root / "tests" / name for name in DRIVERS]
    return {p.relative_to(root).as_posix():pipeline.sha256(p) for p in sorted(paths)}


def player() -> dict:
    data = pipeline.production_profile(ROOT)
    path = Path(data["directory"]) if data.get("directory") else None
    data["recovery_backups"] = ({str(p.relative_to(path)):pipeline.sha256(p) for p in sorted((path / "collection-backups").rglob("*")) if p.is_file()}
                                if path is not None else {})
    return data


def audible_receipt(pcm: array, rate: int, channels: int, event_seconds: float) -> dict:
    """Find the actual authored cue inside the movie mix, rather than treating
    background music alone as proof that the collection chirp was audible.
    The small bounded offline correlation is never part of runtime gameplay.
    """
    with wave.open(str(ROOT / "assets/audio/pickup_collect.wav"),"rb") as sample:
        assert sample.getframerate() == rate and sample.getnchannels() == 1
        kernel = [v/32768 for v in array("h", sample.readframes(sample.getnframes()))]
    begin = max(0, int((event_seconds-.12)*rate))
    end = min(len(pcm)//channels, int((event_seconds+.30)*rate)+len(kernel))
    mixed = [sum(pcm[index*channels:(index+1)*channels])/(channels*32768) for index in range(begin,end)]
    square = [0.0]
    for value in mixed: square.append(square[-1]+value*value)
    reference_energy = sum(value*value for value in kernel)
    best, where = -1.0, 0
    stop = min(len(mixed)-len(kernel), int(.24*rate))
    for offset in range(0, stop+1, max(1,rate//4000)):
        actual_energy = square[offset+len(kernel)]-square[offset]
        cross = sum(value*mixed[offset+index] for index,value in enumerate(kernel))
        correlation = cross/math.sqrt(reference_energy*actual_energy+1e-20)
        if correlation > best: best, where = correlation, offset
    assert best > .50, "Actual mixed soundtrack must contain the distinctive authored collection cue"
    return {"authored_cue_normalised_correlation":best,"cue_offset_from_receipt_seconds":(begin+where)/rate-event_seconds,
            "method":"bounded offline waveform correlation against the actual180ms authored pickup sample; verifies the cue itself inside ordinary music/SFX mix"}


def validate(data: dict, rendered: bool) -> dict:
    assert not data["failures"], data["failures"]
    assert data["main_created"] and data["normal_main_floor_audio_routes"] and data["native_view"] == [640,360]
    assert not data["attraction_implemented"] and data["radius_after"] == 18
    assert data["isolated_collection_unchanged_by_combat"]
    assert data["collected"] >= 1 and data["expired"] >= 1
    contacts = [r for r in data["collections"] if r["movie_frame"] >= 0 and r["phase"] == "off_centre_approach"]
    assert contacts and 14 < contacts[0]["actual_swept_gap"] <= 18, "Film must prove the modest added forgiveness with an actual missed-old-radius pass"
    assert any(row["pickup"]["collection_flairs"] for row in data["rows"])
    assert any(any(item["warning"] for item in row["pickup"]["active"]) for row in data["rows"])
    assert any(row["pickup"]["expired"] > 0 for row in data["rows"])
    assert all(row["pickup"]["draw_before_rigs"] and not row["pickup"]["attraction"] for row in data["rows"])
    assert max(len(row["pickup"]["collection_flairs"]) for row in data["rows"]) <= 2
    if rendered:
        assert data["sound_counts"].get("pickup_collect",0) >= 1
        for feature in ("approach", "collection_flair", "collected_floor", "expiry_warning", "expired_floor"):
            assert feature in data["feature_frames"], feature
            record = pipeline.png_record(Path(data["feature_frames"][feature]["path"]))
            assert record["width"] == 640 and record["height"] == 360
    return {"actual_swept_gap":contacts[0]["actual_swept_gap"],"old_radius":14,"new_radius":18,
            "real_clears":len(data["actual_clears"]),"filmed_collections":len(contacts),"expiry_samples":sum(r["pickup"]["expired"]>0 for r in data["rows"]),
            "actual_collection_sound_playbacks":data["sound_counts"].get("pickup_collect",0),"native_flair_visible_samples":sum(bool(r["pickup"]["collection_flairs"]) for r in data["rows"])}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-snapshot", required=True, type=Path)
    parser.add_argument("--qa-root", type=Path)
    parser.add_argument("--engine")
    parser.add_argument("--ffmpeg")
    parser.add_argument("--diagnostic", action="store_true")
    parser.add_argument("--seed", type=int, default=421)
    parser.add_argument("--starter", choices=["breaker","bastion","vane"], default="vane")
    parser.add_argument("--name", default="003a1_pickup_feel")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z0-9_-]+",args.name): parser.error("Use a simple review artifact name")
    if args.seed <= 0: parser.error("Use a positive deterministic Run seed")
    qa = workspace.create_task_workspace("003A.1", args.qa_root)
    identity = args.name+"_"+datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    manifest, raw = qa / "manifests" / (identity+".json"), qa / "temp" / (identity+".avi")
    video, frames = qa / "video" / (args.name+".mp4"), qa / "frames" / identity
    profile_dir = qa / "temp" / (identity+"_profile")
    snapshot = qa / "temp" / (identity+"_source")
    assert not manifest.exists() and not raw.exists() and not snapshot.exists() and not profile_dir.exists()
    if not args.diagnostic: assert not video.exists(), "Preserve existing final reviews"
    profile_dir.mkdir()
    before_player = player()
    source = hashes(ROOT)
    shutil.copytree(args.base_snapshot, snapshot)
    for family in ("scripts","assets",".godot"):
        shutil.copytree(ROOT / family, snapshot / family, dirs_exist_ok=True)
    for name in DRIVERS: shutil.copy2(ROOT / "tests" / name, snapshot / "tests" / name)
    original = (ROOT / "project.godot").read_bytes()
    adjusted = original.replace(b"window/size/window_width_override=1280",b"window/size/window_width_override=640").replace(b"window/size/window_height_override=720",b"window/size/window_height_override=360")
    (snapshot / "project.godot").write_bytes(adjusted)
    assert hashes(snapshot) == source, "Snapshot must match all current transitive game/assets/driver inputs"
    command = [workspace.find_tool("godot",args.engine),"--path",str(snapshot),"--script","res://tests/capture_pickup_feel_003a1.gd"]
    command += (["--headless"] if args.diagnostic else ["--resolution","640x360","--fixed-fps","60","--disable-vsync","--write-movie",str(raw),"--audio-driver","Dummy"])
    command += ["--","--manifest="+str(manifest),"--profile="+str(profile_dir / "collection.json"),"--starter="+args.starter,"--run-seed="+str(args.seed)]
    command += ["--diagnostic"] if args.diagnostic else ["--frames="+str(frames)]
    process = pipeline.run_logged(command, qa / "logs" / (identity+".log"),1200)
    data = json.loads(manifest.read_text(encoding="utf-8"))
    proof = validate(data, not args.diagnostic)
    assert hashes(snapshot) == source, "Frozen capture source changed"
    assert player() == before_player, "Review altered actual player collection, settings or backups"
    data.update(capture_process=process,content_proof=proof,source_sha256=source,source_git_sha=pipeline.git(ROOT,"rev-parse","HEAD"),
                captured_working_tree=pipeline.git(ROOT,"status","--porcelain"),frozen_source=str(snapshot),native_display_only_override=True,
                project_canonical_sha256=hashlib.sha256(original).hexdigest(),project_capture_sha256=hashlib.sha256(adjusted).hexdigest(),
                real_player_before=before_player,real_player_unchanged=True,human_acceptance="Pending; seeded automated control and actual mixed audio do not establish human or physical phone acceptance")
    if not args.diagnostic:
        ffmpeg = workspace.find_tool("ffmpeg",args.ffmpeg)
        raw_meta = movie_metadata(ffmpeg,raw)
        encode = [ffmpeg,"-v","error","-i",str(raw)]
        if not raw_meta["has_audio"]: encode += ["-i",str(raw.with_suffix(".wav"))]
        # The native gameplay image has no caption overlay. A separate lower
        # strip explains each scene without covering the new combat-safe HUD.
        filters = ["scale=1280:720:flags=neighbor","pad=1280:760:0:0:color=0x10151f"]
        captions = {"off_centre_approach":"SLIGHTLY OFF-CENTRE APPROACH / SHORT CHIRP + FLOOR RECEIPT / NO MAGNET",
                    "hold_centre_expiry":"LEAVE THIS ONE ON THE FLOOR / SOFT EXPIRY WARNING / NO COLLECTION BURST"}
        for phase in data["phases"]:
            start, stop = phase["from_frame"]/60, phase["to_frame"]/60
            filters.append("drawtext=fontfile='C\\:/Windows/Fonts/consola.ttf':text='"+captions[phase["phase"]]+"':x=12:y=732:fontsize=16:fontcolor=0xd8e3dc:enable='between(t,"+f"{start:.6f},{stop:.6f}"+")'")
        encode += ["-map","0:v:0","-map","0:a:0" if raw_meta["has_audio"] else "1:a:0","-vf",",".join(filters),
                   "-c:v","libx264","-crf","18","-preset","fast","-pix_fmt","yuv420p","-c:a","aac","-b:a","160k","-movflags","+faststart",str(video)]
        encoder = pipeline.run_logged(encode,qa / "logs" / (identity+"_encode.log"),600)
        decoder = pipeline.run_logged([ffmpeg,"-v","error","-i",str(video),"-f","null","-"],qa / "logs" / (identity+"_decode.log"),180)
        metadata = movie_metadata(ffmpeg,video)
        assert metadata["has_audio"] and abs(metadata["duration_seconds"]-data["nominal_seconds"]) < .3
        mix = qa / "temp" / (identity+"_actual_mix.wav")
        decoded_audio = pipeline.run_logged([ffmpeg,"-v","error","-i",str(video),"-map","0:a:0","-c:a","pcm_s16le",str(mix)],qa / "logs" / (identity+"_mix.log"),120)
        with wave.open(str(mix),"rb") as stream:
            rate, channels = stream.getframerate(), stream.getnchannels()
            pcm = array("h",stream.readframes(stream.getnframes()))
        contact = next(row for row in data["collections"] if row["phase"] == "off_centre_approach" and row["movie_frame"] >= 0)
        start = int(contact["movie_frame"]/60*rate)*channels
        segment = pcm[start:start+int(rate*.35)*channels]
        rms = math.sqrt(sum(value*value for value in segment)/len(segment))/32768
        assert rms > .001, "Actual collection window must contain audible game mix"
        cue_proof = audible_receipt(pcm,rate,channels,contact["movie_frame"]/60)
        data.update(video=str(video),video_sha256=pipeline.sha256(video),movie_metadata=metadata,encoder=encoder,decoder=decoder,
                    raw_movie=str(raw),raw_sha256=pipeline.sha256(raw),actual_mixed_audio=str(mix),mixed_audio_sha256=pipeline.sha256(mix),
                    decoded_audio=decoded_audio,collection_window_rms=rms,collection_audio_proof=cue_proof,soundtrack="Actual movie-writer mix of unchanged accepted Run music and ordinary event SFX; no replacement audio",
                    editorial="Native640x360 game rendered untouched, enlarged integer2x nearest to1280x720 with a separate40px caption strip. Only executed unrendered warmup gaps omitted between the two labelled actual-contact/expiry scenes.")
    manifest.write_text(json.dumps(data,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"passed":True,"manifest":str(manifest),"video":data.get("video"),"seconds":data["nominal_seconds"],"proof":proof},indent=2))


if __name__ == "__main__": main()
