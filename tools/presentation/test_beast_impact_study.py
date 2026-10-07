"""Offline analysis must retain raw contacts and distinguish force from motion."""
import unittest

from beast_impact_study import quantiles, summarize


class ImpactAnalysisTests(unittest.TestCase):
    def fixture(self):
        def event(identity,impulse,closing,severity):
            return {"collision_id":identity,"impulse":impulse,"closing":closing,"severity":severity,"player_involved":True}
        return {"scope":"Test telemetry", "runs":[{"context":{"id":"defensive"},"seed":421,"starting_stats":{},"elapsed":60,"simulation_ticks":3600,"ended_naturally":False,"reason":"observation_horizon","level":1,"powers":[],"ranks":{},"mutations":{},"events":[event(1,20000,.1,.08),event(2,2000,100,.45),event(3,5000,250,1.13)],"presentation":{"spawned":1,"suppressed":0,"peak_live":1}}]}

    def test_linear_quantiles_and_endpoint_preservation(self):
        q=quantiles([30,0,10,20])
        self.assertEqual(q["0"],0)
        self.assertEqual(q["0.5"],15)
        self.assertEqual(q["1"],30)
        self.assertEqual(quantiles([]),{})

    def test_work_rejects_high_force_stationary_contact(self):
        data=self.fixture()
        work=summarize(data,1_000_000)
        force=summarize(data,10_000,"impulse")
        self.assertEqual(work["number_qualifying"],1)
        self.assertEqual(work["runs"][0]["qualifying_examples"][0]["collision_id"],3)
        self.assertEqual(force["runs"][0]["qualifying_examples"][0]["collision_id"],1)

    def test_raw_and_meaningful_contacts_report_separately(self):
        result=summarize(self.fixture(),1_000_000)
        self.assertEqual(result["total_raw_full_top_collision_events"],3)
        self.assertEqual(result["total_meaningful_full_top_collision_events"],2)
        self.assertEqual(sum(row["count"] for row in result["collision_work_histogram"]),3)
        self.assertEqual(result["number_actually_shown_after_cooldown_and_deduplication"],1)

    def test_duplicate_collision_identity_is_invalid_evidence(self):
        data=self.fixture()
        data["runs"][0]["events"].append(data["runs"][0]["events"][0].copy())
        with self.assertRaises(AssertionError): summarize(data,1_000_000)


if __name__=="__main__": unittest.main()
