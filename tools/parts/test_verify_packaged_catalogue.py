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

import verify_packaged_catalogue as verifier


class PackagedEconomyContracts(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "isolated_collection.json"
        source = json.loads((verifier.ROOT / "assets/data/parts_catalogue.json").read_text(encoding="utf-8"))
        self.expected = {category + ":" + local for category,parts in source["categories"].items() for local in parts}
        self.saved = {"schema_version":2,"starter_selected":"breaker","owned_part_ids":sorted(self.expected),
                      "equipped_build":{"blade":"smash","ratchet":"high","bit":"flat"},
                      "progression":{"credits":0,"salvage":0,"packet_serial":0,"pending_packet":{},
                                     "last_packet":{},"run_serial":0,"active_run":"","last_reward":{}}}

    def tearDown(self): self.temp.cleanup()

    def write(self): self.path.write_text(json.dumps(self.saved),encoding="utf-8")

    def test_schema_two_qa_collection_requires_empty_progression(self):
        self.write()
        result = verifier.verify_collection(self.path,self.expected)
        self.assertEqual(result["schema_version"],2)
        self.assertTrue(result["qa_economy_empty"])
        self.assertEqual(result["owned_count"],31)

    def test_schema_one_fixture_is_rejected(self):
        self.saved["schema_version"] = 1
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


if __name__ == "__main__": unittest.main(verbosity=2)
