"""Promotion failure guards; all builds/profiles are disposable test fixtures."""
from pathlib import Path
import json
import struct
import tempfile
import unittest
from unittest.mock import patch

import windows_checkpoint as pipeline


class PromotionGuards(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.base = Path(self.temporary.name)
        self.root = self.base / "repo"
        self.qa = self.base / "qa"
        self.candidate = self.base / "candidate"
        self.candidate.mkdir()
        self.latest = self.root / "builds" / "latest"
        self.latest.mkdir(parents=True)
        (self.latest / pipeline.EXE).write_bytes(b"known-good human build")
        (self.latest / "unknown-note.txt").write_text("preserve this local note")
        (self.candidate / pipeline.EXE).write_bytes(b"MZ" + b"fixture only" * 400)
        (self.candidate / "README.txt").write_text("fixture, never an exported game")
        digest = pipeline.sha256(self.candidate / pipeline.EXE)
        (self.candidate / (pipeline.EXE + ".sha256")).write_text(digest + "  " + pipeline.EXE + "\n")
        logs = self.base / "logs"
        logs.mkdir()
        phases = {}
        for phase in ("import", "export", "smoke"):
            log = logs / (phase + ".log")
            log.write_text(pipeline.SMOKE_MARKER if phase == "smoke" else "fixture process exit 0")
            phases[phase] = {"exit_code": 0, "log": str(log), "log_sha256": pipeline.sha256(log)}
        captures = []
        for name in pipeline.REQUIRED_CAPTURES:
            image = self.base / name
            # Only header parsing is tested; these are not gameplay screenshots.
            image.write_bytes(b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", 640, 360) + b"x" * 1200)
            captures.append(pipeline.png_record(image))
        self.manifest = {
            "schema": 1, "checkpoint": "002C.5", "validation": "passed",
            "qa_task": "002C.5.1", "human_acceptance": "PENDING HOME HUMAN PLAYTEST",
            "source": {"git_sha": "a" * 40, "tracked_clean": True},
            "import": phases["import"], "export": phases["export"],
            "packaged_smoke": {**phases["smoke"], "marker": pipeline.SMOKE_MARKER,
                               "engine_log": phases["smoke"]["log"], "engine_log_sha256": phases["smoke"]["log_sha256"],
                               "profile_unchanged": True, "captures": captures},
            "delivery_sha256": {name: pipeline.sha256(self.candidate / name) for name in pipeline.DELIVERY_FILES[:-1]},
        }
        self.save_manifest()

    def tearDown(self):
        self.temporary.cleanup()

    def save_manifest(self):
        pipeline.write_json(self.candidate / "build-manifest.json", self.manifest)

    def assert_latest_preserved(self):
        self.assertEqual((self.latest / pipeline.EXE).read_bytes(), b"known-good human build")
        self.assertTrue((self.latest / "unknown-note.txt").is_file())

    def reject(self):
        with self.assertRaises(ValueError):
            pipeline.promote_candidate(self.candidate, self.root, self.qa, "002C.5")
        self.assert_latest_preserved()

    def test_failed_validation_never_replaces_latest(self):
        self.manifest["validation"] = "failed"
        self.save_manifest()
        self.reject()

    def test_003a_requires_pending_human_progression_acceptance(self):
        self.manifest["checkpoint"] = "003A"
        self.manifest["qa_task"] = "003A"
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, "pending human progression"):
            pipeline.verify_candidate(self.candidate)
        self.assert_latest_preserved()

    def test_003a_requires_actual_shop_flow_marker(self):
        self.manifest.update(checkpoint="003A", qa_task="003A", human_acceptance="PENDING HUMAN PROGRESSION PLAYTEST")
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, "Shop flow marker"):
            pipeline.verify_candidate(self.candidate)
        self.assert_latest_preserved()

    def test_003a_requires_verified_shop_captures(self):
        self.manifest.update(checkpoint="003A", qa_task="003A", human_acceptance="PENDING HUMAN PROGRESSION PLAYTEST")
        smoke = self.manifest["packaged_smoke"]
        log = Path(smoke["log"])
        log.write_text(pipeline.SMOKE_MARKER + "\nSHOP_PROGRESSION_SMOKE_PASS (isolated fixture)")
        smoke["log_sha256"] = smoke["engine_log_sha256"] = pipeline.sha256(log)
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, "Missing packaged smoke capture: 003a-shop"):
            pipeline.verify_candidate(self.candidate)
        self.assert_latest_preserved()

    def prepare_shop_candidate(self, persisted=True, qa_task="003A"):
        self.manifest.update(checkpoint=qa_task, qa_task=qa_task, human_acceptance="PENDING HUMAN PROGRESSION PLAYTEST")
        smoke = self.manifest["packaged_smoke"]
        log = Path(smoke["log"])
        log.write_text(pipeline.SMOKE_MARKER + "\n" + pipeline.SHOP_SMOKE_MARKER + " (labelled flow fixture)")
        smoke["log_sha256"] = smoke["engine_log_sha256"] = pipeline.sha256(log)
        for name in pipeline.SHOP_REQUIRED_CAPTURES:
            image = self.base / name
            image.write_bytes(b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", 640, 360) + b"x" * 1200)
            smoke["captures"].append(pipeline.png_record(image))
        self.shop_save = self.qa / qa_task / "temp" / "fixture" / "isolated-collection.json"
        rows = [
            {"category":"blade", "id":"balance", "part_id":"blade:balance", "rarity":"COMMON", "new":True, "salvage":0},
            {"category":"ratchet", "id":"kickback", "part_id":"ratchet:kickback", "rarity":"RARE", "new":True, "salvage":0},
            {"category":"bit", "id":"flat", "part_id":"bit:flat", "rarity":"COMMON", "new":False, "salvage":1},
        ]
        self.shop_state = {"schema_version":3, "starter_selected":"breaker",
            "owned_part_ids":["blade:smash", "ratchet:high", "bit:flat", "blade:balance", "ratchet:kickback"],
            "equipped_build":{"blade":"balance", "ratchet":"high", "bit":"flat"},
            "progression":{"credits":0, "salvage":1, "packet_serial":1, "pending_packet":{},
                "last_packet":{"id":"packet-1", "request_nonce":"packet-1", "kind":"standard", "currency":"credits", "cost":48,
                               "status":"resolved", "rows":rows, "total_salvage":1,
                               "quantity":1,"cursor":1,"packets":[{"rows":rows,"total_salvage":1}]},
                "run_serial":1, "active_run":"", "last_reward":{"id":"run-1", "credits":48, "eligible":True,
                                                           "breakdown":{"threats":48, "elites":0, "bosses":0}}}}
        smoke.update(qa_task=qa_task, child_environment={"TOPGAME_QA_ROOT":str(self.qa.resolve())},
                     isolated_collection=str(self.shop_save.resolve()),
                     command=[str(self.candidate / pipeline.EXE), "--", "--smoke-test", "--qa-task=" + qa_task,
                              "--collection-path=" + str(self.shop_save)])
        if persisted:
            pipeline.write_json(self.shop_save, self.shop_state)
            smoke["shop_progression"] = pipeline.shop_progression_record(self.shop_save, qa_root=self.qa, qa_task=qa_task)
        self.save_manifest()

    def save_tampered_shop(self):
        # Update only the declared file hash. The independent semantic checks
        # must reject an invalid receipt/wallet even if its new bytes are hashed.
        pipeline.write_json(self.shop_save, self.shop_state)
        self.manifest["packaged_smoke"]["shop_progression"]["sha256"] = pipeline.sha256(self.shop_save)
        self.save_manifest()

    def reject_shop(self, message):
        with self.assertRaisesRegex(ValueError, message):
            pipeline.promote_candidate(self.candidate, self.root, self.qa, self.manifest["checkpoint"])
        self.assert_latest_preserved()
        self.assertFalse((self.root / "builds/checkpoints" / self.manifest["checkpoint"]).exists())

    def test_003a_markers_and_captures_without_persisted_progress_are_rejected(self):
        self.prepare_shop_candidate(persisted=False)
        self.reject_shop("persisted Shop progression")

    def test_003a_old_unfunded_unchanged_save_cannot_be_certified(self):
        self.prepare_shop_candidate()
        self.shop_state["owned_part_ids"] = ["blade:smash", "ratchet:high", "bit:flat"]
        self.shop_state["equipped_build"] = {"blade":"smash", "ratchet":"high", "bit":"flat"}
        self.shop_state["progression"].update(packet_serial=0, run_serial=0, salvage=0, last_packet={}, last_reward={})
        self.save_tampered_shop()
        self.reject_shop("did not actually grow")

    def test_003a_missing_persisted_save_is_rejected(self):
        self.prepare_shop_candidate()
        self.shop_save.unlink()
        self.reject_shop("persisted save is missing")

    def test_003a_save_bytes_are_rechecked_even_if_state_remains_valid(self):
        self.prepare_shop_candidate()
        with self.shop_save.open("a") as stream:
            stream.write("\n")
        self.reject_shop("save/hash/summary changed")

    def test_003a_double_purchase_serial_is_rejected(self):
        self.prepare_shop_candidate()
        self.shop_state["progression"]["packet_serial"] = 2
        self.save_tampered_shop()
        self.reject_shop("exactly one packet")

    def test_003a_replayed_duplicate_salvage_is_rejected(self):
        self.prepare_shop_candidate()
        self.shop_state["progression"]["salvage"] = 2
        self.save_tampered_shop()
        self.reject_shop("duplicate grant or replay")

    def test_003a_replayed_receipt_id_is_rejected(self):
        self.prepare_shop_candidate()
        self.shop_state["progression"]["last_packet"]["id"] = "packet-2"
        self.save_tampered_shop()
        self.reject_shop("resolved paid receipt")

    def test_003a_wrong_receipt_nonce_is_rejected(self):
        self.prepare_shop_candidate()
        self.shop_state["progression"]["last_packet"]["request_nonce"] = "packet-0"
        self.save_tampered_shop()
        self.reject_shop("resolved paid receipt")

    def test_003a_unpaid_wallet_is_rejected_even_with_rehashed_save(self):
        self.prepare_shop_candidate()
        self.shop_state["progression"]["credits"] = 48
        self.save_tampered_shop()
        self.reject_shop("actual 48-CREDIT debit")

    def test_003a_unfunded_reward_is_rejected(self):
        self.prepare_shop_candidate()
        self.shop_state["progression"]["last_reward"]["credits"] = 0
        self.save_tampered_shop()
        self.reject_shop("saved 48-CREDIT funding reward")

    def test_003a_funding_nonce_replay_is_rejected(self):
        self.prepare_shop_candidate()
        self.shop_state["progression"]["run_serial"] = 2
        self.save_tampered_shop()
        self.reject_shop("funding Run nonce")

    def test_003a_clear_counts_cannot_replace_saved_credit_contributions(self):
        self.prepare_shop_candidate()
        self.shop_state["progression"]["last_reward"]["breakdown"]["threats"] = 4
        self.save_tampered_shop()
        self.reject_shop("saved fixture funding ledger changed")

    def test_003a_saved_new_part_must_be_equipped(self):
        self.prepare_shop_candidate()
        self.shop_state["equipped_build"] = {"blade":"smash", "ratchet":"high", "bit":"flat"}
        self.save_tampered_shop()
        self.reject_shop("NEW design was not actually equipped")

    def test_003a_ungranted_owned_parts_are_rejected(self):
        self.prepare_shop_candidate()
        self.shop_state["owned_part_ids"].append("blade:hammerfall")
        self.save_tampered_shop()
        self.reject_shop("ownership does not match")

    def test_003a_pending_receipt_cannot_be_promoted(self):
        self.prepare_shop_candidate()
        self.shop_state["progression"]["pending_packet"] = self.shop_state["progression"]["last_packet"].copy()
        self.save_tampered_shop()
        self.reject_shop("not acknowledged")

    def test_003a_active_run_cannot_be_promoted(self):
        self.prepare_shop_candidate()
        self.shop_state["progression"]["active_run"] = "run-1"
        self.save_tampered_shop()
        self.reject_shop("active Run was not retired")

    def test_003a_tampered_receipt_rows_are_rejected(self):
        self.prepare_shop_candidate()
        self.shop_state["progression"]["last_packet"]["rows"].pop()
        self.save_tampered_shop()
        self.reject_shop("three physical slots")

    def test_003a_wrong_receipt_cost_is_rejected(self):
        self.prepare_shop_candidate()
        self.shop_state["progression"]["last_packet"]["cost"] = 60
        self.save_tampered_shop()
        self.reject_shop("resolved paid receipt")

    def test_003a_bulk_quantity_cannot_masquerade_as_single_smoke(self):
        self.prepare_shop_candidate()
        self.shop_state["progression"]["last_packet"]["quantity"] = 3
        self.save_tampered_shop()
        self.reject_shop("single batch receipt")

    def test_003a_unfinished_single_cursor_is_rejected(self):
        self.prepare_shop_candidate()
        self.shop_state["progression"]["last_packet"]["cursor"] = 0
        self.save_tampered_shop()
        self.reject_shop("single batch receipt")

    def test_003a_altered_batch_group_is_rejected(self):
        self.prepare_shop_candidate()
        self.shop_state["progression"]["last_packet"]["packets"] = []
        self.save_tampered_shop()
        self.reject_shop("single batch receipt")

    def test_003a_old_schema_cannot_accept_new_build_smoke(self):
        self.prepare_shop_candidate()
        self.shop_state["schema_version"] = 2
        self.save_tampered_shop()
        self.reject_shop("schema3")

    def test_003a_boolean_wallet_is_not_an_integer_balance(self):
        self.prepare_shop_candidate()
        self.shop_state["progression"]["credits"] = False
        self.save_tampered_shop()
        self.reject_shop("actual 48-CREDIT debit")

    def test_003a_report_summary_is_revalidated(self):
        self.prepare_shop_candidate()
        self.manifest["packaged_smoke"]["shop_progression"]["summary"]["owned_count"] = 31
        self.save_manifest()
        self.reject_shop("save/hash/summary changed")

    def test_003a_save_must_match_actual_child_command(self):
        self.prepare_shop_candidate()
        self.manifest["packaged_smoke"]["command"][-1] = "--collection-path=" + str(self.base / "other-save.json")
        self.save_manifest()
        self.reject_shop("actual smoke command")

    def test_003a_explicit_child_qa_boundary_is_required(self):
        self.prepare_shop_candidate()
        self.manifest["packaged_smoke"].pop("child_environment")
        self.save_manifest()
        self.reject_shop("explicit child QA boundary")

    def test_003a_player_profile_path_is_refused_before_read(self):
        path = self.base / "player-profile" / "collection.json"
        pipeline.write_json(path, {"private":"fixture not read"})
        with self.assertRaisesRegex(ValueError, "Path must remain inside"):
            pipeline.shop_progression_record(path, qa_root=self.qa, qa_task="003A")

    def test_003a_valid_persisted_progression_promotes_only_fixture(self):
        self.prepare_shop_candidate()
        result = pipeline.promote_candidate(self.candidate, self.root, self.qa, "003A")
        self.assertEqual(result["checkpoint"], str(self.root / "builds/checkpoints/003A" / pipeline.EXE))
        self.assertEqual(pipeline.sha256(self.latest / pipeline.EXE), self.manifest["delivery_sha256"][pipeline.EXE])
        self.assertEqual((Path(result["preserved_previous"]) / "latest" / pipeline.EXE).read_bytes(), b"known-good human build")

    def test_003a1_valid_persisted_progression_promotes_only_fixture(self):
        self.prepare_shop_candidate(qa_task="003A.1")
        result = pipeline.promote_candidate(self.candidate, self.root, self.qa, "003A.1")
        self.assertEqual(result["checkpoint"], str(self.root / "builds/checkpoints/003A.1" / pipeline.EXE))
        self.assertEqual(pipeline.sha256(self.latest / pipeline.EXE), self.manifest["delivery_sha256"][pipeline.EXE])
        self.assertEqual((Path(result["preserved_previous"]) / "latest" / pipeline.EXE).read_bytes(), b"known-good human build")

    def test_003a2_valid_persisted_progression_promotes_only_fixture(self):
        self.prepare_shop_candidate(qa_task="003A.2")
        result = pipeline.promote_candidate(self.candidate, self.root, self.qa, "003A.2")
        self.assertEqual(result["checkpoint"], str(self.root / "builds/checkpoints/003A.2" / pipeline.EXE))
        self.assertEqual(pipeline.sha256(self.latest / pipeline.EXE), self.manifest["delivery_sha256"][pipeline.EXE])
        self.assertEqual((Path(result["preserved_previous"]) / "latest" / pipeline.EXE).read_bytes(), b"known-good human build")

    def test_003a2_unpaid_wallet_cannot_promote(self):
        self.prepare_shop_candidate(qa_task="003A.2")
        self.shop_state["progression"]["credits"] = 48
        self.save_tampered_shop()
        self.reject_shop("actual 48-CREDIT debit")

    def test_003a2_requires_actual_shop_captures(self):
        self.prepare_shop_candidate(qa_task="003A.2")
        self.manifest["packaged_smoke"]["captures"] = [row for row in self.manifest["packaged_smoke"]["captures"] if Path(row["path"]).name != "003a-packet-result.png"]
        self.save_manifest()
        self.reject_shop("Missing packaged smoke capture: 003a-packet-result")

    def test_003a1_shop_marker_is_required_even_with_saved_receipt(self):
        self.prepare_shop_candidate(qa_task="003A.1")
        smoke = self.manifest["packaged_smoke"]
        Path(smoke["log"]).write_text(pipeline.SMOKE_MARKER)
        smoke["log_sha256"] = smoke["engine_log_sha256"] = pipeline.sha256(Path(smoke["log"]))
        self.save_manifest()
        self.reject_shop("Shop flow marker")

    def test_003a1_shop_capture_is_required_even_with_saved_receipt(self):
        self.prepare_shop_candidate(qa_task="003A.1")
        self.manifest["packaged_smoke"]["captures"] = [row for row in self.manifest["packaged_smoke"]["captures"] if Path(row["path"]).name != "003a-packet-result.png"]
        self.save_manifest()
        self.reject_shop("Missing packaged smoke capture: 003a-packet-result")

    def test_003a1_markers_and_captures_cannot_replace_persisted_receipt(self):
        self.prepare_shop_candidate(persisted=False, qa_task="003A.1")
        self.reject_shop("persisted Shop progression")

    def test_003a1_rehashed_unpaid_wallet_is_rejected(self):
        self.prepare_shop_candidate(qa_task="003A.1")
        self.shop_state["progression"]["credits"] = 48
        self.save_tampered_shop()
        self.reject_shop("actual 48-CREDIT debit")

    def test_003a1_changed_valid_receipt_bytes_are_rechecked(self):
        self.prepare_shop_candidate(qa_task="003A.1")
        with self.shop_save.open("a") as stream:
            stream.write("\n")
        self.reject_shop("save/hash/summary changed")

    def test_003a1_cannot_relabel_003a_saved_receipt_boundary(self):
        self.prepare_shop_candidate()
        smoke = self.manifest["packaged_smoke"]
        self.manifest.update(checkpoint="003A.1", qa_task="003A.1")
        smoke["qa_task"] = "003A.1"
        smoke["command"][-2] = "--qa-task=003A.1"
        self.save_manifest()
        self.reject_shop("Path must remain inside")

    def test_003a1_checkpoint_and_qa_task_must_agree(self):
        self.prepare_shop_candidate(qa_task="003A.1")
        self.manifest["qa_task"] = "003A"
        self.save_manifest()
        self.reject_shop("checkpoint must match")

    def test_003a1_pending_human_progression_acceptance_is_required(self):
        self.prepare_shop_candidate(qa_task="003A.1")
        self.manifest["human_acceptance"] = "accepted"
        self.save_manifest()
        self.reject_shop("pending human progression")

    def test_shop_verifier_rejects_nearby_task_ids_before_reading(self):
        for qa_task in ("003A.10", "003A.1.preview", "003A.20"):
            with self.subTest(qa_task=qa_task), self.assertRaisesRegex(ValueError, "explicit 003A, 003A.1 or 003A.2"):
                pipeline.shop_progression_record(self.base / "absent.json", qa_root=self.qa, qa_task=qa_task)

    def test_shop_build_rejects_mismatched_task_before_staging(self):
        from argparse import Namespace
        with self.assertRaisesRegex(ValueError, "checkpoint must match"):
            pipeline.build(Namespace(checkpoint="003A.1", task="003A"))
        self.assert_latest_preserved()

    def test_changed_executable_never_replaces_latest(self):
        with (self.candidate / pipeline.EXE).open("ab") as stream:
            stream.write(b"modified")
        self.reject()

    def test_changed_evidence_never_replaces_latest(self):
        Path(self.manifest["packaged_smoke"]["log"]).write_text("ERROR: fixture failed")
        self.reject()

    def test_changed_engine_log_never_replaces_latest(self):
        self.manifest["packaged_smoke"]["engine_log_sha256"] = "f" * 64
        self.save_manifest()
        self.reject()

    def test_changed_real_profile_never_replaces_latest(self):
        self.manifest["packaged_smoke"]["profile_unchanged"] = False
        self.save_manifest()
        self.reject()

    def test_missing_capture_never_replaces_latest(self):
        self.manifest["packaged_smoke"]["captures"].pop()
        self.save_manifest()
        self.reject()

    def test_checkpoint_path_is_rejected(self):
        with self.assertRaises(ValueError):
            pipeline.promote_candidate(self.candidate, self.root, self.qa, "../../unrelated")
        self.assert_latest_preserved()

    def test_candidate_task_metadata_is_required(self):
        self.manifest["qa_task"] = "../../unrelated"
        self.save_manifest()
        self.reject()

    def test_pending_human_acceptance_is_required(self):
        self.manifest["human_acceptance"] = "accepted"
        self.save_manifest()
        self.reject()

    def test_stacked_c5_content_cannot_approve_parent_gameplay(self):
        self.manifest["checkpoint"] = "002C.5.2"
        self.manifest["qa_task"] = "002C.5.2"
        self.manifest["human_acceptance"] = "accepted"
        self.save_manifest()
        with self.assertRaises(ValueError):
            pipeline.promote_candidate(self.candidate, self.root, self.qa, "002C.5.2")
        self.assert_latest_preserved()

    def test_stacked_c5_validated_build_can_retain_pending_acceptance(self):
        self.manifest["checkpoint"] = "002C.5.2"
        self.manifest["qa_task"] = "002C.5.2"
        self.save_manifest()
        result = pipeline.promote_candidate(self.candidate, self.root, self.qa, "002C.5.2")
        self.assertEqual(result["checkpoint"], str(self.root / "builds/checkpoints/002C.5.2" / pipeline.EXE))

    def test_c6_false_human_acceptance_never_replaces_latest(self):
        self.manifest["checkpoint"] = "002C.6"
        self.manifest["qa_task"] = "002C.6"
        self.manifest["human_acceptance"] = "accepted"
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, "pending human presentation"):
            pipeline.promote_candidate(self.candidate, self.root, self.qa, "002C.6")
        self.assert_latest_preserved()
        self.assertFalse((self.root / "builds/checkpoints/002C.6").exists())

    def test_c6_pending_validated_candidate_promotes_fixture(self):
        self.manifest["checkpoint"] = "002C.6"
        self.manifest["qa_task"] = "002C.6"
        self.manifest["human_acceptance"] = "PENDING HUMAN PRESENTATION PLAYTEST"
        self.save_manifest()
        result = pipeline.promote_candidate(self.candidate, self.root, self.qa, "002C.6")
        self.assertEqual(result["checkpoint"], str(self.root / "builds/checkpoints/002C.6" / pipeline.EXE))
        self.assertEqual(pipeline.sha256(self.latest / pipeline.EXE), self.manifest["delivery_sha256"][pipeline.EXE])
        self.assertEqual((Path(result["preserved_previous"]) / "latest" / pipeline.EXE).read_bytes(), b"known-good human build")

    def test_build_directory_redirect_is_rejected(self):
        with patch.object(pipeline, "is_reparse", lambda path: Path(path) == self.root / "builds"):
            self.reject()

    def test_latest_redirect_is_rejected(self):
        with patch.object(pipeline, "is_reparse", lambda path: Path(path) == self.latest):
            self.reject()

    def test_success_preserves_previous_build_and_unknown_note(self):
        result = pipeline.promote_candidate(self.candidate, self.root, self.qa, "002C.5")
        self.assertEqual(pipeline.sha256(self.latest / pipeline.EXE), self.manifest["delivery_sha256"][pipeline.EXE])
        checkpoint = self.root / "builds" / "checkpoints" / "002C.5" / pipeline.EXE
        self.assertEqual(pipeline.sha256(checkpoint), self.manifest["delivery_sha256"][pipeline.EXE])
        archive = Path(result["preserved_previous"]) / "latest"
        self.assertEqual((archive / pipeline.EXE).read_bytes(), b"known-good human build")
        self.assertTrue((archive / "unknown-note.txt").is_file())
        self.assertFalse((self.root / "builds" / ".promotion.lock").exists())

    def test_rename_failure_rolls_back_previous_latest_and_checkpoint(self):
        checkpoint = self.root / "builds" / "checkpoints" / "002C.5"
        checkpoint.mkdir(parents=True)
        (checkpoint / pipeline.EXE).write_bytes(b"known-good checkpoint")
        original = Path.rename

        def fail_latest(source, target):
            if source.name.startswith(".promotion-") and Path(target) == self.latest:
                raise OSError("fixture rename failure")
            return original(source, target)

        with patch.object(Path, "rename", fail_latest), self.assertRaises(OSError):
            pipeline.promote_candidate(self.candidate, self.root, self.qa, "002C.5")
        self.assert_latest_preserved()
        self.assertEqual((checkpoint / pipeline.EXE).read_bytes(), b"known-good checkpoint")
        self.assertFalse((self.root / "builds" / ".promotion.lock").exists())


