"""Read saved native art and actual exports, not the constructor's outcome."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from PIL import Image, ImageOps
import ecology_art003a2 as art

class EcologyArtTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest=json.loads((art.OUT/'manifest.json').read_text(encoding='utf-8'))
        cls.qa=art.ROOT.parent/'GyroBrothers-QA/003A.2/temp'
        cls.qa.mkdir(parents=True,exist_ok=True)

    def test_exact_eight_ids_and_no_base_art_replacement(self):
        self.assertEqual(set(self.manifest['art']),{b for pair in art.FAMILIES.values() for b in pair})
        self.assertEqual(len(self.manifest['art']),8)
        self.assertTrue(all(not b.endswith('_ii') for b in self.manifest['art']))
        self.assertEqual(self.manifest['filter'],'nearest')

    def test_editable_native_layers_tags_durations_pivots(self):
        for family,branches in art.FAMILIES.items():
            for group,size,pivot,layers,count in [('cards',[64,64],[32,32],art.CARD_LAYERS,6),('icons',[16,16],[8,8],art.ICON_LAYERS,1)]:
                with self.subTest(family=family,group=group):
                    frames,meta=art.read_ase(art.SOURCE/f'{family}_{group}.aseprite')
                    self.assertEqual(meta['cell'],size);self.assertEqual(meta['pivot'],pivot)
                    self.assertEqual(meta['layers'],layers);self.assertEqual(list(meta['tags']),branches)
                    self.assertEqual(len(frames),count*2)
                    self.assertEqual(meta['durations_ms'],[v for b in branches for v in art.TIMES[b]] if group=='cards' else [160,160])
                    self.assertTrue(all(span['to']-span['from']+1==count for span in meta['tags'].values()))

    def test_six_distinct_source_poses_for_every_branch(self):
        for family,branches in art.FAMILIES.items():
            frames,meta=art.read_ase(art.SOURCE/f'{family}_cards.aseprite')
            for branch in branches:
                span=meta['tags'][branch];cels=frames[span['from']:span['to']+1]
                self.assertEqual(len({hashlib.sha256(im.tobytes()).hexdigest() for im in cels}),6,branch)

    def test_siblings_are_different_compositions_without_colour(self):
        for family,branches in art.FAMILIES.items():
            frames,_=art.read_ase(art.SOURCE/f'{family}_cards.aseprite')
            first=frames[art.STATIC[branches[0]]];second=frames[6+art.STATIC[branches[1]]]
            self.assertNotEqual(ImageOps.grayscale(first).tobytes(),ImageOps.grayscale(second).tobytes(),family)
            # Real displaced silhouettes/floor layouts differ. Recolouring an
            # identical composition cannot satisfy this alpha-mask comparison.
            difference=sum(a!=b for a,b in zip(first.getchannel('A').tobytes(),second.getchannel('A').tobytes()))
            self.assertGreater(difference,100,family)

    def test_every_card_has_transparent_field_and_intact_native_scale(self):
        for family in art.FAMILIES:
            frames,_=art.read_ase(art.SOURCE/f'{family}_cards.aseprite')
            for frame in frames:
                self.assertEqual(frame.size,(64,64))
                opaque=sum(value>0 for value in frame.getchannel('A').tobytes())
                self.assertGreater(opaque,300);self.assertLess(opaque,64*64*.55)
                self.assertEqual(frame.getpixel((0,0))[3],0)

    def test_native_body_components_are_copied_without_resize_or_recolour(self):
        blades,meta,parts=art.references()
        for kind in ('bastion','breaker'):
            expected=Image.new('RGBA',(64,64));offset=(8,6)
            expected.alpha_composite(parts['needle' if kind=='bastion' else 'flat'],offset)
            expected.alpha_composite(parts['ratchet'],offset)
            expected.alpha_composite(blades[meta['tags'][kind]['from']+3],offset)
            actual=Image.new('RGBA',(64,64));art.top(actual,kind,32,32,2)
            self.assertEqual(actual.tobytes(),expected.tobytes())

    def test_saved_source_runtime_rgba_and_metadata(self):
        for family in art.FAMILIES:
            for group in ('cards','icons'):
                frames,meta=art.read_ase(art.SOURCE/f'{family}_{group}.aseprite')
                saved=self.manifest['families'][family][group]
                for key in ('cell','pivot','layers','tags','durations_ms'):self.assertEqual(saved[key],meta[key])
                self.assertEqual(saved['source_sha256'],art.sha(art.SOURCE/f'{family}_{group}.aseprite'))
                target=art.OUT/f'{family}_{group}.png';self.assertEqual(saved['texture_sha256'],art.sha(target))
                sheet=Image.open(target).convert('RGBA');w,h=meta['cell'];columns=saved['columns']
                for index,frame in enumerate(frames):
                    cel=sheet.crop((index%columns*w,index//columns*h,(index%columns+1)*w,(index//columns+1)*h))
                    self.assertTrue(art.visible_equal(frame,cel))
                self.assertTrue(saved['native_runtime_rgba_exact'])

    def test_independent_unique_sixteen_pixel_icons(self):
        icons=[]
        for family in art.FAMILIES:
            frames,meta=art.read_ase(art.SOURCE/f'{family}_icons.aseprite')
            self.assertEqual(meta['cell'],[16,16]);icons.extend(frames)
        self.assertEqual(len({hashlib.sha256(im.tobytes()).hexdigest() for im in icons}),8)

    def test_card_timing_and_static_pose_come_from_native_metadata(self):
        for family,branches in art.FAMILIES.items():
            _,native=art.read_ase(art.SOURCE/f'{family}_cards.aseprite')
            for branch in branches:
                metadata=self.manifest['art'][branch];span=native['tags'][branch]
                self.assertEqual(metadata['card_frames'],6);self.assertEqual(metadata['card_cell'],64)
                self.assertEqual(metadata['card_row'],span['from']//6)
                self.assertEqual(metadata['card_durations_ms'],native['durations_ms'][span['from']:span['to']+1])
                self.assertIn(metadata['card_static_frame'],range(6))

    def test_accepted_reference_fingerprints_still_match(self):
        self.assertEqual(self.manifest['references'],{name:art.sha(art.ROOT/name) for name in art.REFERENCES})

    def test_actual_aseprite_open_and_parity_without_asset_writes(self):
        before={p:art.sha(p) for folder in (art.SOURCE,art.OUT) for p in folder.rglob('*') if p.is_file()}
        with tempfile.TemporaryDirectory(dir=self.qa,prefix='ecology-native-check-') as tmp:
            report=art.export(Path(r'F:\SteamLibrary\steamapps\common\Aseprite\Aseprite.exe'),Path(tmp)/'native',check=True)
            self.assertEqual(report['masters'],8);self.assertTrue(report['actual_aseprite_runtime_rgba_parity'])
        self.assertEqual(before,{p:art.sha(p) for p in before})

    def test_author_refuses_existing_artist_owned_masters(self):
        before={p:art.sha(p) for p in art.SOURCE.glob('*.aseprite')}
        with self.assertRaisesRegex(ValueError,'existing artist-owned'):art.author()
        self.assertEqual(before,{p:art.sha(p) for p in before})

    def test_deterministic_export_from_saved_sources(self):
        ase=Path(r'F:\SteamLibrary\steamapps\common\Aseprite\Aseprite.exe')
        with tempfile.TemporaryDirectory(dir=self.qa,prefix='ecology-export-determinism-') as tmp:
            base=Path(tmp)
            for index in (1,2):art.export(ase,base/f'native{index}',out_dir=base/f'runtime{index}')
            first={p.name:art.sha(p) for p in (base/'runtime1').iterdir()}
            second={p.name:art.sha(p) for p in (base/'runtime2').iterdir()}
            self.assertEqual(first,second)

if __name__=='__main__':unittest.main()
