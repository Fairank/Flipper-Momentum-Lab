"""Manifest audits must not execute code or count dynamic names as literal IDs."""

import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "audit_app_union", Path(__file__).resolve().parents[1] / "audit_app_union.py"
)
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class AppUnionAuditTests(unittest.TestCase):
    def test_identity_is_appid_not_translated_name(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            current, reference = root / "current", root / "reference"
            current.mkdir()
            reference.mkdir()
            (current / "application.fam").write_text(
                'raise RuntimeError("MUST NOT EXECUTE")\nApp(appid="clock", name="时钟")',
                encoding="utf-8",
            )
            (reference / "application.fam").write_text(
                'App(appid="clock",name="Clock")\nApp(appid="calendar",name="Calendar")\nApp(appid=f"dynamic_{index}")',
                encoding="utf-8",
            )
            report = audit.compare([current], reference, "pinned")
            self.assertEqual(report["counts"]["shared_literal_ids"], 1)
            self.assertEqual(report["counts"]["reference_ids_absent_from_current"], 1)
            self.assertEqual(
                report["reference_candidates_absent_from_current"][0]["appid"],
                "calendar",
            )
            self.assertEqual(len(report["reference"]["unresolved"]), 1)
            self.assertFalse(report["current"]["errors"])

    def test_unreadable_manifest_is_reported_not_silently_dropped(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "application.fam").write_text("App(", encoding="utf-8")
            self.assertEqual(len(audit.inventory(root)["errors"]), 1)
