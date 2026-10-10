"""Presentation batch guards with disposable paths and mocked engine/profile IO."""
from contextlib import ExitStack, redirect_stdout
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import verify_foundation as verifier


class FoundationGuards(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.base = Path(self.temporary.name)
        self.qa = self.base / "external-qa"
        self.task = self.qa / "002C.6"
        self.profile = {"available": True, "directory": str(self.base / "mock-userdata"),
                        "files": {"collection.json": "unchanged fixture hash"}}
        self.source = {"sha256": "source fixture", "files": {}}
        self.assets = {"sha256": "asset fixture", "files": {}}
        self.children = []
        self.stack = ExitStack()
        self.stack.enter_context(patch.dict(os.environ, {"TOPGAME_QA_ROOT": "previous-fixture-root"}))
        self.stack.enter_context(patch.object(verifier.pipeline, "production_profile", return_value=self.profile))
        self.stack.enter_context(patch.object(verifier.pipeline, "git", return_value="mock-branch-or-head"))
        self.stack.enter_context(patch.object(verifier, "source_fingerprint", return_value=self.source))
        self.stack.enter_context(patch.object(verifier, "asset_fingerprint", return_value=self.assets))
        self.stack.enter_context(patch.object(verifier.workspace, "find_tool", return_value="MOCK-NO-ENGINE"))
        self.runner = self.stack.enter_context(patch.object(verifier, "run_suite", side_effect=self.fake_child))

    def tearDown(self):
        self.stack.close()
        self.temporary.cleanup()

    def fake_child(self, command, log, suite, timeout):
        self.children.append({"command": command, "qa_root": os.environ.get("TOPGAME_QA_ROOT")})
        # Explicitly synthetic guard evidence, never a gameplay/engine result.
        log.write_text("MOCK only: no engine launched\n", encoding="utf-8")
        return {"suite": suite, "status": "passed", "seconds": 0, "checks": 1, "passed": True}

    def invoke(self, suites="music", qa=None, extra=None):
        args = ["guard-fixture", "--qa-root", str(qa or self.qa), "--stem", "guard", "--suites", suites]
        with patch.object(sys, "argv", args + (extra or [])), redirect_stdout(io.StringIO()):
            return verifier.main()

    def preserved(self, relative):
        path = self.task / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("preserve earlier evidence", encoding="utf-8")
        return path

    def report(self):
        return json.loads((self.task / "manifests/guard.json").read_text(encoding="utf-8"))

    def test_existing_aggregate_is_preserved_before_child(self):
        path = self.preserved("manifests/guard.json")
        with self.assertRaisesRegex(RuntimeError, "Preserved report"):
            self.invoke()
        self.assertEqual(path.read_text(), "preserve earlier evidence")
        self.runner.assert_not_called()

    def test_existing_child_report_is_preserved_before_child(self):
        path = self.preserved("manifests/guard_music.json")
        with self.assertRaisesRegex(RuntimeError, "Preserved suite report"):
            self.invoke()
        self.assertEqual(path.read_text(), "preserve earlier evidence")
        self.runner.assert_not_called()

    def test_existing_log_is_preserved_before_child(self):
        path = self.preserved("logs/guard_music.log")
        with self.assertRaisesRegex(RuntimeError, "Preserved log"):
            self.invoke()
        self.assertEqual(path.read_text(), "preserve earlier evidence")
        self.runner.assert_not_called()

    def test_existing_parts_benchmark_is_preserved(self):
        path = self.preserved("benchmarks/guard_parts.json")
        with self.assertRaisesRegex(RuntimeError, "Preserved benchmark"):
            self.invoke("parts_catalogue")
        self.assertEqual(path.read_text(), "preserve earlier evidence")
        self.runner.assert_not_called()

    def test_userdata_root_and_descendant_rejected_before_creation(self):
        for root in [Path(self.profile["directory"]), Path(self.profile["directory"]) / "qa"]:
            with self.subTest(root=root), patch.object(verifier.workspace, "create_task_workspace") as create:
                with self.assertRaisesRegex(ValueError, "player profile"):
                    self.invoke(qa=root)
                create.assert_not_called()
        self.runner.assert_not_called()

    def test_external_root_reaches_child_and_previous_environment_restored(self):
        self.assertEqual(self.invoke("music,presentation_retention,mobile_combat_input"), 0)
        self.assertTrue(all(child["qa_root"] == str(self.qa.resolve()) for child in self.children))
        self.assertEqual(os.environ["TOPGAME_QA_ROOT"], "previous-fixture-root")
        self.assertIn("--report=" + str(self.task / "manifests/guard_music.json"), self.children[0]["command"])
        for child in self.children[1:]:
            self.assertIn("--qa-task=002C.6", child["command"])

    def test_initially_absent_environment_remains_absent(self):
        os.environ.pop("TOPGAME_QA_ROOT", None)
        self.assertEqual(self.invoke(), 0)
        self.assertNotIn("TOPGAME_QA_ROOT", os.environ)

    def test_input_and_overdrive_receive_fixed_fps_and_separate_fresh_profiles(self):
        self.assertEqual(self.invoke("input_acceptance_003a1,overdrive_lifecycle_003a1"), 0)
        self.assertEqual(len(self.children), 2)
        profiles = []
        for suite, child in zip(["input_acceptance_003a1", "overdrive_lifecycle_003a1"], self.children):
            command = child["command"]
            self.assertLess(command.index("--fixed-fps"), command.index("--"))
            self.assertEqual(command[command.index("--fixed-fps") + 1], "60")
            expected = self.task / "temp" / ("guard_" + suite + "_profiles")
            self.assertIn("--profiles=" + str(expected), command)
            self.assertIn("--report=" + str(self.task / "manifests" / ("guard_" + suite + ".json")), command)
            self.assertFalse(expected.exists(), "Only the engine driver creates its fresh profile directory")
            profiles.append(expected)
        self.assertNotEqual(*profiles)
        self.assertIn("--kind=all", self.children[0]["command"])
        self.assertNotIn("--kind=all", self.children[1]["command"])
        self.assertTrue(self.report()["profile_unchanged"])

    def test_existing_driver_and_derived_profiles_are_preserved_before_any_child(self):
        for suite, suffix in [("input_acceptance_003a1", ""), ("input_acceptance_003a1", "_mapping"),
                              ("input_acceptance_003a1", "_mapping_lifecycle"), ("overdrive_lifecycle_003a1", "")]:
            with self.subTest(suite=suite, suffix=suffix):
                relative = "temp/guard_" + suite + "_profiles" + suffix + "/preserved.json"
                sentinel = self.preserved(relative)
                with self.assertRaisesRegex(RuntimeError, "Preserved driver profile"):
                    self.invoke(suite)
                self.assertEqual(sentinel.read_text(), "preserve earlier evidence")
                sentinel.unlink()
                sentinel.parent.rmdir()
        self.runner.assert_not_called()

    def test_fresh_fixture_root_routes_historical_children_inside_current_task(self):
        fixture = self.task / "temp" / "isolated-fixtures"
        self.assertEqual(self.invoke("music_escalation,presentation_retention,roster_draft", extra=["--fixture-qa-root", str(fixture)]), 0)
        self.assertTrue(fixture.is_dir())
        self.assertEqual(self.children[0]["qa_root"], str(self.qa.resolve()))
        self.assertIn("--qa-task=002C.6", self.children[0]["command"])
        self.assertTrue(all(child["qa_root"] == str(fixture.resolve()) for child in self.children[1:]))
        self.assertIn("--report=" + str(self.task / "manifests/guard_roster_draft.json"), self.children[2]["command"])
        self.assertEqual(os.environ["TOPGAME_QA_ROOT"], "previous-fixture-root")

    def test_fixture_root_outside_task_temp_or_existing_is_preserved(self):
        existing = self.task / "temp" / "old-fixtures"
        existing.mkdir(parents=True)
        sentinel = existing / "preserved.json"
        sentinel.write_text("prior evidence")
        for fixture in [self.qa / "003A", self.task / "temp", existing]:
            with self.subTest(fixture=fixture), self.assertRaises((ValueError, RuntimeError)):
                self.invoke(extra=["--fixture-qa-root", str(fixture)])
        self.assertEqual(sentinel.read_text(), "prior evidence")
        self.runner.assert_not_called()

    def test_child_failure_restores_environment_and_retains_failed_manifest(self):
        self.runner.side_effect = RuntimeError("MOCK child failure, no engine launched")
        with self.assertRaisesRegex(RuntimeError, "MOCK child failure"):
            self.invoke()
        self.assertEqual(os.environ["TOPGAME_QA_ROOT"], "previous-fixture-root")
        self.assertEqual(self.report()["status"], "failed")
        self.assertIn("MOCK child failure", self.report()["error"])

    def test_finalization_failure_still_restores_environment(self):
        with patch.object(verifier, "asset_fingerprint", side_effect=[self.assets, OSError("MOCK final fingerprint IO failure")]):
            with self.assertRaisesRegex(OSError, "final fingerprint"):
                self.invoke()
        self.assertEqual(os.environ["TOPGAME_QA_ROOT"], "previous-fixture-root")

    def test_changed_profile_stops_before_second_child(self):
        changed = {**self.profile, "files": {"collection.json": "different fixture hash"}}
        with patch.object(verifier.pipeline, "production_profile", side_effect=[self.profile, self.profile, changed, changed]):
            with self.assertRaisesRegex(RuntimeError, "profile changed"):
                self.invoke("music,frontend")
        self.assertEqual(len(self.children), 1)
        self.assertFalse(self.report()["profile_unchanged"])
        self.assertEqual(os.environ["TOPGAME_QA_ROOT"], "previous-fixture-root")

    def test_source_change_invalidates_successful_child_results(self):
        with patch.object(verifier, "source_fingerprint", side_effect=[self.source, {"sha256": "changed", "files": {}}]):
            self.assertEqual(self.invoke(), 1)
        self.assertEqual(self.report()["status"], "failed")
        self.assertFalse(self.report()["source_unchanged"])

    def test_asset_change_invalidates_successful_child_results(self):
        with patch.object(verifier, "asset_fingerprint", side_effect=[self.assets, {"sha256": "changed", "files": {}}]):
            self.assertEqual(self.invoke(), 1)
        self.assertFalse(self.report()["assets_unchanged"])

    def test_failed_suite_does_not_become_accepted(self):
        self.runner.side_effect = lambda *_args: {"suite": "music", "status": "failed", "seconds": 0, "checks": 10, "passed": False}
        self.assertEqual(self.invoke(), 1)
        self.assertEqual(self.report()["failed_suites"], ["music"])
        self.assertEqual(self.report()["checks"], 0)

    def test_historical_contracts_and_unknown_suites_are_rejected(self):
        for name in ["baseline_physics", "parts_legacy", "catalogue_legacy_run", "../../outside", "unrecognised_fixture"]:
            with self.subTest(suite=name), self.assertRaises(ValueError):
                self.invoke(name)
        self.runner.assert_not_called()


if __name__ == "__main__":
    unittest.main(verbosity=2)
