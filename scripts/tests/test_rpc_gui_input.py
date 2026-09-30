"""Compile the real RPC GUI input handler against recording host substitutes.

The handler, input enums/event layout, RPC contract assertions and protobuf
enum values come from this checkout. Only the surrounding types, assertions,
logging, response sender and input publisher are substituted. A host compiler
is required; this regression fails rather than silently skipping without one.
It does not exercise BLE, protobuf decoding, the GUI thread or a real device.
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
RPC_GUI = ROOT / "applications/services/rpc/rpc_gui.c"
INPUT = ROOT / "applications/services/input/input.h"
KEYS = ROOT / "targets/f7/furi_hal/furi_hal_resources.h"
GUI_PROTO = ROOT / "assets/protobuf_overrides/gui.proto"
MAIN_PROTO = ROOT / "assets/protobuf_overrides/flipper.proto"
HANDLER = "rpc_system_gui_send_input_event_request_process"


def section(text, start, end):
    begin = text.index(start)
    return text[begin : text.index(end, begin)]


def proto_enum(text, name, prefix):
    body = re.search(r"\benum\s+" + name + r"\s*\{(.*?)\}", text, re.S)
    if body is None:
        raise AssertionError(f"Missing production protobuf enum {name}")
    body = re.sub(r"/\*.*?\*/|//[^\n]*", "", body.group(1), flags=re.S)
    values = re.findall(r"\b([A-Z][A-Z0-9_]*)\s*=\s*(-?\d+)\s*;", body)
    if not values:
        raise AssertionError(f"No values in production protobuf enum {name}")
    entries = ",\n".join(f"    {prefix}_{key} = {value}" for key, value in values)
    return f"typedef enum {{\n{entries}\n}} {prefix};\n"


def production_source():
    rpc = RPC_GUI.read_text(encoding="utf-8")
    inputs = INPUT.read_text(encoding="utf-8")
    keys = KEYS.read_text(encoding="utf-8")
    gui_proto = GUI_PROTO.read_text(encoding="utf-8")
    main_proto = MAIN_PROTO.read_text(encoding="utf-8")
    function = re.search(
        r"static void\s+" + HANDLER + r"\([^)]*\)\s*\{.*?^\}", rpc, re.S | re.M
    )
    if function is None:
        raise AssertionError(f"Missing production handler {HANDLER}")
    tag = re.search(
        r"\bSendInputEventRequest\s+gui_send_input_event_request\s*=\s*(\d+)\s*;",
        main_proto,
    )
    reset = re.search(r"^#define RPC_GUI_INPUT_RESET[^\n]*", rpc, re.M)
    counter_mask = re.search(r"^#define RPC_GUI_INPUT_COUNTER_MASK[^\n]*", rpc, re.M)
    counters = re.search(
        r"    uint32_t input_key_counter\[InputKeyMAX\];\s*"
        r"    uint32_t input_counter;",
        rpc,
    )
    software_source = re.search(
        r"^#define INPUT_SEQUENCE_SOURCE_SOFTWARE[^\n]*", inputs, re.M
    )
    if any(
        value is None for value in (tag, reset, counter_mask, counters, software_source)
    ):
        raise AssertionError(
            "Missing production tag, reset, counter or source declaration"
        )
    return (
        INCLUDES
        + section(keys, "/* Input Keys */", "/* Light */")
        + section(inputs, "/** Input Types", "typedef enum {\n    AsciiValueNUL")
        + software_source.group(0)
        + "\n"
        + proto_enum(gui_proto, "InputKey", "PB_Gui_InputKey")
        + proto_enum(gui_proto, "InputType", "PB_Gui_InputType")
        + proto_enum(main_proto, "CommandStatus", "PB_CommandStatus")
        + section(rpc, "// Contract assertion", '#define TAG "RpcGui"')
        + f"#define PB_Main_gui_send_input_event_request_tag {tag.group(1)}\n"
        + reset.group(0)
        + "\n"
        + counter_mask.group(0)
        + "\n"
        + STUB_TYPES.replace("/* PRODUCTION_COUNTER_FIELDS */", counters.group(0))
        + RECORDING_STUBS
        + function.group(0)
        + "\n"
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
"""

