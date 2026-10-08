"""Read actual saved native art and exported pixels, independent of painters."""
import json, math, sys, unittest
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from build_power_art import read_ase

class CombatNativeArt(unittest.TestCase):
    def test_venue_metadata_and_projection(self):
        frames,meta=read_ase(ROOT/'assets/source-art/arena_foundry_eight.aseprite')
        self.assertEqual((meta['cell'],meta['pivot'],meta['durations_ms'],meta['tags']),([640,360],[320,180],[100],{}))
        self.assertEqual(meta['layers'],['backdrop','structure','surface','markings','rear_rim','front_rim'])
        self.assertEqual(len(frames),1)
        geometry=json.loads((ROOT/'assets/arena/manifest.json').read_text())
        self.assertEqual(geometry['projection']['origin'],[320,165]);self.assertEqual(geometry['bounds']['world_playable'],[[-166,-104],[-104,-166],[104,-166],[166,-104],[166,104],[104,166],[-104,166],[-166,104]])
        self.assertEqual([g['region'] for g in geometry['ring_out_gates']],['u-v < -264 and abs(u+v)<=36','u-v > 264 and abs(u+v)<=36'])

    def test_separate_native_venue_layers_are_editable(self):
        for name in ['backdrop','structure','surface','markings','rear_rim','front_rim']:
            image=Image.open(ROOT/f'assets/arena/{name}.png').convert('RGBA')
            self.assertEqual(image.size,(640,360));self.assertIsNotNone(image.getbbox())
        surface=Image.open(ROOT/'assets/arena/surface.png').convert('RGBA')
        self.assertEqual(surface.getpixel((320,165))[3],255)
        self.assertEqual(surface.getpixel((12,165))[3],0)

    def test_embedded_hardware_has_five_native_states(self):
        frames,meta=read_ase(ROOT/'assets/source-art/combat_003a1/venue_lights.aseprite')
        self.assertEqual(meta['cell'],[640,360]);self.assertEqual(meta['pivot'],[0,0])
        self.assertEqual(list(meta['tags']),['EARLY','BUILDING','MID','LATE','EXTREME'])
        self.assertEqual(len(meta['layers']),3);self.assertEqual(len(frames),5)
        self.assertEqual(len({im.tobytes() for im in frames}),5)
        # Embedded hardware leaves the central battle floor entirely clear.
        for image in frames:self.assertIsNone(image.crop((220,110,420,220)).getbbox())

    def test_redline_ring_is_expanding_and_uncluttered(self):
        frames,meta=read_ase(ROOT/'assets/source-art/combat_003a1/redline_ring.aseprite')
        self.assertEqual(meta['pivot'],[64,64]);self.assertEqual(meta['tags'],{'IGNITE':{'from':0,'to':7}})
        widths=[]
        for image in frames:
            box=image.getbbox();self.assertIsNotNone(box);widths.append(box[2]-box[0])
            # All meaningful pixels belong to floor-plane ring/streak bands,
            # leaving the physical top's contact centre readable.
            self.assertIsNone(image.crop((61,61,68,68)).getbbox())
            self.assertLess(sum(a>0 for a in image.getchannel('A').tobytes()),image.width*image.height*.09)
        self.assertTrue(all(b>a for a,b in zip(widths,widths[1:])))

    def test_pursuit_uses_separate_saved_heading_keys(self):
        frames,meta=read_ase(ROOT/'assets/source-art/combat_003a1/power_motion.aseprite')
        signatures=[]
        for heading in ['e','se','s','sw','w','nw','n','ne']:
            tag=meta['tags']['PREDATOR_FLOW_'+heading];self.assertEqual(tag['to']-tag['from']+1,8)
            signatures.append(frames[tag['from']+3].tobytes())
        self.assertEqual(len(set(signatures)),8)
        self.assertEqual(len(meta['layers']),3);self.assertEqual(meta['pivot'],[24,16])

    def test_corrected_cards_keep_timelines_and_transparent_composition(self):
        for family,count in [('redline',5),('afterimage',6)]:
            frames,meta=read_ase(ROOT/f'assets/source-art/power_identity_002c5/{family}_cards.aseprite')
            manifest=json.loads((ROOT/f'assets/powers/identity/{family}_manifest.json').read_text())['cards']
            self.assertEqual(meta['layers'],manifest['layers']);self.assertEqual(len(meta['layers']),count)
            self.assertEqual(meta['durations_ms'],manifest['durations_ms']);self.assertEqual(meta['tags'],manifest['tags'])
            self.assertEqual(len(frames),48);self.assertEqual(meta['pivot'],[32,32])
            self.assertTrue(all(sum(a>0 for a in im.getchannel('A').tobytes())<64*64*.55 for im in frames))
            self.assertTrue(all(max(meta['durations_ms'][s['from']:s['to']+1])>min(meta['durations_ms'][s['from']:s['to']+1]) for s in meta['tags'].values()))

    def test_runtime_accent_manifest_retains_native_names_and_pivots(self):
        manifest=json.loads((ROOT/'assets/powers/combat_003a1/manifest.json').read_text())
        self.assertEqual(manifest['filter'],'nearest');self.assertTrue(manifest['presentation_only'])
        for family,export in manifest['families'].items():
            _,native=read_ase(ROOT/export['source'])
            for key in ['cell','pivot','tags','durations_ms','layers']:self.assertEqual(export[key],native[key])
            with Image.open(ROOT/export['texture'].removeprefix('res://')) as image:
                self.assertEqual(image.size,(export['cell'][0]*export['columns'],export['cell'][1]*math.ceil(export['frame_count']/export['columns'])))

if __name__=='__main__':unittest.main()
