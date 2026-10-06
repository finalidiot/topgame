"""Render the original editable Foundry Circuit score to five aligned PCM loops.

Requires NumPy (available in the Codex bundled Python). No downloaded samples,
external song inputs or runtime/game RNG. --verify-only checks frozen output;
--review-dir creates external audition mixes, never source/runtime replacements.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
from pathlib import Path
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets/audio/music"
SCORE = ASSETS / "foundation_score.json"
NAMES = ("title", "workshop", "run_base", "run_pressure", "run_boss")


def fingerprint(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def synth(kind: str, note: int, seconds: float, rate: int, seed: int) -> np.ndarray:
    """Small original subtractive/FM palette; random texture is offline only."""
    count = max(1, round(seconds * rate))
    t = np.arange(count, dtype=np.float64) / rate
    frequency = 440.0 * 2 ** ((note - 69) / 12)
    phase = math.tau * frequency * t
    attack = 0.005
    release = 0.06
    if kind == "pad":
        attack, release = 0.14, 0.35
        signal = (np.sin(phase) + 0.26 * np.sin(phase * 2 + 0.11 * np.sin(t * 3.2)) + 0.12 * np.sin(phase * 3)) * 0.65
    elif kind == "bass":
        signal = np.tanh(1.35 * (np.sin(phase) + 0.25 * np.sin(phase * 2))) * np.exp(-t * 1.5)
        release = 0.045
    elif kind in ("pluck", "glass", "brass"):
        if kind == "glass":
            signal = (np.sin(phase + 0.6 * np.sin(phase * 2) * np.exp(-t * 12)) + 0.15 * np.sin(phase * 3)) * np.exp(-t * 3.8)
        elif kind == "brass":
            signal = np.tanh(1.2 * (np.sin(phase) + 0.35 * np.sin(phase * 2) + 0.16 * np.sin(phase * 3))) * np.exp(-t * 1.8)
            attack = 0.025
        else:
            signal = (np.sin(phase + 1.0 * np.sin(phase * 2) * np.exp(-t * 9)) + 0.15 * np.sin(phase * 3)) * np.exp(-t * 3.0)
    elif kind == "kick":
        f0, f1, decay = 126.0, 46.0, 35.0
        swept = math.tau * (f1 * t + (f0 - f1) * (1 - np.exp(-decay * t)) / decay)
        signal = np.tanh(1.4 * np.sin(swept)) * np.exp(-t * 15)
        attack, release = 0.0015, 0.025
    elif kind in ("snare", "hat"):
        # Separate deterministic offline noise for each written drum note.
        noise = np.random.default_rng(seed).uniform(-1.0, 1.0, count)
        high = noise - np.convolve(noise, np.ones(9) / 9, mode="same")
        if kind == "snare":
            signal = (0.6 * high + 0.32 * np.sin(math.tau * 178 * t) + 0.14 * np.sin(math.tau * 283 * t)) * np.exp(-t * 24)
        else:
            signal = high * np.exp(-t * 85) * 0.52
        attack, release = 0.001, 0.015
    elif kind == "tom":
        signal = (np.sin(phase * (1 + 0.18 * np.exp(-t * 24))) + 0.14 * np.sin(phase * 2.71)) * np.exp(-t * 17)
        attack, release = 0.003, 0.025
    else:
        raise ValueError(kind)
    envelope = np.minimum(1.0, t / attack) * np.minimum(1.0, (seconds - t) / release)
    return signal * np.maximum(0.0, envelope)


def render(score: dict) -> tuple[dict[str, np.ndarray], dict]:
    grid = score["grid"]
    rate = int(grid["sample_rate"])
    beats = int(grid["bars"]) * int(grid["beats_per_bar"])
    frames = round(beats * 60 / float(grid["bpm"]) * rate)
    seconds_per_beat = frames / rate / beats
    stems = {name: np.zeros((frames, 2), dtype=np.float64) for name in NAMES}
    notes = {name: 0 for name in NAMES}

    def add(name: str, kind: str, beat: float, length: float, note: int, gain: float, pan: float = 0.0) -> None:
        if gain <= 0: return
        start = round(beat / beats * frames)
        tail = 0.38 if kind == "pad" else (0.12 if kind in ("pluck", "glass", "brass") else 0.035)
        seed = 0x2C6000 + NAMES.index(name) * 10000 + notes[name]
        voice = synth(kind, note, length * seconds_per_beat + tail, rate, seed) * gain
        stereo = voice[:, None] * np.array([math.sqrt((1 - pan) / 2), math.sqrt((1 + pan) / 2)])
        # Every note and its release tail is periodic across the common boundary.
        indices = (start + np.arange(len(voice))) % frames
        np.add.at(stems[name], indices, stereo)
        notes[name] += 1

    for bar, harmony_name in enumerate(score["progression"]):
        harmony = score["harmony"][harmony_name]
        beat = bar * 4
        for name in NAMES:
            part = score["parts"][name]
            for tone, note in enumerate(harmony[:4]):
                add(name, "pad", beat, 4.0, note + 12, part["pad"] / 4, (-0.45 if tone % 2 else 0.45))
            for offset, length in score["bass_rhythm"]:
                add(name, "bass", beat + offset, length, harmony[0] - 12, part["bass"])
            if name in ("title", "run_base"):
                for offset, length, note in score["melody_bars"][bar % 8]:
                    add(name, "pluck", beat + offset, length, note, part["melody"], -0.12)
            elif name == "workshop":
                for offset, tone in ((0.5, 0), (1.75, 2), (3, 3)):
                    add(name, "glass", beat + offset, 0.85, harmony[tone] + 12, part["melody"], 0.18)
            elif name == "run_pressure":
                for index, tone in enumerate(score["pressure_order"]):
                    if index in (1, 4): continue
                    add(name, "pluck", beat + index * 0.5 + 0.25, 0.24, harmony[tone] + 24, part["melody"], 0.26)
            elif name == "run_boss":
                for index, tone in enumerate(score["boss_order"]):
                    add(name, "brass", beat + index * 0.5, 0.36 if index < 7 else 0.65, harmony[tone] + 12, part["melody"], 0.0)
                if bar % 4 == 3:
                    for offset, note in ((2.75, 50), (3.25, 45), (3.75, 38)):
                        add(name, "tom", beat + offset, 0.35, note, part["drums"] * 0.65, -0.2)
            for index, tone in enumerate(score["run_arp_order"]):
                add(name, "glass" if name == "workshop" else "pluck", beat + index * 0.5, 0.24, harmony[tone] + 12, part["arp"], 0.3)
            for drum, offsets in score["drums"][name].items():
                for offset in offsets:
                    add(name, drum, beat + offset, 0.3 if drum != "hat" else 0.12, 36, part["drums"] * (0.50 if drum == "hat" else 1.0), 0.24 if drum == "hat" else 0.0)

    # Join the final and first PCM samples with a 2 ms raised-cosine bridge.
    # Wrapped release tails stay present; this is not a fade-to-silence/padding
    # of the bar. Both edges meet at the same value and near-zero derivative.
    join_frames = round(rate * 0.002)
    bridge = np.sin(np.linspace(0, math.pi / 2, join_frames)) ** 2
    for samples in stems.values():
        boundary = (samples[0] + samples[-1]) * 0.5
        samples[:join_frames] = boundary + (samples[:join_frames] - boundary) * bridge[:, None]
        samples[-join_frames:] = boundary + (samples[-join_frames:] - boundary) * bridge[::-1, None]
    peak = max(float(np.max(np.abs(stems[n]))) for n in ("title", "workshop"))
    run_mix = stems["run_base"] + stems["run_pressure"] + stems["run_boss"]
    peak = max(peak, float(np.max(np.abs(run_mix))))
    gain = min(1.0, float(score["mix"]["maximum_full_run_peak"]) / peak)
    for name in NAMES: stems[name] *= gain
    return stems, {"sample_rate": rate, "channels": 2, "sample_width_bytes": 2, "frames": frames,
                   "seconds": frames / rate, "beats": beats, "bars": grid["bars"], "bpm": grid["bpm"],
                   "actual_bpm": beats * 60 * rate / frames, "render_gain": gain, "note_counts": notes}


def write_wav(path: Path, samples: np.ndarray, rate: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.round(np.clip(samples, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as output:
        output.setnchannels(2); output.setsampwidth(2); output.setframerate(rate)
        output.writeframes(pcm.tobytes())


def read_wav(path: Path) -> tuple[np.ndarray, dict]:
    with wave.open(str(path), "rb") as source:
        spec = {"sample_rate": source.getframerate(), "channels": source.getnchannels(), "sample_width_bytes": source.getsampwidth(), "frames": source.getnframes()}
        samples = np.frombuffer(source.readframes(source.getnframes()), dtype="<i2").astype(np.float64).reshape(-1, spec["channels"]) / 32767
    return samples, spec


def metrics(samples: np.ndarray) -> dict:
    peak = float(np.max(np.abs(samples)))
    rms = math.sqrt(float(np.mean(samples ** 2)))
    seam = float(np.max(np.abs(samples[0] - samples[-1])))
    return {"peak": peak, "rms": rms, "rms_dbfs": 20 * math.log10(max(rms, 1e-12)),
            "boundary_step": seam, "largest_adjacent_step": float(np.max(np.abs(np.diff(samples, axis=0)))),
            "clipped_samples": int(np.count_nonzero(np.abs(samples) >= 0.999))}


def verify(directory: Path, score: dict, expected: dict) -> dict:
    output = {}
    stems = {}
    for name in NAMES:
        path = directory / (name + ".wav")
        samples, spec = read_wav(path)
        assert all(spec[key] == expected[key] for key in spec), f"Mismatched stem/grid: {name}"
        stats = metrics(samples)
        assert stats["clipped_samples"] == 0 and 0.002 < stats["rms"] < 0.25
        assert stats["boundary_step"] < 0.006, f"Loop seam clicks: {name}"
        output[name] = dict(spec, **stats, sha256=fingerprint(path), description=score["parts"][name]["description"])
        stems[name] = samples
    combinations = {"normal_run": stems["run_base"], "pressure_run": stems["run_base"] + stems["run_pressure"],
                    "boss_run": stems["run_base"] + stems["run_pressure"] + stems["run_boss"]}
    mix = {name: metrics(samples) for name, samples in combinations.items()}
    assert all(record["peak"] <= 0.701 and record["clipped_samples"] == 0 and record["boundary_step"] < 0.012 for record in mix.values())
    return {"schema_version": 1, "title": score["title"], "authorship": score["authorship"], "score_sha256": fingerprint(SCORE),
            "generator_sha256": fingerprint(Path(__file__)), "grid": expected, "stems": output, "mixes": mix,
            "loop": {"begin_frame": 0, "end_frame": expected["frames"], "mode": "forward", "tails": "written notes and releases wrap into the beginning", "boundary_bridge_seconds": 0.002},
            "mix": score["mix"], "source": "foundation_score.json + tools/audio/compose_foundation.py"}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ASSETS)
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--review-dir", type=Path)
    args = parser.parse_args()
    score = json.loads(SCORE.read_text(encoding="utf-8"))
    stems, grid = render(score)
    if not args.verify_only:
        for name, samples in stems.items(): write_wav(args.out / (name + ".wav"), samples, grid["sample_rate"])
    manifest = verify(args.out, score, grid)
    if not args.verify_only: (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    else:
        previous = json.loads((args.out / "manifest.json").read_text(encoding="utf-8"))
        assert previous == manifest, "Frozen score/generator/audio metadata changed"
        for name in NAMES:
            source, _ = read_wav(args.out / (name + ".wav"))
            regenerated = np.round(stems[name] * 32767) / 32767
            assert np.array_equal(source, regenerated), f"Regeneration mismatch: {name}"
    if args.review_dir:
        reviews = {"title": stems["title"], "workshop": stems["workshop"], "normal_run": stems["run_base"],
                   "pressure_run": stems["run_base"] + stems["run_pressure"],
                   "boss_run": stems["run_base"] + stems["run_pressure"] + stems["run_boss"]}
        for name, samples in reviews.items():
            # Runtime Music trim/default volume, before the existing Master slider.
            mastered = samples * (10 ** (-8 / 20)) * 0.55
            write_wav(args.review_dir / ("002c6_music_" + name + ".wav"), np.concatenate([mastered, mastered]), grid["sample_rate"])
    print(json.dumps({"passed": True, "grid": grid, "stems": {name: manifest["stems"][name]["rms_dbfs"] for name in NAMES}, "mixes": manifest["mixes"]}, indent=2))


if __name__ == "__main__": main()
