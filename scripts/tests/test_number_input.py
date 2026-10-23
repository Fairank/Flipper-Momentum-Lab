"""Host regressions for the values the GUI NumberInput accepts.

The C test compiles number_input.c unchanged from its structs onwards, with
lib/toolbox/strint.c, the parser behind its range checks and its save key.
Keys are pressed and the view is drawn through the callbacks
number_input_alloc() registers, against small stand-ins for the view, the
canvas and FuriString that keep the model and record whether the save key is
drawn blocked. They do not replace a firmware build or a check on a Flipper.
"""

from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
GUI = "applications/services/gui"
NUMBER_INPUT_C = f"{GUI}/modules/number_input.c"
NUMBER_INPUT_H = f"{GUI}/modules/number_input.h"
CANVAS_H = f"{GUI}/canvas.h"
VIEW_H = f"{GUI}/view.h"
INPUT_H = "applications/services/input/input.h"
INPUT_KEYS_H = "targets/f7/furi_hal/furi_hal_resources.h"
CORE_DEFINES_H = "furi/core/core_defines.h"
STRINT_C = "lib/toolbox/strint.c"

# Firmware definitions number_input.c uses: file, start, text right after it
DECLARATIONS = [
    (CORE_DEFINES_H, "#ifndef MAX", "\n#ifndef ABS"),
    (CORE_DEFINES_H, "#ifndef CLAMP\n", "\n#ifndef CLAMP_WRAPAROUND"),
    (CORE_DEFINES_H, "#ifndef COUNT_OF", "\n#ifndef FURI_SWAP"),
    (CANVAS_H, "/** Color enumeration */", "\n/** Canvas anonymous structure */"),
    (INPUT_KEYS_H, "/* Input Keys */", "\n/* Light */"),
    (INPUT_H, "/** Input Types", "\ntypedef enum {\n    AsciiValueNUL"),
    (VIEW_H, "/** View model types */", "\n/** Allocate and init View"),
    (VIEW_H, "#define with_view_model(", "\n#endif"),
    (NUMBER_INPUT_H, "typedef struct NumberInput NumberInput;", "\n/** Allocate"),
]


def source_between(path, start, end=None):
    text = (ROOT / path).read_text(encoding="utf-8")
    begin = text.index(start)
    return text[begin : text.index(end, begin) if end else len(text)]


def native_test(source):
    compiler = shutil.which("cc")
    if compiler is None:
        raise AssertionError("A host C compiler is required")
    with tempfile.TemporaryDirectory() as folder:
        src = Path(folder) / "regression.c"
        exe = Path(folder) / "regression"
        src.write_text(source, encoding="utf-8")
        command = [compiler, "-std=c11", "-Wall", "-Wextra", "-Werror", "-I."]
        if sys.platform.startswith("linux"):
            # A sanitizer report ends the run instead of passing unseen in stderr
            command += [
                "-fsanitize=address,undefined",
                "-fno-sanitize-recover=all",
                "-fno-omit-frame-pointer",
                "-O1",
            ]
        command += [str(src), "-o", str(exe)]
        # Run from the repository root so the production sources resolve
        build = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        if build.returncode != 0:
            raise AssertionError(f"Native regression failed to build:\n{build.stderr}")
        result = subprocess.run([str(exe)], capture_output=True, text=True, timeout=120)
        if result.returncode != 0:
            raise AssertionError(
                f"Native regression returned {result.returncode}:\n"
                f"{result.stdout}{result.stderr}"
            )


INCLUDES = r"""
#undef NDEBUG
#include <assert.h>
#include <inttypes.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h> // strncasecmp() for strint.c under -std=c11
"""

