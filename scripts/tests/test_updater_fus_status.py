"""Exercise the real updater CLI dispatcher against an isolated Core2 transport.

These tests never connect to a device. Removing either readiness/mode guard,
querying twice (which can start FUS), or dispatching a write command must fail.
"""

from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
CLI = ROOT / "applications/system/updater/cli/updater_cli.c"
GLUE = ROOT / "targets/f7/ble_glue/ble_glue.c"

WRAPPER_HARNESS = r'''
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "ble_glue.h"
typedef void FuriMutex;
typedef void FuriTimer;
/* PRODUCTION_BLE_GLUE_TYPE */
static BleGlue* ble_glue = NULL;
/* SHCI_ERROR_ENUM */
static int query_calls;
uint8_t SHCI_C2_FUS_GetState(SHCI_FUS_GetState_ErrorCode_t* error) {
    ++query_calls;
    assert(query_calls == 1);
    *error = FUS_STATE_ERROR_IMG_CORRUPT;
    return 0xff;
}
/* PRODUCTION_FUS_WRAPPER */
int main(int argc, char** argv) {
    assert(argc == 2);
    BleGlue fixture;
    memset(&fixture, 0, sizeof(fixture));
    fixture.status = BleGlueStatusC2Started;
    fixture.c2_info.mode = BleGlueC2ModeFUS;
    ble_glue = &fixture;
    if(strcmp(argv[1], "missing") == 0) ble_glue = NULL;
    else if(strcmp(argv[1], "startup") == 0) fixture.status = BleGlueStatusStartup;
    else if(strcmp(argv[1], "broken") == 0) fixture.status = BleGlueStatusBroken;
    else if(strcmp(argv[1], "stack") == 0) fixture.c2_info.mode = BleGlueC2ModeStack;
    else if(strcmp(argv[1], "unknown") == 0) fixture.c2_info.mode = BleGlueC2ModeUnknown;
    uint8_t state = 0xa5, error = 0x5a;
    uint8_t* state_arg = strcmp(argv[1], "null-state") == 0 ? NULL : &state;
    uint8_t* error_arg = strcmp(argv[1], "null-error") == 0 ? NULL : &error;
    bool read = ble_glue_fus_read_status(state_arg, error_arg);
    if(strcmp(argv[1], "fus") == 0) {
        assert(read);
        assert(query_calls == 1);
        assert(state == 0xff && error == 0x02);
    } else {
        assert(!read);
        assert(query_calls == 0);
        assert(state == 0xa5 && error == 0x5a);
    }
    printf("FUS wrapper scenario passed\n");
    fflush(stdout);
    return 0;
}
'''

