"""Two original arrangement stems on the accepted grid; preserve all old PCM."""
from __future__ import annotations
import argparse,hashlib,json,math,sys
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/audio'))
import compose_foundation as foundation
OUT=ROOT/'assets/audio/music'
SCORE=OUT/'run_arrangement_003a1.json'
NAMES=('run_opening','run_motion')
OLD=('title','workshop','run_base','run_pressure','run_boss')

def render(score,base):
    grid=base['grid']; rate=int(grid['sample_rate']);frames=int(grid['frames']);beats=int(grid['beats'])
    seconds=frames/rate;beat_seconds=seconds/beats
    original=json.loads((OUT/'foundation_score.json').read_text())
    stems={name:np.zeros((frames,2)) for name in NAMES};counts={name:{} for name in NAMES};cache={}
    def add(name,kind,beat,length,note,gain,pan=0.0,variant=1):
        duration=length*beat_seconds+{'chug':.025,'power':.18,'lead':.11,'crash':.8}.get(kind,.035)
        key=(kind,note,round(duration,7),variant)
        if key not in cache:cache[key]=foundation.synth(kind,note,duration,rate,variant)
        voice=cache[key]*gain;start=round(beat/beats*frames)
        stereo=voice[:,None]*np.array([math.sqrt((1-pan)/2),math.sqrt((1+pan)/2)])
        indices=(start+np.arange(len(voice)))%frames;np.add.at(stems[name],indices,stereo)
        counts[name][kind]=counts[name].get(kind,0)+1
    for bar,chord in enumerate(original['progression']):
        harmony=original['harmony'][chord];root=harmony['guitar_root'];beat=bar*4
        for offset,length,interval in score['opening_riffs'][bar%4]:
            for pan,variant in ((-.73,0),(.73,2)):add('run_opening','chug',beat+offset+.018*(variant==2),length,root+interval,.34,pan,variant)
            add('run_opening','bass',beat+offset,length+0.35,harmony['bass']+interval,.23)
        for offset in score['opening_kick']:add('run_opening','kick',beat+offset,.28,36,.28,0,bar%3)
        for offset in score['opening_snare']:add('run_opening','snare',beat+offset,.38,38,.19,-.10,bar%3)
        for offset in score['opening_hat']:add('run_opening','hat',beat+offset,.16,42,.035,.38,bar%3)
        if bar in score['opening_hook_bars']:
            for offset,length,interval in score['opening_hook']:add('run_opening','power',beat+offset,length,root+interval,.12,-.08,1)
        for offset,length,interval in score['motion_riffs'][bar%2]:
            add('run_motion','chug',beat+offset,length,root+interval,.20,-.50 if bar%2 else .50,bar%3)
            add('run_motion','bass',beat+offset,length,harmony['bass']+interval,.12)
        for offset in score['motion_kick']:add('run_motion','kick',beat+offset,.22,36,.16,0,(bar+1)%3)
        if bar%4==3:
            for i,offset in enumerate((3.0,3.5,3.75)):add('run_motion','snare',beat+offset,.2,38,.065,-.25+i*.20,bar%3)
        if bar in score['motion_hook_bars']:
            for offset,length,interval in score['motion_hook']:add('run_motion','power',beat+offset,length,root+interval,.10,.12,1)
    for name,stem in stems.items():
        join=round(rate*.002);bridge=np.sin(np.linspace(0,math.pi/2,join))**2
        boundary=(stem[0]+stem[-1])*.5
        stem[:join]=boundary+(stem[:join]-boundary)*bridge[:,None]
        stem[-join:]=boundary+(stem[-join:]-boundary)*bridge[::-1,None]
        stem-=stem.mean(axis=0,keepdims=True)
        stem*=({'run_opening':.46,'run_motion':.16}[name]/float(np.max(np.abs(stem))))
    old={name:foundation.read_wav(OUT/(name+'.wav'))[0] for name in OLD[2:]}
    def peak_at(gain):
        maximum=0.0
        for mask in range(1,32):
            mix=np.zeros_like(stems[NAMES[0]])
            for i,name in enumerate((*OLD[2:],*NAMES)):
                if mask&(1<<i):mix+=old[name] if name in old else stems[name]*gain
            maximum=max(maximum,float(np.max(np.abs(mix))))
        return maximum
    low,high=0.0,1.0
    if peak_at(high)>score['mix_peak_ceiling']:
        for _ in range(18):
            middle=(low+high)/2
            if peak_at(middle)<=score['mix_peak_ceiling']:low=middle
            else:high=middle
        gain=low
    else:gain=1.0
    for stem in stems.values():stem*=gain
    return stems,{'sample_rate':rate,'frames':frames,'seconds':seconds,'beats':beats,'instrument_events':counts,'render_gain':gain,'all_run_stem_cube_peak':peak_at(1.0)}

def main():
    p=argparse.ArgumentParser();p.add_argument('--verify-only',action='store_true');args=p.parse_args()
    score=json.loads(SCORE.read_text());base=json.loads((OUT/'manifest.json').read_text())
    protected={name:foundation.fingerprint(OUT/(name+'.wav')) for name in OLD}
    stems,grid=render(score,base);records={}
    for name,samples in stems.items():
        path=OUT/(name+'.wav')
        if not args.verify_only:foundation.write_wav(path,samples,grid['sample_rate'])
        actual,spec=foundation.read_wav(path)
        expected=np.round(samples*32767)/32767
        assert np.array_equal(actual,expected)
        stats=foundation.metrics(actual)
        assert stats['clipped_samples']==0 and stats['boundary_step']<.006
        assert .002<stats['rms']<.25
        records[name]={**spec,**stats,'sha256':foundation.fingerprint(path),'description':'Half-time spacious steel riff and backbeat' if name=='run_opening' else 'Mid-Run syncopated low riff and rhythmic answer'}
    assert protected=={name:foundation.fingerprint(OUT/(name+'.wav')) for name in OLD}
    record={'schema':1,'title':score['title'],'authorship':score['authorship'],'score_sha256':foundation.fingerprint(SCORE),
        'generator_sha256':foundation.fingerprint(Path(__file__)),'grid':grid,'stems':records,'preserved_music_sha256':protected,
        'opening_perceived_backbeat_bpm':score['opening_perceived_backbeat_bpm'],'transport_bpm':score['transport_bpm'],
        'runtime_arrangements':score['runtime_arrangements'],'original_music_manifest_sha256':foundation.fingerprint(OUT/'manifest.json'),
        'source':'run_arrangement_003a1.json + tools/audio/compose_run_variety_003a1.py; existing instrument synthesis, original new notes; no pitch/time stretching.'}
    manifest=OUT/'run_arrangement_003a1_manifest.json'
    if args.verify_only:assert json.loads(manifest.read_text())==record
    else:manifest.write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'passed':True,'stems':list(records),'old_music_wavs_byte_identical':True,'all_run_stem_cube_peak':grid['all_run_stem_cube_peak'],'manifest':str(manifest)},indent=2))
if __name__=='__main__':main()
