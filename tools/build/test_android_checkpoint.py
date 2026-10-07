"""Synthetic promotion guards, never Android gameplay/installation acceptance."""
from pathlib import Path
import json
import struct
import tempfile
import unittest
from unittest.mock import patch

import android_checkpoint as android
import windows_checkpoint as windows


class AndroidPromotionGuards(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.base = Path(self.temporary.name).resolve()
        self.root = self.base / "repo"
        self.qa = self.base / "qa"
        self.task = self.qa / "003A"
        self.candidate = self.base / "candidate"
        self.candidate.mkdir()
        self.latest = self.root / "builds/latest"
        self.checkpoint = self.root / "builds/checkpoints/003A"
        for directory in (self.latest, self.checkpoint):
            directory.mkdir(parents=True)
            (directory / windows.EXE).write_bytes(b"preserved Windows fixture")
            (directory / "unknown-note.txt").write_text("preserve this unrelated local note")
            windows.write_json(directory / "build-manifest.json", {"source": {"git_sha": "a" * 40}})
            for name in android.DELIVERY_FILES:
                (directory / name).write_bytes(("old Android fixture " + name).encode())
        (self.candidate / android.APK).write_bytes(b"explicit synthetic APK guard fixture, not a real Android package")
        self.logs = self.task / "logs"
        self.logs.mkdir(parents=True)
        process = {}
        for name in ("import", "export", "signature", "badging", "manifest"):
            log = self.logs / (name + ".log")
            log.write_text("synthetic successful process evidence")
            process[name] = {"log": str(log), "log_sha256": windows.sha256(log), "exit_code": 0}
        request_id = "b" * 32
        isolated = "user://test_collection/android_003a_" + request_id + ".json"
        installed = self.task / "temp/installed.apk"
        installed.parent.mkdir()
        installed.write_bytes((self.candidate / android.APK).read_bytes())
        image = self.task / "images/capture.png"
        image.parent.mkdir()
        image.write_bytes(b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", 640, 360) + b"x" * 1200)
        state = self.task / "manifests/state.json"
        state.parent.mkdir()
        windows.write_json(state, {"platform": "Android", "debug": True, "isolated_collection": isolated, "run_id": request_id})
        adb = self.logs / "adb.log"
        adb.write_text("synthetic adb evidence; not an installation claim")
        self.smoke = {"platform": "Android", "package": android.PACKAGE, "apk_sha256": windows.sha256(self.candidate / android.APK), "checks_passed": 117, "failures": [], "profile_before": {}, "profile_after": {}, "profile_unchanged": True, "isolated_collection": isolated, "device": {"serial": "synthetic-only", "physical": False}, "coverage": {name: True for name in android.COVERAGE}, "installed_apk": android.record(installed), "captures": [android.record(image)], "state_reports": [android.record(state)], "adb_log": android.record(adb)}
        self.smoke_path = self.task / "manifests/smoke.json"
        self.save_smoke()
        self.manifest = {"schema": 1, "platform": "Android", "checkpoint": "003A", "qa_task": "003A", "qa_root": str(self.qa), "evidence": str(self.task / "manifests/build.json"), "build_date_utc": "synthetic fixture", "human_acceptance": android.HUMAN_REVIEW, "validation": "passed", "source": {"git_sha": "a" * 40, "branch": "test fixture", "tracked_clean": True}, "import": process["import"], "export": process["export"], "package_inspection": {"apk": android.record(self.candidate / android.APK), "debug_signed": True, "signature": process["signature"], "badging": process["badging"], "manifest": process["manifest"]}}
        self.save_manifest()

    def tearDown(self):
        self.temporary.cleanup()

    def save_smoke(self):
        windows.write_json(self.smoke_path, self.smoke)

    def save_manifest(self):
        self.manifest["android_smoke"] = android.verify_smoke(self.smoke_path, self.candidate / android.APK, self.qa, "003A")
        android.write_delivery(self.candidate, self.manifest)

    def reject_smoke(self):
        self.save_smoke()
        with self.assertRaises(ValueError):
            android.verify_smoke(self.smoke_path, self.candidate / android.APK, self.qa, "003A")

    def assert_previous(self):
        for directory in (self.latest, self.checkpoint):
            self.assertEqual((directory / windows.EXE).read_bytes(), b"preserved Windows fixture")
            self.assertTrue((directory / "unknown-note.txt").is_file())
            for name in android.DELIVERY_FILES:
                self.assertEqual((directory / name).read_bytes(), ("old Android fixture " + name).encode())

    def test_valid_hash_linked_fixture(self):
        self.assertEqual(android.verify_candidate(self.candidate)["android_smoke"]["checks_passed"], 117)

    def test_any_missing_native_coverage_rejected(self):
        for key in android.COVERAGE:
            with self.subTest(key=key):
                self.smoke["coverage"][key] = False
                self.reject_smoke()
                self.smoke["coverage"][key] = True

    def test_failed_native_check_rejected(self):
        self.smoke["failures"] = ["touch ownership"]
        self.reject_smoke()

    def test_zero_native_check_count_rejected(self):
        self.smoke["checks_passed"] = 0
        self.reject_smoke()

    def test_boolean_check_count_rejected(self):
        self.smoke["checks_passed"] = True
        self.reject_smoke()

    def test_profile_changed_rejected(self):
        self.smoke["profile_after"] = {"collection": "different hash"}
        self.reject_smoke()

    def test_default_profile_path_rejected(self):
        self.smoke["isolated_collection"] = "user://collection.json"
        self.reject_smoke()

    def test_wrong_apk_rejected(self):
        self.smoke["apk_sha256"] = "0" * 64
        self.reject_smoke()

    def test_wrong_package_rejected(self):
        self.smoke["package"] = "unrelated.app"
        self.reject_smoke()

    def test_absent_native_device_rejected(self):
        self.smoke["device"] = {}
        self.reject_smoke()

    def test_tampered_installed_apk_rejected(self):
        Path(self.smoke["installed_apk"]["path"]).write_bytes(b"changed installed package")
        self.reject_smoke()

    def test_tampered_capture_rejected(self):
        Path(self.smoke["captures"][0]["path"]).write_bytes(b"changed screenshot")
        self.reject_smoke()

    def test_wrong_native_state_rejected(self):
        path = Path(self.smoke["state_reports"][0]["path"])
        windows.write_json(path, {"platform": "Windows", "debug": True, "isolated_collection": self.smoke["isolated_collection"], "run_id": "b" * 32})
        self.smoke["state_reports"] = [android.record(path)]
        self.reject_smoke()

    def test_portrait_capture_rejected(self):
        path = Path(self.smoke["captures"][0]["path"])
        path.write_bytes(b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", 360, 640) + b"x" * 1200)
        self.smoke["captures"] = [android.record(path)]
        self.reject_smoke()

    def test_candidate_apk_change_rejected(self):
        (self.candidate / android.APK).write_bytes(b"modified candidate")
        with self.assertRaises(ValueError): android.verify_candidate(self.candidate)
        self.assert_previous()

    def test_process_log_change_rejected(self):
        Path(self.manifest["export"]["log"]).write_text("modified export log")
        with self.assertRaises(ValueError): android.verify_candidate(self.candidate)
        self.assert_previous()

    def test_no_human_acceptance_claim(self):
        self.manifest["human_acceptance"] = "accepted automatically"
        windows.write_json(self.candidate / android.MANIFEST, self.manifest)
        with self.assertRaises(ValueError): android.verify_candidate(self.candidate)

    def test_awaiting_smoke_not_promotable(self):
        self.manifest["validation"] = "awaiting_android_smoke"
        android.write_delivery(self.candidate, self.manifest)
        with self.assertRaises(ValueError): android.verify_candidate(self.candidate)
        self.assert_previous()

    def test_preserve_windows_unknown_and_old_apk(self):
        with patch.object(android, "current_source"):
            result = android.promote(self.candidate, self.root, self.qa, "003A")
        archive = Path(result["preserved_previous"])
        for directory in (self.latest, self.checkpoint):
            self.assertEqual((directory / windows.EXE).read_bytes(), b"preserved Windows fixture")
            self.assertTrue((directory / "unknown-note.txt").is_file())
            self.assertEqual((directory / android.APK).read_bytes(), (self.candidate / android.APK).read_bytes())
            for name in android.DELIVERY_FILES:
                self.assertEqual((archive / directory.name / name).read_bytes(), ("old Android fixture " + name).encode())

    def test_matching_windows_sha_required(self):
        windows.write_json(self.latest / "build-manifest.json", {"source": {"git_sha": "c" * 40}})
        with patch.object(android, "current_source"):
            with self.assertRaises(ValueError): android.promote(self.candidate, self.root, self.qa, "003A")
        self.assert_previous()

    def test_shared_promotion_lock_preserved(self):
        lock = self.root / "builds/.promotion.lock"
        lock.write_text("another platform is promoting")
        with patch.object(android, "current_source"):
            with self.assertRaises(FileExistsError): android.promote(self.candidate, self.root, self.qa, "003A")
        self.assertEqual(lock.read_text(), "another platform is promoting")
        self.assert_previous()

    def test_mid_promotion_rolls_back_both_platforms(self):
        original = Path.rename
        injected = False

        def fail_once(path, target):
            nonlocal injected
            if not injected and path.name == android.README and path.parent.name.startswith(".android-promotion"):
                injected = True
                raise OSError("synthetic transfer failure")
            return original(path, target)

        with patch.object(android, "current_source"), patch.object(Path, "rename", fail_once):
            with self.assertRaises(OSError): android.promote(self.candidate, self.root, self.qa, "003A")
        self.assert_previous()
        self.assertFalse((self.root / "builds/.promotion.lock").exists())


if __name__ == "__main__":
    unittest.main()
