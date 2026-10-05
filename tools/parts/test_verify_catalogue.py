"""Regression acceptance must distinguish counters from actual failures."""
import unittest
from verify_catalogue import has_failures


class SummaryGuards(unittest.TestCase):
    def test_passing_summaries_are_accepted(self):
        for text in ("COLLECTION_SAVE_PASS checks=371 failures=0",
                     "127776 field comparisons, 0 failures",
                     "checks: 8945, failures: 0", "371 checks / 0 failures"):
            with self.subTest(text=text):
                self.assertFalse(has_failures(text))

    def test_nonzero_failures_are_rejected(self):
        for text in ("checks=371 failures=1", "checks: 100, failures: 12",
                     "2 failures", "failed=1", "FAIL: ownership mismatch"):
            with self.subTest(text=text):
                self.assertTrue(has_failures(text))


if __name__ == "__main__":
    unittest.main(verbosity=2)
