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
    def test_each_variant_uses_its_own_radio(self):
        core = ROOT / "applications/main/nearby_radar"
        source = (core / "nearby_radar.c").read_text()
        configuration = source[
            source.index("#ifndef RADAR_WIFI_ONLY") : source.index("typedef struct")
        ]
        scans = re.findall(
            r"static void scan_command\([^)]*\)\s*\{.*?^\}", source, re.S | re.M
        )
        self.assertEqual(len(scans), 2)
        manifest = ast.parse((core / "application.fam").read_text())
        for call in (
            node.value for node in manifest.body if isinstance(node, ast.Expr)
        ):
            fields = {kw.arg: kw.value for kw in call.keywords}
            appid = ast.literal_eval(fields["appid"])
            flags = ast.literal_eval(fields["cflags"]) if "cflags" in fields else []
            wifi = appid == "wifi_radar"
            with self.subTest(appid=appid), tempfile.TemporaryDirectory(
                prefix="radar-mode-"
            ) as temp:
                folder = Path(temp)
                harness = folder / "scan.c"
                harness.write_text(
                    "#undef NDEBUG\n#include <assert.h>\n#include <stdbool.h>\n#include <stdint.h>\n#include <stdio.h>\n#include <string.h>\n"
                    "typedef struct { uint32_t start_at; bool scan_open; void* view; } RadarApp;\n"
                    "static const char* sent; static unsigned native;\n"
                    + configuration
                    + "\n#if RADAR_WIFI_ONLY\n"
                    "static void command(RadarApp* a,const char*s){(void)a;sent=s;}\n"
                    "#else\n"
                    "typedef struct {bool opened; struct{bool ready,running;}core; char status[40];}RadarModel;\n"
                    "static RadarModel model; enum{FuriHalBtStackFull};\n"
                    "#define with_view_model(v,decl,body,update) do{(void)(v);RadarModel*m=&model;body;}while(0)\n"
                    "static void observation(void){}\n"
                    "static int furi_hal_bt_get_radio_stack(void){return FuriHalBtStackFull;}\n"
                    "static bool furi_hal_bt_start_scan(void(*cb)(void),void*ctx){assert(cb==observation&&ctx);native++;return true;}\n"
                    "#endif\n"
                    "static uint32_t now_ms(void){return 42;}\n"
                    + "#if RADAR_WIFI_ONLY\n"
                    + scans[0]
                    + "\n#else\n"
                    + scans[1]
                    + "\n#endif\n"
                    + "\nint main(void){setvbuf(stdout,NULL,_IONBF,0);RadarApp a={0};scan_command(&a);"
                    + (
                        'assert(sent&&!strcmp(sent,"NR1,SCAN,W\\n")&&!native);'
                        if wifi
                        else "assert(!sent&&native==1&&a.scan_open&&model.core.ready&&model.core.running);"
                    )
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

    def test_native_hci_parser_and_advertising_names(self):
        with tempfile.TemporaryDirectory(prefix="native-ble-") as temp:
            folder = Path(temp)
            (folder / "furi_hal_version.h").write_text(
                "#define FURI_HAL_VERSION_DEVICE_NAME_LENGTH 32\n"
            )
            core = ROOT / "applications/main/nearby_radar"
            gap = ROOT / "targets/f7/ble_glue"
            executable = build(
                folder,
                [
                    gap / "ble_scan_parser.c",
                    core / "radar_core.c",
                    core / "radar_ble.c",
                    Path(__file__).parent / "fixtures/native_ble.c",
                ],
                "native_ble",
                [
                    "-I" + str(folder),
                    "-I" + str(gap),
                    "-I" + str(core),
                    "-Wall",
                    "-Wextra",
                    "-Werror",
                ],
            )
            result = subprocess.run(
                [str(executable)], capture_output=True, text=True, timeout=30
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("Native BLE parser and tracking passed", result.stdout)

    def test_native_scan_ownership_and_stop_lifetime(self):
        source = (ROOT / "targets/f7/ble_glue/gap.c").read_text()
        production = source[
            source.index("bool gap_scan_start(") : source.index("void gap_thread_stop(")
        ]
        with tempfile.TemporaryDirectory(prefix="ble-scan-state-") as temp:
            folder = Path(temp)
            harness = folder / "scan_state.c"
            harness.write_text(
                r"""
#undef NDEBUG
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
typedef void(*GapScanCallback)(void);
typedef struct {void*state_mutex;GapScanCallback scan_callback;void*scan_context;bool scan_active,scan_stopping;}Gap;
static Gap storage={.state_mutex=(void*)1}, *gap=&storage;
static int locked, started, stopped, result;
enum{FuriWaitForever, BLE_STATUS_SUCCESS=0, CFG_IDENTITY_ADDRESS=0, GAP_OBSERVATION_PROC=128};
static void furi_mutex_acquire(void*m,int t){(void)m;(void)t;assert(!locked++);}
static void furi_mutex_release(void*m){(void)m;assert(locked--==1);}
static int aci_gap_start_observation_proc(int interval,int window,int active,int address,int duplicates,int filter){
assert(locked&&interval>=window&&window>0&&!active&&address==CFG_IDENTITY_ADDRESS&&!duplicates&&!filter);started++;return result;}
static int aci_gap_terminate_gap_proc(int proc){assert(locked&&proc==GAP_OBSERVATION_PROC);stopped++;return result;}
static void cb(void){}
"""
                + production
                + r"""
int main(void){int owner,other;
assert(!gap_scan_start(NULL,&owner)&&!gap_scan_start(cb,NULL)&&!started);
result=12;assert(!gap_scan_start(cb,&owner)&&!gap_scan_is_active(&owner));
result=0;assert(gap_scan_start(cb,&owner)&&gap_scan_is_active(&owner));
assert(!gap_scan_start(cb,&other)&&!gap_scan_stop(&other));
assert(gap_scan_start(cb,&owner)&&started==2);
assert(gap_scan_stop(&owner)&&stopped==1&&!gap->scan_callback);
assert(gap_scan_stop(&owner)&&stopped==1&&!gap_scan_is_active(&owner));
assert(!gap_scan_start(cb,&owner));
gap->scan_active=gap->scan_stopping=false; /* Real completion event. */
assert(gap_scan_start(cb,&owner)&&started==3);
result=12;assert(!gap_scan_stop(&owner)&&!gap->scan_callback);
result=0;assert(gap_scan_start(cb,&owner)&&gap->scan_callback==cb);
assert(gap_scan_stop(&owner)&&!gap->scan_callback);
gap=NULL;assert(gap_scan_stop(&owner)&&!gap_scan_is_active(&owner)&&!gap_scan_start(cb,&owner));
puts("Native scan ownership and callback lifetime passed");return 0;}
"""
            )
            executable = build(
                folder, [harness], "scan_state", ["-Wall", "-Wextra", "-Werror"]
            )
            result = subprocess.run(
                [str(executable)], capture_output=True, text=True, timeout=30
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn(
                "Native scan ownership and callback lifetime passed", result.stdout
            )

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
