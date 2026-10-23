"""Exercise production discovery parsing, target retention and relative RSSI logic."""

from pathlib import Path
import subprocess
import tempfile
import unittest
from scripts.tests.test_storage_upgrade import build

ROOT = Path(__file__).resolve().parents[2]


class NearbyRadarTests(unittest.TestCase):
    def test_production_parser_and_target_tracking(self):
        with tempfile.TemporaryDirectory(prefix="nearby-radar-") as temp:
            core = ROOT / "applications/main/nearby_radar"
            executable = build(
                Path(temp),
                [
                    core / "radar_core.c",
                    Path(__file__).parent / "fixtures/nearby_radar.c",
                ],
                "nearby_radar",
                ["-I" + str(core), "-Wall", "-Wextra", "-Werror"],
            )
            result = subprocess.run(
                [str(executable)], capture_output=True, text=True, timeout=30
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("Nearby radar core passed", result.stdout)


if __name__ == "__main__":
    unittest.main()
