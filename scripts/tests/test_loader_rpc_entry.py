"""Host integration for the public and private loader start queue entries.

Compile loader_start_internal, loader_start and loader_start_from_rpc directly
from loader.c, with the real header declarations and LoaderMessage types.
Queue/API-lock substitutes record the message and fill its real status_value
pointer only when the caller waits. This checks entry routing and parameter
preservation, not the loader worker, FAP loading or a BLE connection.

rpc_system_app_start_process is intentionally outside this narrow harness:
its RPC-context formatting assumes the device's 32-bit pointer/printf ABI.
A host compiler is mandatory; an unavailable compiler fails rather than skips.
"""

import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
LOADER = ROOT / "applications/services/loader"


def declaration(text, kind, name):
    # These named leaf declarations have no nested braces. The full message
    # union is taken separately, unchanged, from loader_i.h below.
    pattern = r"typedef\s+" + kind + r"\s*\{[^{}]*\}\s*" + name + r"\s*;"
    found = re.search(pattern, text, re.S)
    if found is None:
        raise AssertionError(f"Missing production declaration {name}")
    return found.group(0) + "\n"


def function(text, result_type, name):
    pattern = (
        r"(?:static\s+)?" + result_type + r"\s+" + name + r"\s*\([^)]*\)\s*\{.*?^\}"
    )
    found = re.search(pattern, text, re.S | re.M)
    if found is None:
        raise AssertionError(f"Missing production function {name}")
    return found.group(0) + "\n"


def prototype(text, name):
    found = re.search(r"LoaderStatus\s+" + name + r"\s*\([^;]*\);", text, re.S)
    if found is None:
        raise AssertionError(f"Missing production entry prototype {name}")
    return found.group(0) + "\n"


def production_source():
    implementation = (LOADER / "loader.c").read_text(encoding="utf-8")
    public = (LOADER / "loader.h").read_text(encoding="utf-8")
    private = (LOADER / "loader_rpc.h").read_text(encoding="utf-8")
    internal = (LOADER / "loader_i.h").read_text(encoding="utf-8")
    queue = (LOADER / "loader_queue.h").read_text(encoding="utf-8")
    locks = (ROOT / "lib/toolbox/api_lock.h").read_text(encoding="utf-8")
    base = (ROOT / "furi/core/base.h").read_text(encoding="utf-8")
    api_lock = re.search(r"typedef FuriEventFlag\* FuriApiLock;", locks)
    queue_field = re.search(r"^    FuriMessageQueue\* queue;", internal, re.M)
    if api_lock is None or queue_field is None:
        raise AssertionError("Missing production API-lock type or Loader queue field")
    # This tail contains all real message types, including its two unions.
    message_start = internal.index(
        declaration(internal, "enum", "LoaderMessageType").strip()
    )
    message_end = internal.index("} LoaderMessage;", message_start) + len(
        "} LoaderMessage;"
    )
    return (
        INCLUDES
        + declaration(base, "enum", "FuriWait")
        + declaration(base, "enum", "FuriStatus")
        + LEAF_STUB_TYPES
        + api_lock.group(0)
        + "\n"
        + "typedef struct Loader Loader;\n"
        + declaration(public, "enum", "LoaderStatus")
        + declaration(public, "enum", "LoaderDeferredLaunchFlag")
        + declaration(queue, "struct", "LoaderDeferredLaunchRecord")
        + internal[message_start:message_end]
        + "\n"
        + "struct Loader {\n"
        + queue_field.group(0)
        + "\n};\n"
        + prototype(public, "loader_start")
        + prototype(private, "loader_start_from_rpc")
        + RECORDING_STUBS
        + function(
            implementation, "LoaderMessageLoaderStatusResult", "loader_start_internal"
        )
        + function(implementation, "LoaderStatus", "loader_start")
        + function(implementation, "LoaderStatus", "loader_start_from_rpc")
        + SCENARIOS
    )


INCLUDES = r"""
#undef NDEBUG
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#define furi_check assert
"""

LEAF_STUB_TYPES = r"""
typedef struct { uint32_t marker; } FuriString;
typedef struct { uint32_t marker; } FuriMessageQueue;
typedef struct { bool alive; } FuriEventFlag;
"""

