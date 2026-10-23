"""App inventory comparisons must not confuse aliases, missing sources and parity."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class AppUnionDetailTests(unittest.TestCase):
    def test_code_aliases_missing_sources_and_untrusted_manifests(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            current = base / "current"
            reference = base / "reference"
            marker = base / "must-not-execute"

            def app(tree, name, appid, entry, source=None, plugin=False):
                folder = tree / name
                folder.mkdir(parents=True)
                (folder / "application.fam").write_text(
                    f"raise RuntimeError('never execute manifests')\n"
                    f"open({str(marker)!r}, 'w').write('unsafe')\n"
                    f"App(appid={appid!r}, name={name!r}, entry_point={entry!r}, "
                    f"apptype=FlipperAppType.{'PLUGIN' if plugin else 'EXTERNAL'})\n",
                    encoding="utf-8",
                )
                if source is not None:
                    (
                        folder / ("renamed.c" if tree == reference else "app.c")
                    ).write_bytes(source)

            app(
                current / "applications/union",
                "mine",
                "mine",
                "same_entry",
                b"int value;\r\n",
            )
            app(reference, "alias", "other", "same_entry", b"int value;\n")
            app(reference, "sparse", "sparse", "same_entry")
            app(reference, "changed", "changed", "same_entry", b"int other;\n")
            app(reference, "unmatched", "unmatched", "different", b"int extra;\n")
            app(reference, "plugin", "plugin", "plugin_start", b"int plugin;\n", True)
            output = base / "result.json"
            subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts/audit_app_union_detail.py"),
                    "--root",
                    str(current),
                    "--reference",
                    str(reference),
                    "--reference-commit",
                    "fixture",
                    "--output",
                    str(output),
                ],
                check=True,
                capture_output=True,
            )
            report = json.loads(output.read_text(encoding="utf-8"))
            statuses = {
                row["reference"]["appid"]: row["status"] for row in report["findings"]
            }
            self.assertEqual(
                statuses,
                {
                    "other": "app_local_source_identical",
                    "sparse": "matched_source_unavailable_review_required",
                    "changed": "matched_source_differs_review_required",
                    "unmatched": "unmatched_application",
                    "plugin": "unmatched_plugin",
                },
            )
            self.assertFalse(marker.exists())
            self.assertEqual(report["parse_errors"], [])

    def test_missing_reference_cannot_produce_a_successful_empty_report(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            output = base / "result.json"
            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts/audit_app_union_detail.py"),
                    "--root",
                    str(base),
                    "--reference",
                    str(base / "absent"),
                    "--reference-commit",
                    "fixture",
                    "--output",
                    str(output),
                ],
                capture_output=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(output.exists())
