"""Reject incomplete/mislabeled accounting evidence; synthetic validator tests."""
from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest
import upgrade_sustain_003a1 as study

def fixture():
    rows = []
    for investments in (0,3,6,12):
        for seed in (421,7341,2026):
            for policy in (["active", "active_then_hands_off"] if investments == 12 else ["active"]):
                ranks = {} if investments == 0 else {"fixture":investments}
                rows.append({"style":"defensive","investments":investments,"seed":seed,"policy":policy,"initial_ranks":ranks,"final_ranks":ranks,
                             "starting_rpm":1,"final_rpm":.65,"total_loss":.6,"total_gain":.25,"loss_by_source":{"passive":.4,"collisions":.2},"gain_by_source":{"elimination":.25},
                             "ledger_closure_error":0,"survival_seconds":300,"seconds_above_90":50})
    return {"runs":rows,"horizon":480}

class UpgradeEvidenceContracts(unittest.TestCase):
    def setUp(self): self.data = fixture()
    def test_complete_closed_evidence_accepted(self): study.validate(self.data)
    def test_missing_investment_rejected(self):
        self.data["runs"] = [r for r in self.data["runs"] if r["investments"] != 6]
        with self.assertRaises(AssertionError): study.validate(self.data)
    def test_missing_seed_rejected(self):
        self.data["runs"] = [r for r in self.data["runs"] if r["seed"] != 2026]
        with self.assertRaises(AssertionError): study.validate(self.data)
    def test_missing_hands_off_contrast_rejected(self):
        self.data["runs"] = [r for r in self.data["runs"] if r["policy"] != "active_then_hands_off"]
        with self.assertRaises(AssertionError): study.validate(self.data)
    def test_false_closed_ledger_rejected(self):
        self.data["runs"][0]["final_rpm"] = 1
        with self.assertRaises(AssertionError): study.validate(self.data)
    def test_unreported_loss_source_rejected(self):
        self.data["runs"][0]["loss_by_source"]["wall"] = .2
        with self.assertRaises(AssertionError): study.validate(self.data)
    def test_unreported_gain_source_rejected(self):
        self.data["runs"][0]["gain_by_source"]["clutch"] = .2
        with self.assertRaises(AssertionError): study.validate(self.data)
    def test_live_upgrade_contamination_rejected(self):
        self.data["runs"][0]["final_ranks"] = {"clutch":1}
        with self.assertRaises(AssertionError): study.validate(self.data)
    def test_false_investment_level_rejected(self):
        self.data["runs"][3]["initial_ranks"] = {}
        self.data["runs"][3]["final_ranks"] = {}
        with self.assertRaises(AssertionError): study.validate(self.data)
    def test_impossible_time_near_full_rejected(self):
        self.data["runs"][0]["seconds_above_90"] = 600
        with self.assertRaises(AssertionError): study.validate(self.data)

class HumanProfileBoundaryContracts(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.paths = []
        self.boundary = {"human_confirmed_play_or_save":True,"affected_provenance":{}}
        for style in ("aggressive","defensive","mixed"):
            data = fixture()
            for row in data["runs"]: row["style"] = style
            path = Path(self.temp.name) / (style + ".json")
            path.write_text(json.dumps(data),encoding="utf-8")
            provenance = path.with_name(path.stem+"_provenance.json")
            guard = {"report_sha256":study.pipeline.sha256(path),"source_unchanged":True,"driver_unchanged":True,"player_unchanged":False,"player_before":{"collection":"prior"},"player_after":{"collection":"human_saved"}}
            provenance.write_text(json.dumps(guard),encoding="utf-8")
            self.boundary["affected_provenance"][str(provenance)] = {"provenance_sha256":study.pipeline.sha256(provenance),"player_before":guard["player_before"],"player_after":guard["player_after"]}
            self.paths.append(path)
    def tearDown(self): self.temp.cleanup()
    def test_unexplained_profile_change_rejected(self):
        with self.assertRaises(AssertionError): study.load_reports(self.paths)
    def test_confirmed_exact_boundary_keeps_failed_guard_visible(self):
        rows,guards = study.load_reports(self.paths,self.boundary)
        self.assertEqual(len(rows),45)
        self.assertTrue(all(g["player_unchanged"] is False for g in guards))
    def test_false_confirmation_rejected(self):
        self.boundary["human_confirmed_play_or_save"] = False
        with self.assertRaises(AssertionError): study.load_reports(self.paths,self.boundary)
    def test_changed_provenance_rejected(self):
        next(iter(self.boundary["affected_provenance"].values()))["provenance_sha256"] = "changed"
        with self.assertRaises(AssertionError): study.load_reports(self.paths,self.boundary)
    def test_wrong_before_bytes_rejected(self):
        next(iter(self.boundary["affected_provenance"].values()))["player_before"] = {"collection":"unrelated"}
        with self.assertRaises(AssertionError): study.load_reports(self.paths,self.boundary)

if __name__ == "__main__": unittest.main()
