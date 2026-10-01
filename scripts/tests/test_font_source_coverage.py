"""Font collection includes compiled app scopes and tolerates legacy comments."""

import importlib.util
from pathlib import Path
import re
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import generate_native_zh_font as generator
from generate_lab_font import parse_font, verify_subset, extract_font


class FontSourceCoverageTests(unittest.TestCase):
    def test_all_application_scopes_and_legacy_comments(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixtures = {
                "applications/main/a/a.c": '"主";',
                "applications/services/power/a.c": '"电";',
                "applications/settings/a/a.c": '"设";',
                "applications/system/a/a.c": '"系";',
                "applications/external/a/a.cpp": '"外";',
                "applications/union/a/a.h": '"并";',
                "applications_user/a/a.c": '"用";',
            }
            for name, text in fixtures.items():
                p = root / name
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_bytes(
                    b"// legacy quote \x93\n"
                    + text.encode("utf-8")
                    + "\n/* 不应收集 */".encode("utf-8")
                )
            ignored = root / "applications/main/a/sample_font.h"
            ignored.write_text('"忽略"', encoding="utf-8")
            (root / "applications/union/a/application.fam").write_text(
                'App(appid="不收录", name="番茄" "钟", fap_description="忽略")',
                encoding="utf-8",
            )
            with patch.object(generator, "ROOT", root):
                actual = generator.required_characters()
            self.assertEqual(actual, set(map(ord, "主电设系外并用番茄钟")))

    def test_ram_updater_has_verified_small_cjk_only_font(self):
        header = generator.UPDATER_OUTPUT.read_text(encoding="utf-8")
        body = header.split("updater_zh_font[] = {", 1)[1].split("};", 1)[0]
        data = bytes(int(x, 16) for x in re.findall(r"0x([0-9a-f]{2})", body))
        original, _ = extract_font(
            (generator.ROOT / "lib/u8g2/u8g2_fonts.c").read_text(encoding="utf-8"),
            "u8g2_font_wqy12_t_gb2312",
        )
        required = generator.required_characters(updater=True)
        subset = verify_subset(parse_font(original), data, required)
        self.assertFalse(subset.ascii)
        self.assertEqual(set(subset.unicode), required)
        self.assertLess(
            len(data), 8192
        )  # Separate CI check enforces the whole updater limit.
