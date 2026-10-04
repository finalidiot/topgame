"""Original Task 002C short mechanical signatures, 22050Hz mono PCM16.

This exporter writes only new named escalation cues. No samples, downloads,
runtime loops, or gameplay RNG are used. Components are deliberately staggered
strikes/sweeps so overload, anchoring, storage and route closure sound different.
"""
from pathlib import Path
import json
import math
import random
import struct
import wave

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/"assets/audio"
RATE=22050

# (start,duration,startHz,endHz,gain,noise,decay,inharmonic ratio)
CUES={
    "rank_up":(.43,[(0,.15,370,430,.45,.35,8,2.7),(.09,.23,720,880,.40,.10,6,2.04),(.21,.22,1100,1350,.32,.06,5,1.51)]),
    "mutation_available":(.66,[(0,.26,220,330,.40,.18,4,2.1),(.12,.30,620,730,.35,.05,4,1.50),(.36,.30,930,1180,.33,.08,4,1.25)]),
    "mutation_select":(.61,[(0,.17,105,56,.70,.75,9,2.73),(.05,.37,420,680,.43,.22,5,1.51),(.19,.39,880,1320,.35,.05,5,2.01)]),
    "redline_ii":(.32,[(0,.28,150,930,.55,.48,2.4,2.71),(.08,.17,320,1080,.24,.20,3,3.13)]),
    "runaway":(.27,[(0,.13,190,570,.42,.55,4,2.71),(.07,.13,240,690,.38,.45,4,3.13),(.16,.10,390,950,.34,.25,4,2.21)]),
    "runaway_hit":(.18,[(0,.14,160,48,.60,.70,8,3.1),(.02,.16,760,460,.25,.20,7,2.7)]),
    "breakneck_charge":(.28,[(0,.26,70,850,.48,.40,1.5,2.71),(.10,.18,270,1700,.25,.13,1.5,2.03)]),
    "breakneck_impact":(.44,[(0,.39,86,34,.79,.85,8,2.73),(.02,.31,710,290,.33,.42,7,3.17),(.07,.37,1400,590,.20,.15,7,2.27)]),
    "anchor":(.22,[(0,.09,160,90,.41,.54,8,2.7),(.07,.09,140,75,.39,.42,8,3.1),(.14,.08,98,55,.56,.55,9,2.2)]),
    "anchor_break":(.24,[(0,.21,540,230,.37,.72,5,3.3),(.03,.17,290,75,.41,.45,7,2.7)]),
    "bulwark_impact":(.38,[(0,.32,63,38,.74,.77,9,2.73),(.01,.37,410,330,.43,.20,6,3.19),(.03,.30,940,710,.22,.14,8,2.4)]),
    "counterweight_store":(.24,[(0,.10,310,160,.40,.43,8,2.7),(.055,.185,240,600,.40,.15,2.2,1.51)]),
    "counterweight_release":(.42,[(0,.34,710,70,.62,.61,6,2.71),(.04,.20,280,56,.53,.42,8,3.1),(.10,.32,980,280,.22,.09,5,1.5)]),
    "afterimage_ii":(.15,[(0,.15,890,410,.30,.16,4,2.03),(.035,.11,1260,680,.20,.09,5,1.5)]),
    "ghost_closure":(.30,[(0,.23,840,960,.35,.04,5,1.50),(.055,.245,1120,1280,.34,.05,5,2.01)]),
    "ghost_activation":(.47,[(0,.38,110,54,.47,.30,5,2.71),(.01,.46,470,720,.33,.06,4,1.50),(.11,.35,940,1440,.22,.02,5,2.01)]),
    "slipstream_cross":(.18,[(0,.18,410,1370,.34,.25,2.0,1.51),(.05,.13,920,1800,.23,.09,3.5,2.03)]),
}


def render(name,duration,components):
    samples=[0.0]*round(duration*RATE)
    for index,(start,length,frequency,last_frequency,gain,noise,decay,ratio) in enumerate(components):
        rng=random.Random(name+str(index));phase=0.0;filtered=0.0;previous=0.0
        for offset in range(round(length*RATE)):
            position=round(start*RATE)+offset
            if position>=len(samples):break
            t=offset/RATE;u=t/length
            phase+=math.tau*(frequency+(last_frequency-frequency)*u)/RATE
            # Short attack and tail prevent edit-boundary clicks. Harmonic ratios
            # distinguish steel strikes from more tonal clutch/circuit signatures.
            envelope=min(1,t/.0025)*min(1,(length-t)/.014)*math.exp(-u*decay)
            metal=math.sin(phase)*.70+math.sin(phase*ratio)*.20+math.sin(phase*4.13)*.10
            white=rng.uniform(-1,1);filtered=filtered*.72+white*.28
            texture=.70*filtered+.16*(white-previous);previous=white
            samples[position]+=(metal*gain+texture*noise)*envelope
    peak=max(abs(s) for s in samples) or 1
    scale=min(1,.86/peak)
    raw=b"".join(struct.pack("<h",round(s*scale*30000)) for s in samples)
    with wave.open(str(OUT/(name+".wav")),"wb") as output:
        output.setnchannels(1);output.setsampwidth(2);output.setframerate(RATE);output.writeframes(raw)
    return {"file":name+".wav","duration_ms":round(duration*1000),"sample_rate":RATE,"channels":1,"sample_bits":16,"loop":False,"peak":round(peak*scale,4)}


if __name__=="__main__":
    OUT.mkdir(parents=True,exist_ok=True)
    manifest={"version":1,"authoring":"deterministic original component synthesis; finite mono mechanical one-shots","cues":{}}
    for name,(duration,components) in CUES.items():manifest["cues"][name]=render(name,duration,components)
    (OUT/"escalation_manifest.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    print("Exported 17 finite escalation signatures, 150–660ms. Existing cues untouched.")
