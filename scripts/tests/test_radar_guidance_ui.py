"""Run the real radar draw/input paths with recording device boundaries.

The canvas captures the text a user receives, rather than inspecting source
wording. Real range/core code is linked; only the hardware and GUI boundary is
replaced. Device screenshots still own visual acceptance.
"""

from pathlib import Path
import re
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

    def circle_geometry(self, output):
        circles = [
            tuple(map(int, match))
            for match in re.findall(r"(?m)^circle=(-?\d+),(-?\d+),(\d+)$", output)
        ]
        discs = [
            tuple(map(int, match))
            for match in re.findall(r"(?m)^disc=(-?\d+),(-?\d+),(\d+)$", output)
        ]
        dots = [
            tuple(map(int, match))
            for match in re.findall(r"(?m)^dot=(-?\d+),(-?\d+)$", output)
        ]
        self.assertGreaterEqual(len(circles), 2, output)
        outer = max(circles, key=lambda circle: circle[2])
        inner = [
            circle
            for circle in circles
            if circle[:2] == outer[:2] and 0 < circle[2] < outer[2]
        ]
        self.assertTrue(inner, output)
        self.assertIn(outer[:2], dots, output)
        return outer, discs

    def test_circle_marker_contracts_toward_centre_for_both_calibrated_and_rough_proximity(
        self,
    ):
        # Removing the circle, omitting the live target, or reversing near/far
        # must fail. Exact pixel constants remain a design choice.
        for mode in ("cal", "uncal"):
            distances = []
            centres = []
            vectors = []
            for proximity in ("close", "near", "far"):
                with self.subTest(mode=mode, proximity=proximity):
                    output = self.scenario(f"circle-{mode}-{proximity}")
                    outer, discs = self.circle_geometry(output)
                    self.assertEqual(len(discs), 1, output)
                    x, y, radius = discs[0]
                    dx, dy = x - outer[0], y - outer[1]
                    distances.append(dx * dx + dy * dy)
                    centres.append(outer[:2])
                    vectors.append((dx, dy))
                    self.assertLessEqual(
                        dx * dx + dy * dy, (outer[2] - radius) ** 2, output
                    )
            self.assertEqual(
                len(distances), 3, "Incomplete live circle geometry: " + mode
            )
            self.assertEqual(len(set(centres)), 1)
            self.assertLess(distances[0], distances[1])
            self.assertLess(distances[1], distances[2])
            # A fixed radial scale does not invent a changing compass bearing.
            self.assertEqual(
                vectors[0][0] * vectors[2][1], vectors[0][1] * vectors[2][0]
            )
            self.assertEqual(
                vectors[1][0] * vectors[2][1], vectors[1][1] * vectors[2][0]
            )

    def test_circle_never_presents_a_live_marker_for_degraded_or_collecting_signal(
        self,
    ):
        for state in ("paused", "aging", "lost", "unstable", "collecting"):
            with self.subTest(state=state):
                output = self.scenario("range-" + state)
                _, discs = self.circle_geometry(output)
                self.assertEqual(discs, [], output)


if __name__ == "__main__":
    unittest.main()