STUB_TYPES = r"""
#define TAG "RpcGui"
#define furi_assert assert
#define FURI_LOG_D(tag, ...) ((void)(tag))
#define FURI_LOG_W(tag, ...) ((void)(tag), warning_count++)
typedef struct { uint32_t identity; } RpcSession;
typedef struct { uint32_t identity; } FuriPubSub;
typedef struct {
    uint32_t canary_before;
    RpcSession* session;
    FuriPubSub* input_events;
    /* PRODUCTION_COUNTER_FIELDS */
    uint32_t canary_after;
} RpcGuiSystem;
typedef struct {
    PB_Gui_InputKey key;
    PB_Gui_InputType type;
} PB_Gui_SendInputEventRequest;
typedef struct {
    uint32_t command_id;
    uint32_t which_content;
    union {
        PB_Gui_SendInputEventRequest gui_send_input_event_request;
    } content;
} PB_Main;
static RpcSession session;
static FuriPubSub input_events;
static RpcGuiSystem gui;
static InputEvent published;
static uint32_t publish_count, response_count, response_command, warning_count;
static PB_CommandStatus response_status;
"""

RECORDING_STUBS = r"""
static void rpc_send_and_release_empty(
    RpcSession* target, uint32_t command_id, PB_CommandStatus status) {
    assert(target == &session);
    response_count++;
    response_command = command_id;
    response_status = status;
}
static void furi_pubsub_publish(FuriPubSub* target, const void* event) {
    assert(target == &input_events);
    published = *(const InputEvent*)event;
    publish_count++;
}
"""

