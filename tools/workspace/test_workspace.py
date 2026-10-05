"""Safety checks for path validation and the deliberately narrow cleaner."""
import tempfile
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

import workspace
from workspace import CATEGORIES, clean_temp, create_task_workspace, valid_task


class WorkspaceSafety(unittest.TestCase):
    def test_self_contained_git_storage_is_expected_and_not_scanned(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "repo"
            (root / ".git" / "objects").mkdir(parents=True)
            (root / ".git" / "objects" / "metadata.bin").write_bytes(b"historical object")
            (root / "assets").mkdir()
            with patch.object(workspace, "repo_root", return_value=root), patch.object(workspace, "git_paths", return_value=set()):
                report = workspace.audit()
            self.assertEqual(report["unexpected_root_folders"], [])
            self.assertEqual(report["largest_files"], [])

    def test_explicit_dry_run_and_conflicting_cleanup_flags(self):
        with tempfile.TemporaryDirectory() as directory:
            task = create_task_workspace("002C.5.1", directory)
            disposable = task / "temp" / "encoding.part"
            disposable.write_text("generated")
            command = [sys.executable, str(Path(workspace.__file__).resolve()), "--qa-root", directory,
                       "clean-temp", "--task", "002C.5.1", "--dry-run"]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("DRY-RUN " + str(disposable), result.stdout)
            self.assertTrue(disposable.exists())
            conflict = subprocess.run(command + ["--apply"], capture_output=True, text=True)
            self.assertEqual(conflict.returncode, 2)
            self.assertIn("not allowed with argument --dry-run", conflict.stderr)
            self.assertTrue(disposable.exists())

    def test_task_ids_cannot_escape_root(self):
        for value in ("../002C.5", "002C.5/elsewhere", "archive", "002c5", "C:/"):
            with self.assertRaises(ValueError):
                valid_task(value)
        self.assertEqual(valid_task("002C.5.1"), "002C.5.1")

    def test_cleaner_dry_run_and_preservation(self):
        with tempfile.TemporaryDirectory() as directory:
            task = create_task_workspace("002C.5.1", directory)
            self.assertEqual({p.name for p in task.iterdir()}, set(CATEGORIES))
            disposable = task / "temp/encoding.part"
            disposable.write_text("generated")
            protected = []
            for name in ("review.mp4", "matrix.png", "manifest.json", "unknown.bin", "master.aseprite"):
                path = task / "temp" / name
                path.write_text("preserve")
                protected.append(path)
            self.assertEqual(clean_temp("002C.5.1", directory), [str(disposable)])
            self.assertTrue(disposable.exists())
            clean_temp("002C.5.1", directory, apply=True)
            self.assertFalse(disposable.exists())
            self.assertTrue(all(path.exists() for path in protected))


if __name__ == "__main__":
    unittest.main()
