"""Real input-driven003A progression loop and seeded physical packet review.

All collection/settings writes use fresh external QA files. The full loop starts
with exactly three starter parts and zero wallet. Showcase fixtures are labelled.
"""
from __future__ import annotations

import argparse
from array import array
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import shutil
import sys
import wave

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/workspace"))
import workspace
sys.path.insert(0, str(ROOT / "tools/build"))
import windows_checkpoint as pipeline
sys.path.insert(0, str(ROOT / "tools/capture"))
from presentation_showcase import movie_metadata


def validate(data: dict, visible: bool) -> None:
    assert data["task"] == "003A" and data["native_view"] == [640, 360]
    assert all(row["type"] in ["key", "joy_button", "joy_axes", "gui_mouse_click"] for row in data["input_events"])
    assert all(len(receipt["rows"]) == 3 and receipt["status"] == "resolved" for receipt in data["receipts"])
    if data["showcase"]:
        assert data["fixture"]["initial_credits"] == 600 and data["fixture"]["initial_owned"] == 3
        assert len(data["receipts"]) == 2 and data["receipts"][0]["rows"] == data["fixture"]["preview"]["rows"]
        first = data["receipts"][0]["rows"]
        assert any(row["rarity"] == "COMMON" for row in first)
        assert any(row["rarity"] in ["RARE", "EPIC", "LEGENDARY"] for row in first)
        assert any(row["new"] for row in first) and any(not row["new"] for row in first)
        assert data["final_collection"]["progression"]["salvage"] > 0
    else:
        assert not data["fixture"] and data["collection_before"]["total_owned"] == 3
        assert data["collection_before"]["progression"]["credits"] == 0
        assert 1 <= len(data["natural_results"]) <= 2
        assert sum(int(result["credits_earned"]) for result in data["natural_results"]) >= int(data["economy_config"]["packets"]["standard"]["cost"])
        for result in data["natural_results"]:
            assert result["continuous_run"] and not result["won"] and not result["reward_fixture"]
            assert result["reward_provenance"] == "earned-clear-v1"
        assert len(data["receipts"]) == 1
        assert data["collection_after"]["total_owned"] > 3
        row = data["equipped_new"]
        assert row["new"] and data["final_collection"]["equipped_build"][row["category"]] == row["id"]
    if visible:
        for name in ["shop_native", "packet_sealed", "packet_crinkle", "packet_tear", "packet_spill", "packet_result"]:
            assert pipeline.png_record(Path(data["images"][name]["path"]))["width"] == 640


def preserve_target(path: Path, name: str) -> Path:
    return path if not path.exists() else path.with_name(name + "_" + path.name)


def native_images(data: dict, task: Path, name: str) -> dict:
    font = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 16)
    result = {}
    shop = preserve_target(task / "images/003a_shop_native.png", name)
    shutil.copyfile(data["images"]["shop_native"]["path"], shop)
    result["shop_native"] = str(shop)
    keys = ["packet_sealed", "packet_crinkle", "packet_tear", "packet_spill", "packet_result"]
    sheet = Image.new("RGB", (640 * len(keys), 386), (20, 25, 32))
    draw = ImageDraw.Draw(sheet)
    for index, key in enumerate(keys):
        label = key.removeprefix("packet_").upper()
        if data["showcase"]:
            label += " / QA SEED " + str(data["fixture"]["seed"])
        draw.text((index * 640 + 10, 4), label, fill=(232, 236, 225), font=font)
        pixels = Image.open(data["images"][key]["path"]).convert("RGB")
        assert pixels.size == (640, 360)
        sheet.paste(pixels, (index * 640, 26))
    sequence = preserve_target(task / "images/003a_packet_sequence.png", name)
    sheet.save(sequence)
    result["packet_sequence"] = str(sequence)
    if "packet_odds" in data["images"]:
        odds = preserve_target(task / "images/003a_packet_odds.png", name)
        shutil.copyfile(data["images"]["packet_odds"]["path"], odds)
        result["packet_odds"] = str(odds)
    if "packet_reclaimed_odds" in data["images"]:
        odds = preserve_target(task / "images/003a_reclaimed_packet_odds.png", name)
        shutil.copyfile(data["images"]["packet_reclaimed_odds"]["path"], odds)
        result["reclaimed_packet_odds"] = str(odds)
    if not data["showcase"]:
        proof = Image.new("RGB", (1280, 386), (20, 25, 32))
        draw = ImageDraw.Draw(proof)
        for index, key in enumerate(["collection_before", "collection_after"]):
            snapshot = data[key]
            caption = f"{'BEFORE' if index == 0 else 'AFTER REAL PACKET'} / {snapshot['total_owned']} OWNED DESIGNS"
            draw.text((index * 640 + 10, 4), caption, fill=(232, 236, 225), font=font)
            proof.paste(Image.open(data["images"][key]["path"]).convert("RGB"), (index * 640, 26))
        target = preserve_target(task / "images/003a_collection_progress.png", name)
        proof.save(target)
        result["collection_progress"] = str(target)
    return result


