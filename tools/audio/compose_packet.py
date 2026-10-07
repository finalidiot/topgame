"""Render original finite packet foley from an editable 003A material score.

No recordings or external sample libraries are used. Deterministic offline noise
excites paper folds, rough seam fracture and short metal/wood modes. The eight
short cues sit on the existing SFX bus; rarity uses a restrained metal accent.
Default exports the saved score. --author reconstructs it explicitly, while
--verify-only compares frozen WAV bytes and exact PCM metrics without writes.
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
OUT = ROOT / "assets/audio/shop_003a"
SCORE_PATH = OUT / "packet_score.json"
RATE = 32000


def original_score():
    # Finite paper pulses have intentionally asymmetric pressure/release timing.
    # Metal accents name physical damped modes, rather than celebratory arpeggios.
    return {"version":1,"task":"003A","sample_rate":RATE,"channels":1,
            "authoring":"Original project-authored finite material synthesis; no recordings/samples.",
            "mix":"Existing SFX bus. Quiet dry pouch foley; two-strike rare accent. No soundtrack restart.",
            "cues":{
        "packet_land":{"seconds":0.24,"seed":30801,"peak":0.48,"paper":[[0.006,0.050,0.55],[0.030,0.080,0.32],[0.096,0.060,0.14]],"modes":[[0.009,160,0.28,40],[0.015,290,0.19,50],[0.028,620,0.07,65]]},
        "packet_crinkle":{"seconds":0.34,"seed":30802,"peak":0.55,"paper":[[0.010,0.035,0.45],[0.055,0.026,0.60],[0.092,0.045,0.38],[0.148,0.030,0.67],[0.186,0.045,0.50],[0.254,0.031,0.28]],"modes":[]},
        "packet_tear":{"seconds":0.56,"seed":30803,"peak":0.56,"tear":[[0.018,0.105,0.70],[0.124,0.140,0.62],[0.270,0.165,0.76],[0.438,0.051,0.42]],"paper":[[0.027,0.018,0.40],[0.096,0.012,0.35],[0.175,0.017,0.39],[0.257,0.011,0.44],[0.350,0.016,0.36],[0.465,0.025,0.29]],"modes":[]},
        "packet_spill":{"seconds":0.57,"seed":30804,"peak":0.51,"paper":[[0.008,0.100,0.44],[0.103,0.077,0.31],[0.207,0.067,0.18]],"modes":[[0.13,760,0.26,24],[0.21,1550,0.20,32],[0.29,2650,0.16,40],[0.40,1900,0.06,42]]},
        "packet_clink":{"seconds":0.28,"seed":30805,"peak":0.45,"paper":[[0.002,0.017,0.12]],"modes":[[0.003,1340,0.42,24],[0.003,2371,0.26,37],[0.006,3520,0.14,46],[0.059,1700,0.06,48]]},
        "packet_new":{"seconds":0.38,"seed":30806,"peak":0.43,"paper":[[0.004,0.030,0.15]],"modes":[[0.006,330,0.36,22],[0.006,995,0.10,32],[0.094,660,0.28,17],[0.094,1980,0.05,29]]},
        "packet_rare":{"seconds":0.66,"seed":30807,"peak":0.44,"paper":[[0.004,0.020,0.10]],"modes":[[0.006,440,0.36,12],[0.006,1120,0.13,21],[0.156,660,0.31,9],[0.156,1690,0.09,16],[0.156,2410,0.025,26]]},
        "packet_recycle":{"seconds":0.34,"seed":30808,"peak":0.44,"paper":[[0.010,0.026,0.31],[0.058,0.041,0.24],[0.133,0.059,0.17]],"modes":[[0.015,490,0.29,22],[0.055,810,0.20,28],[0.136,240,0.19,24]]},
    }}


def band_noise(count, rng, low, high):
    # Pad before frequency shaping, so the finite tail never wraps to the start.
    size=1 << (count+2048-1).bit_length()
    spectrum=np.fft.rfft(rng.uniform(-1,1,size))
    hz=np.fft.rfftfreq(size,1/RATE)
    response=hz**2/(hz**2+low**2) / np.sqrt(1+(hz/high)**8)
    return np.fft.irfft(spectrum*response,n=size)[:count]


def render_cue(spec):
    count=round(float(spec["seconds"])*RATE)
    t=np.arange(count,dtype=float)/RATE
    signal=np.zeros(count)
    rng=np.random.default_rng(int(spec["seed"]))
    paper=band_noise(count,rng,760,6400)
    rasp=band_noise(count,rng,1700,7300)
    # Deliberately finite material grains. The pulses sound like small creases
    # under pressure rather than an endlessly running ambient hiss.
    for start,duration,amplitude in spec.get("paper",[]):
        local=t-start
        phase=np.clip(local/duration,0,1)
        envelope=(local>=0)*(local<duration)*np.sin(math.pi*phase)**1.8
        flutter=0.60+0.40*np.sin(math.tau*(113+start*70)*local+0.18)**2
        signal+=paper*envelope*flutter*amplitude
    for start,duration,amplitude in spec.get("tear",[]):
        local=t-start
        phase=np.clip(local/duration,0,1)
        envelope=(local>=0)*(local<duration)*np.sin(math.pi*phase)**0.65
        fracture=0.28+0.72*np.sin(math.tau*(72+start*31)*local)**6
        signal+=rasp*envelope*fracture*amplitude
    for start,frequency,amplitude,decay in spec.get("modes",[]):
        local=np.maximum(0,t-start)
        # Smooth sub-millisecond impact gives a dry contact without PCM clicks.
        attack=np.minimum(1,local/.0008)
        mode=np.sin(math.tau*frequency*local+.05*np.sin(math.tau*frequency*.006*local))
        signal+=(t>=start)*mode*np.exp(-decay*local)*attack*amplitude
    # A short final window removes the last residual mode without automatic WAV
    # trimming; timing is an exact grid used by production cues and QA.
    signal*=np.minimum(1,t/.002)*np.minimum(1,np.maximum(0,float(spec["seconds"])-t)/.035)
    signal-=float(signal.mean())
    signal*=np.minimum(1,t/.002)*np.minimum(1,np.maximum(0,float(spec["seconds"])-t)/.020)
    maximum=float(np.max(np.abs(signal)))
    if maximum>0:
        signal*=float(spec["peak"])/maximum
    return np.round(signal*32767).astype("<i2")


def metrics(pcm):
    samples=pcm.astype(float)/32768
    return {"pcm_frames":len(pcm),"seconds":len(pcm)/RATE,
            "peak_dbfs":round(20*math.log10(max(1e-12,float(np.max(np.abs(samples))))),4),
            "rms_dbfs":round(20*math.log10(max(1e-12,float(np.sqrt(np.mean(samples**2))))),4),
            "dc_mean":round(float(samples.mean()),8),"pcm_sha256":hashlib.sha256(pcm.tobytes()).hexdigest()}


def read_score():
    score=json.loads(SCORE_PATH.read_text(encoding="utf-8"))
    assert score["sample_rate"]==RATE and score["channels"]==1
    assert set(score["cues"])==set(original_score()["cues"])
    return score


def write():
    score=read_score()
    manifest={"version":1,"task":"003A","score":"packet_score.json","sample_rate":RATE,"channels":1,"format":"16-bit signed little-endian PCM","original":True,"cues":{}}
    for name,spec in score["cues"].items():
        pcm=render_cue(spec)
        path=OUT / f"{name}.wav"
        with wave.open(str(path),"wb") as audio:
            audio.setnchannels(1);audio.setsampwidth(2);audio.setframerate(RATE);audio.writeframes(pcm.tobytes())
        manifest["cues"][name]={"file":f"{name}.wav",**metrics(pcm),"file_sha256":hashlib.sha256(path.read_bytes()).hexdigest()}
    (OUT / "manifest.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    return manifest


def verify():
    score=read_score()
    manifest=json.loads((OUT / "manifest.json").read_text())
    for name,spec in score["cues"].items():
        expected=render_cue(spec)
        path=OUT / f"{name}.wav"
        with wave.open(str(path),"rb") as audio:
            assert (audio.getnchannels(),audio.getsampwidth(),audio.getframerate())==(1,2,RATE),f"{name}: PCM format"
            actual=audio.readframes(audio.getnframes())
        assert actual==expected.tobytes(),f"{name}: edited score/runtime mismatch"
        assert manifest["cues"][name]=={"file":f"{name}.wav",**metrics(expected),"file_sha256":hashlib.sha256(path.read_bytes()).hexdigest()},f"{name}: manifest drift"
        assert abs(int(expected[0]))<=1 and abs(int(expected[-1]))<200,f"{name}: finite endpoints"
        assert len(expected)>0 and float(np.max(np.abs(expected.astype(float))))<32767,f"{name}: PCM clipping"
    return {"task":"003A","read_only":True,"original_material_synthesis":True,"score_runtime_parity":True,"cues_verified":8,"manifest":manifest}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--author",action="store_true")
    parser.add_argument("--verify-only",action="store_true")
    parser.add_argument("--report",type=Path)
    parser.add_argument("--audition",type=Path,help="External QA joined cue sequence WAV")
    args=parser.parse_args()
    for path in [args.report,args.audition]:
        if path and (path.resolve()==ROOT or ROOT in path.resolve().parents):
            raise ValueError("QA output must be outside game repository")
    if args.author and args.verify_only:
        parser.error("--verify-only is read-only")
    if args.author:
        OUT.mkdir(parents=True,exist_ok=True)
        SCORE_PATH.write_text(json.dumps(original_score(),indent=2)+"\n",encoding="utf-8")
    report=verify() if args.verify_only else write()
    if args.report:
        args.report.parent.mkdir(parents=True,exist_ok=True)
        args.report.write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    if args.audition:
        score=read_score()
        pieces=[]
        for spec in score["cues"].values():
            pieces.extend([render_cue(spec),np.zeros(round(RATE*.45),dtype="<i2")])
        args.audition.parent.mkdir(parents=True,exist_ok=True)
        with wave.open(str(args.audition),"wb") as audio:
            audio.setnchannels(1);audio.setsampwidth(2);audio.setframerate(RATE);audio.writeframes(np.concatenate(pieces).tobytes())
    print(json.dumps(report,indent=2))


if __name__=="__main__":
    main()