SCENARIOS = r"""
static void reset(void) {
    memset(&gui, 0, sizeof(gui));
    memset(&published, 0, sizeof(published));
    gui.canary_before = UINT32_C(0xDA7AFEED);
    gui.canary_after = UINT32_C(0xABCD1357);
    gui.session = &session;
    gui.input_events = &input_events;
    publish_count = response_count = response_command = warning_count = 0;
    response_status = PB_CommandStatus_ERROR;
}

static void send(int32_t key, int32_t type, PB_CommandStatus expected_status) {
    const uint32_t previous_responses = response_count;
    const uint32_t previous_publishes = publish_count;
    const uint32_t command_id = UINT32_C(0x10203000) + previous_responses;
    PB_Main request = {
        .command_id = command_id,
        .which_content = PB_Main_gui_send_input_event_request_tag,
        .content.gui_send_input_event_request = {
            .key = (PB_Gui_InputKey)key,
            .type = (PB_Gui_InputType)type,
        },
    };
    rpc_system_gui_send_input_event_request_process(&request, &gui);
    assert(response_count == previous_responses + 1);
    assert(response_command == command_id && response_status == expected_status);
    assert(publish_count == previous_publishes + (expected_status == PB_CommandStatus_OK));
    assert(gui.canary_before == UINT32_C(0xDA7AFEED));
    assert(gui.canary_after == UINT32_C(0xABCD1357));
    if(expected_status == PB_CommandStatus_OK) {
        assert((int32_t)published.key == key && (int32_t)published.type == type);
        assert(published.sequence_source == INPUT_SEQUENCE_SOURCE_SOFTWARE);
    }
}

static void accepted(int32_t key, int32_t type, uint32_t sequence) {
    send(key, type, PB_CommandStatus_OK);
    assert(published.sequence_counter == sequence);
}

static void rejected(int32_t key, int32_t type) {
    unsigned char before[sizeof(gui)], previous_event[sizeof(published)];
    memcpy(before, &gui, sizeof(gui));
    memcpy(previous_event, &published, sizeof(published));
    const uint32_t previous_warnings = warning_count;
    send(key, type, PB_CommandStatus_ERROR_INVALID_PARAMETERS);
    // In addition to no publication, no counter, key state or prior event may change.
    assert(memcmp(before, &gui, sizeof(gui)) == 0);
    assert(memcmp(previous_event, &published, sizeof(published)) == 0);
    assert(warning_count == previous_warnings);
}

static void legal_matrix(void) {
    for(int32_t key = 0; key < InputKeyMAX; key++) {
        for(int32_t type = 0; type < InputTypeMAX; type++) {
            reset();
            gui.input_counter = 41;
            for(int32_t other = 0; other < InputKeyMAX; other++) {
                gui.input_key_counter[other] = (uint32_t)(100 + other);
            }
            const uint32_t sequence = type == InputTypePress ? 42 : (uint32_t)(100 + key);
            accepted(key, type, sequence);
            assert(gui.input_counter == (type == InputTypePress ? 42u : 41u));
            for(int32_t other = 0; other < InputKeyMAX; other++) {
                const uint32_t expected = other != key ? (uint32_t)(100 + other) :
                    (type == InputTypeRelease ? RPC_GUI_INPUT_RESET : sequence);
                assert(gui.input_key_counter[other] == expected);
            }
            assert(warning_count == 0);
        }
    }
}

static void invalid_boundaries(void) {
    reset();
    accepted(InputKeyOk, InputTypePress, 1);
    const int32_t bad_keys[] = {-1, INT32_MIN, InputKeyMAX, InputKeyMAX + 1, INT32_MAX};
    const int32_t bad_types[] = {-1, INT32_MIN, InputTypeMAX, InputTypeMAX + 1, INT32_MAX};
    for(size_t i = 0; i < sizeof(bad_keys) / sizeof(bad_keys[0]); i++) {
        for(int32_t type = 0; type < InputTypeMAX; type++) rejected(bad_keys[i], type);
    }
    for(size_t i = 0; i < sizeof(bad_types) / sizeof(bad_types[0]); i++) {
        for(int32_t key = 0; key < InputKeyMAX; key++) rejected(key, bad_types[i]);
    }
    for(size_t i = 0; i < sizeof(bad_keys) / sizeof(bad_keys[0]); i++) {
        for(size_t j = 0; j < sizeof(bad_types) / sizeof(bad_types[0]); j++) {
            rejected(bad_keys[i], bad_types[j]);
        }
    }
    // Rejections while a button is held must not break its eventual release.
    accepted(InputKeyOk, InputTypeShort, 1);
    accepted(InputKeyOk, InputTypeRelease, 1);
    assert(gui.input_key_counter[InputKeyOk] == RPC_GUI_INPUT_RESET);
    assert(gui.input_counter == 1 && warning_count == 0);
}

static void press_short_release(void) {
    reset();
    accepted(InputKeyOk, InputTypePress, 1);
    accepted(InputKeyOk, InputTypeShort, 1);
    accepted(InputKeyOk, InputTypeRelease, 1);
    assert(gui.input_key_counter[InputKeyOk] == RPC_GUI_INPUT_RESET);
    accepted(InputKeyOk, InputTypePress, 2);
    accepted(InputKeyOk, InputTypeLong, 2);
    accepted(InputKeyOk, InputTypeRepeat, 2);
    accepted(InputKeyOk, InputTypeRelease, 2);
    assert(gui.input_counter == 2 && warning_count == 0);
}

static void independent_keys(void) {
    reset();
    accepted(InputKeyUp, InputTypePress, 1);
    accepted(InputKeyDown, InputTypePress, 2);
    accepted(InputKeyUp, InputTypeShort, 1);
    accepted(InputKeyDown, InputTypeLong, 2);
    accepted(InputKeyUp, InputTypeRelease, 1);
    assert(gui.input_key_counter[InputKeyUp] == RPC_GUI_INPUT_RESET);
    assert(gui.input_key_counter[InputKeyDown] == 2);
    accepted(InputKeyDown, InputTypeRepeat, 2);
    accepted(InputKeyDown, InputTypeRelease, 2);
    assert(gui.input_key_counter[InputKeyDown] == RPC_GUI_INPUT_RESET);
    accepted(InputKeyBack, InputTypePress, 3);
    accepted(InputKeyBack, InputTypeRelease, 3);
    assert(gui.input_counter == 3 && warning_count == 0);
}

static void uint32_wrap_skips_reset(void) {
    reset();
    gui.input_counter = UINT32_MAX;
    accepted(InputKeyBack, InputTypePress, 1);
    assert(gui.input_counter == 1 && gui.input_key_counter[InputKeyBack] == 1);
    accepted(InputKeyBack, InputTypeShort, 1);
    accepted(InputKeyBack, InputTypeRelease, 1);
    assert(gui.input_key_counter[InputKeyBack] == RPC_GUI_INPUT_RESET);
    accepted(InputKeyLeft, InputTypePress, 2);
    accepted(InputKeyLeft, InputTypeRelease, 2);
    assert(gui.input_counter == 2 && warning_count == 0);
}

static void event_sequence_wrap_skips_reset(void) {
    reset();
    // InputEvent's production declaration stores sequence_counter in 30 bits.
    // Reach its last representable value first, then start a fresh sequence.
    gui.input_counter = UINT32_C(0x3FFFFFFE);
    accepted(InputKeyOk, InputTypePress, UINT32_C(0x3FFFFFFF));
    assert(gui.input_counter == UINT32_C(0x3FFFFFFF));
    accepted(InputKeyOk, InputTypeShort, UINT32_C(0x3FFFFFFF));
    accepted(InputKeyOk, InputTypeRelease, UINT32_C(0x3FFFFFFF));
    assert(gui.input_key_counter[InputKeyOk] == RPC_GUI_INPUT_RESET);
    accepted(InputKeyBack, InputTypePress, 1);
    assert(gui.input_counter == 1 && gui.input_key_counter[InputKeyBack] == 1);
    accepted(InputKeyBack, InputTypeShort, 1);
    accepted(InputKeyBack, InputTypeRelease, 1);
    assert(gui.input_key_counter[InputKeyBack] == RPC_GUI_INPUT_RESET);
    assert(warning_count == 0);
}

static void out_of_sequence_compatibility(void) {
    reset();
    accepted(InputKeyRight, InputTypeShort, RPC_GUI_INPUT_RESET);
    assert(warning_count == 1 && gui.input_counter == 0);
    accepted(InputKeyRight, InputTypeRelease, RPC_GUI_INPUT_RESET);
    assert(warning_count == 2 && gui.input_counter == 0);
    accepted(InputKeyRight, InputTypePress, 1);
    accepted(InputKeyRight, InputTypeRelease, 1);
    assert(warning_count == 2 && gui.input_key_counter[InputKeyRight] == RPC_GUI_INPUT_RESET);
}

int main(int argc, char** argv) {
    assert(argc == 2);
    if(strcmp(argv[1], "legal") == 0) legal_matrix();
    else if(strcmp(argv[1], "invalid") == 0) invalid_boundaries();
    else if(strcmp(argv[1], "sequence") == 0) press_short_release();
    else if(strcmp(argv[1], "keys") == 0) independent_keys();
    else if(strcmp(argv[1], "wrap") == 0) uint32_wrap_skips_reset();
    else if(strcmp(argv[1], "event-wrap") == 0) event_sequence_wrap_skips_reset();
    else if(strcmp(argv[1], "stray") == 0) out_of_sequence_compatibility();
    else assert(!"Unknown regression scenario");
    puts("RPC GUI input scenario passed");
    return 0;
}
"""


