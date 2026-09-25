"""Keep iPhone launcher names aligned with this pinned firmware's app manifests."""
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class FunctionLaunchCatalogTests(unittest.TestCase):
    def test_built_in_launch_names_exist_in_firmware(self):
        source = (ROOT / "mobile/FlipperLab/Sources/FlipperCore/FlipperFunction.swift").read_text(
            encoding="utf-8"
        )
        names = re.findall(r'launchName: "([^"]+)"', source)
        self.assertGreaterEqual(len(names), 10)
        manifests = set()
        for path in (ROOT / "applications").rglob("application.fam"):
            manifests.update(
                re.findall(
                    r'^\s*name="([^"]+)"', path.read_text(encoding="utf-8"), re.M
                )
            )
        # "Apps" is the loader's built-in application-browser entry, not an app manifest.
        self.assertEqual(sorted(set(names) - manifests - {"Apps"}), [])


if __name__ == "__main__":
    unittest.main()
