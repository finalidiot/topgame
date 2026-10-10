"""Validate actual editable pickup keys and one-shot PCM, not a second drawing."""
from array import array
import hashlib
import importlib.util
import io
import json
import math
from pathlib import Path
import sys
import unittest
import wave

from PIL import Image

import pickup_flair as art
sys.path.insert(0, str(art.ROOT / "tools"))
from build_power_art import read_ase


class PickupFlairTests(unittest.TestCase):
    def setUp(self):
        self.frames, self.native = read_ase(art.SOURCE)
        self.meta = json.loads((art.OUT / "manifest.json").read_text(encoding="utf-8"))

    def test_native_editable_layers_tag_timing_and_floor_pivot(self):
        self.assertEqual(self.native["layers"], art.LAYERS)
        self.assertEqual(self.native["tags"], {"collect":{"from":0,"to":5}})
        self.assertEqual(self.native["durations_ms"], [30,35,45,55,65,80])
        self.assertEqual(self.native["pivot"], [20,12])
        self.assertEqual(len(self.frames), 6)
        self.assertEqual(len({hashlib.sha256(f.tobytes()).hexdigest() for f in self.frames}), 6)

    def test_runtime_pixels_match_native_with_only_native_blend_rounding(self):
        with Image.open(art.OUT / "collection.png") as source:
            runtime = source.convert("RGBA")
        self.assertEqual(runtime.size, (240,24))
        for index, frame in enumerate(self.frames):
            actual = runtime.crop((index*40,0,(index+1)*40,24)).tobytes()
            expected = frame.tobytes()
            for offset in range(0, len(actual), 4):
                self.assertEqual(actual[offset+3], expected[offset+3])
                self.assertLessEqual(max(abs(actual[offset+k]-expected[offset+k]) for k in range(3)), 1)

    def test_export_metadata_and_import_preserve_native_size_filter(self):
        self.assertTrue(self.meta["native_runtime_rgba_exact"])
        self.assertTrue(self.meta["floor_only"])
        self.assertFalse(self.meta["loop"])
        self.assertEqual(self.meta["source_sha256"], art.sha(art.SOURCE))
        self.assertEqual(self.meta["texture_sha256"], art.sha(art.OUT / "collection.png"))
        self.assertEqual(self.meta["duration_ms"], 310)
        imported = (art.OUT / "collection.png.import").read_text(encoding="utf-8")
        self.assertIn("mipmaps/generate=false", imported)
        self.assertIn("compress/mode=0", imported)
        self.assertIn("process/size_limit=0", imported)

    def test_floor_response_is_small_translucent_and_resolves_once(self):
        for frame in self.frames:
            self.assertTrue(frame.getbbox())
            left, top, right, bottom = frame.getbbox()
            self.assertGreater(left, 0); self.assertGreater(top, 0)
            self.assertLess(right, 40); self.assertLess(bottom, 24)
            self.assertLess(max(frame.getchannel("A").tobytes()), 255)
            self.assertLess(sum(a>0 for a in frame.getchannel("A").tobytes()), 140)
        self.assertLess(sum(self.frames[-1].getchannel("A").tobytes()), sum(self.frames[0].getchannel("A").tobytes()))

    def test_short_collection_audio_has_headroom_and_deterministic_pcm(self):
        path = art.ROOT / "tools/audio/compose_pickup.py"
        spec = importlib.util.spec_from_file_location("compose_pickup",path)
        recipe = importlib.util.module_from_spec(spec);spec.loader.exec_module(recipe)
        data = (art.ROOT / "assets/audio/pickup_collect.wav").read_bytes()
        self.assertEqual(data, recipe.wav_bytes())
        self.assertNotEqual(data, (art.ROOT / "assets/audio/card_select.wav").read_bytes())
        with wave.open(io.BytesIO(data),"rb") as sample:
            self.assertEqual(sample.getnchannels(),1)
            self.assertEqual(sample.getsampwidth(),2)
            self.assertEqual(sample.getframerate(),48000)
            self.assertAlmostEqual(sample.getnframes()/sample.getframerate(),.18)
            pcm = array("h",sample.readframes(sample.getnframes()))
        peak = max(abs(v) for v in pcm)/32768
        rms = math.sqrt(sum(v*v for v in pcm)/len(pcm))/32768
        self.assertGreater(peak,.2);self.assertLess(peak,.7)
        self.assertGreater(rms,.03);self.assertLess(rms,.2)
        self.assertEqual(pcm[0],0);self.assertEqual(pcm[-1],0)


if __name__ == "__main__": unittest.main()