HARNESS = r'''
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <ctype.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ble_glue.h"

#define UNUSED(value) ((void)(value))
#define COUNT_OF(value) (sizeof(value) / sizeof((value)[0]))
typedef struct { char text[512]; } FuriString;
typedef void PipeSide;
typedef void Storage;
typedef enum { UpdatePrepareResultOK } UpdatePrepareResult;
static const char* RECORD_STORAGE = "storage";
static int mutation_calls, query_calls, info_calls, locks;
static BleGlueStatus c2_status = BleGlueStatusC2Started;
static BleGlueC2Info c2_info;
static bool absent_info;
static bool lose_readiness_on_lock, change_to_stack_on_lock;
static uint8_t raw_state = 0xff;
static uint8_t raw_error = 0x02;

FuriString* furi_string_alloc(void) { return calloc(1, sizeof(FuriString)); }
void furi_string_free(FuriString* value) { free(value); }
const char* furi_string_get_cstr(FuriString* value) { return value->text; }
bool furi_string_empty(FuriString* value) { return value->text[0] == '\0'; }
int furi_string_cmp_str(FuriString* value, const char* text) {
    return strcmp(value->text, text);
}
bool args_read_string_and_trim(FuriString* args, FuriString* out) {
    const char* start = args->text;
    while(isspace((unsigned char)*start)) ++start;
    const char* end = start;
    while(*end && !isspace((unsigned char)*end)) ++end;
    size_t length = (size_t)(end - start);
    memcpy(out->text, start, length);
    out->text[length] = '\0';
    while(isspace((unsigned char)*end)) ++end;
    memmove(args->text, end, strlen(end) + 1);
    return length != 0;
}
bool furi_hal_bt_is_alive(void) { return c2_status >= BleGlueStatusC2Started; }
void furi_hal_bt_lock_core2(void) {
    assert(locks == 0); ++locks;
    if(lose_readiness_on_lock) c2_status = BleGlueStatusBroken;
    if(change_to_stack_on_lock) c2_info.mode = BleGlueC2ModeStack;
}
void furi_hal_bt_unlock_core2(void) { assert(locks == 1); --locks; }
BleGlueStatus ble_glue_get_c2_status(void) { return c2_status; }
const BleGlueC2Info* ble_glue_get_c2_info(void) {
    assert(locks == 1);
    ++info_calls;
    return absent_info ? NULL : &c2_info;
}
bool ble_glue_fus_read_status(uint8_t* state, uint8_t* error) {
    assert(locks == 1);
    ++query_calls;
    assert(query_calls == 1); /* Do not repeat a hardware status request. */
    *state = raw_state;
    *error = raw_error;
    return true;
}
UpdatePrepareResult update_operation_prepare(const char* path) {
    UNUSED(path); ++mutation_calls; return UpdatePrepareResultOK;
}
const char* update_operation_describe_preparation_result(UpdatePrepareResult value) {
    UNUSED(value); return "test result";
}
void furi_delay_ms(unsigned delay) { UNUSED(delay); }
void furi_hal_power_reset(void) { ++mutation_calls; }
Storage* furi_record_open(const char* name) {
    UNUSED(name); ++mutation_calls; return (Storage*)1;
}
void furi_record_close(const char* name) { UNUSED(name); }
bool int_backup_create(Storage* storage, const char* path) {
    UNUSED(storage); UNUSED(path); ++mutation_calls; return false;
}
bool int_backup_unpack(Storage* storage, const char* path) {
    UNUSED(storage); UNUSED(path); ++mutation_calls; return false;
}

/* PRODUCTION_UPDATER_CLI */

int main(int argc, char** argv) {
    assert(argc == 3);
    memset(&c2_info, 0, sizeof(c2_info));
    c2_info.mode = BleGlueC2ModeFUS;
    if(strcmp(argv[1], "startup") == 0) c2_status = BleGlueStatusStartup;
    else if(strcmp(argv[1], "broken") == 0) c2_status = BleGlueStatusBroken;
    else if(strcmp(argv[1], "stack") == 0) c2_info.mode = BleGlueC2ModeStack;
    else if(strcmp(argv[1], "unknown") == 0) c2_info.mode = BleGlueC2ModeUnknown;
    else if(strcmp(argv[1], "null-info") == 0) absent_info = true;
    else if(strcmp(argv[1], "lost-ready") == 0) lose_readiness_on_lock = true;
    else if(strcmp(argv[1], "changed-to-stack") == 0) change_to_stack_on_lock = true;
    else if(strcmp(argv[1], "idle") == 0) {
        raw_state = 0x00; raw_error = 0x00;
    } else if(strcmp(argv[1], "not-running") == 0) {
        raw_state = 0xff; raw_error = 0xfe;
    } else assert(strcmp(argv[1], "corrupt") == 0);
    FuriString args = {0};
    assert(strlen(argv[2]) < sizeof(args.text));
    strcpy(args.text, argv[2]);
    updater_cli_ep(NULL, &args, NULL);
    assert(locks == 0);
    assert(mutation_calls == 0);
    printf("\nOBS queries=%d info=%d mutations=%d locks=%d\n",
           query_calls, info_calls, mutation_calls, locks);
    fflush(stdout);
    return 0;
}
'''


class UpdaterFusStatusTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        compiler = next((x for n in ("cc", "gcc", "clang") if (x := shutil.which(n))), None)
        if compiler is None and sys.platform == "win32":
            shim = ROOT.parent / "flipper-tools/cc.cmd"
            if shim.is_file():
                compiler = str(shim)
        if compiler is None:
            raise AssertionError("A host C compiler is required; FUS guard tests must not skip")
        temporary = tempfile.TemporaryDirectory(prefix="flipper-fus-status-")
        cls.addClassCleanup(temporary.cleanup)
        folder = Path(temporary.name)
        production = CLI.read_text(encoding="utf-8")
        start = production.index("typedef void (*cmd_handler)")
        end = production.index("static void updater_start_app", start)
        source = folder / "updater_fus_status.c"
        source.write_text(
            HARNESS.replace("/* PRODUCTION_UPDATER_CLI */", production[start:end]), encoding="utf-8"
        )
        cls.executable = folder / ("updater_fus_status.exe" if sys.platform == "win32" else "updater_fus_status")
        command = [compiler, "-std=c11", "-Wall", "-Wextra", "-Werror", "-O1", "-UNDEBUG"]
        if sys.platform.startswith("linux"):
            command += ["-fsanitize=address,undefined", "-fno-sanitize-recover=all"]
        command += ["-I" + str(ROOT / "targets/f7/ble_glue"), str(source), "-o", str(cls.executable)]
        environment = os.environ.copy()
        environment["ZIG_GLOBAL_CACHE_DIR"] = str(folder / "zig-global")
        environment["ZIG_LOCAL_CACHE_DIR"] = str(folder / "zig-local")
        result = subprocess.run(command, capture_output=True, text=True, env=environment, timeout=180)
        if result.returncode:
            raise AssertionError("FUS CLI harness build failed:\n" + result.stdout + result.stderr)

    def invoke(self, mode, command="fus-status"):
        result = subprocess.run([str(self.executable), mode, command], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def test_fus_error_is_reported_raw_with_one_transport_query(self):
        output = self.invoke("corrupt")
        self.assertIn("FUS state: 0xFF, error: 0x02", output)
        self.assertIn("OBS queries=1 info=1 mutations=0 locks=0", output)

    def test_idle_is_reported_without_starting_an_operation(self):
        output = self.invoke("idle")
        self.assertIn("FUS state: 0x00, error: 0x00", output)
        self.assertIn("OBS queries=1 info=1 mutations=0 locks=0", output)

    def test_not_running_response_is_not_retried(self):
        output = self.invoke("not-running")
        self.assertIn("FUS state: 0xFF, error: 0xFE", output)
        self.assertIn("OBS queries=1 info=1 mutations=0 locks=0", output)

    def test_unready_core2_is_refused_before_info_or_transport_access(self):
        for mode in ("startup", "broken"):
            with self.subTest(mode=mode):
                output = self.invoke(mode)
                self.assertIn("refused", output)
                self.assertIn("OBS queries=0 info=0 mutations=0 locks=0", output)

    def test_stack_unknown_and_absent_info_are_refused_without_get_state(self):
        for mode in ("stack", "unknown", "null-info"):
            with self.subTest(mode=mode):
                output = self.invoke(mode)
                self.assertIn("refused", output)
                self.assertIn("OBS queries=0 info=1 mutations=0 locks=0", output)

    def test_diagnostic_rejects_extra_arguments_before_touching_core2(self):
        output = self.invoke("corrupt", "fus-status retry")
        self.assertIn("Usage: update fus-status", output)
        self.assertIn("OBS queries=0 info=0 mutations=0 locks=0", output)

    def test_readiness_lost_before_lock_is_rechecked_without_get_state(self):
        output = self.invoke("lost-ready")
        self.assertIn("refused", output)
        self.assertIn("OBS queries=0 info=0 mutations=0 locks=0", output)

    def test_mode_changed_to_stack_before_lock_is_refused_without_get_state(self):
        output = self.invoke("changed-to-stack")
        self.assertIn("refused", output)
        self.assertIn("OBS queries=0 info=1 mutations=0 locks=0", output)

    def test_missing_install_path_does_not_start_an_update(self):
        output = self.invoke("corrupt", "install")
        self.assertIn("Commands:", output)
        self.assertIn("OBS queries=0 info=0 mutations=0 locks=0", output)


class BleGlueFusStatusWrapperTests(unittest.TestCase):
    def test_read_only_wrapper_guards_transport_and_preserves_raw_response(self):
        production = GLUE.read_text(encoding="utf-8")
        wrapper = re.search(
            r"bool ble_glue_fus_read_status\([^)]*\)\s*\{.*?^\}", production, re.S | re.M
        )
        self.assertIsNotNone(wrapper, "The raw read-only FUS hardware interface is not implemented")
        glue_type = re.search(r"typedef struct\s*\{[^{}]*\}\s*BleGlue;", production)
        self.assertIsNotNone(glue_type, "The real Core2 context type is unavailable")
        shci = (ROOT / "lib/stm32wb_copro/wpan/interface/patterns/ble_thread/shci/shci.h").read_text()
        error_enum = re.search(r"typedef enum\s*\{[^{}]*\}\s*SHCI_FUS_GetState_ErrorCode_t;", shci)
        self.assertIsNotNone(error_enum, "The real SHCI error type is unavailable")
        compiler = next((x for n in ("cc", "gcc", "clang") if (x := shutil.which(n))), None)
        if compiler is None and sys.platform == "win32":
            shim = ROOT.parent / "flipper-tools/cc.cmd"
            if shim.is_file():
                compiler = str(shim)
        self.assertIsNotNone(compiler, "A host C compiler is required; wrapper tests must not skip")
        with tempfile.TemporaryDirectory(prefix="flipper-fus-wrapper-") as temporary:
            folder = Path(temporary)
            source = folder / "fus_wrapper.c"
            source.write_text(
                WRAPPER_HARNESS.replace("/* PRODUCTION_BLE_GLUE_TYPE */", glue_type[0])
                .replace("/* SHCI_ERROR_ENUM */", error_enum[0])
                .replace("/* PRODUCTION_FUS_WRAPPER */", wrapper[0]), encoding="utf-8"
            )
            executable = folder / ("fus_wrapper.exe" if sys.platform == "win32" else "fus_wrapper")
            command = [compiler, "-std=c11", "-Wall", "-Wextra", "-Werror", "-O1", "-UNDEBUG"]
            if sys.platform.startswith("linux"):
                command += ["-fsanitize=address,undefined", "-fno-sanitize-recover=all"]
            command += ["-I" + str(ROOT / "targets/f7/ble_glue"), str(source), "-o", str(executable)]
            environment = os.environ.copy()
            environment["ZIG_GLOBAL_CACHE_DIR"] = str(folder / "zig-global")
            environment["ZIG_LOCAL_CACHE_DIR"] = str(folder / "zig-local")
            result = subprocess.run(command, capture_output=True, text=True, env=environment, timeout=180)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            for mode in ("missing", "startup", "broken", "stack", "unknown", "null-state", "null-error", "fus"):
                with self.subTest(mode=mode):
                    result = subprocess.run([str(executable), mode], capture_output=True, text=True, timeout=15)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn("FUS wrapper scenario passed", result.stdout)


if __name__ == "__main__":
    unittest.main()
