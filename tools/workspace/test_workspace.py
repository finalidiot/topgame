"""Safety checks for path validation and the deliberately narrow cleaner."""
import tempfile
from pathlib import Path
import unittest

from workspace import CATEGORIES, clean_temp, create_task_workspace, valid_task


class WorkspaceSafety(unittest.TestCase):
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
