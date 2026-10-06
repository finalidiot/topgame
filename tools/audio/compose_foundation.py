"""Render an original editable 32-bar metal score to five synchronized loops.

NumPy only; no samples, songs, external instruments or runtime/game RNG.
Modal plucked strings feed an oversampled smooth amp/cabinet model. Written
notes/riffs/drums define the music; fixed offline noise only excites instruments.
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


def filtered(signal: np.ndarray, rate: int, kind: str) -> np.ndarray:
    """Original cabinet/band shaping, padded to keep circular FFT tails quiet."""
    count = len(signal)
    size = 1 << (count + round(rate * .06) - 1).bit_length()
    spectrum = np.fft.rfft(signal, n=size)
    hz = np.fft.rfftfreq(size, 1 / rate)
    if kind == "cabinet":
        curve = hz ** 2 / (hz ** 2 + 82 ** 2)
        curve *= 1 / np.sqrt(1 + (hz / 4300) ** 10)
        curve *= 1 + .52 * np.exp(-((hz - 760) / 390) ** 2)
        curve *= 1 + .28 * np.exp(-((hz - 1650) / 650) ** 2)
        curve *= 1 - .35 * np.exp(-((hz - 3350) / 630) ** 2)
    elif kind == "clean":
        curve = hz ** 2 / (hz ** 2 + 75 ** 2) / np.sqrt(1 + (hz / 4900) ** 8)
    elif kind == "snare":
        curve = hz ** 2 / (hz ** 2 + 650 ** 2) / np.sqrt(1 + (hz / 7100) ** 8)
    else:
        curve = hz ** 2 / (hz ** 2 + 2900 ** 2) / np.sqrt(1 + (hz / 11200) ** 10)
    return np.fft.irfft(spectrum * curve, n=size)[:count]


def string(note: int, t: np.ndarray, muted: bool, variant: int) -> np.ndarray:
    """Dispersive/damped string modes and pick position, rather than a beep."""
    frequency = 440 * 2 ** ((note - 69 + (variant - 1) * .035) / 12)
    modes = min(48, int(6400 / frequency))
    signal = np.zeros(len(t), dtype=np.float64)
    pickup = .19 + .013 * variant
    for harmonic in range(1, modes + 1):
        partial = frequency * harmonic * math.sqrt(1 + .000014 * harmonic ** 2)
        amplitude = math.sin(math.pi * harmonic * pickup) * math.exp(-harmonic * .042) / harmonic ** .73
        decay = (12.0 if muted else 1.1) + harmonic * (.52 if muted else .09)
        phase = math.tau * partial * t + .11 * np.sin(math.tau * 5.4 * t) * np.minimum(1, t / .18)
        signal += amplitude * np.sin(phase - .22 * harmonic) * np.exp(-t * decay)
    pick = np.random.default_rng(0x2C6A00 + note * 7 + variant).uniform(-1, 1, len(t))
    signal += .055 * pick * np.exp(-t * 230)
    return signal * .48


def synth(kind: str, note: int, seconds: float, rate: int, variant: int) -> np.ndarray:
    count = max(1, round(seconds * rate))
    attack, release = .003, .035
    if kind in ("chug", "power", "lead", "clean"):
        oversample = 1 if kind == "clean" else 2
        t = np.arange(count * oversample, dtype=np.float64) / (rate * oversample)
        if kind in ("chug", "power"):
            signal = np.zeros(len(t), dtype=np.float64)
            for tone, weight, shift in [(0, .68, 0), (7, .23, .0018), (12, .15, .0031)]:
                shifted = np.maximum(0, t - shift)
                signal += string(note + tone, shifted, kind == "chug", variant) * weight
            attack = .0018
            release = .024 if kind == "chug" else .09
        else:
            signal = string(note, t, False, variant)
            release = .075
        if kind != "clean":
            # Two smooth amplifier stages; no hard waveform clipping. Cabinet
            # suppresses newly created treble before decimation to native32k.
            signal = np.tanh(4.2 * signal + .16 * signal ** 2)
            signal = np.tanh(1.45 * signal) * .72
            signal = filtered(signal, rate * oversample, "cabinet")[::oversample]
        else:
            signal = filtered(signal, rate, "clean") * .8
    else:
        t = np.arange(count, dtype=np.float64) / rate
        noise = np.random.default_rng(0x2C6D00 + variant * 97 + note).uniform(-1, 1, count)
        frequency = 440 * 2 ** ((note - 69) / 12)
        if kind == "bass":
            signal = (np.sin(math.tau * frequency * t) + .30 * np.sin(math.tau * frequency * 2 * t) + .12 * np.sin(math.tau * frequency * 3 * t)) * np.exp(-t * 2.8)
            signal = np.tanh(signal * 1.8) * .76
        elif kind == "kick":
            phase = math.tau * (51 * t + (168 - 51) * (1 - np.exp(-t * 68)) / 68)
            beater = filtered(noise, rate, "snare") * np.exp(-t * 180) * .25
            signal = np.sin(phase) * np.exp(-t * 17) * .91 + beater
            attack, release = .0006, .020
        elif kind == "snare":
            signal = (filtered(noise, rate, "snare") * .62 + np.sin(math.tau * 185 * t) * .36 + np.sin(math.tau * 331 * t) * .10) * np.exp(-t * 20)
            attack, release = .0006, .025
        elif kind in ("hat", "ride", "crash"):
            decay = {"hat":75, "ride":9, "crash":3.9}[kind]
            signal = filtered(noise, rate, "cymbal") * .34
            for index, mode in enumerate([2143, 2851, 3279, 3881, 4427, 5033, 5711, 6419, 7297, 8219, 9343, 10729]):
                signal += .038 * np.sin(math.tau * (mode + variant * 3) * t + index) * np.exp(-t * (index * .28))
            signal *= np.exp(-t * decay)
            attack, release = .0008, .035
        elif kind == "tom":
            phase = math.tau * frequency * (t + .11 * (1 - np.exp(-t * 32)) / 32)
            signal = (np.sin(phase) + .19 * np.sin(phase * 1.51) + noise * np.exp(-t * 95) * .15) * np.exp(-t * 12)
        else: raise ValueError(kind)
    t = np.arange(count, dtype=np.float64) / rate
    envelope = np.minimum(1, t / attack) * np.minimum(1, (seconds - t) / release)
    return signal[:count] * np.maximum(0, envelope)


def harmonized(note: int, dominant: bool) -> int:
    scale = [0, 2, 3, 5, 7, 8, 11 if dominant else 10]
    pitches = [40 + octave * 12 + degree for octave in range(-2, 7) for degree in scale]
    index = min(range(len(pitches)), key=lambda i: abs(pitches[i] - note))
    return pitches[min(len(pitches) - 1, index + 2)]


def render(score: dict) -> tuple[dict[str, np.ndarray], dict]:
    grid = score["grid"]
    rate = int(grid["sample_rate"]); beats = int(grid["bars"]) * int(grid["beats_per_bar"])
    assert len(score["progression"]) == len(score["phrase_order"]) == len(score["sections"]) == int(grid["bars"])
    frames = round(beats * 60 / float(grid["bpm"]) * rate); beat_seconds = frames / rate / beats
    stems = {name:np.zeros((frames, 2), dtype=np.float64) for name in NAMES}
    counts = {name:0 for name in NAMES}; instruments = {name:{} for name in NAMES}; cache = {}

    def add(name, kind, beat, length, note, gain, pan=0.0, variant=1, echo=False):
        if gain <= 0: return
        tails = {"chug":.025, "power":.18, "lead":.11, "clean":.16, "crash":.9, "ride":.25}
        seconds = length * beat_seconds + tails.get(kind, .035)
        key = (kind, note, round(seconds, 7), variant)
        if key not in cache: cache[key] = synth(kind, note, seconds, rate, variant)
        voice = cache[key] * gain; start = round(beat / beats * frames)
        stereo = voice[:,None] * np.array([math.sqrt((1-pan)/2),math.sqrt((1+pan)/2)])
        if start + len(voice) <= frames: stems[name][start:start+len(voice)] += stereo
        else:
            first = frames-start; stems[name][start:] += stereo[:first]; stems[name][:len(voice)-first] += stereo[first:]
        if echo:
            for delay,level in [(.5,.14),(1,.065)]:
                index=(start+round(delay*beat_seconds)+np.arange(len(voice))) % frames
                np.add.at(stems[name],index,stereo[:,::-1]*level)
        counts[name] += 1; instruments[name][kind] = instruments[name].get(kind,0)+1

    def rhythm(name,part,bar,harmony,section):
        beat=bar*4; root=harmony["guitar_root"]
        pattern=score["riff_patterns"]["space" if section=="bridge" else "gallop" if bar%4!=2 else "drive"]
        turns=score["riff_turns"][bar%8]
        for i,(offset,length) in enumerate(pattern):
            note=root+(turns[i-len(pattern)+2] if i>=len(pattern)-2 else 0)
            for pan,variant in [(-.73,0),(.73,2)]: add(name,"chug",beat+offset+(0 if variant==0 else .018),length,note,part["rhythm"]*.61,pan,variant)
            add(name,"bass",beat+offset,length,harmony["bass"]+(7 if i==len(pattern)-1 and bar%4==3 else 0),part["bass"])
        if section in ("hook","anthem"):
            for pan,variant in [(-.68,0),(.68,2)]: add(name,"power",beat,.8,root,part["rhythm"]*.25,pan,variant)

    def revised_part(name, part, bar, harmony):
        """Written riff/groove/hook form; solo punctuation occupies two bars.

        Accepted workshop and opening-Run arrangements bypass this function.
        All new notes follow their established moving harmony and PCM grid.
        """
        revision = score["human_feedback_revision"]
        form = revision["arrangements"][name]
        section = form["sections"][bar]
        beat = bar * 4; root = harmony["guitar_root"]
        pattern = revision["riffs"][form["patterns"][section]]
        for index, (offset, length, interval) in enumerate(pattern):
            # Brief alternating low riffs, independently voiced stereo takes.
            for pan, variant in [(-.73, 0), (.73, 2)]:
                add(name, "chug", beat + offset + (.018 if variant == 2 else 0), length,
                    root + interval, part["rhythm"] * .61, pan, variant)
            add(name, "bass", beat + offset, length, harmony["bass"] + interval,
                part["bass"] * (1.13 if section == "drive" else 1))
        if section in ("hook", "return"):
            for pan, variant in [(-.65, 0), (.65, 2)]:
                add(name, "power", beat, 1.15, root, part["rhythm"] * .4, pan, variant)
        if bar in form["hook_bars"]:
            phrase = revision["hooks"]["answer" if bar % 2 else "call"]
            for offset, length, interval in phrase:
                note = root + 12 + interval
                add(name, "lead", beat + offset, length, note, part["lead"], -.12, 1)
                add(name, "lead", beat + offset + .015, length, harmonized(note, score["progression"][bar] == "B"),
                    part["harmony"], .35, 2)
        if bar in form["lead_break_bars"]:
            for offset, length, interval in revision["lead_break"]["answer" if bar % 2 else "call"]:
                add(name, "lead", beat + offset, length, root + 36 + interval,
                    part["lead"] * 1.08, -.08, 1, True)
        # Sections breathe: groove is spacious, drive completes sixteenth kicks,
        # hooks broaden the backbeat, and written fills mark phrase boundaries.
        drums = score["drums"]
        if name == "title":
            kick = revision["groove_kick"] if section == "groove" else drums["base_kick"]
            if section in ("drive", "return"): kick = kick + drums["pressure_kick"]
            for offset in kick: add(name, "kick", beat + offset, .3, 36, part["kick"], 0, bar % 3)
            for offset in drums["snare"]: add(name, "snare", beat + offset, .5, 38, part["snare"], -.1, bar % 3)
            for i, offset in enumerate(drums["ride"]):
                add(name, "hat" if section in ("riff", "groove") else "ride", beat + offset, .2, 42,
                    part["cymbal"] * (1 if i % 2 else 1.22), .38, bar % 3)
        elif name == "run_pressure":
            kick = revision["groove_pressure_kick"] if section == "groove" else drums["pressure_kick"]
            for offset in kick: add(name, "kick", beat + offset, .3, 36, part["kick"], 0, (bar + 1) % 3)
            for offset in (.25, 1.25, 2.25, 3.25): add(name, "hat", beat + offset, .15, 42, part["cymbal"], -.34, bar % 3)
        elif name == "run_boss":
            for offset in (0, 2):
                for pan, variant in [(-.62, 0), (.62, 2)]:
                    add(name, "power", beat + offset, 1.4, root, part["rhythm"] * .48, pan, variant)
            for offset in (1, 3): add(name, "snare", beat + offset, .4, 38, part["snare"] * .52, -.05, bar % 3)
            if section in ("drive", "return"):
                for offset in (1.875, 3.875): add(name, "kick", beat + offset, .25, 36, part["kick"])
        if bar % 8 == 0: add(name, "crash", beat, 1.4, 49, part["cymbal"] * .95, -.28, bar % 3)
        if bar % 4 == 3:
            for i, (offset, kind, note) in enumerate(drums["fills"]["cadence" if bar % 8 == 7 else "short"]):
                add(name, kind, beat + offset, .35, note, (part["snare"] + .025) * .74, -.38 + i * .1, bar % 3)

    for bar,chord in enumerate(score["progression"]):
        harmony=score["harmony"][chord]; section=score["sections"][bar]; beat=bar*4
        phrase=score["lead_phrases"][score["phrase_order"][bar]]
        for name in NAMES:
            part=score["parts"][name]
            if name in score.get("human_feedback_revision", {}).get("arrangements", {}):
                revised_part(name, part, bar, harmony)
                continue
            if name in ("title","run_base"): rhythm(name,part,bar,harmony,section)
            elif name=="workshop":
                for i,note in enumerate(harmony["clean"]): add(name,"clean",beat+i,.85,note,part["rhythm"],(-.35 if i%2 else .35),i%3)
                add(name,"bass",beat,1.7,harmony["bass"],part["bass"])
                for offset,length,note in phrase[::3]: add(name,"clean",beat+offset,length*1.1,note-12,part["lead"],.1,1,True)
            elif name=="run_boss":
                for offset in (0,2):
                    for pan,variant in [(-.62,0),(.62,2)]: add(name,"power",beat+offset,1.6,harmony["guitar_root"],part["rhythm"]*.68,pan,variant)
                for offset,note in [(0,harmony["clean"][0]),(1.5,harmony["clean"][2]),(2.5,harmony["clean"][1]),(3.5,harmony["clean"][3])]: add(name,"lead",beat+offset,.4,note,part["lead"],-.28,0)
            if name in ("title","run_pressure"):
                for offset,length,note in phrase: add(name,"lead",beat+offset,length,note,part["lead"]*(.84 if section=="bridge" else 1),-.09,1,True)
            if name in ("title","run_boss"):
                for offset,length,note in phrase: add(name,"lead",beat+offset+.015,length,harmonized(note,chord=="B"),part["harmony"],.33,2,True)
            drums=score["drums"]
            if name in ("title","run_base"):
                kick=drums["base_kick"]+(drums["pressure_kick"] if name=="title" else [])
                for offset in kick: add(name,"kick",beat+offset,.3,36,part["kick"],0,bar%3)
                for offset in drums["snare"]: add(name,"snare",beat+offset,.5,38,part["snare"],-.1,bar%3)
                for i,offset in enumerate(drums["ride"]): add(name,"hat" if section=="verse" else "ride",beat+offset,.2,42,part["cymbal"]*(1 if i%2 else 1.22),.38,bar%3)
            elif name=="workshop":
                add(name,"kick",beat,.3,36,part["kick"]); add(name,"snare",beat+2,.4,38,part["snare"])
                for offset in (0,1,2,3): add(name,"hat",beat+offset,.16,42,part["cymbal"],.28)
            elif name=="run_pressure":
                for offset in drums["pressure_kick"]: add(name,"kick",beat+offset,.3,36,part["kick"],0,(bar+1)%3)
                for offset in (.25,1.25,2.25,3.25): add(name,"hat",beat+offset,.15,42,part["cymbal"],-.34,bar%3)
            if name in ("title","run_base","run_pressure","run_boss") and bar%8==0: add(name,"crash",beat,1.4,49,part["cymbal"]*.95,-.28,bar%3)
            if name in ("title","run_pressure","run_boss") and bar%4==3:
                for i,(offset,kind,note) in enumerate(drums["fills"]["cadence" if bar%8==7 else "short"]): add(name,kind,beat+offset,.35,note,(part["snare"]+.025)*.74,-.38+i*.1,bar%3)
            if name=="run_boss" and section=="anthem":
                for offset in (1.875,3.875): add(name,"kick",beat+offset,.25,36,part["kick"])

    join_frames=round(rate*.002); bridge=np.sin(np.linspace(0,math.pi/2,join_frames))**2
    for samples in stems.values():
        boundary=(samples[0]+samples[-1])*.5
        samples[:join_frames]=boundary+(samples[:join_frames]-boundary)*bridge[:,None]
        samples[-join_frames:]=boundary+(samples[-join_frames:]-boundary)*bridge[::-1,None]
        # The asymmetric amp/pick/envelope combination may leave a tiny DC
        # residue. A constant per-channel correction preserves the loop join.
        samples -= np.mean(samples,axis=0,keepdims=True)
    # The two human-liked stems retain the accepted exact mastering gain. New
    # layers are bounded around that fixed base; edits cannot silently remaster
    # First Machine, Results or ordinary opening-Run PCM.
    revision = score.get("human_feedback_revision")
    if revision:
        preserved = revision["preserved"]
        for name in ("workshop", "run_base"): stems[name] *= float(preserved["render_gain"])
        title_gain = min(1.0, float(revision["title_peak"]) / float(np.max(np.abs(stems["title"]))))
        stems["title"] *= title_gain
        base = stems["run_base"]
        layer_gain = 1.0; ceiling = float(score["mix"]["maximum_full_run_peak"])
        # Each vertex is fixed_base + gain * revised_layers. Solve its linear
        # sample inequalities exactly rather than repeatedly rendering mixes.
        for mask in range(1, 8):
            fixed = base if mask & 1 else np.zeros_like(base)
            layers = np.zeros_like(base)
            if mask & 2: layers += stems["run_pressure"]
            if mask & 4: layers += stems["run_boss"]
            nonzero = np.abs(layers) > 1e-12
            limits = (ceiling - np.sign(layers[nonzero]) * fixed[nonzero]) / np.abs(layers[nonzero])
            if limits.size: layer_gain = min(layer_gain, float(np.min(limits)))
        for name in ("run_pressure", "run_boss"): stems[name] *= layer_gain
        mastering = {"preserved_gain":float(preserved["render_gain"]), "title_gain":title_gain, "revised_layer_gain":layer_gain}
        gain = float(preserved["render_gain"])
    else:
        mastering = {}
        # All cube vertices bound every0..1 adaptive gain combination, including
    # combinations peaking higher than the complete sum due to phase.
        peak=max(float(np.max(np.abs(stems[n]))) for n in ("title","workshop"))
        for mask in range(1,8):
            combined=sum((stems[NAMES[2+i]] for i in range(3) if mask&(1<<i)),np.zeros_like(stems["run_base"]))
            peak=max(peak,float(np.max(np.abs(combined))))
        gain=min(1,float(score["mix"]["maximum_full_run_peak"])/peak)
        for samples in stems.values(): samples *= gain
    return stems,{"sample_rate":rate,"channels":2,"sample_width_bytes":2,"frames":frames,"seconds":frames/rate,"beats":beats,"bars":grid["bars"],"bpm":grid["bpm"],"actual_bpm":beats*60*rate/frames,"render_gain":gain,"mastering":mastering,"note_counts":counts,"instrument_events":instruments,"cached_voices":len(cache)}


def write_wav(path: Path,samples: np.ndarray,rate: int) -> None:
    path.parent.mkdir(parents=True,exist_ok=True)
    assert np.max(np.abs(samples))<1,"Audio rendering must never depend on hard clipping"
    pcm=np.round(samples*32767).astype("<i2")
    with wave.open(str(path),"wb") as output:
        output.setnchannels(2); output.setsampwidth(2); output.setframerate(rate); output.writeframes(pcm.tobytes())


def read_wav(path: Path) -> tuple[np.ndarray,dict]:
    with wave.open(str(path),"rb") as source:
        spec={"sample_rate":source.getframerate(),"channels":source.getnchannels(),"sample_width_bytes":source.getsampwidth(),"frames":source.getnframes()}
        samples=np.frombuffer(source.readframes(source.getnframes()),dtype="<i2").astype(np.float64).reshape(-1,spec["channels"])/32767
    return samples,spec


def metrics(samples: np.ndarray) -> dict:
    rms=math.sqrt(float(np.mean(samples**2)))
    return {"peak":float(np.max(np.abs(samples))),"rms":rms,"rms_dbfs":20*math.log10(max(rms,1e-12)),"boundary_step":float(np.max(np.abs(samples[0]-samples[-1]))),"largest_adjacent_step":float(np.max(np.abs(np.diff(samples,axis=0)))),"clipped_samples":int(np.count_nonzero(np.abs(samples)>=.999))}


def verify(directory: Path,score: dict,expected: dict) -> dict:
    output={}; stems={}
    for name in NAMES:
        path=directory/(name+".wav"); samples,spec=read_wav(path); stats=metrics(samples)
        assert all(spec[k]==expected[k] for k in spec),name+" grid differs"
        assert stats["clipped_samples"]==0 and .002<stats["rms"]<.25,name+" invalid energy"
        assert stats["boundary_step"]<.006,name+" loop seam clicks"
        output[name]=dict(spec,**stats,sha256=fingerprint(path),description=score["parts"][name]["description"]); stems[name]=samples
        preserved = score.get("human_feedback_revision", {}).get("preserved", {}).get("wav_sha256", {})
        if name in preserved: assert output[name]["sha256"] == preserved[name], "Human-liked PCM changed: " + name
    mixes={"normal_run":metrics(stems["run_base"]),"pressure_run":metrics(stems["run_base"]+stems["run_pressure"]),"boss_run":metrics(stems["run_base"]+stems["run_pressure"]+stems["run_boss"])}
    peaks=[]
    for mask in range(1,8):
        combined=sum((stems[NAMES[2+i]] for i in range(3) if mask&(1<<i)),np.zeros_like(stems["run_base"]))
        peaks.append(float(np.max(np.abs(combined))))
    assert max(peaks)<=.7001 and all(x["clipped_samples"]==0 for x in mixes.values())
    return {"schema_version":1,"title":score["title"],"authorship":score["authorship"],"score_sha256":fingerprint(SCORE),"generator_sha256":fingerprint(Path(__file__)),"grid":expected,"stems":output,"mixes":mixes,"adaptive_vertex_maximum_peak":max(peaks),"loop":{"begin_frame":0,"end_frame":expected["frames"],"mode":"forward","tails":"written string/drum releases and tempo echoes wrap into the beginning","boundary_bridge_seconds":.002},"mix":score["mix"],"source":"foundation_score.json + tools/audio/compose_foundation.py"}


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out",type=Path,default=ASSETS); parser.add_argument("--verify-only",action="store_true")
    parser.add_argument("--review-dir",type=Path); parser.add_argument("--review-stem",default="002c6_metal"); parser.add_argument("--review-seconds",type=float,default=24)
    args=parser.parse_args(); score=json.loads(SCORE.read_text(encoding="utf-8")); stems,grid=render(score)
    if not args.verify_only:
        for name,samples in stems.items(): write_wav(args.out/(name+".wav"),samples,grid["sample_rate"])
    manifest=verify(args.out,score,grid)
    if not args.verify_only: (args.out/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    else:
        assert json.loads((args.out/"manifest.json").read_text(encoding="utf-8"))==manifest,"Frozen score/generator/metadata changed"
        for name in NAMES:
            source,_=read_wav(args.out/(name+".wav")); regenerated=np.round(stems[name]*32767)/32767
            assert np.array_equal(source,regenerated),"Regeneration mismatch: "+name
    if args.review_dir:
        destination=args.review_dir.resolve(); assert destination!=ROOT and ROOT not in destination.parents,"Reviews belong outside repository"
        assert 12<=args.review_seconds<=24 and args.review_stem.replace("_","").isalnum()
        mixes={"title":stems["title"],"workshop":stems["workshop"],"normal_run":stems["run_base"],"pressure_run":stems["run_base"]+stems["run_pressure"],"boss_run":stems["run_base"]+stems["run_pressure"]+stems["run_boss"]}
        for name,samples in mixes.items():
            path=destination/(args.review_stem+"_"+name+".wav"); assert not path.exists(),"Preserved review already exists"
            mastered=samples*(10**(-8/20))*.55
            write_wav(path,mastered[:round(args.review_seconds*grid["sample_rate"])],grid["sample_rate"])
        path=destination/(args.review_stem+"_boss_two_loops.wav"); assert not path.exists()
        write_wav(path,np.tile(mixes["boss_run"]*(10**(-8/20))*.55,(2,1)),grid["sample_rate"])
    print(json.dumps({"passed":True,"grid":grid,"stems":{n:manifest["stems"][n]["rms_dbfs"] for n in NAMES},"mixes":manifest["mixes"],"adaptive_vertex_maximum_peak":manifest["adaptive_vertex_maximum_peak"]},indent=2))


if __name__=="__main__": main()
