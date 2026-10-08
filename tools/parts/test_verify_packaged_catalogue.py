"""Package verifier rejects economic fixture leaks and imported asset drift.

Synthetic report dictionaries test validation only. Actual Windows validation
still launches the compiled read-only probe against a fresh isolated collection.
"""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import wave
from PIL import Image

import verify_packaged_catalogue as verifier


class PackagedEconomyContracts(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "isolated_collection.json"
        source = json.loads((verifier.ROOT / "assets/data/parts_catalogue.json").read_text(encoding="utf-8"))
        self.expected = {category + ":" + local for category,parts in source["categories"].items() for local in parts}
        self.saved = {"schema_version":3,"starter_selected":"breaker","owned_part_ids":sorted(self.expected),
                      "equipped_build":{"blade":"smash","ratchet":"high","bit":"flat"},
                      "progression":{"credits":0,"salvage":0,"packet_serial":0,"pending_packet":{},
                                     "last_packet":{},"run_serial":0,"active_run":"","last_reward":{}}}

    def tearDown(self): self.temp.cleanup()

    def write(self): self.path.write_text(json.dumps(self.saved),encoding="utf-8")

    def test_schema_three_qa_collection_requires_empty_progression(self):
        self.write()
        result = verifier.verify_collection(self.path,self.expected)
        self.assertEqual(result["schema_version"],3)
        self.assertTrue(result["qa_economy_empty"])
        self.assertEqual(result["owned_count"],31)

    def test_schema_one_fixture_is_rejected(self):
        self.saved["schema_version"] = 1
        self.write()
        with self.assertRaisesRegex(RuntimeError,"31 qualified"):
            verifier.verify_collection(self.path,self.expected)

    def test_old_schema_two_probe_is_rejected(self):
        self.saved["schema_version"] = 2
        self.write()
        with self.assertRaisesRegex(RuntimeError,"31 qualified"):
            verifier.verify_collection(self.path,self.expected)

    def test_fixture_currency_and_counter_leaks_rejected(self):
        for key in ("credits","salvage","packet_serial","run_serial"):
            original = deepcopy(self.saved)
            for value in (1,-1,True,False,"0"):
                with self.subTest(key=key,value=value):
                    self.saved["progression"][key] = value
                    self.write()
                    with self.assertRaisesRegex(RuntimeError,"zero economic"):
                        verifier.verify_collection(self.path,self.expected)
                    self.saved = deepcopy(original)

    def test_fixture_pending_or_previous_transactions_rejected(self):
        for key,value in (("pending_packet",{"id":"packet-1"}),("last_packet",{"id":"packet-1"}),
                          ("active_run","run-1"),("last_reward",{"id":"run-1"})):
            with self.subTest(key=key):
                original = deepcopy(self.saved)
                self.saved["progression"][key] = value
                self.write()
                with self.assertRaisesRegex(RuntimeError,"zero economic"):
                    verifier.verify_collection(self.path,self.expected)
                self.saved = original

    def test_owned_duplicates_and_altered_build_rejected(self):
        self.saved["owned_part_ids"][-1] = self.saved["owned_part_ids"][0]
        self.write()
        with self.assertRaises(RuntimeError): verifier.verify_collection(self.path,self.expected)
        self.saved["owned_part_ids"] = sorted(self.expected)
        self.saved["equipped_build"]["blade"] = "guard"
        self.write()
        with self.assertRaisesRegex(RuntimeError,"Breaker"): verifier.verify_collection(self.path,self.expected)


def source_shop_report() -> dict:
    """Synthetic expected report built from actual source; never a package claim."""
    root = verifier.ROOT
    report = {"packet_json":{},"packet_textures":[],"packet_audio":[]}
    for kind in ("packet","reclaimed_packet","reveal_mat"):
        relative = "assets/ui/shop_003a/" + kind
        meta = json.loads((root / (relative + ".json")).read_text(encoding="utf-8"))
        report["packet_json"][kind] = json.dumps(meta)
        size,digest = verifier._visible_pixels(root / (relative + ".png"))
        row = {"kind":kind,"path":"res://" + relative + ".png","metadata_path":"res://" + relative + ".json",
               "valid":True,"visible_pixels":True,"size":size,"visible_rgba_sha256":digest,
               "transparent_rgb_normalized":True}
        row.update({key:meta[key] for key in ("cell","pivot","tags","durations_ms","columns","frame_count")})
        report["packet_textures"].append(row)
    config = json.loads((root / "assets/data/packet_economy.json").read_text(encoding="utf-8"))
    report["economy_json"] = json.dumps(config)
    report["economy_config"] = deepcopy(config)
    report["economy_validation_errors"] = []
    report["economy_odds"] = {"kind":"standard","guarantee":"UNCOMMON+","new_guarantee":False,
                              "categories":verifier._source_economy_odds(root),"rarity_weights":config["rarity_weights"],
                              "rules":config["rules"]["standard"],"missing_rarity_rule":config["rules"]["missing_rarity"]}
    audio = json.loads((root / "assets/audio/shop_003a/manifest.json").read_text(encoding="utf-8"))
    report["packet_audio_json"] = json.dumps(audio)
    for kind,cue in audio["cues"].items():
        path = "res://assets/audio/shop_003a/" + cue["file"]
        with wave.open(str(root / path.removeprefix("res://")),"rb") as sample:
            frames,rate,channels = sample.getnframes(),sample.getframerate(),sample.getnchannels()
            digest = hashlib.sha256(sample.readframes(frames)).hexdigest()
        report["packet_audio"].append({"kind":kind,"path":path,"valid":True,"mix_rate":rate,"channels":channels,
                                       "stereo":False,"format":1,"loop_mode":0,"pcm_frames":frames,"pcm_sha256":digest})
    return report


class ShopAssetsContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.expected = source_shop_report()

    def setUp(self): self.report = deepcopy(self.expected)

    def test_expected_source_report_accepted(self):
        result = verifier.verify_shop_assets(self.report)
        self.assertEqual(result["packet_textures_verified"],3)
        self.assertEqual(result["packet_audio_cues_verified"],8)
        self.assertTrue(result["production_odds_match"])

    def test_packet_texture_omission_rejected(self):
        self.report["packet_textures"].pop()
        with self.assertRaisesRegex(RuntimeError,"both packet"): verifier.verify_shop_assets(self.report)

    def test_actual_packet_pixel_drift_rejected(self):
        self.report["packet_textures"][0]["visible_rgba_sha256"] = "0" * 64
        with self.assertRaisesRegex(RuntimeError,"packet pixels"): verifier.verify_shop_assets(self.report)

    def test_authored_metadata_drift_rejected(self):
        data = json.loads(self.report["packet_json"]["packet"])
        data["durations_ms"][0] += 1
        self.report["packet_json"]["packet"] = json.dumps(data)
        with self.assertRaisesRegex(RuntimeError,"authored metadata"): verifier.verify_shop_assets(self.report)

    def test_imported_topology_drift_rejected(self):
        self.report["packet_textures"][0]["pivot"] = [0,0]
        with self.assertRaisesRegex(RuntimeError,"topology"): verifier.verify_shop_assets(self.report)

    def test_economy_config_drift_rejected(self):
        data = json.loads(self.report["economy_json"])
        data["packets"]["standard"]["cost"] += 1
        self.report["economy_json"] = json.dumps(data)
        with self.assertRaisesRegex(RuntimeError,"economy differs"): verifier.verify_shop_assets(self.report)

    def test_actual_compiled_odds_drift_rejected(self):
        self.report["economy_odds"]["categories"]["blade"]["COMMON"] += .001
        with self.assertRaisesRegex(RuntimeError,"compiled packet odds"): verifier.verify_shop_assets(self.report)

    def test_compiled_economy_validation_errors_rejected(self):
        self.report["economy_validation_errors"] = ["Invalid guarantee pool"]
        with self.assertRaisesRegex(RuntimeError,"economy differs"): verifier.verify_shop_assets(self.report)

    def test_odds_source_fingerprint_must_be_current(self):
        with patch.object(verifier.workspace,"sha256",return_value="stale-source-hash"):
            with self.assertRaisesRegex(RuntimeError,"odds evidence is stale"):
                verifier._source_economy_odds(verifier.ROOT)

    def test_missing_audio_cue_rejected(self):
        self.report["packet_audio"].pop()
        with self.assertRaisesRegex(RuntimeError,"eight physical"): verifier.verify_shop_assets(self.report)

    def test_exact_imported_pcm_drift_rejected(self):
        self.report["packet_audio"][0]["pcm_sha256"] = "0" * 64
        with self.assertRaisesRegex(RuntimeError,"packet PCM"): verifier.verify_shop_assets(self.report)

    def test_audio_loop_stereo_format_or_frame_drift_rejected(self):
        for key,value in (("loop_mode",1),("stereo",True),("format",0),("channels",2),("pcm_frames",1),("mix_rate",44100)):
            with self.subTest(key=key):
                report = deepcopy(self.report)
                report["packet_audio"][0][key] = value
                with self.assertRaisesRegex(RuntimeError,"packet PCM"): verifier.verify_shop_assets(report)


class UIPolishAssetsContracts(unittest.TestCase):
    """Synthetic helper fixtures never substitute for actual EXE evidence."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        directory = self.root / "assets/ui/human_feedback003a"
        directory.mkdir(parents=True)
        self.report = {"ui_polish_json": {}, "ui_polish_textures": []}
        for index, (kind, (cell, frames)) in enumerate(verifier.UI_POLISH_LAYOUT.items()):
            metadata = {"cell": cell, "pivot": [cell[0] // 2, cell[1] // 2], "columns": frames,
                        "frame_count": frames, "texture": kind + ".png", "filter": "nearest",
                        "native_pixels": True, "durations_ms": [100] * frames,
                        "layers": ["authored fixture"], "tags": {"ALL": {"from": 0, "to": frames - 1}}}
            (directory / (kind + ".json")).write_text(json.dumps(metadata), encoding="utf-8")
            pixels = Image.new("RGBA", (cell[0] * frames, cell[1]), (index * 20, 80, 100, 0))
            pixels.putpixel((1, 1), (30, 50, 70, 255))
            pixels.save(directory / (kind + ".png"))
            size, digest = verifier._visible_pixels(directory / (kind + ".png"))
            self.report["ui_polish_json"][kind] = json.dumps(metadata)
            row = {"kind": kind, "path": "res://assets/ui/human_feedback003a/" + kind + ".png",
                   "metadata_path": "res://assets/ui/human_feedback003a/" + kind + ".json",
                   "size": size, "valid": True, "visible_pixels": True,
                   "transparent_rgb_normalized": True, "visible_rgba_sha256": digest}
            row.update({key: deepcopy(metadata[key]) for key in
                        ("cell", "pivot", "tags", "durations_ms", "layers", "columns", "frame_count")})
            self.report["ui_polish_textures"].append(row)

    def tearDown(self): self.temp.cleanup()

    def verify(self, report=None): return verifier.verify_ui_polish_assets(self.report if report is None else report, self.root)

    def test_complete_source_pixels_metadata_and_native_topology_accepted(self):
        result = self.verify()
        self.assertEqual(result["ui_polish_textures_verified"], 7)
        self.assertTrue(result["ui_polish_pixels_exact"])
        self.assertTrue(result["ui_polish_metadata_matches_source"])

    def test_missing_duplicate_unknown_or_marker_only_reports_rejected(self):
        cases = [deepcopy(self.report) for _ in range(5)]
        cases[0]["ui_polish_textures"].pop()
        cases[1]["ui_polish_textures"][-1] = deepcopy(cases[1]["ui_polish_textures"][0])
        cases[2]["ui_polish_textures"][0]["kind"] = "unknown"
        cases[3]["ui_polish_json"].pop("merchant")
        cases[4] = {"ui_polish_pass": True}
        for case in cases:
            with self.subTest(case=case):
                with self.assertRaisesRegex(RuntimeError, "all seven"): self.verify(case)

    def test_one_visible_pixel_or_alpha_change_rejected(self):
        path = self.root / "assets/ui/human_feedback003a/merchant.png"
        for value in [(31, 50, 70, 255), (30, 50, 70, 254)]:
            with self.subTest(value=value):
                with Image.open(path) as source: pixels = source.copy()
                pixels.putpixel((1, 1), value)
                pixels.save(path)
                with self.assertRaisesRegex(RuntimeError, "UI pixels"): self.verify()

    def test_invisible_rgb_normalization_does_not_hide_visible_changes(self):
        path = self.root / "assets/ui/human_feedback003a/merchant.png"
        with Image.open(path) as source: pixels = source.copy()
        pixels.putpixel((2, 2), (255, 20, 35, 0))
        pixels.save(path)
        self.assertTrue(self.verify()["ui_polish_pixels_exact"])

    def test_no_visible_source_cannot_pass_with_success_flags(self):
        row = self.report["ui_polish_textures"][0]
        path = self.root / row["path"].removeprefix("res://")
        Image.new("RGBA", tuple(row["size"]), (255, 10, 20, 0)).save(path)
        row["visible_rgba_sha256"] = verifier._visible_pixels(path)[1]
        with self.assertRaisesRegex(RuntimeError, "UI pixels"): self.verify()

    def test_metadata_and_runtime_resource_path_drift_rejected(self):
        for field in ("path", "metadata_path"):
            report = deepcopy(self.report)
            report["ui_polish_textures"][0][field] = "res://assets/ui/other.png"
            with self.subTest(field=field):
                with self.assertRaisesRegex(RuntimeError, "path differs"): self.verify(report)
        metadata = json.loads(self.report["ui_polish_json"]["merchant"])
        metadata["durations_ms"][0] += 1
        self.report["ui_polish_json"]["merchant"] = json.dumps(metadata)
        with self.assertRaisesRegex(RuntimeError, "authored metadata differs"): self.verify()

    def test_imported_pivot_tags_duration_layers_and_grid_drift_rejected(self):
        for field, value in (("pivot", [0, 0]), ("tags", {}), ("durations_ms", []),
                             ("layers", []), ("columns", 1), ("frame_count", 1), ("cell", [1, 1])):
            report = deepcopy(self.report)
            report["ui_polish_textures"][3][field] = value
            with self.subTest(field=field):
                with self.assertRaisesRegex(RuntimeError, "topology differs"): self.verify(report)

    def test_incomplete_pixel_evidence_or_failure_flags_rejected(self):
        for field, value in (("visible_rgba_sha256", "0" * 64), ("valid", False),
                             ("visible_pixels", False), ("transparent_rgb_normalized", False), ("size", [1, 1])):
            report = deepcopy(self.report)
            report["ui_polish_textures"][0][field] = value
            with self.subTest(field=field):
                with self.assertRaisesRegex(RuntimeError, "UI pixels"): self.verify(report)


class FinalAcceptanceAssetsTests(unittest.TestCase):
    """Parser rejection fixtures; actual EXE/APK evidence comes from the probe."""

    @classmethod
    def setUpClass(cls):
        root = verifier.ROOT
        manifest_path = root / "assets/powers/defence003a/manifest.json"
        defence_text = manifest_path.read_text(encoding="utf-8")
        defence = json.loads(defence_text)
        cls.fixture = {"defence_json": defence_text, "defence_textures": [],
                       "arena_json": {}, "arena_textures": []}
        for family, groups in defence["families"].items():
            for group in ("cards", "icons", "fx"):
                meta = groups[group]
                row = cls.make_row(family + "/" + group, meta,
                                   "res://assets/powers/defence003a/manifest.json")
                row.update(family=family, group=group)
                cls.fixture["defence_textures"].append(row)
        for kind in ("display_panel", "machinery", "perimeter", "sparks", "vent", "warning_bank"):
            metadata_path = "res://assets/arena/escalation003a/" + kind + ".json"
            content = (root / metadata_path.removeprefix("res://")).read_text(encoding="utf-8")
            cls.fixture["arena_json"][kind] = content
            cls.fixture["arena_textures"].append(cls.make_row(kind, json.loads(content), metadata_path))

    @staticmethod
    def make_row(kind, meta, metadata_path):
        size, digest = verifier._visible_pixels(verifier.ROOT / meta["texture"].removeprefix("res://"))
        source = verifier.ROOT / meta["source"]
        row = {"kind": kind, "path": meta["texture"], "metadata_path": metadata_path,
               "size": size, "valid": True, "visible_pixels": True,
               "transparent_rgb_normalized": True, "visible_rgba_sha256": digest,
               "native_source_available": True,
               "native_source_sha256": hashlib.sha256(source.read_bytes()).hexdigest()}
        row.update({key: deepcopy(meta[key]) for key in
                    ("cell", "pivot", "tags", "durations_ms", "layers", "columns", "frame_count", "source")})
        return row

    def setUp(self): self.report = deepcopy(self.fixture)
    def verify(self): return verifier.verify_final_acceptance_assets(self.report)

    def test_all_fifteen_actual_source_assets_and_native_masters_are_required(self):
        result = self.verify()
        self.assertEqual((result["defence_textures_verified"], result["arena_textures_verified"],
                          result["native_masters_verified"]), (9, 6, 15))
        self.assertTrue(result["final_acceptance_metadata_matches_source"])
        self.assertTrue(result["final_acceptance_pixels_exact"])

    def test_missing_duplicate_unknown_or_marker_only_pixel_reports_rejected(self):
        for key in ("defence_textures", "arena_textures"):
            for change in ("missing", "duplicate", "unknown"):
                self.report = deepcopy(self.fixture)
                rows = self.report[key]
                if change == "missing": rows.pop()
                elif change == "duplicate": rows[-1] = deepcopy(rows[0])
                else: rows[0]["kind"] = "unknown"
                with self.subTest(key=key, change=change):
                    with self.assertRaisesRegex(RuntimeError, "did not inspect all"): self.verify()
        self.report = {"final_acceptance_pass": True}
        with self.assertRaisesRegex(RuntimeError, "defence metadata"): self.verify()

    def test_actual_metadata_text_changes_and_invalid_json_rejected(self):
        for key in ("defence_json", "arena_json"):
            for bad in ("invalid-json", "changed"):
                self.report = deepcopy(self.fixture)
                text = self.report[key] if key == "defence_json" else self.report[key]["machinery"]
                data = json.loads(text)
                if key == "defence_json": data["families"]["gyro_lock"]["cards"]["pivot"][0] += 1
                else: data["durations_ms"][0] += 1
                text = "{" if bad == "invalid-json" else json.dumps(data)
                if key == "defence_json": self.report[key] = text
                else: self.report[key]["machinery"] = text
                with self.subTest(key=key, bad=bad):
                    with self.assertRaisesRegex(RuntimeError, "metadata (is invalid|differs)"): self.verify()
        self.report = deepcopy(self.fixture)
        self.report["arena_json"].pop("vent")
        with self.assertRaisesRegex(RuntimeError, "six arena metadata"): self.verify()

    def test_actual_imported_pixels_alpha_visibility_and_dimensions_rejected(self):
        for key in ("defence_textures", "arena_textures"):
            for field, value in (("visible_rgba_sha256", "0" * 64), ("valid", False),
                                 ("visible_pixels", False), ("transparent_rgb_normalized", False),
                                 ("size", [1, 1])):
                self.report = deepcopy(self.fixture)
                self.report[key][0][field] = value
                with self.subTest(key=key, field=field):
                    with self.assertRaisesRegex(RuntimeError, "alpha/visible RGB pixels"): self.verify()

    def test_actual_resource_paths_cannot_be_substituted(self):
        for key in ("defence_textures", "arena_textures"):
            for field in ("path", "metadata_path"):
                self.report = deepcopy(self.fixture)
                self.report[key][0][field] = "res://assets/wrong.png"
                with self.subTest(key=key, field=field):
                    with self.assertRaisesRegex(RuntimeError, "runtime/metadata path"): self.verify()
        for field in ("family", "group"):
            self.report = deepcopy(self.fixture)
            self.report["defence_textures"][0][field] = "wrong"
            with self.subTest(field=field):
                with self.assertRaisesRegex(RuntimeError, "family/group identity"): self.verify()

    def test_native_import_topology_and_master_provenance_cannot_drift(self):
        for key in ("defence_textures", "arena_textures"):
            for field, value in (("cell", [1, 1]), ("pivot", [0, 0]), ("tags", {}),
                                 ("durations_ms", []), ("layers", []), ("columns", 0),
                                 ("frame_count", 0), ("source", "assets/wrong.aseprite")):
                self.report = deepcopy(self.fixture)
                self.report[key][0][field] = value
                with self.subTest(key=key, field=field):
                    with self.assertRaisesRegex(RuntimeError, "topology differs"): self.verify()

    def test_optional_package_master_presence_is_explicit_and_consistent(self):
        for key in ("defence_textures", "arena_textures"):
            for field, value in (("native_source_available", "true"),
                                 ("native_source_sha256", "0" * 64)):
                self.report = deepcopy(self.fixture)
                self.report[key][0][field] = value
                with self.subTest(key=key, field=field):
                    with self.assertRaisesRegex(RuntimeError, "native-source evidence"): self.verify()
        self.report = deepcopy(self.fixture)
        for row in self.report["defence_textures"] + self.report["arena_textures"]:
            row.update(native_source_available=False, native_source_sha256="")
        result = self.verify()
        self.assertEqual(result["native_masters_verified"], 15)
        self.assertFalse(any(result["packaged_native_master_presence"].values()))


class BeastColourPackageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        meta = json.loads((verifier.ROOT / "assets/powers/beasts_002c5_2/manifest.json").read_text(encoding="utf-8"))
        cls.fixture = {"beast_json": json.dumps(meta), "beast_textures": []}
        for kind, item in meta["effects"].items():
            size, visible = verifier._visible_pixels(verifier.ROOT / item["texture"].removeprefix("res://"))
            cls.fixture["beast_textures"].append({"kind": kind, "path": item["texture"], "size": size,
                "valid": True, "visible_pixels": True, "transparent_rgb_normalized": True,
                "visible_rgba_sha256": visible})

    def setUp(self): self.report = deepcopy(self.fixture)

    def test_exact_colour_and_alpha_source_report_accepted(self):
        result = verifier.verify_beast_assets(self.report)
        self.assertTrue(result["beast_colour_identity_verified"])
        self.assertTrue(result["beast_transparency_alpha_exact"])

    def test_old_grayscale_or_pixel_alpha_drift_rejected(self):
        for index in range(4):
            self.report = deepcopy(self.fixture)
            row = self.report["beast_textures"][index]
            row["visible_rgba_sha256"] = "0" * 64
            with self.subTest(beast=row["kind"]), self.assertRaisesRegex(RuntimeError, "colour/alpha pixels"):
                verifier.verify_beast_assets(self.report)

    def test_colour_identity_metadata_drift_rejected(self):
        meta = json.loads(self.report["beast_json"])
        for field, value in (("colour_identity", "charcoal"), ("runtime_colour_tint", True),
                             ("native_palette", {}), ("native_alpha_sha256", "0" * 64)):
            altered = deepcopy(meta)
            altered["effects"]["stone_tortoise"][field] = value
            self.report["beast_json"] = json.dumps(altered)
            with self.subTest(field=field), self.assertRaisesRegex(RuntimeError, "manifest differs"):
                verifier.verify_beast_assets(self.report)

    def test_duplicate_or_missing_beast_rejected(self):
        self.report["beast_textures"][0] = self.report["beast_textures"][1]
        with self.assertRaisesRegex(RuntimeError, "all four"): verifier.verify_beast_assets(self.report)

    def test_invalid_manifest_rejected(self):
        self.report["beast_json"] = "broken"
        with self.assertRaisesRegex(RuntimeError, "manifest is invalid"): verifier.verify_beast_assets(self.report)


class PickupPackageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        meta = json.loads((verifier.ROOT / "assets/powers/pickup_003a1/manifest.json").read_text(encoding="utf-8"))
        size,digest = verifier._visible_pixels(verifier.ROOT / meta["texture"].removeprefix("res://"))
        row = {"kind":"collect","path":meta["texture"],"metadata_path":"res://assets/powers/pickup_003a1/manifest.json",
               "valid":True,"visible_pixels":True,"size":size,"visible_rgba_sha256":digest,"transparent_rgb_normalized":True,
               "native_source_available":True,"native_source_sha256":meta["source_sha256"]}
        row.update({key:deepcopy(meta[key]) for key in ("cell","pivot","columns","frame_count","durations_ms","tags","layers","source")})
        path = "res://assets/audio/pickup_collect.wav"
        with wave.open(str(verifier.ROOT / path.removeprefix("res://")),"rb") as sample:
            digest = hashlib.sha256(sample.readframes(sample.getnframes())).hexdigest()
        cls.fixture = {"pickup_flair_json":json.dumps(meta),"pickup_flair_texture":row,"pickup_collect_audio":{
            "kind":"pickup_collect","path":path,"valid":True,"format":1,"stereo":False,"channels":1,"mix_rate":48000,
            "loop_mode":0,"pcm_frames":8640,"duration_seconds":.18,"pcm_sha256":digest}}

    def setUp(self): self.report = deepcopy(self.fixture)
    def verify(self): return verifier.verify_pickup_assets(self.report)

    def test_actual_source_native_pixels_and_short_pcm_fixture_accepted(self):
        result = self.verify()
        self.assertTrue(result["pickup_flair_visible_rgba_exact"])
        self.assertTrue(result["pickup_collection_audio_pcm_exact"])
        self.assertEqual(result["pickup_collection_audio_seconds"],.18)

    def test_missing_marker_or_unknown_receipts_rejected(self):
        for key in ("pickup_flair_texture","pickup_collect_audio"):
            for row in (None,{},[],{"kind":"unknown"}):
                self.report = deepcopy(self.fixture);self.report[key]=row
                with self.subTest(key=key,row=row),self.assertRaisesRegex(RuntimeError,"did not inspect"):self.verify()

    def test_changed_or_invalid_native_manifest_rejected(self):
        for value in (None,"broken",json.dumps({"duration_ms":310})):
            self.report = deepcopy(self.fixture);self.report["pickup_flair_json"]=value
            with self.subTest(value=value),self.assertRaisesRegex(RuntimeError,"manifest (is invalid|differs)"):self.verify()

    def test_imported_visible_rgba_alpha_and_path_drift_rejected(self):
        for key,value,expected in (("path","res://assets/wrong.png","resource path"),("metadata_path","res://assets/wrong.json","resource path"),
                                   ("valid",False,"alpha/visible"),("visible_pixels",False,"alpha/visible"),("size",[1,1],"alpha/visible"),
                                   ("visible_rgba_sha256","0"*64,"alpha/visible"),("transparent_rgb_normalized",False,"alpha/visible")):
            self.report = deepcopy(self.fixture);self.report["pickup_flair_texture"][key]=value
            with self.subTest(key=key),self.assertRaisesRegex(RuntimeError,expected):self.verify()

    def test_native_animation_topology_and_provenance_drift_rejected(self):
        for key,value in (("pivot",[0,0]),("cell",[1,1]),("columns",1),("frame_count",1),("durations_ms",[]),
                          ("tags",{}),("layers",[]),("source","assets/wrong.aseprite")):
            self.report = deepcopy(self.fixture);self.report["pickup_flair_texture"][key]=value
            with self.subTest(key=key),self.assertRaisesRegex(RuntimeError,"topology"):self.verify()
        for key,value in (("native_source_available","true"),("native_source_sha256","0"*64)):
            self.report = deepcopy(self.fixture);self.report["pickup_flair_texture"][key]=value
            with self.subTest(key=key),self.assertRaisesRegex(RuntimeError,"native-source evidence"):self.verify()

    def test_audio_pcm_loop_length_format_and_resource_drift_rejected(self):
        for key,value in (("path","res://assets/audio/card_select.wav"),("valid",False),("format",2),("stereo",True),
                          ("channels",2),("mix_rate",32000),("loop_mode",1),("pcm_frames",9000),("pcm_sha256","0"*64),
                          ("duration_seconds",.5),("duration_seconds",True),("duration_seconds",".18"),("duration_seconds",float("nan"))):
            self.report = deepcopy(self.fixture);self.report["pickup_collect_audio"][key]=value
            with self.subTest(key=key,value=value),self.assertRaisesRegex(RuntimeError,"PCM or one-shot timing"):self.verify()

    def test_optional_native_master_absence_is_explicit(self):
        self.report["pickup_flair_texture"].update(native_source_available=False,native_source_sha256="")
        result = self.verify()
        self.assertTrue(result["pickup_native_master_verified"])
        self.assertFalse(result["pickup_packaged_native_master_available"])


def _combat_pcm_fixture(path,kind,stereo=False):
    with wave.open(str(verifier.ROOT/path.removeprefix("res://")),"rb") as sample:
        frames=sample.getnframes();rate=sample.getframerate();channels=sample.getnchannels();pcm=sample.readframes(frames)
    return {"kind":kind,"path":path,"valid":True,"format":1,"stereo":stereo,"channels":channels,"mix_rate":rate,"loop_mode":0,"loop_begin":0,"loop_end":0,"pcm_frames":frames,"duration_seconds":frames/rate,"pcm_sha256":hashlib.sha256(pcm).hexdigest()}

class CombatArtPackageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture={}
        locations={"combat_art_json":"assets/powers/combat_003a1/manifest.json","combat_identity_json":"assets/powers/identity_manifest.json","combat_spark_json":"assets/powers/impact_003a1/manifest.json","combat_arena_geometry_json":"assets/arena/manifest.json"}
        for field,path in locations.items():cls.fixture[field]=(verifier.ROOT/path).read_text()
        art=json.loads(cls.fixture['combat_art_json']);identity=json.loads(cls.fixture['combat_identity_json']);sparks=json.loads(cls.fixture['combat_spark_json'])
        rows=[]
        def add(kind,meta,metadata_path,layer=None):
            size,digest=verifier._visible_pixels(verifier.ROOT/meta['texture'].removeprefix('res://'))
            row={key:deepcopy(meta[key]) for key in ('cell','pivot','columns','frame_count','tags','durations_ms','layers','source')}
            row.update(kind=kind,path=meta['texture'],metadata_path=metadata_path,valid=True,visible_pixels=True,size=size,visible_rgba_sha256=digest,transparent_rgb_normalized=True,native_source_available=False,native_source_sha256='')
            if layer is not None:row['native_layer']=layer
            rows.append(row)
        for layer,path in art['base_arena']['textures'].items():
            meta=deepcopy(art['base_arena']);meta['texture']=path;add('arena_base/'+layer,meta,'res://assets/powers/combat_003a1/manifest.json',layer)
        for family,meta in art['families'].items():add('combat/'+family,meta,'res://assets/powers/combat_003a1/manifest.json')
        for family in ('redline','afterimage','orbit_drive','predator_line'):add('card/'+family,identity['families'][family]['cards'],'res://assets/powers/identity_manifest.json')
        add('combat/contact_sparks',sparks,'res://assets/powers/impact_003a1/manifest.json')
        cls.fixture['combat_art_textures']=rows

    def setUp(self):self.report=deepcopy(self.fixture)
    def verify(self):return verifier.verify_combat_presentation_assets(self.report)

    def test_all_compiled_venue_motion_card_and_spark_pixels_accepted(self):
        result=self.verify();self.assertEqual(result['combat_art_sheets_verified'],14);self.assertEqual(result['combat_native_master_count'],9);self.assertTrue(result['combat_native_runtime_parity_exact'])

    def test_missing_extra_duplicate_or_unknown_sheet_rejected(self):
        for mode in ('missing','extra','duplicate','unknown'):
            self.report=deepcopy(self.fixture);rows=self.report['combat_art_textures']
            if mode=='missing':rows.pop()
            elif mode=='extra':rows.append(deepcopy(rows[0]))
            elif mode=='duplicate':rows[0]=deepcopy(rows[1])
            else:rows[0]['kind']='unknown'
            with self.subTest(mode=mode),self.assertRaisesRegex(RuntimeError,'fourteen combat'):self.verify()

    def test_wrong_fixed_geometry_or_source_metadata_rejected(self):
        for key in ('combat_art_json','combat_identity_json','combat_spark_json','combat_arena_geometry_json'):
            self.report=deepcopy(self.fixture);self.report[key]='{}'
            with self.subTest(field=key),self.assertRaisesRegex(RuntimeError,'metadata differs'):self.verify()

    def test_invalid_native_metadata_report_rejected(self):
        for value in (None,'broken',False):
            self.report=deepcopy(self.fixture);self.report['combat_art_json']=value
            with self.subTest(value=value),self.assertRaisesRegex(RuntimeError,'metadata is invalid'):self.verify()

    def test_changed_alpha_visible_rgb_or_actual_import_dimensions_rejected(self):
        for key,value in (('valid',False),('visible_pixels',False),('visible_rgba_sha256','0'*64),('size',[1,1]),('transparent_rgb_normalized',False)):
            self.report=deepcopy(self.fixture);self.report['combat_art_textures'][0][key]=value
            with self.subTest(field=key),self.assertRaisesRegex(RuntimeError,'alpha/visible RGBA'):self.verify()

    def test_runtime_path_or_wrong_native_layer_rejected(self):
        for key,value in (('path','res://assets/wrong.png'),('metadata_path','res://assets/wrong.json'),('native_layer','surface')):
            self.report=deepcopy(self.fixture);self.report['combat_art_textures'][0][key]=value
            with self.subTest(field=key),self.assertRaisesRegex(RuntimeError,'resource/layer path'):self.verify()

    def test_native_tag_timeline_pivot_layer_and_frame_count_drift_rejected(self):
        for key,value in (('cell',[1,1]),('pivot',[0,0]),('tags',{}),('durations_ms',[]),('layers',[]),('columns',0),('frame_count',0),('source','assets/wrong.aseprite')):
            self.report=deepcopy(self.fixture);row=next(r for r in self.report['combat_art_textures'] if r['kind']=='combat/contact_sparks');row[key]=value
            with self.subTest(field=key),self.assertRaisesRegex(RuntimeError,'native topology'):self.verify()

    def test_optional_native_master_presence_is_exact_boolean_fact(self):
        for key,value in (('native_source_available','true'),('native_source_sha256','0'*64)):
            self.report=deepcopy(self.fixture);self.report['combat_art_textures'][0][key]=value
            with self.subTest(field=key),self.assertRaisesRegex(RuntimeError,'native-source evidence'):self.verify()

class CombatAudioPackageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        text=(verifier.ROOT/'assets/audio/impact_003a1/manifest.json').read_text();meta=json.loads(text)
        cls.fixture={'combat_audio_json':text,'combat_audio':[_combat_pcm_fixture('res://assets/audio/impact_003a1/'+kind+'.wav',kind) for kind in meta['sounds']]}
    def setUp(self):self.report=deepcopy(self.fixture)
    def verify(self):return verifier.verify_combat_audio_assets(self.report)
    def test_seven_exact_original_pcm_cues_accepted(self):
        result=self.verify();self.assertEqual(result['metal_audio_cues_verified'],7);self.assertTrue(result['metal_audio_pcm_exact'])
    def test_missing_duplicate_or_unknown_cue_rejected(self):
        for mode in ('missing','duplicate','unknown'):
            self.report=deepcopy(self.fixture);rows=self.report['combat_audio']
            if mode=='missing':rows.pop()
            elif mode=='duplicate':rows[0]=deepcopy(rows[1])
            else:rows[0]['kind']='unknown'
            with self.subTest(mode=mode),self.assertRaisesRegex(RuntimeError,'seven metal'):self.verify()
    def test_format_channels_pcm_length_hash_loop_and_path_drift_rejected(self):
        for key,value in (('valid',False),('path','res://assets/audio/card_select.wav'),('format',2),('format',True),('stereo',True),('channels',2),('mix_rate',48000),('pcm_frames',999),('pcm_sha256','0'*64),('loop_mode',1)):
            self.report=deepcopy(self.fixture);self.report['combat_audio'][0][key]=value
            with self.subTest(field=key,value=value),self.assertRaisesRegex(RuntimeError,'actual imported PCM'):self.verify()
    def test_duration_nan_string_bool_or_wrong_seconds_rejected(self):
        for value in (float('nan'),True,'.095',.5):
            self.report=deepcopy(self.fixture);self.report['combat_audio'][0]['duration_seconds']=value
            with self.subTest(value=value),self.assertRaisesRegex(RuntimeError,'PCM duration'):self.verify()
    def test_authored_source_metadata_drift_rejected(self):
        self.report['combat_audio_json']='{}'
        with self.assertRaisesRegex(RuntimeError,'metadata differs'):self.verify()

class MusicVariationPackageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        folder=verifier.ROOT/'assets/audio/music';text=(folder/'run_arrangement_003a1_manifest.json').read_text();meta=json.loads(text)
        combined=json.loads((folder/'manifest.json').read_text());combined['stems'].update(meta['stems']);combined['run_variation']=meta
        cls.fixture={'music_variation_json':text,'music_variation_score_json':(folder/'run_arrangement_003a1.json').read_text(),'music_asset_metadata':combined,'music_variation_stems':[_combat_pcm_fixture('res://assets/audio/music/'+kind+'.wav',kind,True) for kind in meta['stems']]}
    def setUp(self):self.report=deepcopy(self.fixture)
    def verify(self):return verifier.verify_music_variation_assets(self.report)
    def test_two_new_original_pcm_stems_and_seven_stem_metadata_accepted(self):
        result=self.verify();self.assertEqual(result['music_variation_stems_verified'],2);self.assertTrue(result['original_five_music_bytes_preserved']);self.assertTrue(result['music_seven_stem_asset_metadata_verified'])
    def test_missing_or_duplicate_new_stem_rejected(self):
        for mode in ('missing','duplicate'):
            self.report=deepcopy(self.fixture)
            if mode=='missing':self.report['music_variation_stems'].pop()
            else:self.report['music_variation_stems'][0]=deepcopy(self.report['music_variation_stems'][1])
            with self.subTest(mode=mode),self.assertRaisesRegex(RuntimeError,'both new Run'):self.verify()
    def test_original_or_new_stem_missing_from_actual_music_metadata_rejected(self):
        for kind in ('title','run_base','run_opening','run_motion'):
            self.report=deepcopy(self.fixture);self.report['music_asset_metadata']['stems'].pop(kind)
            with self.subTest(kind=kind),self.assertRaisesRegex(RuntimeError,'seven synchronized'):self.verify()
    def test_pcm_rate_stereo_format_hash_and_import_loop_drift_rejected(self):
        for key,value in (('mix_rate',48000),('stereo',False),('format',2),('pcm_sha256','0'*64),('pcm_frames',100),('loop_mode',1),('duration_seconds',.5)):
            self.report=deepcopy(self.fixture);self.report['music_variation_stems'][0][key]=value
            with self.subTest(field=key),self.assertRaisesRegex(RuntimeError,'actual imported PCM'):self.verify()
    def test_authored_score_sidecar_or_metadata_drift_rejected(self):
        for key in ('music_variation_json','music_variation_score_json'):
            self.report=deepcopy(self.fixture);self.report[key]='{}'
            with self.subTest(field=key),self.assertRaisesRegex(RuntimeError,'metadata differs'):self.verify()
    def test_same_numeric_music_metadata_accepts_godot_json_number_types(self):
        self.report['music_asset_metadata']['grid']['frames']=float(self.report['music_asset_metadata']['grid']['frames'])
        self.assertTrue(self.verify()['music_seven_stem_asset_metadata_verified'])
    def test_boolean_cannot_substitute_for_numeric_music_grid(self):
        self.report['music_asset_metadata']['grid']['frames']=True
        with self.assertRaisesRegex(RuntimeError,'seven synchronized'):self.verify()

if __name__ == "__main__": unittest.main(verbosity=2)
