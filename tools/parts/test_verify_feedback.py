"""Historical differences cannot hide current failures or script/import errors."""
import unittest
from verify_feedback import historical_failure, parse_checks


class FeedbackEvidenceGuards(unittest.TestCase):
    def test_observed_drift_comparison_is_explicitly_superseded(self):
        log = "FAIL assembly movement tick 0 pos old / new\nBaseline differential: 127776 field comparisons across48 assemblies, 23040 failures"
        self.assertTrue(historical_failure("baseline_physics", 1, log))
        self.assertEqual(parse_checks("baseline_physics", log), 127776)

    def test_runtime_errors_are_never_superseded(self):
        log = "FAIL assembly movement tick 0 pos old / new\nBaseline differential: 127776 field comparisons across48 assemblies, 23040 failures"
        for error in ["SCRIPT ERROR: Missing method", "ERROR: Broken resource"]:
            with self.subTest(error=error): self.assertFalse(historical_failure("baseline_physics", 1, log+"\n"+error))

    def test_wrong_exit_or_current_suite_is_never_superseded(self):
        log = 'Legacy physical parity: 0 / 48 exact; failures ["BALANCE"]'
        self.assertTrue(historical_failure("parts_legacy", 1, log))
        for code in [0, 2, 3221225477]: self.assertFalse(historical_failure("parts_legacy", code, log))
        self.assertFalse(historical_failure("parts_catalogue", 1, log))

    def test_python_and_engine_counters_do_not_count_zero_failures(self):
        for content,count in [("Ran21 tests",0),("Ran 21 tests\nOK",21),("POWER_FEEDBACK_PASS checks=2463 failures=0",2463),("148 checks, 0 failures",148)]:
            with self.subTest(content=content): self.assertEqual(parse_checks("guard",content),count)


if __name__ == "__main__": unittest.main(verbosity=2)
