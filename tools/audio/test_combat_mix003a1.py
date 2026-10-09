"""PCM headroom/dynamic range, loop continuity and accepted-music byte locks."""
import hashlib,json,math,os,subprocess,unittest,wave
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/audio/impact_003a1'
def pcm(name):
    with wave.open(str(OUT/(name+'.wav')),'rb') as w:
        assert (w.getnchannels(),w.getsampwidth(),w.getframerate())==(1,2,32000)
        return np.frombuffer(w.readframes(w.getnframes()),dtype='<i2').astype(float)/32768
class AudioMix(unittest.TestCase):
    def test_original_pcm_bounded_without_clipping(self):
        manifest=json.loads((OUT/'manifest.json').read_text())
        self.assertEqual(len(manifest['sounds']),11)
        for name,row in manifest['sounds'].items():
            samples=pcm(name);self.assertLess(np.max(np.abs(samples)),.77)
            self.assertFalse(np.any(np.abs(samples)>=1));self.assertLess(abs(np.mean(samples)),.0001)
            self.assertAlmostEqual(len(samples)/32000,row['duration_seconds'])
    def test_obvious_five_level_ladder(self):
        gains={'metal_light':-22,'metal_normal':-16,'metal_clang':-10,'metal_massive':-8,'metal_extreme':-6}
        peaks=[20*math.log10(np.max(np.abs(pcm(k))))+db for k,db in gains.items()]
        self.assertTrue(all(b-a>=2 for a,b in zip(peaks,peaks[1:])),peaks)
        self.assertGreater(peaks[-1]-peaks[0],20,'Routine contact must not sit at the front like the strongest hit')
        grind=20*math.log10(np.max(np.abs(pcm('metal_grind'))))-29
        self.assertLess(grind,peaks[0]-6,'Steady friction sits beneath light contact and music')
    def test_short_crack_and_nonclicking_loop(self):
        snap=pcm('metal_crack');loop=pcm('metal_grind')
        self.assertLess(len(snap)/32000,.08)
        self.assertLess(abs(loop[-1]-loop[0]),.06,'Periodic texture must not have a resetting impact at its seam')
        self.assertLess(np.max(np.abs(snap[-256:])),.01,'No thunder or long electrical tail')
    def test_music_all_assets_byte_exact(self):
        configured=os.environ.get('TOPGAME_PRESERVATION_BASELINE')
        candidates=[Path(configured)] if configured else sorted((ROOT.parent/'GyroBrothers-QA/003A.1/manifests').glob('*preservation_start*.json'),reverse=True)
        records=[]
        for p in candidates:
            data=json.loads(p.read_text())
            if 'assets' in data:records.append(data)
        if not records:self.skipTest('Supply TOPGAME_PRESERVATION_BASELINE for exact accepted worktree byte locks')
        baseline=max(records,key=lambda x:x.get('created_utc',''))['assets']
        files=[rel for rel in baseline if rel.startswith('assets/audio/music/')]
        self.assertGreater(len(files),10)
        # Accepted native masters use mixed authored LF/Windows CRLF text.
        # The preservation start hashes are authoritative byte locks; Git's
        # normalized JSON blob cannot prove an exact original worktree byte.
        for rel in files:self.assertEqual(hashlib.sha256((ROOT/rel).read_bytes()).hexdigest(),baseline[rel]['sha256'],rel)
if __name__=='__main__':unittest.main()
