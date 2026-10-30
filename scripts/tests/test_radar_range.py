"""Exercise the production signal/range model against independent RF scenarios."""

from pathlib import Path
import subprocess
import tempfile
import unittest
from scripts.tests.test_storage_upgrade import build

ROOT = Path(__file__).resolve().parents[2]


class RadarRangeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temp = tempfile.TemporaryDirectory(prefix="radar-range-")
        cls.addClassCleanup(temp.cleanup)
        core = ROOT / "applications/main/nearby_radar"
        cls.executable = build(
            Path(temp.name),
            [
                core / "radar_range.c",
                core / "radar_core.c",
                Path(__file__).parent / "fixtures/radar_range.c",
            ],
            "radar_range",
            ["-I" + str(core), "-Wall", "-Wextra", "-Werror"],
        )

    def scenario(self, name):
        result = subprocess.run(
            [str(self.executable), name],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Range scenario passed", result.stdout)

    def test_unknown_reference_never_invents_meters(self):
        self.scenario("unknown")

    def test_calibrated_range_has_broad_bounds_and_monotonic_distance(self):
        self.scenario("distance")

    def test_bursts_and_single_outliers_cannot_create_confident_range(self):
        self.scenario("outliers")

    def test_old_and_paused_observations_hide_numeric_and_movement_guidance(self):
        self.scenario("freshness")

    def test_manual_calibration_collects_new_spaced_samples_and_wins_over_beacon(self):
        self.scenario("calibration")

    def test_failed_and_cancelled_calibration_preserve_previous_reference(self):
        self.scenario("calibration-failure")

    def test_proximity_hysteresis_and_trend_ignore_jitter(self):
        self.scenario("guidance")

    def test_core_reference_is_target_scoped_and_does_not_survive_eviction(self):
        self.scenario("identity")

    def test_sparse_packets_cannot_reuse_old_samples_for_current_meters(self):
        self.scenario("sparse")

    def test_changed_advertised_reference_reacquires_before_showing_meters(self):
        self.scenario("reference-change")

    def test_healthy_one_hertz_target_can_finish_six_second_calibration(self):
        self.scenario("one-hertz-calibration")

    def test_calibrated_proximity_is_independent_of_transmitter_power(self):
        self.scenario("relative-proximity")

    def test_one_hertz_single_outlier_does_not_invent_retreat_guidance(self):
        self.scenario("one-hertz-outlier")

    def test_two_missed_packets_can_calibrate_with_a_wider_model_interval(self):
        self.scenario("two-missed-packets")

    def test_opposite_outliers_cannot_masquerade_as_a_stable_low_sample_window(self):
        self.scenario("opposite-outliers")

    def test_queued_observation_before_confirmation_does_not_end_or_seed_calibration(
        self,
    ):
        self.scenario("queued-calibration")

    def test_queued_calibration_timestamp_order_survives_clock_wrap(self):
        self.scenario("queued-calibration-wrap")


if __name__ == "__main__":
    unittest.main()