class PackagedSmokeEnvironmentGuards(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.base = Path(self.temporary.name)
        self.qa = self.base / "configured-qa"

    def tearDown(self):
        self.temporary.cleanup()

    def smoke(self):
        return pipeline.run_packaged_smoke(self.base / pipeline.EXE, self.base / "engine.log",
            self.base / "images", self.qa / "003A/temp/isolated.json", self.base / "smoke.log", self.qa, "003A")

    def test_actual_child_receives_task_and_configured_root_then_prior_environment_returns(self):
        def child(command, log, timeout):
            self.assertIn("--qa-task=003A", command)
            self.assertIn("--collection-path=" + str(self.qa / "003A/temp/isolated.json"), command)
            self.assertEqual(pipeline.os.environ["TOPGAME_QA_ROOT"], str(self.qa.resolve()))
            return {"command":command, "exit_code":0}
        with patch.dict(pipeline.os.environ, {"TOPGAME_QA_ROOT":"prior-external-qa"}), patch.object(pipeline, "run_logged", side_effect=child):
            result = self.smoke()
            self.assertEqual(pipeline.os.environ["TOPGAME_QA_ROOT"], "prior-external-qa")
        self.assertEqual(result["child_environment"], {"TOPGAME_QA_ROOT":str(self.qa.resolve())})
        self.assertEqual(result["qa_task"], "003A")

    def test_child_failure_restores_prior_environment(self):
        with patch.dict(pipeline.os.environ, {"TOPGAME_QA_ROOT":"prior-external-qa"}), patch.object(pipeline, "run_logged", side_effect=RuntimeError("fixture child failed")):
            with self.assertRaisesRegex(RuntimeError, "fixture child failed"):
                self.smoke()
            self.assertEqual(pipeline.os.environ["TOPGAME_QA_ROOT"], "prior-external-qa")

    def test_absent_qa_environment_remains_absent_after_child(self):
        with patch.dict(pipeline.os.environ, {}, clear=True), patch.object(pipeline, "run_logged", return_value={"exit_code":0}):
            self.smoke()
            self.assertNotIn("TOPGAME_QA_ROOT", pipeline.os.environ)


class ColdImportRetryGuards(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.logs = Path(self.temporary.name)
        self.command = ["fixture-engine", "--headless", "--editor", "--import"]

    def tearDown(self):
        self.temporary.cleanup()

    def record(self, name, exit_code, content):
        log = self.logs / name
        log.write_text(content)
        return {"command": self.command, "exit_code": exit_code, "log": str(log), "log_sha256": pipeline.sha256(log)}

    def test_observed_native_first_attempt_then_success_is_retained(self):
        first = self.record("import.log", 3221225477, "[ DONE ] reimport\n[ DONE ] loading_editor_layout\n")
        second = self.record("import-retry.log", 0, "import finished normally")
        with patch.object(pipeline, "run_logged", side_effect=[pipeline.ProcessValidationError(first), second]) as runner:
            result = pipeline.import_source(self.command, self.logs)
        self.assertEqual(runner.call_count, 2)
        self.assertEqual(result["attempts"], [first, second])
        self.assertEqual(result["exit_code"], 0)

    def test_regular_failure_is_not_retried(self):
        first = self.record("import.log", 1, "import failed")
        with patch.object(pipeline, "run_logged", side_effect=pipeline.ProcessValidationError(first)) as runner:
            with self.assertRaises(pipeline.ProcessValidationError):
                pipeline.import_source(self.command, self.logs)
        self.assertEqual(runner.call_count, 1)

    def test_script_error_with_native_exit_is_not_retried(self):
        first = self.record("import.log", 3221225477, "[ DONE ] reimport\nSCRIPT ERROR: fixture broken")
        with patch.object(pipeline, "run_logged", side_effect=pipeline.ProcessValidationError(first)) as runner:
            with self.assertRaises(pipeline.ProcessValidationError):
                pipeline.import_source(self.command, self.logs)
        self.assertEqual(runner.call_count, 1)

    def test_native_failure_before_completed_reimport_is_not_retried(self):
        first = self.record("import.log", 3221225477, "reimport still running")
        with patch.object(pipeline, "run_logged", side_effect=pipeline.ProcessValidationError(first)) as runner:
            with self.assertRaises(pipeline.ProcessValidationError):
                pipeline.import_source(self.command, self.logs)
        self.assertEqual(runner.call_count, 1)

    def test_repeated_native_failure_stops_after_two_attempts(self):
        first = self.record("import.log", -1073741819, "[ DONE ] reimport")
        second = self.record("import-retry.log", 3221225477, "[ DONE ] reimport")
        with patch.object(pipeline, "run_logged", side_effect=[pipeline.ProcessValidationError(first), pipeline.ProcessValidationError(second)]) as runner:
            with self.assertRaises(pipeline.ProcessValidationError) as caught:
                pipeline.import_source(self.command, self.logs)
        self.assertEqual(runner.call_count, 2)
        self.assertEqual(caught.exception.attempts, [first, second])

    def test_successful_first_attempt_is_not_retried(self):
        first = self.record("import.log", 0, "import finished normally")
        with patch.object(pipeline, "run_logged", return_value=first) as runner:
            result = pipeline.import_source(self.command, self.logs)
        self.assertEqual(runner.call_count, 1)
        self.assertEqual(result["attempts"], [first])

    def test_ansi_completed_native_import_is_recognised_without_changing_log(self):
        content = "[ DONE ]\x1b[39m \x1b[1mreimport\x1b[22m\n"
        first = self.record("import.log", 3221225477, content)
        self.assertTrue(pipeline.completed_native_import_crash(first))
        self.assertEqual(Path(first["log"]).read_text(), content)
        self.assertEqual(pipeline.sha256(Path(first["log"])), first["log_sha256"])

    def test_ansi_inside_script_error_prevents_retry(self):
        content = "[ DONE ]\x1b[39m \x1b[1mreimport\x1b[22m\nSCR\x1b[31mIPT ER\x1b[39mROR: fixture broken"
        first = self.record("import.log", 3221225477, content)
        with patch.object(pipeline, "run_logged", side_effect=pipeline.ProcessValidationError(first)) as runner:
            with self.assertRaises(pipeline.ProcessValidationError):
                pipeline.import_source(self.command, self.logs)
        self.assertEqual(runner.call_count, 1)

    def test_ansi_partial_import_is_not_retried(self):
        content = "[  67% ]\x1b[39m \x1b[1mreimport\x1b[22m | still importing\n"
        first = self.record("import.log", 3221225477, content)
        with patch.object(pipeline, "run_logged", side_effect=pipeline.ProcessValidationError(first)) as runner:
            with self.assertRaises(pipeline.ProcessValidationError):
                pipeline.import_source(self.command, self.logs)
        self.assertEqual(runner.call_count, 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
