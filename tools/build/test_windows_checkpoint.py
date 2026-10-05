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


if __name__ == "__main__":
    unittest.main(verbosity=2)
