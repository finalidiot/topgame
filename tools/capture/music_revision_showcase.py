"""Record the labelled 003A music revision with the real synchronized mixer.

This is an auditory review, not gameplay: Run observations are visible fixtures.
One continuous native transport covers a full title form and all requested
contexts. A final default-volume segment auditions four labelled production SFX.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/workspace"))
sys.path.insert(0, str(ROOT / "tools/build"))
import workspace
import windows_checkpoint as pipeline
import metal_music_showcase as review

PHASES = ["title", "first_machine", "shop", "workshop", "early_run", "mid_run", "late_run", "boss", "results", "normal_mix_sfx"]
SOURCE_FILES = ["scripts/music.gd", "scripts/sound.gd", "scripts/front_end.gd", "tests/capture_music_revision.gd", "tools/capture/music_revision_showcase.py", "tools/audio/compose_foundation.py", "assets/audio/music/foundation_score.json", "assets/audio/music/manifest.json"]
SOURCE_FILES += [f"assets/audio/music/{stem}.wav" for stem in review.STEMS]
SOURCE_FILES += [f"assets/audio/music/{stem}.wav.import" for stem in review.STEMS]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine")
    parser.add_argument("--ffmpeg")
    parser.add_argument("--qa-root", type=Path)
    parser.add_argument("--name", default="003a_human_feedback_music_revision")
    parser.add_argument("--baseline-ref", default="7c26ae7e949324bac8cff0707b2905af76a033c3")
    args = parser.parse_args()
    assert args.name.replace("_", "").isalnum()
    task = workspace.create_task_workspace("003A", args.qa_root)
    os.environ["TOPGAME_QA_ROOT"] = str(task.parent)
    name = args.name + "_" + datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    output = task / "manifests" / (name + ".json")
    raw = task / "temp" / (name + ".avi")
    video = task / "video" / (args.name + ".mp4")
    pcm = task / "video" / (args.name + ".wav")
    assert not any(path.exists() for path in [output, raw, video, pcm]), "Preserve earlier review media"
    before = {path: pipeline.sha256(ROOT / path) for path in SOURCE_FILES}
    profile_before = pipeline.production_profile(ROOT)
    baseline = review.preserve_baseline(task, name, args.baseline_ref)
    command = [workspace.find_tool("godot", args.engine), "--path", str(ROOT), "--script", "res://tests/capture_music_revision.gd", "--fixed-fps", "60", "--disable-vsync", "--write-movie", str(raw), "--audio-driver", "Dummy", "--", "--manifest=" + str(output)]
    print("MUSIC_REVISION_NATIVE_CAPTURE " + str(output), flush=True)
    process = pipeline.run_logged(command, task / "logs" / (name + ".log"), 600)
    data = json.loads(output.read_text())
    assert [phase["name"] for phase in data["phases"]] == PHASES
    assert not data["collection_opened"] and not data["battle_created"]
    assert data["native_view"] == [640, 360] and "FIXTURES" in data["fixture_label"]
    assert data["music_final"]["asset_errors"] == [] and data["music_final"]["transport_starts"] == 1
    assert all(row["music"]["transport_starts"] == 1 for row in data["rows"])
    settled = {phase["name"]: phase["settled_music"] for phase in data["phases"]}
    assert settled["first_machine"]["targets"] == settled["shop"]["targets"] == settled["workshop"]["targets"] == [0, 1, 0, 0, 0]
    assert settled["results"]["targets"] == [0, .65, 0, 0, 0]
    assert settled["early_run"]["targets"] == [0, 0, 1, 0, 0]
    assert settled["mid_run"]["targets"][3] == .5 and settled["mid_run"]["targets"][4] == .25
    assert settled["late_run"]["targets"][3] == .75 and settled["late_run"]["targets"][4] == .5
    assert settled["boss"]["targets"][3:] == [1, 1]
    assert [cue["cue"] for cue in data["cue_auditions"]] == ["ui", "heavy", "low_rpm", "level_up"]
    assert data["sfx_final"]["played"] == {"ui": 1, "heavy": 1, "low_rpm": 1, "level_up": 1}, "Every labelled cue must actually play in the production SFX node"
    assert any(row["music"]["duck_left"] > 0 for row in data["rows"])
    after = {path: pipeline.sha256(ROOT / path) for path in SOURCE_FILES}
    profile_after = pipeline.production_profile(ROOT)
    assert before == after, "Music review sources changed during native recording"
    assert profile_before == profile_after, "Read-only audition changed the real profile"
    comparison = review.source_review(data, baseline)
    for stem in ["workshop", "run_base"]:
        assert comparison["stems"][stem]["new_pcm"]["file_sha256"] == comparison["stems"][stem]["old_pcm"]["file_sha256"], "Human-liked PCM changed"
    ffmpeg = workspace.find_tool("ffmpeg", args.ffmpeg)
    encode = pipeline.run_logged([ffmpeg, "-v", "error", "-i", str(raw), "-vf", "scale=1280:720:flags=neighbor", "-c:v", "libx264", "-crf", "18", "-preset", "fast", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-movflags", "+faststart", str(video)], task / "logs" / (name + "_encode.log"), 360)
    decode = pipeline.run_logged([ffmpeg, "-v", "error", "-i", str(video), "-f", "null", "-"], task / "logs" / (name + "_decode.log"), 120)
    pcm_export = pipeline.run_logged([ffmpeg, "-v", "error", "-i", str(raw), "-map", "0:a:0", "-c:a", "copy", str(pcm)], task / "logs" / (name + "_exact_pcm.log"), 120)
    samples, specification = review.read_pcm(pcm)
    metrics = review.signal_metrics(samples, specification["sample_rate"])
    assert metrics["clipped_samples"] == 0 and .01 < metrics["peak"] < .99 and metrics["rms"] > .001
    phase_audio = {}
    for phase in data["phases"]:
        start = round(phase["from_frame"] / 60 * specification["sample_rate"])
        end = round(phase["to_frame"] / 60 * specification["sample_rate"])
        phase_audio[phase["name"]] = review.signal_metrics(samples[start:end], specification["sample_rate"])
    score = json.loads((ROOT / "assets/audio/music/foundation_score.json").read_text())
    arrangements = score["human_feedback_revision"]["arrangements"]
    data.update(capture_process=process, source_sha256=before, source_unchanged=True, source_git_sha=pipeline.git(ROOT, "rev-parse", "HEAD"), profile_before=profile_before, profile_after=profile_after, profile_unchanged=True, baseline_ref=args.baseline_ref, baseline_preserved=str(baseline), independent_source_review=comparison, raw_movie=str(raw), raw_sha256=pipeline.sha256(raw), video=str(video), video_sha256=pipeline.sha256(video), exact_native_mix_pcm=str(pcm), pcm_specification=specification, native_mix=metrics, native_phase_audio=phase_audio, encoder=encode, decoder=decode, pcm_export=pcm_export, movie_metadata=review.movie_metadata(ffmpeg, video), authored_forms=arrangements, preserved_contexts={"first_machine":"workshop x1.0", "results":"workshop x0.65", "ordinary_early_run":"run_base x1.0"}, human_subjective_status="PENDING HUMAN LISTENING; metrics do not determine enjoyment, guitar character or fatigue", provenance="Uncut production AudioStreamSynchronized/player/buses/envelopes and original SFX mixed by Godot MovieMaker. Raw Master PCM exported directly, not reconstructed from stems or decoded from AAC. Always-visible labels identify controlled Run observations. No Main, collection or Battle exists.")
    output.write_text(json.dumps(data, indent=2) + "\n")
    print(json.dumps({"passed":True, "manifest":str(output), "video":str(video), "exact_pcm":str(pcm), "profile_unchanged":True, "human_listening":"PENDING"}, indent=2))


if __name__ == "__main__": main()