STUBS = r"""
#define furi_assert(x) assert(x)
#define furi_check(x)  assert(x)
#define furi_crash()   abort()

// Icons only tell what the save key shows
typedef struct {
    bool save;
    bool blocked;
} Icon;

static const Icon I_KeySave_22x11 = {true, false};
static const Icon I_KeySaveSelected_22x11 = {true, false};
static const Icon I_KeySaveBlocked_22x11 = {true, true};
static const Icon I_KeySaveBlockedSelected_22x11 = {true, true};
static const Icon I_KeyBackspace_17x11 = {false, false};
static const Icon I_KeyBackspaceSelected_17x11 = {false, false};
static const Icon I_KeySign_21x11 = {false, false};
static const Icon I_KeySignSelected_21x11 = {false, false};

// Drawing records the save key; everything else draws nothing
typedef struct Canvas {
    size_t save_keys;
    bool save_blocked;
} Canvas;

static void canvas_draw_icon(Canvas* canvas, int32_t x, int32_t y, const Icon* icon) {
    (void)x;
    (void)y;
    if(icon->save) {
        canvas->save_keys++;
        canvas->save_blocked = icon->blocked;
    }
}

static void canvas_draw_str(Canvas* canvas, int32_t x, int32_t y, const char* str) {
    (void)canvas;
    (void)x;
    (void)y;
    (void)str;
}

static void canvas_draw_glyph(Canvas* canvas, int32_t x, int32_t y, uint16_t code) {
    (void)canvas;
    (void)x;
    (void)y;
    (void)code;
}

static void canvas_set_font(Canvas* canvas, Font font) {
    (void)canvas;
    (void)font;
}

static void canvas_set_color(Canvas* canvas, Color color) {
    (void)canvas;
    (void)color;
}

static void
    elements_slightly_rounded_frame(Canvas* canvas, int32_t x, int32_t y, size_t width, size_t height) {
    (void)canvas;
    (void)x;
    (void)y;
    (void)width;
    (void)height;
}

static void
    elements_slightly_rounded_box(Canvas* canvas, int32_t x, int32_t y, size_t width, size_t height) {
    (void)canvas;
    (void)x;
    (void)y;
    (void)width;
    (void)height;
}

typedef struct {
    char data[64];
    size_t size;
} FuriString;

static FuriString* furi_string_alloc(void) {
    FuriString* s = calloc(1, sizeof(FuriString));
    assert(s);
    return s;
}

static void furi_string_free(FuriString* s) {
    free(s);
}

static const char* furi_string_get_cstr(const FuriString* s) {
    return s->data;
}

static bool furi_string_empty(const FuriString* s) {
    return s->size == 0;
}

static int furi_string_cmp_str(const FuriString* s, const char str[]) {
    return strcmp(s->data, str);
}

// Codepoints: the bytes that do not continue a UTF-8 sequence
static size_t furi_string_utf8_length(FuriString* s) {
    size_t length = 0;
    for(size_t i = 0; i < s->size; i++) {
        if(((unsigned char)s->data[i] & 0xC0) != 0x80) length++;
    }
    return length;
}

// memmove: number_input.c shortens the string from its own buffer
static void furi_string_set_strn(FuriString* s, const char str[], size_t length) {
    assert(length < sizeof(s->data));
    memmove(s->data, str, length);
    s->size = length;
    s->data[length] = '\0';
}

static void furi_string_set_str(FuriString* s, const char str[]) {
    furi_string_set_strn(s, str, strlen(str));
}

// A _Generic macro in furi; number_input.c only sets C strings
static void furi_string_set(FuriString* s, const char str[]) {
    furi_string_set_str(s, str);
}

static void furi_string_cat_str(FuriString* s, const char str[]) {
    size_t length = strlen(str);
    assert(s->size + length < sizeof(s->data));
    memcpy(&s->data[s->size], str, length + 1);
    s->size += length;
}

// number_input.c only formats int32_t with "%ld", which is long on the firmware
static int furi_string_printf(FuriString* s, const char format[], ...) {
    assert(strcmp(format, "%ld") == 0);
    va_list args;
    va_start(args, format);
    int32_t value = va_arg(args, int32_t);
    va_end(args);
    int written = snprintf(s->data, sizeof(s->data), "%" PRId32, value);
    assert(written > 0 && (size_t)written < sizeof(s->data));
    s->size = (size_t)written;
    return written;
}

typedef struct View View;
typedef void (*ViewDrawCallback)(Canvas* canvas, void* model);
typedef bool (*ViewInputCallback)(InputEvent* event, void* context);

// Keeps the callbacks and the model, which is held between get and commit
struct View {
    void* context;
    void* model;
    ViewDrawCallback draw;
    ViewInputCallback input;
    bool locked;
};

static View* view_alloc(void) {
    View* view = calloc(1, sizeof(View));
    assert(view);
    return view;
}

static void view_free(View* view) {
    assert(!view->locked);
    free(view->model);
    free(view);
}

static void view_set_context(View* view, void* context) {
    view->context = context;
}

static void view_set_draw_callback(View* view, ViewDrawCallback callback) {
    view->draw = callback;
}

static void view_set_input_callback(View* view, ViewInputCallback callback) {
    view->input = callback;
}

static void view_allocate_model(View* view, ViewModelType type, size_t size) {
    (void)type;
    assert(!view->model);
    view->model = calloc(1, size);
    assert(view->model);
}

static void* view_get_model(View* view) {
    assert(view->model && !view->locked);
    view->locked = true;
    return view->model;
}

static void view_commit_model(View* view, bool update) {
    (void)update;
    assert(view->locked);
    view->locked = false;
}
"""