def edit_spans(data: dict) -> list[tuple[int, int]]:
    end = int(data["raw_frames"]) - 1
    if data["showcase"]:
        assert 20 <= end / 60 <= 45, f"Showcase chronology is {end / 60:.2f}s"
        return [(0, end)]
    spans = []
    long_sections = []
    for section in data["sections"]:
        start, stop = int(section["from_frame"]), min(int(section["to_frame"]), end)
        if stop <= start:
            continue
        if (section["name"].endswith("_natural_play") or section["name"].endswith("_earned_target")) and stop - start > 900:
            spans.extend([(start, start + 480), (stop - 360, stop)])
            long_sections.append((start + 480, stop - 360))
        else:
            spans.append((start, stop))
    retained = sum(stop - start for start, stop in spans)
    if retained < 3900:
        for start, stop in long_sections:
            addition = min(stop - start, 3900 - retained)
            if addition > 0:
                spans.append((start, start + addition))
                retained += addition
            if retained >= 3900:
                break
    spans.sort()
    merged = []
    for start, stop in spans:
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(stop, merged[-1][1]))
        else:
            merged.append((start, stop))
    seconds = sum(stop - start for start, stop in merged) / 60
    assert 60 <= seconds <= 120, f"Progression chronological edit is {seconds:.2f}s"
    return merged


