"""Exercise production discovery parsing, target retention and relative RSSI logic."""

from pathlib import Path
import ast
import re
import subprocess
import tempfile
import unittest
from scripts.tests.test_storage_upgrade import build

ROOT = Path(__file__).resolve().parents[2]


class NearbyRadarTests(unittest.TestCase):
    def test_each_variant_sends_only_its_own_scan_command(self):
        core = ROOT / "applications/main/nearby_radar"
        source = (core / "nearby_radar.c").read_text()
        configuration = source[
            source.index("#ifndef RADAR_WIFI_ONLY") : source.index("typedef struct")
        ]
        scan = re.search(
            r"static void scan_command\([^)]*\)\s*\{.*?^\}", source, re.S | re.M
        )[0]
        manifest = ast.parse((core / "application.fam").read_text())
        for call in (
            node.value for node in manifest.body if isinstance(node, ast.Expr)
        ):
            fields = {kw.arg: kw.value for kw in call.keywords}
            appid = ast.literal_eval(fields["appid"])
            flags = ast.literal_eval(fields["cflags"]) if "cflags" in fields else []
            expected = "W" if appid == "wifi_radar" else "B"
            with self.subTest(appid=appid), tempfile.TemporaryDirectory(
                prefix="radar-mode-"
            ) as temp:
                folder = Path(temp)
                harness = folder / "scan.c"
                harness.write_text(
                    "#undef NDEBUG\n#include <assert.h>\n#include <stdint.h>\n#include <stdio.h>\n#include <string.h>\n"
                    "typedef struct { uint32_t start_at; } RadarApp;\n"
                    "static const char* sent;\n"
                    "static void command(RadarApp* a,const char*s){(void)a;sent=s;}\n"
                    "static uint32_t now_ms(void){return 42;}\n"
                    + configuration
                    + scan
                    + "\nint main(void){setvbuf(stdout,NULL,_IONBF,0);RadarApp a={0};scan_command(&a);"
                    + f'assert(!strcmp(sent,"NR1,SCAN,{expected}\\n"));'
                    + 'assert(a.start_at==42);puts("Radio mode passed");return 0;}\n'
                )
                executable = build(
                    folder, [harness], "scan", flags + ["-Wall", "-Wextra", "-Werror"]
                )
                result = subprocess.run(
                    [str(executable)], capture_output=True, text=True, timeout=30
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("Radio mode passed", result.stdout)

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