HARNESS = r"""
static size_t saved_count;
static int32_t saved_number;

// Result callback of every case; the context is where the number goes
static void record_result(void* context, int32_t number) {
    assert(context == &saved_number);
    saved_number = number;
    saved_count++;
}

static NumberInputModel* model_of(NumberInput* input) {
    return number_input_get_view(input)->model;
}

static const char* text_of(NumberInput* input) {
    return furi_string_get_cstr(model_of(input)->text_buffer);
}

static void start(NumberInput* input, int32_t number, int32_t min, int32_t max) {
    number_input_set_result_callback(input, record_result, &saved_number, number, min, max);
}

static void expect_text(NumberInput* input, const char* text) {
    if(strcmp(text_of(input), text) != 0) {
        fprintf(stderr, "field shows \"%s\", expected \"%s\"\n", text_of(input), text);
        abort();
    }
}

// The number the field holds and the text it shows for it
static void expect_field(NumberInput* input, int32_t number, const char* text) {
    expect_text(input, text);
    if(model_of(input)->current_number != number) {
        fprintf(
            stderr,
            "field \"%s\" holds %ld, expected %ld\n",
            text,
            (long)model_of(input)->current_number,
            (long)number);
        abort();
    }
}

// Selects the key with this symbol and presses OK through the view input callback
static void press(NumberInput* input, char symbol) {
    NumberInputModel* model = model_of(input);
    bool found = false;
    for(size_t row = 0; row < keyboard_row_count; row++) {
        const NumberInputKey* keys = number_input_get_row(row);
        for(size_t column = 0; column < number_input_get_row_size(row); column++) {
            if(!found && keys[column].text == symbol) {
                model->selected_row = row;
                model->selected_column = column;
                found = true;
            }
        }
    }
    // The sign key is only drawn, and reachable, when the range has both signs
    assert(found && (symbol != sign_symbol || number_input_use_sign(model)));
    View* view = number_input_get_view(input);
    InputEvent event = {.key = InputKeyOk, .type = InputTypeShort};
    size_t count = saved_count;
    bool consumed = view->input(&event, view->context);
    assert(consumed && !view->locked);
    assert(symbol == enter_symbol || saved_count == count); // only save reports a number
}

// Draws the view and tells whether the save key is drawn blocked
static bool save_key_blocked(NumberInput* input) {
    View* view = number_input_get_view(input);
    Canvas canvas = {0};
    view->draw(&canvas, view->model);
    assert(canvas.save_keys == 1);
    return canvas.save_blocked;
}

// Presses save: the callback gets the number exactly when it should, and the save key
// was drawn blocked exactly when it does not
static void check_save(NumberInput* input, bool should_save, int32_t number) {
    bool blocked = save_key_blocked(input);
    size_t count = saved_count;
    press(input, enter_symbol);
    bool saved = saved_count != count;
    bool ok = saved_count - count <= 1 && saved == should_save && blocked != should_save;
    if(ok && saved) {
        ok = saved_number == number && model_of(input)->current_number == number;
    }
    if(!ok) {
        fprintf(
            stderr,
            "\"%s\" in [%ld, %ld]: %u save(s), last %ld, save key %s; expected ",
            text_of(input),
            (long)model_of(input)->min_value,
            (long)model_of(input)->max_value,
            (unsigned)(saved_count - count),
            (long)saved_number,
            blocked ? "blocked" : "enabled");
        if(should_save) {
            fprintf(stderr, "one save of %ld\n", (long)number);
        } else {
            fprintf(stderr, "none and a blocked save key\n");
        }
        abort();
    }
}

static void expect_saved(NumberInput* input, int32_t number) {
    check_save(input, true, number);
}

static void expect_refused(NumberInput* input) {
    check_save(input, false, 0);
}
"""

