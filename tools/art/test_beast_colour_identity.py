"""Native colour correction preserves original authored anatomy and alpha.

Baseline fingerprints were collected from the verified starting 003A masters
before colour edits, with an actual native Aseprite/runtime parity export.
Tests read current production masters/PNG metadata and reject geometry drift;
they do not reconstruct a second copy of the authored drawing implementation.
"""
from contextlib import redirect_stdout
import hashlib
import io
import json
from pathlib import Path
import shutil
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import zlib

from PIL import Image

import beast_colour_identity as colour
sys.path.insert(0, str(colour.ROOT / "tools"))
from build_power_art import read_ase
import beast_manifestations as exporter


class NativeBeastColourTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.baseline = json.loads((colour.ROOT / "tests/fixtures/beast_003a_colour_invariants.json").read_text(encoding="utf-8"))["baseline"]
        cls.manifest = json.loads((colour.ROOT / "assets/powers/beasts_002c5_2/manifest.json").read_text(encoding="utf-8"))
        cls.masters = {name: colour.ROOT / f"assets/source-art/beasts_002c5_2/{name}.aseprite" for name in colour.SPIRIT_PALETTES}

    def test_all_original_noncolour_chunks_cel_alpha_and_shapes_preserved(self):
        for name, source in self.masters.items():
            with self.subTest(beast=name):
                self.assertEqual(colour.invariant_signature(source.read_bytes()), self.baseline[name]["invariants"])

    def test_native_source_palette_and_visible_cel_colours_match_identity(self):
        for name, source in self.masters.items():
            palette = colour.SPIRIT_PALETTES[name]
            self.assertEqual(colour.native_palette(source.read_bytes()), palette)
            authored = {colour.rgb(value) for value in palette.values()}
            used = set()
            for _, chunks in colour.frames(source.read_bytes()):
                for kind, payload in chunks:
                    if kind == 0x2005:
                        raw = colour.cel_pixels(payload)
                        used.update(raw[index:index+3] for index in range(0, len(raw), 4) if raw[index+3])
            with self.subTest(beast=name): self.assertEqual(used, authored)

    def test_four_colours_are_distinct_and_restrained(self):
        bodies = {name: tuple(colour.rgb(palette["body"])) for name, palette in colour.SPIRIT_PALETTES.items()}
        self.assertEqual(len(set(bodies.values())), 4)
        self.assertLess(max(bodies["black_arrow"])-min(bodies["black_arrow"]), 20)
        self.assertGreater(bodies["iron_bull"][0], bodies["iron_bull"][1] * 1.5)
        self.assertGreater(bodies["stone_tortoise"][1], max(bodies["stone_tortoise"][0], bodies["stone_tortoise"][2]) * 1.5)
        self.assertGreater(bodies["coil_dragon"][2], bodies["coil_dragon"][0] * 1.5)
        self.assertTrue(all(max(body) < 130 for body in bodies.values()))

    def test_layer_tag_timing_pivot_and_eighty_distinct_keys(self):
        for name, source in self.masters.items():
            frames, meta = read_ase(source)
            with self.subTest(beast=name):
                self.assertEqual((meta["cell"], meta["pivot"], len(meta["layers"]), len(frames)), ([128, 128], [64, 96], 4, 20))
                self.assertEqual(list(meta["tags"]), ["prepare", "travel", "strike", "recovery", "guard"])
                self.assertEqual(meta["durations_ms"], [65,60,60,65,135,110,115,140,60,70,80,90,55,65,80,100,140,110,110,140])
                self.assertEqual(len({hashlib.sha256(frame.tobytes()).hexdigest() for frame in frames}), 20)
                self.assertTrue(all(all(0 < value < 128 for value in frame.getbbox()) for frame in frames))

    def test_export_metadata_matches_native_palette_alpha_and_fingerprints(self):
        for name, source in self.masters.items():
            meta = self.manifest["effects"][name]
            runtime = colour.ROOT / meta["texture"].removeprefix("res://")
            with Image.open(runtime) as image:
                image = image.convert("RGBA")
                expected_colour = colour.colour_metadata(name, source, image)
                alpha = hashlib.sha256(image.getchannel("A").tobytes()).hexdigest()
            with self.subTest(beast=name):
                self.assertEqual({key: meta[key] for key in expected_colour}, expected_colour)
                self.assertEqual(alpha, self.baseline[name]["baseline_native_alpha_sha256"])
                self.assertEqual(meta["source_sha256"], colour.sha(source.read_bytes()))
                self.assertEqual(meta["texture_sha256"], colour.sha(runtime.read_bytes()))
                self.assertTrue(meta["native_runtime_rgba_exact"])
                self.assertGreater(meta["native_translucent_pixel_fraction"], 0.70)
                self.assertFalse(meta["runtime_colour_tint"])

    def test_alpha_mutation_is_detected_independently_of_rgb(self):
        data = self.masters["black_arrow"].read_bytes()
        original = colour.invariant_signature(data)
        native = bytearray(data)
        position = 144
        while position < len(native):
            size, kind = struct.unpack_from("<IH", native, position)
            if kind == 0x2005:
                payload = bytes(native[position+6:position+size])
                raw = bytearray(colour.cel_pixels(payload))
                index = next(i for i in range(3, len(raw), 4) if raw[i])
                raw[index] -= 1
                payload = payload[:20] + zlib.compress(raw, 9)
                replacement = struct.pack("<IH", len(payload)+6, kind) + payload
                difference = len(replacement)-size
                native[position:position+size] = replacement
                struct.pack_into("<I", native, 0, len(native))
                struct.pack_into("<I", native, 128, struct.unpack_from("<I", native, 128)[0]+difference)
                break
            position += size
        actual = colour.invariant_signature(bytes(native))
        self.assertNotEqual(actual["native_cel_alpha_sha256"], original["native_cel_alpha_sha256"])
        self.assertEqual(actual["native_cel_shape_sha256"], original["native_cel_shape_sha256"])

    def test_duration_or_layer_chunk_change_is_detected(self):
        data = bytearray(self.masters["black_arrow"].read_bytes())
        previous = colour.invariant_signature(bytes(data))
        struct.pack_into("<H", data, 136, 66)
        self.assertNotEqual(colour.invariant_signature(bytes(data))["noncolour_native_sha256"], previous["noncolour_native_sha256"])

    def test_second_migration_refused_to_preserve_artist_edits(self):
        source = self.masters["black_arrow"].read_bytes()
        with self.assertRaisesRegex(AssertionError, "second colour migration"):
            colour.recolour_native(source, colour.SPIRIT_PALETTES["black_arrow"])

    def test_repeated_checks_preserve_prior_evidence_and_skip_review(self):
        # Simulated native CLI exercises the QA write boundary only. Actual
        # native export parity remains separately evidenced by Aseprite runs.
        def native_cli(command, **kwargs):
            if "--version" not in command:
                source = Path(command[2])
                _, metadata = read_ase(source)
                shutil.copyfile(colour.ROOT / f"assets/powers/beasts_002c5_2/{source.stem}.png", command[command.index("--sheet")+1])
                data = {"frames": [{"duration": value} for value in metadata["durations_ms"]], "meta": {
                    "layers": [{"name": name} for name in metadata["layers"]],
                    "slices": [{"keys": [{"pivot": {"x": 64, "y": 96}}]}],
                    "frameTags": [{"name": name} for name in metadata["tags"]]}}
                Path(command[command.index("--data")+1]).write_text(json.dumps(data), encoding="utf-8")
            return type("NativeResult", (), {"stdout": "simulated native CLI / QA boundary test", "stderr": ""})()

        production = list(self.masters.values()) + list((colour.ROOT / "assets/powers/beasts_002c5_2").glob("*"))
        before = {str(path): colour.sha(path.read_bytes()) for path in production}
        with tempfile.TemporaryDirectory() as temporary:
            qa_root = Path(temporary)
            arguments = ["beast_manifestations.py", "--check", "--task", "003A", "--qa-root", str(qa_root)]
            with patch.object(sys, "argv", arguments), patch.object(exporter, "find_tool", return_value="native-test"), \
                 patch.object(exporter.subprocess, "run", side_effect=native_cli), \
                 patch.object(exporter, "review", side_effect=AssertionError("--check must not create reviews")), redirect_stdout(io.StringIO()):
                exporter.main()
                previous = {str(path): colour.sha(path.read_bytes()) for path in qa_root.rglob("*") if path.is_file()}
                exporter.main()
            self.assertTrue(previous)
            self.assertTrue(all(colour.sha(Path(path).read_bytes()) == digest for path, digest in previous.items()))
            self.assertEqual(len(list((qa_root/"003A/manifests/beast-manifestations").iterdir())), 2)
            self.assertFalse((qa_root/"003A/images/beast-manifestations").exists())
        self.assertEqual({str(path): colour.sha(path.read_bytes()) for path in production}, before)


if __name__ == "__main__": unittest.main(verbosity=2)
