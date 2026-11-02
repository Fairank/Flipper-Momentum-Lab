"""Run the actual IR grid navigation and press lifecycle without radio hardware."""

from pathlib import Path
import subprocess
import re
import tempfile
import unittest

from scripts.tests.test_storage_upgrade import build

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "applications/main/infrared/views"


class InfraredButtonsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not (CORE / "infrared_layout.c").is_file():
            cls.missing = True
            return
        cls.missing = False
        temporary = tempfile.TemporaryDirectory(prefix="ir-buttons-")
        cls.addClassCleanup(temporary.cleanup)
        folder = Path(temporary.name)
        for name in ("infrared_layout.c", "infrared_layout.h"):
            (folder / name).write_bytes((CORE / name).read_bytes())
        fixture = Path(__file__).parent / "fixtures/infrared_buttons.c"
        (folder / fixture.name).write_bytes(fixture.read_bytes())
        cls.exe = build(
            folder,
            [folder / "infrared_layout.c", folder / fixture.name],
            "infrared_buttons",
            ["-I" + str(folder), "-Wall", "-Wextra", "-Werror"],
        )

    def setUp(self):
        self.assertFalse(
            self.missing, "The horizontal remote navigation has not been implemented"
        )

    def scenario(self, name):
        result = subprocess.run([str(self.exe), name], capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_directions_cross_pages_without_losing_column(self):
        self.scenario("navigation")

    def test_odd_last_row_and_empty_list_never_select_missing_button(self):
        self.scenario("bounds")

    def test_large_button_rectangles_fit_landscape_without_overlap(self):
        self.scenario("geometry")

    def test_display_names_preserve_unknown_labels_and_utf8(self):
        self.scenario("labels")

    def test_releasing_and_cancelling_use_original_pressed_id_once(self):
        self.scenario("hold")

    def test_control_and_library_buttons_never_activate_on_press_or_cancel(self):
        self.scenario("control")

    def test_short_before_release_cannot_leave_transmission_held(self):
        self.scenario("misordered")


class InfraredButtonsUiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temporary = tempfile.TemporaryDirectory(prefix="ir-buttons-ui-")
        cls.addClassCleanup(temporary.cleanup)
        folder = Path(temporary.name)
        for name in ("infrared_layout.c", "infrared_layout.h"):
            (folder / name).write_bytes((CORE / name).read_bytes())

        def without_includes(path):
            return re.sub(
                r"^#(?:include|pragma).*\n",
                "",
                path.read_text(encoding="utf-8"),
                flags=re.M,
            )

        fixture = (Path(__file__).parent / "fixtures/infrared_buttons_ui.c").read_text(
            encoding="utf-8"
        )
        fixture = fixture.replace(
            "/* PRODUCTION_HEADER */", without_includes(CORE / "infrared_buttons.h")
        )
        fixture = fixture.replace(
            "/* PRODUCTION_VIEW */", without_includes(CORE / "infrared_buttons.c")
        )
        source = folder / "infrared_buttons_ui.c"
        source.write_text(fixture, encoding="utf-8")
        cls.exe = build(
            folder,
            [folder / "infrared_layout.c", source],
            "infrared_buttons_ui",
            ["-I" + str(folder), "-Wall", "-Wextra", "-Werror"],
        )

    def scenario(self, name):
        result = subprocess.run([str(self.exe), name], capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_view_draws_model_labels_and_pages_and_preserves_control_ids(self):
        self.scenario("display")

    def test_held_navigation_and_back_cannot_leak_a_send(self):
        self.scenario("release")

    def test_control_callback_can_reset_view_without_lock_reentry(self):
        self.scenario("reset")

    def test_locked_debug_button_shows_requirement_without_activating(self):
        self.scenario("disabled")