class RpcGuiInputTests(unittest.TestCase):
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
        temporary = tempfile.TemporaryDirectory(prefix="rpc-gui-input-")
        cls.addClassCleanup(temporary.cleanup)
        folder = Path(temporary.name)
        source = folder / "rpc_gui_input.c"
        cls.executable = folder / (
            "rpc_gui_input.exe" if sys.platform == "win32" else "rpc_gui_input"
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
        # The local cc shim uses Zig; keep this build's caches with its temporary
        # harness rather than needing writable global caches under AppData.
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
                f"RPC input harness failed to build:\n{result.stdout}{result.stderr}"
            )

    def run_scenario(self, scenario):
        result = subprocess.run(
            [str(self.executable), scenario], capture_output=True, text=True, timeout=30
        )
        self.assertEqual(
            result.returncode,
            0,
            f"RPC input {scenario} failed:\n{result.stdout}{result.stderr}",
        )
        self.assertIn("RPC GUI input scenario passed", result.stdout)

    def test_all_six_keys_and_five_event_types(self):
        self.run_scenario("legal")

    def test_invalid_signed_and_maximum_values_preserve_state(self):
        self.run_scenario("invalid")

    def test_press_short_release_and_repeat_share_the_press_sequence(self):
        self.run_scenario("sequence")

    def test_overlapping_keys_keep_independent_sequences(self):
        self.run_scenario("keys")

    def test_uint32_counter_wrap_skips_zero(self):
        self.run_scenario("wrap")

    def test_30bit_event_sequence_wrap_skips_zero(self):
        self.run_scenario("event-wrap")

    def test_unsequenced_valid_events_keep_existing_warning_behavior(self):
        self.run_scenario("stray")


if __name__ == "__main__":
    unittest.main()