def encode(data: dict, raw: Path, target: Path, task: Path, name: str, ffmpeg: str) -> dict:
    raw_metadata = movie_metadata(ffmpeg, raw)
    args = [ffmpeg, "-v", "error", "-i", str(raw)]
    stream = "0:a"
    sidecar = raw.with_suffix(".wav")
    if not raw_metadata["has_audio"]:
        assert sidecar.is_file(), "Actual MovieMaker mixed audio is required"
        args.extend(["-i", str(sidecar)])
        stream = "1:a"
    spans = edit_spans(data)
    filters = []
    for index, (start, stop) in enumerate(spans):
        label = (f"SEEDED QA WALLET AND PACKET RNG / SEED {data['fixture']['seed']} / ACTUAL PRODUCTION OPENING" if data["showcase"] else f"NORMAL SAVE / REAL RUN REWARDS / CHRONOLOGICAL EXCERPT / RAW {start / 60:.1f}s")
        filters.append(f"[0:v]trim=start_frame={start}:end_frame={stop},setpts=PTS-STARTPTS,scale=1280:720:flags=neighbor,drawtext=fontfile='C\\:/Windows/Fonts/consola.ttf':text='{label}':x=12:y=702:fontsize=12:fontcolor=white:box=1:boxcolor=black@0.75[v{index}]")
        filters.append(f"[{stream}]atrim=start={start / 60:.8f}:end={stop / 60:.8f},asetpts=PTS-STARTPTS[a{index}]")
    filters.append("".join(f"[v{i}][a{i}]" for i in range(len(spans))) + f"concat=n={len(spans)}:v=1:a=1[v][a]")
    args.extend(["-filter_complex", ";".join(filters), "-map", "[v]", "-map", "[a]", "-c:v", "libx264", "-crf", "18", "-preset", "fast", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-movflags", "+faststart", str(target)])
    encoder = pipeline.run_logged(args, task / "logs" / (name + "_encode.log"), 600)
    decoder = pipeline.run_logged([ffmpeg, "-v", "error", "-i", str(target), "-f", "null", "-"], task / "logs" / (name + "_decode.log"), 300)
    metadata = movie_metadata(ffmpeg, target)
    expected = sum(stop - start for start, stop in spans) / 60
    assert metadata["has_audio"] and abs(metadata["duration_seconds"] - expected) < 0.25
    pcm_path = task / "temp" / (name + "_actual_mix.wav")
    pipeline.run_logged([ffmpeg, "-v", "error", "-i", str(target), "-map", "0:a:0", "-c:a", "pcm_s16le", str(pcm_path)], task / "logs" / (name + "_audio.log"), 120)
    with wave.open(str(pcm_path), "rb") as recording:
        assert recording.getnchannels() == 2 and recording.getframerate() == 48000
        samples = array("h", recording.readframes(recording.getnframes()))
    peak = max(abs(value) for value in samples) / 32768
    rms = math.sqrt(sum(value * value for value in samples) / len(samples)) / 32768
    assert rms > 0.001 and 0.005 < peak < 0.99
    return {"video":str(target), "video_sha256":pipeline.sha256(target), "seconds":metadata["duration_seconds"], "raw_movie":str(raw), "raw_sha256":pipeline.sha256(raw), "raw_audio_sidecar":str(sidecar) if sidecar.exists() else None, "actual_audio_pcm":str(pcm_path), "actual_audio_sha256":pipeline.sha256(pcm_path), "audio_peak":peak, "audio_rms":rms, "encoder":encoder, "decoder":decoder, "chronological_spans":[{"from_frame":start, "to_frame":stop} for start, stop in spans], "editorial":"Actual input/physics/production packet opening and mixed music/SFX. Chronological omissions labelled. Native640x360 enlarged integer2x nearest. No altered game imagery or replacement audio."}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine")
    parser.add_argument("--ffmpeg")
    parser.add_argument("--qa-root", type=Path)
    parser.add_argument("--diagnostic", action="store_true")
    parser.add_argument("--showcase", action="store_true")
    parser.add_argument("--seed", type=int, default=421)
    parser.add_argument("--max-run-seconds", type=float, default=300)
    parser.add_argument("--bot-style", choices=["hybrid", "aggressive", "defensive"], default="hybrid")
    args = parser.parse_args()
    task = workspace.create_task_workspace("003A", args.qa_root)
    mode = "packet" if args.showcase else "progression"
    name = "003a_" + mode + ("_diagnostic_" if args.diagnostic else "_capture_") + datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    output = task / "manifests" / (name + ".json")
    raw = task / "temp" / (name + ".avi")
    frame_dir = task / "frames" / name
    target = preserve_target(task / "video" / ("003a_packet_opening_showcase.mp4" if args.showcase else "003a_full_progression_loop.mp4"), name)
    profile_before = pipeline.production_profile(ROOT)
    files = [*sorted(ROOT.glob("scripts/*.gd")), ROOT / "assets/data/packet_economy.json", ROOT / "assets/data/parts_catalogue.json", ROOT / "tests/capture_progression_003a.gd", Path(__file__).resolve()]
    source_before = {path.relative_to(ROOT).as_posix():pipeline.sha256(path) for path in files}
    (task / "manifests" / (name + "_inputs.json")).write_text(json.dumps({"source_git_sha":pipeline.git(ROOT, "rev-parse", "HEAD"), "source_sha256":source_before, "profile_before":profile_before}, indent=2) + "\n")
    command = [workspace.find_tool("godot", args.engine), "--path", str(ROOT), "--script", "res://tests/capture_progression_003a.gd", "--fixed-fps", "60", "--disable-vsync"]
    command.extend(["--headless"] if args.diagnostic else ["--write-movie", str(raw), "--audio-driver", "Dummy"])
    command.extend(["--", "--manifest=" + str(output), "--collection=" + str(task / "temp" / (name + "_collection.json")), "--qa-task=003A", "--run-seed=" + str(args.seed), "--max-run-seconds=" + str(args.max_run_seconds), "--bot-style=" + args.bot_style])
    command.extend(["--diagnostic"] if args.diagnostic else ["--frames=" + str(frame_dir)])
    if args.showcase:
        command.append("--showcase")
    print("INPUT_DRIVEN_003A_CAPTURE " + name, flush=True)
    process = pipeline.run_logged(command, task / "logs" / (name + ".log"), 1200)
    data = json.loads(output.read_text())
    validate(data, not args.diagnostic)
    profile_after = pipeline.production_profile(ROOT)
    assert profile_before == profile_after, "Player collection/settings fingerprints changed"
    source_after = {path.relative_to(ROOT).as_posix():pipeline.sha256(path) for path in files}
    if not args.diagnostic:
        assert source_before == source_after, "Freeze recording inputs until capture completes"
        data["native_images"] = native_images(data, task, name)
        data.update(encode(data, raw, target, task, name, workspace.find_tool("ffmpeg", args.ffmpeg)))
    data.update(capture_process=process, source_git_sha=pipeline.git(ROOT, "rev-parse", "HEAD"), source_sha256=source_after, capture_source_unchanged=source_before == source_after, profile_before=profile_before, profile_after=profile_after, profile_unchanged=True, working_tree=pipeline.git(ROOT, "status", "--porcelain"))
    output.write_text(json.dumps(data, indent=2) + "\n")
    print(json.dumps({"passed":True, "manifest":str(output), "video":data.get("video"), "native_images":data.get("native_images"), "profile_unchanged":True, "natural_runs":len(data["natural_results"]), "packets":len(data["receipts"])}, indent=2))


if __name__ == "__main__":
    main()
