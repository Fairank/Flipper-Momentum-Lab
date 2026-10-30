"""Exercise real BLE advertisements against real per-target range tracking."""

from pathlib import Path
import subprocess
import tempfile
import unittest

from scripts.tests.test_storage_upgrade import build

ROOT = Path(__file__).resolve().parents[2]


class RadarBeaconReferenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="radar-beacon-reference-")
        cls.addClassCleanup(cls.temporary.cleanup)
        core = ROOT / "applications/main/nearby_radar"
        cls.executable = build(
            Path(cls.temporary.name),
            [
                core / "radar_core.c",
                core / "radar_range.c",
                core / "radar_ble.c",
                Path(__file__).parent / "fixtures/radar_beacon_reference.c",
            ],
            "radar_beacon_reference",
            ["-I" + str(core), "-Wall", "-Wextra", "-Werror", "-lm"],
        )

    def check_case(self, name):
        result = subprocess.run(
            [str(self.executable), name],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Beacon reference case passed", result.stdout)

    def test_exact_ibeacon_supplies_signed_one_meter_reference(self):
        self.check_case("valid")

    def test_tx_power_and_other_manufacturer_data_are_not_one_meter_rssi(self):
        self.check_case("unrelated")

    def test_malformed_trailing_ad_cannot_partially_deliver_reference(self):
        self.check_case("malformed")

    def test_implausible_reference_is_ignored_without_dropping_device(self):
        self.check_case("bounds")

    def test_reference_follows_address_type_and_filter_acceptance(self):
        self.check_case("identity")

    def test_advertised_reference_cannot_replace_manual_calibration(self):
        self.check_case("manual")


if __name__ == "__main__":
    unittest.main()
