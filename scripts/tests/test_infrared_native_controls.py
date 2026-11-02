"""Exercise native menu callback contracts and safe remote teardown in real C."""

from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from scripts.tests.test_storage_upgrade import build

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "applications/main/infrared"


class InfraredNativeControlsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Snapshot complete production functions before invoking the compiler.
        library = (APP / "scenes/infrared_scene_universal_from_file.c").read_text(
            encoding="utf-8"
        )
        remote = (APP / "scenes/infrared_scene_remote.c").read_text(encoding="utf-8")
        callback = re.search(
            r"static void\s+infrared_scene_universal_from_file_item_callback\([^)]*\)\s*\{.*?^\}",
            library,
            re.M | re.S,
        ).group()
        on_exit = re.search(
            r"void infrared_scene_remote_on_exit\([^)]*\)\s*\{.*?^\}",
            remote,
            re.M | re.S,
        ).group()
        temporary = tempfile.TemporaryDirectory(prefix="ir-native-controls-")
        cls.addClassCleanup(temporary.cleanup)
        folder = Path(temporary.name)
        (folder / "infrared_custom_event.h").write_bytes(
            (APP / "infrared_custom_event.h").read_bytes()
        )
        fixture = (
            Path(__file__).parent / "fixtures/infrared_native_controls.c"
        ).read_text(encoding="utf-8")
        fixture = fixture.replace("/* PRODUCTION_CALLBACK */", callback).replace(
            "/* PRODUCTION_REMOTE_EXIT */", on_exit
        )
        source = folder / "infrared_native_controls.c"
        source.write_text(fixture, encoding="utf-8")
        cls.exe = build(
            folder,
            [source],
            "infrared_native_controls",
            ["-I" + str(folder), "-Wall", "-Wextra", "-Werror"],
        )

    def scenario(self, name):
        result = subprocess.run([str(self.exe), name], capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_library_common_button_press_does_not_dispatch(self):
        self.scenario("press")

    def test_library_common_button_short_does_not_dispatch(self):
        self.scenario("short")

    def test_library_common_button_release_dispatches_selected_index_once(self):
        self.scenario("release")

    def test_native_press_short_release_dispatches_only_at_release(self):
        self.scenario("sequence")

    def test_remote_exit_stops_transmission_before_resetting_buttons(self):
        self.scenario("exit")
