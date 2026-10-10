"""Read-only native editability, composition and unrelated-card preservation."""
import hashlib,subprocess,sys,tempfile,unittest
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'));sys.path.insert(0,str(ROOT/'tools/art'))
from build_power_art import read_ase
from final_acceptance_cards import split
from breakneck_card003a1 import cel_image
SOURCE=ROOT/'assets/source-art/power_identity_002c5/redline_cards.aseprite'
class NativeBreakneck(unittest.TestCase):
    def test_unrelated_native_chunks(self):
        old=subprocess.check_output(['git','show','HEAD:'+SOURCE.relative_to(ROOT).as_posix()],cwd=ROOT)
        _,before=split(old);_,after=split(SOURCE.read_bytes())
        for i,((_,a),(_,b)) in enumerate(zip(before,after)):
            for (kind,data),(other,payload) in zip(a,b):
                self.assertEqual(kind,other)
                if not(i>=36 and kind==0x2005 and int.from_bytes(data[:2],'little') in [1,2,3,4]):self.assertEqual(data,payload)
    def test_single_moving_machine_and_bounds(self):
        _,frames=split(SOURCE.read_bytes());centres=[]
        for key in range(12):
            body=Image.new('RGBA',(64,64))
            for kind,data in frames[36+key][1]:
                # Actual rotor/bit anatomy must fit. Its cast floor shadow is
                # a separate authored layer and may meet the lower framing.
                if kind==0x2005 and int.from_bytes(data[:2],'little') == 2:body.alpha_composite(cel_image(data))
            box=body.getbbox();self.assertIsNotNone(box)
            self.assertGreaterEqual(box[0],1);self.assertLessEqual(box[2],63)
            self.assertGreaterEqual(box[1],1);self.assertLessEqual(box[3],63)
            centres.append((box[0]+box[2])/2)
            if key<4:self.assertIsNone(body.crop((44,12,63,32)).getbbox(),'The original frozen enemy position must be empty during charge setup')
        self.assertGreater(max(centres)-min(centres),20,'The sole machine really travels into its committed strike')
    def test_editable_topology(self):
        cells,meta=read_ase(SOURCE)
        self.assertEqual(meta['cell'],[64,64]);self.assertEqual(meta['pivot'],[32,32]);self.assertEqual(len(meta['layers']),5)
        self.assertEqual(meta['tags']['breakneck'],{'from':36,'to':47});self.assertEqual(len(cells),48)
        self.assertEqual(meta['durations_ms'][36:],[160,120,90,75,50,35,35,45,80,105,140,190])
    def test_native_runtime_parity_and_other_textures(self):
        qa=ROOT.parent/'GyroBrothers-QA/003A.1/temp'
        with tempfile.TemporaryDirectory(dir=qa,prefix='breakneck-parity-') as tmp:
            target=Path(tmp)/'native.png'
            subprocess.run([r'F:\SteamLibrary\steamapps\common\Aseprite\Aseprite.exe','--batch',str(SOURCE),'--sheet-columns','12','--sheet',str(target)],capture_output=True,check=True)
            self.assertEqual(Image.open(target).convert('RGBA').tobytes(),Image.open(ROOT/'assets/powers/identity/redline_cards.png').convert('RGBA').tobytes())
        for rel in ['assets/powers/identity/redline_icons.png','assets/powers/identity/redline_fx.png']:
            old=subprocess.check_output(['git','show','HEAD:'+rel],cwd=ROOT)
            self.assertEqual(hashlib.sha256(old).digest(),hashlib.sha256((ROOT/rel).read_bytes()).digest())
if __name__=='__main__':unittest.main()
