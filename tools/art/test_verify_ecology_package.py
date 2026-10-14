"""Compiled receipt failures must reject missing, stale or wrongly mapped art."""
import copy
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from PIL import Image
import verify_ecology_package as verify

sys.path.insert(0, str(verify.ROOT / "tools/parts"))
import verify_packaged_catalogue as package


class EcologyPackageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expected = json.loads((verify.ROOT / verify.MANIFEST).read_text(encoding="utf-8"))
        cls.receipt = {"ecology_json": json.dumps(cls.expected), "ecology_textures": []}
        for family in verify.FAMILIES:
            for group in ("cards", "icons"):
                metadata = cls.expected["families"][family][group]
                with Image.open(verify.ROOT / metadata["texture"].removeprefix("res://")) as image:
                    image = image.convert("RGBA")
                    row = {"kind": family + "/" + group, "family": family, "group": group,
                           "path": metadata["texture"], "metadata_path": "res://" + verify.MANIFEST,
                           "size": list(image.size), "visible_pixels": True, "valid": True,
                           "rgba_sha256": hashlib.sha256(image.tobytes()).hexdigest(),
                           "visible_rgba_sha256": hashlib.sha256(verify.visible_bytes(image)).hexdigest(),
                           "transparent_rgb_normalized": True, "packaged_native_master_present": False}
                    row.update({key: copy.deepcopy(metadata[key]) for key in verify.TOPOLOGY})
                    cls.receipt["ecology_textures"].append(row)
        cls.temp = verify.ROOT.parent / "GyroBrothers-QA/003A.2/temp"
        cls.temp.mkdir(parents=True, exist_ok=True)

    def fixture(self):
        return copy.deepcopy(self.receipt)

    def rejects(self, fixture):
        with self.assertRaises(RuntimeError):
            verify.verify_ecology_assets(fixture)

    def test_complete_declared_source_receipt_verifies_eight_unique_atlases(self):
        proof = verify.verify_ecology_assets(self.receipt)
        self.assertEqual(proof["ecology_unique_atlases_verified"], 8)
        self.assertTrue(proof["ecology_alpha_and_visible_rgb_exact"])
        self.assertTrue(proof["ecology_native_topology_and_runtime_parity_exact"])

    def test_current_source_requires_actual_compiled_ecology_fields(self):
        with self.assertRaises(RuntimeError):
            package.verify_optional_ecology_assets({})

    def test_old_minimal_fixture_without_new_manifest_preserves_old_contracts(self):
        with tempfile.TemporaryDirectory(dir=self.temp, prefix="ecology-package-old-") as folder:
            self.assertEqual(package.verify_optional_ecology_assets({}, Path(folder)), {})

    def test_missing_atlas_rejected(self):
        fixture = self.fixture();fixture["ecology_textures"].pop();self.rejects(fixture)

    def test_duplicate_branch_shared_atlas_cannot_replace_missing_unique_sheet(self):
        fixture = self.fixture();fixture["ecology_textures"][1] = copy.deepcopy(fixture["ecology_textures"][0]);self.rejects(fixture)

    def test_manifest_metadata_changes_rejected(self):
        fixture = self.fixture();manifest = json.loads(fixture["ecology_json"])
        manifest["art"]["wallbreaker"]["card_static_frame"] = 0
        fixture["ecology_json"] = json.dumps(manifest);self.rejects(fixture)

    def test_invalid_json_rejected(self):
        fixture = self.fixture();fixture["ecology_json"] = "{broken";self.rejects(fixture)

    def test_every_imported_alpha_byte_and_visible_rgb_byte_matters(self):
        for channel in (0, 3):
            fixture = self.fixture();row = fixture["ecology_textures"][0]
            with Image.open(verify.ROOT / row["path"].removeprefix("res://")) as image:
                data = bytearray(verify.visible_bytes(image))
            offset = next(i for i in range(0, len(data), 4) if data[i + 3] > 0)
            data[offset + channel] ^= 1
            row["visible_rgba_sha256"] = hashlib.sha256(data).hexdigest()
            self.rejects(fixture)

    def test_only_hidden_rgb_padding_may_differ(self):
        fixture = self.fixture();fixture["ecology_textures"][0]["rgba_sha256"] = "a" * 64
        self.assertTrue(verify.verify_ecology_assets(fixture)["ecology_alpha_and_visible_rgb_exact"])

    def test_missing_actual_raw_rgba_digest_rejected(self):
        fixture = self.fixture();fixture["ecology_textures"][0].pop("rgba_sha256");self.rejects(fixture)

    def test_wrong_dimensions_even_with_valid_flag_rejected(self):
        fixture = self.fixture();fixture["ecology_textures"][0]["size"] = [64, 64];self.rejects(fixture)

    def test_wrong_topology_fields_rejected_individually(self):
        for key, value in (("pivot", [0, 0]), ("columns", 12), ("frame_count", 6), ("layers", []), ("durations_ms", [1]), ("tags", {})):
            with self.subTest(key=key):
                fixture = self.fixture();fixture["ecology_textures"][0][key] = value;self.rejects(fixture)

    def test_wrong_family_ownership_and_path_rejected(self):
        for key, value in (("family", "orbit_drive"), ("group", "icons"), ("path", "res://assets/powers/ecology003a2/orbit_drive_cards.png"), ("metadata_path", "res://old.json")):
            fixture = self.fixture();fixture["ecology_textures"][0][key] = value;self.rejects(fixture)

    def test_missing_visibility_or_normalisation_flags_rejected(self):
        for key in ("valid", "visible_pixels", "transparent_rgb_normalized"):
            fixture = self.fixture();fixture["ecology_textures"][0][key] = False;self.rejects(fixture)

    def test_changed_saved_master_is_rejected_before_package_parity(self):
        with tempfile.TemporaryDirectory(dir=self.temp, prefix="ecology-package-changed-master-") as folder:
            source = Path(folder)
            shutil.copytree(verify.ROOT / "assets/powers/ecology003a2", source / "assets/powers/ecology003a2")
            shutil.copytree(verify.ROOT / "assets/source-art/ecology003a2", source / "assets/source-art/ecology003a2")
            master = source / self.expected["families"]["iron_comet"]["cards"]["source"]
            master.write_bytes(master.read_bytes() + b"changed")
            with self.assertRaises(RuntimeError):
                verify.verify_ecology_assets(self.receipt, source)


if __name__ == "__main__":
    unittest.main()
