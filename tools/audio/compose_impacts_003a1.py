"""Original metal contact families: offline struck modes and friction, no samples."""
from __future__ import annotations
import argparse, hashlib, json, math, wave
from pathlib import Path
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/audio/impact_003a1'
RATE=32000
FAMILIES={
    'metal_light':(.095,1180,.42,'tick'),
    'metal_clang':(.29,430,.68,'clang'),
    'metal_edge':(.19,780,.54,'edge'),
    'metal_scrape':(.31,660,.46,'scrape'),
    'metal_massive':(.43,205,.72,'slam'),
    'metal_wall':(.25,315,.60,'rail'),
    'metal_takedown':(.47,290,.66,'defeat'),
}

def render(name):
    seconds,root,peak,kind=FAMILIES[name]
    n=round(seconds*RATE); t=np.arange(n,dtype=np.float64)/RATE
    rng=np.random.default_rng(int.from_bytes(hashlib.sha256(name.encode()).digest()[:8],'little'))
    noise=rng.uniform(-1,1,n)
    # A discontinuous noisy excitation hits inharmonic steel modes. Each mode
    # rings and damps independently: no arcade pitch sweep or UI oscillator.
    signal=np.zeros(n)
    ratios=(1,1.483,2.119,2.873,3.637,4.911,6.207,8.153)
    for i,ratio in enumerate(ratios):
        frequency=root*ratio
        decay=(16 if kind=='tick' else 7.8)+(i*.9)
        if kind in ('edge','scrape'): decay=9+i*1.25
        signal+=(.63/(1+i)**.57)*np.sin(math.tau*frequency*t+.17*i)*np.exp(-t*decay)
    high=noise-np.convolve(noise,np.ones(9)/9,mode='same')
    signal+=high*np.exp(-t*(190 if kind=='tick' else 105))*.72
    # Friction is a short rising/falling blade rake with irregular asperities,
    # while direct slams carry a lower mechanical shell mode and double strike.
    if kind in ('edge','scrape'):
        friction=np.convolve(high,np.array([.3,-.15,.5,-.15]),mode='same')
        rough=.48+.52*np.sin(math.tau*61*t+.6*np.sin(math.tau*13*t))**2
        signal+=friction*rough*np.exp(-t*8)*(1-np.exp(-t*120))*1.25
    if kind in ('slam','rail','defeat'):
        signal+=.62*np.sin(math.tau*(root*.43)*t)*np.exp(-t*23)
        offset=round((.028 if kind=='slam' else .043)*RATE)
        signal[offset:]+=signal[:-offset]*.22
    if kind=='defeat':
        for delay,factor in ((.075,.28),(.145,.17)):
            at=round(delay*RATE)
            signal[at:]+=high[:n-at]*np.exp(-np.arange(n-at)/RATE*75)*factor
    attack=np.minimum(1,t/.0006)
    tail=np.minimum(1,(seconds-t)/.024)
    signal=np.tanh(signal*1.25)*attack*tail
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
        'headroom':'Per-cue peak≤.72; bounded eight-channel SFX mixer, priority/cooldown, existing Master and Music trims. Native mixed-bus capture validates actual headroom.',
        'sounds':records}
    manifest=OUT/'manifest.json'
    if args.verify_only:assert json.loads(manifest.read_text())==record
    else:manifest.write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'passed':True,'original_families':len(records),'manifest':str(manifest),'verify_only':args.verify_only},indent=2))

if __name__=='__main__':main()