MAIN = r"""
int main(void) {
    NumberInput* input = number_input_alloc();

    // A start of zero is clamped like any other: 1..26 starts at 1, which saves
    start(input, 0, 1, 26);
    expect_field(input, 1, "1");
    expect_saved(input, 1);
    start(input, -3, 1, 26);
    expect_field(input, 1, "1");
    start(input, 99, 1, 26);
    expect_field(input, 26, "26");
    expect_saved(input, 26);
    start(input, 7, 1, 26);
    expect_field(input, 7, "7");
    expect_saved(input, 7);

    // A negative-only range starts at its end nearest zero, and its sign stays
    start(input, 0, -10, -5);
    expect_field(input, -5, "-5");
    expect_saved(input, -5);
    press(input, backspace_symbol);
    expect_text(input, "-");
    expect_refused(input);
    press(input, backspace_symbol);
    expect_text(input, "-");
    press(input, '1');
    expect_text(input, "-1"); // above the range, but on the way to -10
    expect_refused(input);
    press(input, '0');
    expect_saved(input, -10);
    press(input, '0');
    expect_field(input, -10, "-10"); // -100 is not taken
    start(input, INT32_MAX, -10, -5);
    expect_field(input, -5, "-5");
    start(input, INT32_MIN, -10, -5);
    expect_field(input, -10, "-10");
    expect_saved(input, -10);

    // Zero shows as an empty field, which saves as zero where zero is in range
    start(input, 0, 0, 26);
    expect_field(input, 0, "");
    expect_saved(input, 0);
    start(input, 0, -10, 10);
    expect_field(input, 0, "");
    expect_saved(input, 0);
    start(input, 0, -10, 0);
    expect_field(input, 0, "");
    expect_saved(input, 0);
    start(input, 7, 0, 26);
    press(input, backspace_symbol);
    expect_text(input, "");
    expect_saved(input, 0);

    // ... and is refused where zero is out of range, like a typed 0
    start(input, 7, 1, 26);
    press(input, backspace_symbol);
    expect_text(input, "");
    expect_refused(input);
    press(input, '0');
    expect_text(input, "0");
    expect_refused(input);
    press(input, '9');
    expect_saved(input, 9);

    // With both signs, a sign alone is refused until digits follow
    start(input, 0, -10, 10);
    press(input, sign_symbol);
    expect_text(input, "-");
    expect_refused(input);
    press(input, '7');
    expect_saved(input, -7);
    press(input, sign_symbol);
    expect_field(input, 7, "7");
    expect_saved(input, 7);

    // The int32 limits save; a digit past them is not taken
    start(input, 214748364, INT32_MIN, INT32_MAX);
    press(input, '8');
    expect_field(input, 214748364, "214748364");
    press(input, '7');
    expect_saved(input, INT32_MAX);
    start(input, -214748364, INT32_MIN, INT32_MAX);
    press(input, '9');
    expect_field(input, -214748364, "-214748364");
    press(input, '8');
    expect_saved(input, INT32_MIN);
    start(input, INT32_MAX, INT32_MIN, INT32_MAX);
    expect_saved(input, INT32_MAX);
    start(input, INT32_MIN, INT32_MIN, INT32_MAX);
    expect_saved(input, INT32_MIN);
    press(input, sign_symbol);
    expect_field(input, INT32_MIN, "-2147483648");
    expect_saved(input, INT32_MIN);
    start(input, INT32_MAX, INT32_MIN, INT32_MAX);
    press(input, sign_symbol);
    expect_field(input, -INT32_MAX, "-2147483647");
    expect_saved(input, -INT32_MAX);
    start(input, 0, INT32_MIN, INT32_MAX);
    expect_saved(input, 0);
    start(input, 0, INT32_MAX, INT32_MAX);
    expect_field(input, INT32_MAX, "2147483647");
    expect_saved(input, INT32_MAX);
    start(input, 0, INT32_MIN, INT32_MIN);
    expect_field(input, INT32_MIN, "-2147483648");
    expect_saved(input, INT32_MIN);

    // Text the keys can't produce is refused too: misplaced signs, numbers past int64,
    // numbers that would only land in the range if narrowed to int32 first, and an
    // empty field in a range without zero
    static const struct {
        const char* text;
        int32_t min;
        int32_t max;
    } refused[] = {
        {"--1", INT32_MIN, INT32_MAX},
        {"+-1", INT32_MIN, INT32_MAX},
        {"99999999999999999999", INT32_MIN, INT32_MAX},
        {"-99999999999999999999", INT32_MIN, INT32_MAX},
        {"18446744073709551617", 1, 26}, // 2^64 + 1
        {"4294967297", 1, 26}, // 2^32 + 1
        {"-4294967295", 1, 26}, // 1 - 2^32
        {"", -10, -5},
    };
    for(size_t i = 0; i < COUNT_OF(refused); i++) {
        start(input, refused[i].min, refused[i].min, refused[i].max);
        furi_string_set(model_of(input)->text_buffer, refused[i].text);
        expect_refused(input);
    }

    number_input_free(input);
    return 0;
}
"""


class NumberInputValueTests(unittest.TestCase):
    def test_start_is_clamped_and_save_takes_only_numbers_in_range(self):
        native_test(
            INCLUDES
            + f'#include "{STRINT_C}"\n'
            + f'#include "{GUI}/utf8_internal.h"\n'
            + "\n".join(source_between(*part) for part in DECLARATIONS)
            + STUBS
            + source_between(NUMBER_INPUT_C, "struct NumberInput {")
            + HARNESS
            + MAIN
        )


if __name__ == "__main__":
    unittest.main()
