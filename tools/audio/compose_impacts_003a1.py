"""Original metal contact families: offline struck modes and friction, no samples."""
from __future__ import annotations
import argparse, hashlib, json, math, wave
from pathlib import Path
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/audio/impact_003a1'
RATE=32000
FAMILIES={
    'metal_light':(.065,1510,.34,'tick'),
    'metal_normal':(.17,680,.48,'contact'),
    'metal_clang':(.30,345,.65,'clang'),
    'metal_edge':(.13,920,.40,'edge'),
    'metal_scrape':(.19,740,.32,'scrape'),
    'metal_massive':(.39,175,.70,'slam'),
    'metal_extreme':(.46,132,.76,'extreme'),
    'metal_crack':(.072,2400,.56,'crack'),
    'metal_grind':(1.0,660,.26,'grind'),
    'metal_wall':(.19,410,.48,'rail'),
    'metal_takedown':(.47,205,.70,'defeat'),
}

def render(name):
    seconds,root,peak,kind=FAMILIES[name]
    n=round(seconds*RATE); t=np.arange(n,dtype=np.float64)/RATE
    rng=np.random.default_rng(int.from_bytes(hashlib.sha256(name.encode()).digest()[:8],'little'))
    noise=rng.normal(0,.45,n)
    if kind=='grind':
        # Periodic band-limited roughness has no resetting attack or click.
        # One persistent loop is enveloped by actual runtime contact, rather
        # than replaying this waveform at every collision or physics tick.
        spectrum=np.fft.rfft(noise)
        frequencies=np.fft.rfftfreq(n,1/RATE)
        spectrum*=np.exp(-((frequencies-2100)/1900)**2)*(1-np.exp(-frequencies/500))
        signal=np.fft.irfft(spectrum,n)
        signal*=(.76+.17*np.sin(math.tau*7*t)+.07*np.sin(math.tau*19*t))
        signal-=signal.mean();signal*=peak/max(1e-12,np.max(np.abs(signal)))
        return np.rint(signal*32767).astype('<i2').tobytes()
    if kind=='crack':
        # Short aperiodic mechanical/electrical fracture; no thunder tail.
        high=noise-np.convolve(noise,np.ones(17)/17,mode='same')
        signal=high*np.exp(-t*105)
        for delay,factor in [(.003,.52),(.009,.22)]:
            at=round(delay*RATE);signal[at:]+=high[:-at]*np.exp(-np.arange(n-at)/RATE*180)*factor
        signal*=np.minimum(1,t/.0003)*np.minimum(1,(seconds-t)/.008)
        signal-=signal.mean();signal*=peak/max(1e-12,np.max(np.abs(signal)))
        return np.rint(signal*32767).astype('<i2').tobytes()
    # A discontinuous noisy excitation hits inharmonic steel modes. Each mode
    # rings and damps independently: no arcade pitch sweep or UI oscillator.
    signal=np.zeros(n)
    ratios=(1,1.731,2.417,3.293,4.739,6.127,8.619,11.173)
    for i,ratio in enumerate(ratios):
        frequency=root*ratio
        decay=(48 if kind=='tick' else (22 if kind=='contact' else 10.5))+(i*2.2)
        if kind in ('edge','scrape'): decay=18+i*2.5
        signal+=(.30/(1+i)**.72)*np.sin(math.tau*frequency*t+.73*i)*np.exp(-t*decay)
    high=noise-np.convolve(noise,np.ones(9)/9,mode='same')
    signal+=high*np.exp(-t*(220 if kind=='tick' else 145))*1.50
    # Friction is a short rising/falling blade rake with irregular asperities,
    # while direct slams carry a lower mechanical shell mode and double strike.
    if kind in ('edge','scrape'):
        friction=np.convolve(high,np.array([.3,-.15,.5,-.15]),mode='same')
        rough=.48+.52*np.sin(math.tau*61*t+.6*np.sin(math.tau*13*t))**2
        signal+=friction*rough*np.exp(-t*8)*(1-np.exp(-t*120))*1.25
    if kind in ('clang','slam','extreme','rail','defeat'):
        signal+=.43*np.sin(math.tau*(root*.53)*t+.24)*np.exp(-t*38)
        offset=round((.028 if kind=='slam' else .043)*RATE)
        signal[offset:]+=signal[:-offset]*.22
    if kind=='defeat':
        for delay,factor in ((.075,.28),(.145,.17)):
            at=round(delay*RATE)
            signal[at:]+=high[:n-at]*np.exp(-np.arange(n-at)/RATE*75)*factor
    attack=np.minimum(1,t/.0006)
    tail=np.minimum(1,(seconds-t)/.024)
    signal=signal*attack*tail
    signal-=signal.mean()
    signal*=peak/max(1e-12,np.max(np.abs(signal)))
    return np.rint(signal*32767).astype('<i2').tobytes()

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--verify-only',action='store_true');args=parser.parse_args()
    OUT.mkdir(parents=True,exist_ok=True); records={}
    for name,(_,_,peak,kind) in FAMILIES.items():
        pcm=render(name);path=OUT/(name+'.wav')
        if args.verify_only:
            with wave.open(str(path),'rb') as wav:
                assert (wav.getnchannels(),wav.getsampwidth(),wav.getframerate())==(1,2,RATE)
                assert wav.readframes(wav.getnframes())==pcm
        else:
            with wave.open(str(path),'wb') as wav:
                wav.setnchannels(1);wav.setsampwidth(2);wav.setframerate(RATE);wav.writeframes(pcm)
        samples=np.frombuffer(pcm,dtype='<i2').astype(np.float64)/32768
        records[name]={'file':path.name,'family':kind,'frames':len(pcm)//2,'duration_seconds':len(pcm)/2/RATE,
            'peak':float(np.max(np.abs(samples))),'rms':float(np.sqrt(np.mean(samples*samples))),
            'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'pcm_sha256':hashlib.sha256(pcm).hexdigest()}
    record={'schema':1,'task':'003A.1','authorship':'Original struck inharmonic steel modes and friction excitations; authored source parameters and fixed offline noise. No commercial/downloaded samples.',
        'format':{'sample_rate':RATE,'channels':1,'sample_bits':16},'runtime_pitch_range':[.97,1.04],
        'hierarchy':'Quiet tick/edge/friction; moderate normal/rail; body clang; rare massive/extreme; short fracture accent. No pitched cartoon sweeps.',
        'grind_loop':'One periodic band-limited loop with runtime contact continuity and smooth attack/release; never per-physics-frame retriggered.',
        'headroom':'Per-cue peak≤.76; eight one-shots plus one quiet grind player share a conservative0.62 full-scale SFX peak budget; unchanged music PCM/transport, existing Music trim and rare-event duck. Native mixed-bus capture validates actual headroom.',
        'sounds':records}
    manifest=OUT/'manifest.json'
    if args.verify_only:assert json.loads(manifest.read_text())==record
    else:manifest.write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'passed':True,'original_families':len(records),'manifest':str(manifest),'verify_only':args.verify_only},indent=2))

if __name__=='__main__':main()
