"""Deterministic short metallic floor-chip receipt, separate from accepted music."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
from pathlib import Path
import random
import struct
import wave

ROOT = Path(__file__).resolve().parents[2]
TARGET = ROOT / "assets/audio/pickup_collect.wav"
RATE = 48000
SECONDS = .18


def wav_bytes() -> bytes:
    noise = random.Random(3001)
    samples = []
    for index in range(round(RATE*SECONDS)):
        t = index/RATE
        attack = min(1.0, t/.0015)
        tail = max(0.0, min(1.0, (SECONDS-t)/.020))
        phase = 2*math.pi*(1070*t-600*t*t)
        clink = .34*math.sin(phase)*math.exp(-t*34)
        clink += .19*math.sin(2*math.pi*1823*t)*math.exp(-t*48)
        clink += .10*math.sin(2*math.pi*2677*t)*math.exp(-t*70)
        click = .12*(noise.random()*2-1)*math.exp(-t*600)
        samples.append(round((clink+click)*attack*tail*32767))
    output = io.BytesIO()
    with wave.open(output, "wb") as stream:
        stream.setnchannels(1); stream.setsampwidth(2); stream.setframerate(RATE)
        stream.writeframes(struct.pack("<"+"h"*len(samples), *samples))
    return output.getvalue()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    expected = wav_bytes()
    if args.verify_only: assert TARGET.read_bytes() == expected, "Pickup PCM differs from its deterministic recipe"
    else: TARGET.write_bytes(expected)
    print(json.dumps({"passed":True,"file":str(TARGET),"sha256":hashlib.sha256(expected).hexdigest(),
                      "duration_seconds":SECONDS,"sample_rate":RATE,"channels":1,"character":"single metallic click/chirp with a soft downward tail; no chord, arpeggio or looping"}))


if __name__ == "__main__": main()
