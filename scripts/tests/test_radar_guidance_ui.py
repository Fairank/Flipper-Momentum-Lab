"""Run the real radar draw/input paths with recording device boundaries.

The canvas captures the text a user receives, rather than inspecting source
wording. Real range/core code is linked; only the hardware and GUI boundary is
replaced. Device screenshots still own visual acceptance.
"""

from pathlib import Path
import subprocess
import tempfile
import unittest

from scripts.tests.test_storage_upgrade import build

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).parent / "fixtures"


class RadarGuidanceUiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temporary = tempfile.TemporaryDirectory(prefix="radar-guidance-ui-")
        cls.addClassCleanup(temporary.cleanup)
        folder = Path(temporary.name)
        core = ROOT / "applications/main/nearby_radar"
        # Snapshot both translation units and headers before invoking a slow
        # compiler. A live editor must not create mixed-layout object files.
        names = ["nearby_radar.c", "radar_core.c", "radar_core.h"]
        names += [
            name
            for name in ("radar_range.c", "radar_range.h")
            if (core / name).is_file()
        ]
        snapshot = {name: (core / name).read_text(encoding="utf-8") for name in names}
        for name, content in snapshot.items():
            (folder / name).write_text(content, encoding="utf-8")
        production = snapshot["nearby_radar.c"]
        # Compile whole production sections, including their static helpers.
        # Extraction is only a build seam, never an assertion on source text.
        types = production[
            production.index("typedef struct {") : production.index(
                "typedef struct {\n    GapScanReport"
            )
        ]
        screen_and_input = production[
            production.index("static void label(") : production.index(
                "static void tick("
            )
        ]
        harness = (FIXTURES / "radar_guidance_ui.c").read_text(encoding="utf-8")
        source = folder / "radar_guidance_ui.c"
        source.write_text(
            harness.replace("/* PRODUCTION_TYPES */", types).replace(
                "/* PRODUCTION_SCREEN_INPUT */", screen_and_input
            ),
            encoding="utf-8",
        )
        sources = [folder / "radar_core.c", source]
        if "radar_range.c" in snapshot:
            sources.append(folder / "radar_range.c")
        cls.executable = build(
            folder,
            sources,
            "radar_guidance_ui",
            ["-I" + str(folder), "-Wall", "-Wextra", "-Werror", "-lm"],
        )

    def scenario(self, name):
        result = subprocess.run(
            [str(self.executable), name], capture_output=True, text=True, timeout=30
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def test_hold_target_opens_one_meter_setup_before_sampling(self):
        # Ignoring long-OK or immediately reusing old samples must fail this.
        output = self.scenario("setup")
        text = "".join(output.lower().split())
        self.assertIn("1m", text, output)
        self.assertRegex(text, r"place|away|still", output)
        self.assertIn("quit=0", output)

    def test_back_from_setup_keeps_target_and_second_back_returns_to_list(self):
        # Back must cancel calibration, rather than silently exit target view.
        output = self.scenario("cancel")
        self.assertIn("after_cancel_detail=1", output)
        self.assertIn("after_cancel_pinned=0", output)
        self.assertIn("after_second_back_detail=0", output)
        self.assertIn("quit=0", output)

    def test_list_hold_still_opens_filter_and_saves_without_target_leak(self):
        output = self.scenario("filter")
        self.assertIn("input_view=1", output)
        self.assertIn("minimum_length=0", output)
        self.assertIn("saved_filter=nomatch", output)
        self.assertIn("remaining_targets=0", output)
        self.assertIn("quit=0", output)

    def test_info_back_returns_to_selected_target_without_exit(self):
        output = self.scenario("info")
        self.assertIn("Bluetooth LE", output)
        self.assertIn("AABBCCDDEEFF", output)
        self.assertIn("after_back_detail=1", output)
        self.assertIn("after_back_info=0", output)
        self.assertIn("quit=0", output)

    def test_calibrated_stable_target_has_large_estimate_and_estimated_range(self):
        # Omitting the primary distance or its uncertainty band is a UI bug.
        output = self.scenario("range-ready")
        self.assertIn("reference_accepted=1", output)
        self.assertRegex(output, r"large_numeric_readings=[1-9]", output)
        self.assertIn("est.", output.lower())

    def test_uncalibrated_target_offers_setup_without_inventing_meters(self):
        output = self.scenario("range-uncalibrated")
        self.assertIn("large_numeric_readings=0", output)
        self.assertIn("1m", "".join(output.lower().split()))

    def test_held_estimates_disappear_when_paused_aging_lost_or_unstable(self):
        # A renderer that keeps old Ready numbers fails in every degraded state.
        for state in ("paused", "aging", "lost", "unstable"):
            with self.subTest(state=state):
                output = self.scenario("range-" + state)
                self.assertIn("reference_accepted=1", output)
                self.assertIn("large_numeric_readings=0", output)
                self.assertNotRegex(output, r"(?im)^(?:Est\.|Estimated)\s+[0-9]")
        self.assertIn("paused", self.scenario("range-paused").lower())
        self.assertIn("lost", self.scenario("range-lost").lower())

    def test_pausing_mid_calibration_cancels_collection_and_keeps_target(self):
        output = self.scenario("calibrate-pause")
        self.assertIn("collecting_before_pause=1", output)
        self.assertIn("collecting_after_pause=0", output)
        self.assertIn("paused=1", output)
        self.assertIn("pinned=0", output)
        self.assertIn("quit=0", output)

    def test_long_ok_repeat_does_not_start_calibration_before_fresh_short_press(self):
        # Holding the setup key generates repeats: these cannot confirm setup.
        output = self.scenario("repeat-setup")
        self.assertIn("collecting_after_repeat=0", output)
        self.assertIn("collecting_after_short=1", output)
        self.assertIn("quit=0", output)

    def test_repeat_actions_do_not_pause_open_info_or_exit_but_navigation_repeats(self):
        output = self.scenario("repeat-actions")
        self.assertIn("paused_after_repeat=0", output)
        self.assertIn("stops_after_repeat=0", output)
        self.assertIn("info_after_repeat=0", output)
        self.assertIn("detail_after_repeat_back=1", output)
        self.assertIn("pinned_after_repeat_back=0", output)
        self.assertIn("focus_after_repeat_down=1", output)
        self.assertIn("quit=0", output)

    def test_model_limits_do_not_present_clamped_numbers_as_measured_bounds(self):
        # Clamping arithmetic cannot turn an open-ended range into a tight band.
        for limit in ("high", "low"):
            with self.subTest(limit=limit):
                output = self.scenario("range-limit-" + limit)
                self.assertIn("reference_accepted=1", output)
                self.assertIn("large_numeric_readings=0", output)
                self.assertNotRegex(output, r"(?im)^(?:Est\.|Estimated)\s+[0-9]")
                self.assertRegex(output.lower(), r"limit|unavailable", output)


if __name__ == "__main__":
    unittest.main()
