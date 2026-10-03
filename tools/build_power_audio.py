"""Reproduce short, dry mechanical power cues (22050 Hz mono PCM16).

All oscillators/noise are authored here; no downloaded samples or dependencies.
Audio randomness is local to offline export and cannot touch combat randomness.
"""
from pathlib import Path
import argparse
import math
import random
import struct
import wave

OUT=Path(__file__).resolve().parents[1]/"assets/audio"
RATE=22050


def render(name,duration,frequency,end_frequency,noise,mix,pulses=1):
    rng=random.Random(name)
    frames=[];phase=0.;last=0.
    for i in range(round(duration*RATE)):
        t=i/RATE;u=t/duration
        phase += math.tau*(frequency+(end_frequency-frequency)*u)/RATE
        strike=math.exp(-u*5.5)
        if pulses>1:
            local=(u*pulses)%1
            strike=math.exp(-local*5)*(.85-.35*u)
        attack=min(1,t/.003)
        tail=min(1,(duration-t)/.020)
        metal=math.sin(phase)*.55+math.sin(phase*2.71)*.25+math.sin(phase*4.13)*.12
        # Filtered one-pole noise gives a short low mechanical pressure component.
        last=last*.78+rng.uniform(-1,1)*.22
        sample=(metal*mix+last*noise)*strike*attack*tail
        frames.append(struct.pack("<h",round(max(-.95,min(.95,sample)) * 25000)))
    with wave.open(str(OUT/(name+".wav")),"wb") as w:
        w.setnchannels(1);w.setsampwidth(2);w.setframerate(RATE);w.writeframes(b"".join(frames))


if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--progression-only",action="store_true",help="Export 002B.1 progression cues without overwriting existing power/combat audio")
    args=parser.parse_args()
    OUT.mkdir(parents=True,exist_ok=True)
    power_cues=[
        ("power_wake",.28,180,45,1.30,.68,1),
        ("redline",.31,190,630,.45,.78,1),
        ("comet_charge",.22,720,1150,.22,.72,1),
        ("comet_release",.22,320,60,1.25,.77,1),
        ("second_wind",.56,160,1150,.38,.73,3),
        ("chain",.25,370,100,.95,.61,2),
        ("wave",.36,500,360,.35,.55,3),
        ("afterimage",.12,580,260,.38,.40,1),
        ("acquire",.37,520,1040,.10,.60,3),
    ]
    progression_cues=[
        # The focus detent stays deliberately quiet and under 60 ms.
        ("ui_focus",.055,920,670,.70,.24,1),
        # A positive latch; acquisition's existing three-strike cue follows it.
        ("card_select",.16,390,940,.54,.70,2),
        # One restrained tension ping on crossing the near-level threshold.
        ("near_level",.13,680,880,.08,.38,1),
        # Heavier three-step pressure release, distinct from all combat cues.
        ("level_up",.49,250,1420,.55,.78,3),
        # A short flywheel clutch settles the player back into combat.
        ("resume",.18,760,310,.52,.49,2),
    ]
    for cue in progression_cues if args.progression_only else power_cues+progression_cues:
        render(*cue)
    print("Exported %d mechanical cues; maximum 0.56 seconds, no loops." % (5 if args.progression_only else 14))
