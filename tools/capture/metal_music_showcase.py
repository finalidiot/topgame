"""Capture a labelled native synchronized-player music audition, never gameplay.

Run with the bundled Python (NumPy/Pillow). Wait for composition and Music.gd
to freeze. Six continuous nine-second phases keep a single audio transport;
Run observations are explicitly labelled fixtures on every native video frame.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import wave

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/workspace"))
import workspace
sys.path.insert(0, str(ROOT / "tools/build"))
import windows_checkpoint as pipeline

STEMS = ["title", "workshop", "run_base", "run_pressure", "run_boss"]
PHASES = ["title", "workshop", "opening_run", "middle_run", "late_anthem", "boss_cue_audition"]
SOURCE_FILES = ["scripts/music.gd", "scripts/sound.gd", "scripts/menus.gd", "scripts/front_end.gd", "scripts/top_preview.gd", "tests/capture_metal_music.gd", "tools/capture/metal_music_showcase.py", "tools/audio/compose_foundation.py", "assets/audio/music/foundation_score.json", "assets/audio/music/manifest.json"]
SOURCE_FILES += [f"assets/audio/music/{name}.wav" for name in STEMS]
SOURCE_FILES += [f"assets/audio/music/{name}.wav.import" for name in STEMS]


def read_pcm(path: Path) -> tuple[np.ndarray, dict]:
    with wave.open(str(path), "rb") as source:
        channels, width, rate, frames = source.getnchannels(), source.getsampwidth(), source.getframerate(), source.getnframes()
        raw = source.readframes(frames)
    assert width == 2 and channels == 2, "Native stereo PCM16 is required"
    samples = np.frombuffer(raw, dtype="<i2").astype(np.float64).reshape(-1, channels) / 32768.0
    return samples, {"sample_rate": rate, "channels": channels, "sample_width": width, "frames": frames, "pcm_sha256": hashlib.sha256(raw).hexdigest(), "file_sha256": pipeline.sha256(path)}


def signal_metrics(samples: np.ndarray, rate: int) -> dict:
    assert len(samples) >= 32768
    peak = float(np.max(np.abs(samples)))
    rms = float(np.sqrt(np.mean(samples * samples)))
    size = 32768
    window = np.hanning(size)
    spectrum = np.zeros(size // 2 + 1, dtype=np.float64)
    for offset in range(0, len(samples) - size + 1, size // 2):
        bins = np.fft.rfft(samples[offset:offset + size] * window[:, None], axis=0)
        spectrum += np.sum(np.abs(bins) ** 2, axis=1)
    frequencies = np.fft.rfftfreq(size, 1.0 / rate)
    total = float(np.sum(spectrum))
    bands = [("sub_bass", 20, 160), ("low_mid_body", 160, 700), ("mid_presence", 700, 4000), ("high_presence", 4000, 8000), ("upper_band", 8000, min(15500, rate / 2))]
    shares = {name: float(np.sum(spectrum[(frequencies >= low) & (frequencies < high)]) / max(total, 1e-30)) for name, low, high in bands}
    return {"peak": peak, "rms": rms, "rms_dbfs": 20 * math.log10(max(rms, 1e-12)), "crest_db": 20 * math.log10(max(peak, 1e-12) / max(rms, 1e-12)), "dc_per_channel": [float(v) for v in np.mean(samples, axis=0)], "clipped_samples": int(np.count_nonzero(np.abs(samples) >= 32767 / 32768)), "largest_adjacent_step": float(np.max(np.abs(np.diff(samples, axis=0)))), "spectral_centroid_hz": float(np.sum(spectrum * frequencies) / max(total, 1e-30)), "band_energy_fraction": shares, "upper_20_percent_energy_fraction": float(np.sum(spectrum[frequencies >= rate * 0.4]) / max(total, 1e-30)), "spectral_method": "Stereo-channel power summed across overlapping32768sample Hann FFT windows; band fractions measure spectral distribution, not perceived enjoyment or proof of absence of aliasing."}


def preserve_baseline(task: Path, name: str, reference: str) -> Path:
    folder = task / "temp" / (name + "_baseline")
    folder.mkdir()
    for stem in STEMS:
        result = subprocess.run(["git", "show", f"{reference}:assets/audio/music/{stem}.wav"], cwd=ROOT, capture_output=True, check=True)
        (folder / (stem + ".wav")).write_bytes(result.stdout)
    return folder


def source_review(data: dict, baseline: Path) -> dict:
    results = {}
    native = {item["name"]: item for item in data["native_stems"]}
    lengths = set()
    for stem in STEMS:
        new, new_spec = read_pcm(ROOT / "assets/audio/music" / (stem + ".wav"))
        old, old_spec = read_pcm(baseline / (stem + ".wav"))
        new_metrics = signal_metrics(new, new_spec["sample_rate"])
        old_metrics = signal_metrics(old, old_spec["sample_rate"])
        assert new_metrics["clipped_samples"] == 0
        assert max(abs(v) for v in new_metrics["dc_per_channel"]) < 0.003
        imported = native[stem]
        assert imported["pcm_sha256"] == new_spec["pcm_sha256"], f"Native PCM differs from source {stem}"
        assert imported["mix_rate"] == new_spec["sample_rate"] == 32000
        assert imported["loop_begin"] == 0 and imported["loop_end"] == new_spec["frames"]
        assert imported["pcm_bytes"] == new_spec["frames"] * 4 and imported["stereo"]
        lengths.add(new_spec["frames"])
        body_new = new_metrics["band_energy_fraction"]["low_mid_body"]
        body_old = old_metrics["band_energy_fraction"]["low_mid_body"]
        results[stem] = {"new_pcm": new_spec, "old_pcm": old_spec, "new": new_metrics, "old": old_metrics, "low_mid_share_ratio_new_to_old": body_new / max(body_old, 1e-12), "low_mid_rms_ratio_new_to_old": new_metrics["rms"] * math.sqrt(body_new) / max(old_metrics["rms"] * math.sqrt(body_old), 1e-12)}
    assert len(lengths) == 1
    return {"stems": results, "native_source_pcm_parity": True, "native_synchronized_loop_frames": next(iter(lengths)), "technical_scope": "Checks actual PCM, native imported parity, DC/clipping and spectral/crest comparisons. Upper-band energy can flag a review concern but does not prove synthesis is alias-free. Guitar character, fatigue and enjoyment remain human listening judgments.", "human_subjective_status": "PENDING HOME HUMAN AUDITION"}


def validate(data: dict, diagnostic: bool) -> None:
    assert [p["name"] for p in data["phases"]] == PHASES
    assert not data["collection_opened"] and not data["battle_created"]
    assert data["native_view"] == [640, 360]
    assert "FIXTURES" in data["fixture_label"]
    assert data["music_final"]["asset_errors"] == []
    assert data["music_final"]["transport_starts"] == (0 if diagnostic else 1)
    for phase in data["phases"]:
        assert 539 <= phase["to_frame"] - phase["from_frame"] <= 543
        assert phase["settled_music"]["context"] == (phase["name"] if phase["name"] in ["title", "workshop"] else "run")
    if diagnostic:
        return
    settled = {p["name"]: p["settled_music"] for p in data["phases"]}
    assert settled["middle_run"]["targets"][3] >= 0.5 and settled["middle_run"]["targets"][4] >= 0.25
    assert settled["late_anthem"]["targets"][3] >= 0.75 and settled["late_anthem"]["targets"][4] >= 0.5
    assert settled["boss_cue_audition"]["targets"][4] == 1.0
    assert all(row["music"]["transport_starts"] == 1 for row in data["rows"])
    contexts = [e for e in data["music_final"]["events"] if e["kind"] == "context"]
    assert [e["context"] for e in contexts] == ["title", "workshop", "run"]
    assert data["sfx_final"]["played"].get("heavy") == 1 and data["sfx_final"]["played"].get("low_rpm") == 1
    assert any(row["music"]["duck_left"] > 0 for row in data["rows"])
    for image in data["images"].values():
        assert image["fixture_label"] == data["fixture_label"]
        assert Image.open(image["path"]).size == (640, 360)


def movie_metadata(ffmpeg: str, path: Path) -> dict:
    result = subprocess.run([ffmpeg, "-hide_banner", "-i", str(path)], capture_output=True, text=True)
    match = re.search(r"Duration: (\d+):(\d+):(\d+(?:\.\d+)?)", result.stderr)
    assert match and "Audio:" in result.stderr
    return {"seconds": int(match[1]) * 3600 + int(match[2]) * 60 + float(match[3]), "metadata": result.stderr}


def matrix(data: dict, destination: Path) -> None:
    image = Image.new("RGB", (1920, 772), (16, 21, 31))
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 14)
    for index, name in enumerate(PHASES):
        point = (index % 3 * 640, index // 3 * 386)
        draw.text((point[0] + 8, point[1] + 4), name.replace("_", " ").upper() + " / FIXTURE", font=font, fill=(227, 232, 220))
        image.paste(Image.open(data["images"][name]["path"]).convert("RGB"), (point[0], point[1] + 26))
    image.save(destination)


def export_media(data: dict, raw: Path, task: Path, name: str, ffmpeg: str) -> dict:
    video = task / "video" / "002c6_metal_music_showcase.mp4"
    pcm = task / "video" / "002c6_metal_music_showcase.wav"
    native_matrix = task / "images" / "002c6_metal_music_native_phases.png"
    assert not any(path.exists() for path in [video, pcm, native_matrix]), "Preserve existing media; use a fresh QA task root for another recording"
    raw_meta = movie_metadata(ffmpeg, raw)
    encode = pipeline.run_logged([ffmpeg, "-v", "error", "-i", str(raw), "-vf", "scale=1280:720:flags=neighbor", "-c:v", "libx264", "-crf", "18", "-preset", "fast", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-movflags", "+faststart", str(video)], task / "logs" / (name + "_encode.log"), 240)
    decode = pipeline.run_logged([ffmpeg, "-v", "error", "-i", str(video), "-f", "null", "-"], task / "logs" / (name + "_decode.log"), 120)
    pcm_export = pipeline.run_logged([ffmpeg, "-v", "error", "-i", str(raw), "-map", "0:a:0", "-c:a", "copy", str(pcm)], task / "logs" / (name + "_exact_pcm.log"), 120)
    pcm_decode = pipeline.run_logged([ffmpeg, "-v", "error", "-i", str(pcm), "-f", "null", "-"], task / "logs" / (name + "_pcm_decode.log"), 120)
    meta = movie_metadata(ffmpeg, video)
    assert 45 <= meta["seconds"] <= 60 and abs(meta["seconds"] - raw_meta["seconds"]) < 0.1
    samples, spec = read_pcm(pcm)
    metrics = signal_metrics(samples, spec["sample_rate"])
    assert metrics["clipped_samples"] == 0 and 0.01 < metrics["peak"] < 0.99 and metrics["rms"] > 0.001
    assert max(abs(v) for v in metrics["dc_per_channel"]) < 0.005
    phase_audio = {}
    for phase in data["phases"]:
        start = round(phase["from_frame"] / 60 * spec["sample_rate"])
        end = round(phase["to_frame"] / 60 * spec["sample_rate"])
        phase_audio[phase["name"]] = signal_metrics(samples[start:end], spec["sample_rate"])
    distributions = {k: np.array(list(v["band_energy_fraction"].values())) for k, v in phase_audio.items()}
    distances = {f"opening_to_{stage}": float(np.linalg.norm(distributions["opening_run"] / np.linalg.norm(distributions["opening_run"]) - distributions[stage] / np.linalg.norm(distributions[stage]))) for stage in ["middle_run", "late_anthem", "boss_cue_audition"]}
    matrix(data, native_matrix)
    return {"video": str(video), "video_sha256": pipeline.sha256(video), "seconds": meta["seconds"], "encoder": encode, "decoder": decode, "exact_native_mix_pcm": str(pcm), "pcm_specification": spec, "pcm_export": pcm_export, "pcm_decoder": pcm_decode, "native_mix": metrics, "native_phase_audio": phase_audio, "normalized_stage_spectral_distances": distances, "native_phase_matrix": str(native_matrix), "matrix_sha256": pipeline.sha256(native_matrix), "raw_movie": str(raw), "raw_sha256": pipeline.sha256(raw), "raw_metadata": raw_meta, "provenance": "Uncut native controlled audition. Production AudioStreamSynchronized/player/stems, Music gain envelopes and accepted SFX are mixed by Godot. Raw MovieMaker Master PCM is exported directly, not reconstructed from stems or decoded from AAC. Always-visible labels identify synthetic Run observations; no fake gameplay exists."}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine")
    parser.add_argument("--ffmpeg")
    parser.add_argument("--qa-root", type=Path)
    parser.add_argument("--baseline-ref", default="c18672000cc28445369c7929cd78fc0cd3cc2ef0")
    parser.add_argument("--diagnostic", action="store_true")
    parser.add_argument("--native-preview", action="store_true", help="Render six labelled UI proofs with playback disabled; no review movie")
    args = parser.parse_args()
    if args.native_preview:
        args.diagnostic = True
    task = workspace.create_task_workspace("002C.6", args.qa_root)
    if args.qa_root:
        os.environ["TOPGAME_QA_ROOT"] = str(task.parent)
    name = "002c6_metal_music_" + ("preview_" if args.native_preview else ("diagnostic_" if args.diagnostic else "capture_")) + datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    output = task / "manifests" / (name + ".json")
    raw = task / "temp" / (name + ".avi")
    frames = task / "frames" / name
    before = {p: pipeline.sha256(ROOT / p) for p in SOURCE_FILES}
    profile_before = pipeline.production_profile(ROOT)
    baseline = preserve_baseline(task, name, args.baseline_ref)
    inputs = {"source_git_sha": pipeline.git(ROOT, "rev-parse", "HEAD"), "source_sha256": before, "profile_before": profile_before, "baseline_ref": args.baseline_ref, "baseline_preserved": str(baseline)}
    (task / "manifests" / (name + "_inputs.json")).write_text(json.dumps(inputs, indent=2) + "\n")
    command = [workspace.find_tool("godot", args.engine), "--path", str(ROOT), "--script", "res://tests/capture_metal_music.gd", "--fixed-fps", "60", "--disable-vsync"]
    command += (["--audio-driver", "Dummy"] if args.native_preview else ["--headless"]) if args.diagnostic else ["--write-movie", str(raw), "--audio-driver", "Dummy"]
    command += ["--", "--manifest=" + str(output)]
    command += ["--diagnostic"] if args.diagnostic else []
    if not args.diagnostic or args.native_preview:
        command += ["--frames=" + str(frames)]
    print("CONTROLLED_NATIVE_METAL_AUDITION " + name, flush=True)
    process = pipeline.run_logged(command, task / "logs" / (name + ".log"), 360)
    data = json.loads(output.read_text())
    validate(data, args.diagnostic)
    after = {p: pipeline.sha256(ROOT / p) for p in SOURCE_FILES}
    profile_after = pipeline.production_profile(ROOT)
    assert before == after, "Keep music, assets and capture source frozen throughout recording"
    assert profile_before == profile_after, "Controlled audition must leave production profile untouched"
    data.update(capture_process=process, source_sha256=before, source_unchanged=True, source_git_sha=inputs["source_git_sha"], profile_before=profile_before, profile_after=profile_after, profile_unchanged=True, baseline_ref=args.baseline_ref, baseline_preserved=str(baseline), independent_source_review=source_review(data, baseline))
    if not args.diagnostic:
        data.update(export_media(data, raw, task, name, workspace.find_tool("ffmpeg", args.ffmpeg)))
    output.write_text(json.dumps(data, indent=2) + "\n")
    print(json.dumps({"passed": True, "manifest": str(output), "video": data.get("video"), "exact_pcm": data.get("exact_native_mix_pcm"), "native_matrix": data.get("native_phase_matrix"), "profile_unchanged": True, "subjective_audition": "PENDING HOME HUMAN AUDITION"}, indent=2))


if __name__ == "__main__":
    main()