RECORDING_STUBS = r"""
static FuriMessageQueue queue;
static Loader loader;
static FuriEventFlag lock;
static LoaderMessageStartByName recorded_start;
static LoaderMessageLoaderStatusResult configured_result;
static LoaderMessageLoaderStatusResult* pending_status;
static uintptr_t recorded_status_address;
static FuriApiLock recorded_lock;
static uint32_t recorded_timeout;
static unsigned allocations, queue_puts, waits, frees, stage;
static const uint32_t written_error_marker = UINT32_C(0xD0123456);

static FuriApiLock api_lock_alloc_locked(void) {
    assert(stage == 0 && !lock.alive);
    allocations++;
    stage = 1;
    lock.alive = true;
    return &lock;
}

static FuriStatus furi_message_queue_put(
    FuriMessageQueue* target, const void* raw_message, uint32_t timeout) {
    assert(stage == 1 && target == &queue && lock.alive);
    const LoaderMessage* message = raw_message;
    assert(message->type == LoaderMessageTypeStartByName);
    assert(message->api_lock == &lock && message->status_value != NULL);
    // Copy only initialized fields, without reading unrelated union/padding bytes.
    recorded_start.name = message->start.name;
    recorded_start.args = message->start.args;
    recorded_start.error_message = message->start.error_message;
    recorded_start.require_api_match = message->start.require_api_match;
    recorded_lock = message->api_lock;
    pending_status = message->status_value;
    recorded_status_address = (uintptr_t)pending_status;
    recorded_timeout = timeout;
    assert(pending_status != &configured_result);
    queue_puts++;
    stage = 2;
    return FuriStatusOk;
}

static void api_lock_wait_unlock_and_free(FuriApiLock target) {
    assert(stage == 2 && target == &lock && lock.alive && pending_status);
    waits++;
    // Simulate worker completion through the pointer actually enqueued by the
    // production function. Returning before this step cannot obtain our result.
    *pending_status = configured_result;
    if(recorded_start.error_message) {
        recorded_start.error_message->marker = written_error_marker;
    }
    pending_status = NULL;
    lock.alive = false;
    frees++;
    stage = 3;
}
"""

SCENARIOS = r"""
static const LoaderStatus statuses[] = {
    LoaderStatusOk,
    LoaderStatusErrorAppStarted,
    LoaderStatusErrorUnknownApp,
    LoaderStatusErrorInternal,
    LoaderStatusErrorApiMismatchCanceled,
};
static const LoaderStatusError errors[] = {
    LoaderStatusErrorUnknown,
    LoaderStatusErrorInvalidFile,
    LoaderStatusErrorInvalidManifest,
    LoaderStatusErrorMissingImports,
    LoaderStatusErrorHWMismatch,
    LoaderStatusErrorOutdatedApp,
    LoaderStatusErrorOutOfMemory,
    LoaderStatusErrorOutdatedFirmware,
};

static void reset(LoaderStatus status, LoaderStatusError error) {
    memset(&recorded_start, 0, sizeof(recorded_start));
    memset(&lock, 0, sizeof(lock));
    pending_status = NULL;
    recorded_status_address = 0;
    recorded_lock = NULL;
    recorded_timeout = 0;
    allocations = queue_puts = waits = frees = stage = 0;
    loader.queue = &queue;
    configured_result.value = status;
    configured_result.error = error;
}

static void check_message(
    const char* name, const char* args, FuriString* error_message, bool require_api_match) {
    assert(recorded_start.name == name);
    assert(recorded_start.args == args);
    assert(recorded_start.error_message == error_message);
    assert(recorded_start.require_api_match == require_api_match);
    assert(recorded_lock == &lock && recorded_status_address != 0);
    assert(recorded_timeout == FuriWaitForever);
    assert(allocations == 1 && queue_puts == 1 && waits == 1 && frees == 1);
    assert(stage == 3 && !lock.alive && pending_status == NULL);
    if(error_message) assert(error_message->marker == written_error_marker);
}

static void public_or_rpc(bool rpc) {
    char names[][48] = {"NFC", "/ext/apps/Tools/clock.fap", "Caller-owned Name"};
    char empty[] = "";
    char rpc_args[] = "RPC";
    char custom_args[] = "profile=/ext/nfc/test.nfc custom";
    const char* arguments[] = {NULL, empty, rpc_args, custom_args};
    for(size_t n = 0; n < sizeof(names) / sizeof(names[0]); n++) {
        for(size_t a = 0; a < sizeof(arguments) / sizeof(arguments[0]); a++) {
            char name_before[48], args_before[64];
            strcpy(name_before, names[n]);
            if(arguments[a]) strcpy(args_before, arguments[a]);
            for(size_t s = 0; s < sizeof(statuses) / sizeof(statuses[0]); s++) {
                for(unsigned with_error = 0; with_error < 2; with_error++) {
                    FuriString error = {.marker = UINT32_C(0xABCDEF99)};
                    FuriString* error_pointer = with_error ? &error : NULL;
                    reset(statuses[s], errors[s]);
                    LoaderStatus returned = rpc ?
                        loader_start_from_rpc(&loader, names[n], arguments[a], error_pointer) :
                        loader_start(&loader, names[n], arguments[a], error_pointer);
                    assert(returned == statuses[s]);
                    check_message(names[n], arguments[a], error_pointer, rpc);
                    assert(strcmp(names[n], name_before) == 0);
                    if(arguments[a]) assert(strcmp(arguments[a], args_before) == 0);
                    if(!with_error) assert(error.marker == UINT32_C(0xABCDEF99));
                }
            }
        }
    }
}

static void internal_result(void) {
    const char name[] = "/ext/apps/Tools/lab.fap";
    const char args[] = "RPC custom context";
    for(size_t s = 0; s < sizeof(statuses) / sizeof(statuses[0]); s++) {
        for(size_t e = 0; e < sizeof(errors) / sizeof(errors[0]); e++) {
            for(unsigned require = 0; require < 2; require++) {
                FuriString error = {.marker = 1};
                reset(statuses[s], errors[e]);
                LoaderMessageLoaderStatusResult returned =
                    loader_start_internal(&loader, name, args, &error, require != 0);
                assert(returned.value == statuses[s] && returned.error == errors[e]);
                check_message(name, args, &error, require != 0);
            }
        }
    }
}

int main(int argc, char** argv) {
    // MinGW host harnesses can lose buffered stdout; the completion marker
    // remains mandatory and is emitted synchronously, without retrying tests.
    assert(setvbuf(stdout, NULL, _IONBF, 0) == 0);
    assert(argc == 2);
    if(strcmp(argv[1], "public") == 0) public_or_rpc(false);
    else if(strcmp(argv[1], "rpc") == 0) public_or_rpc(true);
    else if(strcmp(argv[1], "internal") == 0) internal_result();
    else assert(!"Unknown loader regression scenario");
    printf("Loader RPC entry scenario passed\n");
    return 0;
}
"""


class LoaderRpcEntryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        compiler = next(
            (found for name in ("cc", "gcc", "clang") if (found := shutil.which(name))),
            None,
        )
        if compiler is None and sys.platform == "win32":
            shim = ROOT.parent / "flipper-tools/cc.cmd"
            if shim.is_file():
                compiler = str(shim)
        if compiler is None:
            raise AssertionError("A host C compiler (cc, gcc or clang) is required")
        temporary = tempfile.TemporaryDirectory(prefix="loader-rpc-entry-")
        cls.addClassCleanup(temporary.cleanup)
        folder = Path(temporary.name)
        source = folder / "loader_rpc_entry.c"
        cls.executable = folder / (
            "loader_rpc_entry.exe" if sys.platform == "win32" else "loader_rpc_entry"
        )
        source.write_text(production_source(), encoding="utf-8")
        command = [compiler, "-std=c11", "-Wall", "-Wextra", "-Werror"]
        if sys.platform.startswith("linux"):
            command += [
                "-fsanitize=address,undefined",
                "-fno-sanitize-recover=all",
                "-O1",
            ]
        command += [str(source), "-o", str(cls.executable)]
        environment = os.environ.copy()
        environment["ZIG_GLOBAL_CACHE_DIR"] = str(folder / "zig-global-cache")
        environment["ZIG_LOCAL_CACHE_DIR"] = str(folder / "zig-local-cache")
        result = subprocess.run(
            command,
            cwd=ROOT,
            env=environment,
            capture_output=True,
            text=True,
            timeout=120,
        )
        if result.returncode != 0:
            raise AssertionError(
                f"Loader RPC harness failed to build:\n{result.stdout}{result.stderr}"
            )

    def run_scenario(self, scenario):
        result = subprocess.run(
            [str(self.executable), scenario], capture_output=True, text=True, timeout=30
        )
        self.assertEqual(
            result.returncode, 0, f"{scenario}:\n{result.stdout}{result.stderr}"
        )
        self.assertIn(
            "Loader RPC entry scenario passed",
            result.stdout,
            f"{scenario}: missing completion marker; stderr={result.stderr!r}",
        )

    def test_public_start_preserves_parameters_status_and_disables_api_requirement(
        self,
    ):
        self.run_scenario("public")

    def test_rpc_start_preserves_parameters_status_and_requires_api_match(self):
        self.run_scenario("rpc")

    def test_internal_start_returns_both_worker_result_fields_through_actual_pointer(
        self,
    ):
        self.run_scenario("internal")


if __name__ == "__main__":
    unittest.main()
