"""Host regressions for UTF-8 line wrapping in the GUI TextBox.

The C tests compile the private UTF-8 decoder header and the TextBox seek and
screen text functions unchanged, with a Canvas that has fixed glyph widths and a
small FuriString. They do not replace a firmware build or a check on a Flipper,
whose stock fonts have no CJK glyphs.
"""

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
HEADER = "applications/services/gui/utf8_internal.h"
TEXT_BOX = "applications/services/gui/modules/text_box.c"
TEXT_BOX_H = "applications/services/gui/modules/text_box.h"
REPLACEMENT = 0xFFFD
# Test font: ASCII 6 px, CJK ideographs 12 px, U+FFFD 8 px, WIDE 200 px (wider than
# the 120 px text area) and 0xF600 9 px, the glyph u8g2 draws for EMOJI (U+1F600)
WIDE = chr(0x2588)
EMOJI = chr(0x1F600)

DECODER_VECTORS = [
    # Bytes (the decoder stops at the first NUL), bytes consumed, codepoint
    (b"", 0, 0),
    (b"A", 1, 0x41),
    (b"\n", 1, 0x0A),
    (b"\x7f", 1, 0x7F),
    (b"\xc2\x80", 2, 0x80),
    (b"\xdf\xbf", 2, 0x7FF),
    (b"\xe0\xa0\x80", 3, 0x800),
    ("中".encode(), 3, 0x4E2D),
    (b"\xed\x9f\xbf", 3, 0xD7FF),
    (b"\xee\x80\x80", 3, 0xE000),
    (b"\xef\xbf\xbd", 3, REPLACEMENT),
    (b"\xef\xbf\xbf", 3, 0xFFFF),
    (b"\xf0\x90\x80\x80", 4, 0x10000),
    (EMOJI.encode(), 4, 0x1F600),
    (b"\xf4\x8f\xbf\xbf", 4, 0x10FFFF),
    # Overlong forms
    (b"\xc0\x80", 1, REPLACEMENT),
    (b"\xc1\xbf", 1, REPLACEMENT),
    (b"\xe0\x9f\xbf", 1, REPLACEMENT),
    (b"\xf0\x8f\xbf\xbf", 1, REPLACEMENT),
    # Surrogates, beyond U+10FFFF, and bytes that never start a sequence
    (b"\xed\xa0\x80", 1, REPLACEMENT),
    (b"\xed\xbf\xbf", 1, REPLACEMENT),
    (b"\xf4\x90\x80\x80", 1, REPLACEMENT),
    (b"\xf5\x80\x80\x80", 1, REPLACEMENT),
    (b"\xf8\x88\x80\x80\x80", 1, REPLACEMENT),
    (b"\xff", 1, REPLACEMENT),
    (b"\x80", 1, REPLACEMENT),
    (b"\xbf\x80", 1, REPLACEMENT),
    # Invalid continuation bytes
    (b"\xc2A", 1, REPLACEMENT),
    (b"\xe4\xb8A", 1, REPLACEMENT),
    (b"\xf0\x9f\x98A", 1, REPLACEMENT),
    (b"\xe4\xc0\x80", 1, REPLACEMENT),
    # Cut short by the terminator, with continuation bytes after it
    (b"\xc2\x00\xa9", 1, REPLACEMENT),
    (b"\xe4\x00\xb8\xad", 1, REPLACEMENT),
    (b"\xe4\xb8\x00\xad", 1, REPLACEMENT),
    (b"\xf0\x9f\x98\x00\x80", 1, REPLACEMENT),
]

WRAP_CASES = [
    # Text, whether it is valid UTF-8, expected line start byte offsets up to the end
    ("a" * 45, True, [0, 20, 40, 45]),
    ("中" * 25, True, [0, 30, 60, 75]),
    ("a" * 18 + "中文b", True, [0, 21, 25]),
    ("a" * 19 + "中文" + "b" * 17 + "字", True, [0, 19, 41, 45]),
    ("\n\nA\n\n中\n\n", True, [0, 1, 2, 4, 5, 9, 10]),
    (WIDE + "ab" + WIDE + "\n" + WIDE * 2, True, [0, 3, 5, 9, 12, 15]),
    (EMOJI * 14, True, [0, 52, 56]),
    ("", True, [0]),
    (b"\xe4\xb8" * 10 + b"a", False, [0, 15, 21]),
    (
        b"\xc0\x80\xed\xa0\x80\xf4\x90\x80\x80\xff" + "中".encode() * 8 + b"\xe4\xb8",
        False,
        [0, 19, 36],
    ),
]

TEXT_BOX_PARTS = [
    # File, start of the production code to compile, text right after it
    (TEXT_BOX, "#define TEXT_BOX_TEXT_WIDTH", "\nstruct TextBox {"),
    (TEXT_BOX_H, "typedef enum {", "\n/** Allocate"),
    (TEXT_BOX, "typedef struct {", "\nstatic void text_box_process_down("),
    (
        TEXT_BOX,
        "static bool text_box_end_of_text_reached(",
        "\nstatic void text_box_view_draw_callback(",
    ),
]


def source_between(path, start, end=None):
    text = (ROOT / path).read_text(encoding="utf-8")
    begin = text.index(start)
    return text[begin : text.index(end, begin) if end else len(text)]


def c_string(data):
    """C literal of UTF-8 text or raw bytes, escaped so the C source stays ASCII."""
    if isinstance(data, str):
        data = data.encode("utf-8")
    escaped = "".join(chr(b) if bytes([b]).isalnum() else f"\\{b:03o}" for b in data)
    return f'"{escaped}"'


def c_wrap_case(text, valid, starts):
    fields = [c_string(text), str(valid).lower(), str(len(starts))]
    return "    {" + ", ".join(fields) + ", {" + ", ".join(map(str, starts)) + "}},\n"


def c_constant(name, value):
    return f"static const char {name}[] = {c_string(value)};\n"


def python_decode(data):
    """Reference decode with Python's strict codec: (bytes consumed, codepoint)."""
    data = data.split(b"\0", 1)[0]
    if not data:
        return 0, 0
    for size in range(1, min(len(data), 4) + 1):
        try:
            return size, ord(data[:size].decode("utf-8"))
        except UnicodeDecodeError:
            pass
    return 1, REPLACEMENT


def native_test(source):
    compiler = shutil.which("cc")
    if compiler is None:
        raise unittest.SkipTest("A host C compiler is required")
    with tempfile.TemporaryDirectory() as folder:
        src = Path(folder) / "regression.c"
        exe = Path(folder) / "regression"
        src.write_text(source, encoding="utf-8")
        # Run from the repository root so HEADER resolves to the production file
        build = subprocess.run(
            [
                compiler,
                "-std=c11",
                "-Wall",
                "-Wextra",
                "-Werror",
                "-I.",
                str(src),
                "-o",
                str(exe),
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        if build.returncode != 0:
            raise AssertionError(f"Native regression failed to build:\n{build.stderr}")
        result = subprocess.run(
            [str(exe)], capture_output=True, text=True, timeout=120
        )
        if result.returncode != 0:
            raise AssertionError(
                f"Native regression returned {result.returncode}:\n"
                f"{result.stdout}{result.stderr}"
            )


DECODER_HELPERS = r"""
#undef NDEBUG
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

// Shortest UTF-8 form of a scalar value, the reference for the sweeps below
static size_t encode(uint32_t codepoint, unsigned char* out) {
    if(codepoint < 0x80) {
        out[0] = codepoint;
        return 1;
    } else if(codepoint < 0x800) {
        out[0] = 0xC0 | (codepoint >> 6);
        out[1] = 0x80 | (codepoint & 0x3F);
        return 2;
    } else if(codepoint < 0x10000) {
        out[0] = 0xE0 | (codepoint >> 12);
        out[1] = 0x80 | ((codepoint >> 6) & 0x3F);
        out[2] = 0x80 | (codepoint & 0x3F);
        return 3;
    }
    out[0] = 0xF0 | (codepoint >> 18);
    out[1] = 0x80 | ((codepoint >> 12) & 0x3F);
    out[2] = 0x80 | ((codepoint >> 6) & 0x3F);
    out[3] = 0x80 | (codepoint & 0x3F);
    return 4;
}

static void check(const char* text, size_t size, uint32_t codepoint) {
    uint32_t decoded = 0xDEADBEEF;
    size_t consumed = gui_utf8_decode(text, &decoded);
    if(consumed != size || decoded != codepoint) {
        fprintf(
            stderr,
            "expected %u byte(s) U+%04lX, got %u byte(s) U+%04lX\n",
            (unsigned)size,
            (unsigned long)codepoint,
            (unsigned)consumed,
            (unsigned long)decoded);
    }
    assert(consumed == size && decoded == codepoint);
}
"""

DECODER_SWEEPS = r"""
    // Every scalar value is accepted in its shortest form
    for(uint32_t codepoint = 1; codepoint <= 0x10FFFF; codepoint++) {
        if(codepoint >= 0xD800 && codepoint <= 0xDFFF) continue;
        char text[5] = {0};
        size_t size = encode(codepoint, (unsigned char*)text);
        check(text, size, codepoint);
    }

    // Any three leading bytes: progress, nothing consumed past NUL, only shortest forms
    for(unsigned first = 1; first < 0x100; first++) {
        for(unsigned second = 0; second < 0x100; second++) {
            for(unsigned third = 0; third < 0x100; third++) {
                const char text[] = {
                    (char)first, (char)second, (char)third, (char)0x80, 0, (char)0x80};
                uint32_t codepoint = 0;
                size_t size = gui_utf8_decode(text, &codepoint);
                unsigned char shortest[4];
                bool ok = size >= 1 && size <= strlen(text);
                if(first < 0x80) {
                    ok = ok && size == 1 && codepoint == first;
                } else if(size == 1) {
                    ok = ok && codepoint == GUI_UTF8_REPLACEMENT_CHARACTER;
                } else {
                    ok = ok && codepoint <= 0x10FFFF &&
                         (codepoint < 0xD800 || codepoint > 0xDFFF) &&
                         encode(codepoint, shortest) == size &&
                         memcmp(shortest, text, size) == 0;
                }
                if(!ok) fprintf(stderr, "bytes %02X %02X %02X\n", first, second, third);
                assert(ok);
            }
        }
    }
    return 0;
}
"""

TEXT_BOX_STUBS = r"""
#undef NDEBUG
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct {
    size_t font_height;
    size_t measured;
    uint16_t symbols[8];
} Canvas;

static size_t canvas_glyph_width(Canvas* canvas, uint16_t symbol) {
    if(canvas->measured < 8) canvas->symbols[canvas->measured] = symbol;
    canvas->measured++;
    if(symbol >= 0x20 && symbol < 0x7F) return 6;
    if(symbol >= 0x4E00 && symbol <= 0x9FFF) return 12;
    if(symbol == 0x2588) return 200;
    if(symbol == 0xF600) return 9;
    if(symbol == 0xFFFD) return 8;
    return 0;
}

static size_t canvas_current_font_height(const Canvas* canvas) {
    return canvas->font_height;
}

typedef struct {
    char data[512];
    size_t size;
} FuriString;

static void furi_string_reset(FuriString* s) {
    s->size = 0;
    s->data[0] = '\0';
}

static void furi_string_set_strn(FuriString* s, const char str[], size_t length) {
    assert(length < sizeof(s->data));
    memcpy(s->data, str, length);
    s->size = length;
    s->data[length] = '\0';
}

static size_t furi_string_size(const FuriString* s) {
    return s->size;
}

static char furi_string_get_char(const FuriString* s, size_t index) {
    assert(index < s->size); // m-string asserts the same bound
    return s->data[index];
}

static void furi_string_push_back(FuriString* s, char c) {
    assert(s->size + 1 < sizeof(s->data));
    s->data[s->size++] = c;
    s->data[s->size] = '\0';
}

static void furi_string_cat(FuriString* s, const FuriString* other) {
    assert(s->size + other->size < sizeof(s->data));
    memcpy(&s->data[s->size], other->data, other->size + 1);
    s->size += other->size;
}
"""

TEXT_BOX_HARNESS = r"""
static Canvas test_canvas;
static FuriString test_screen, test_line;

static void model_init(TextBoxModel* model, const char* text) {
    memset(model, 0, sizeof(*model));
    model->text = text;
    model->text_on_screen = &test_screen;
    model->text_line = &test_line;
}

typedef struct {
    const char* text;
    bool valid_utf8;
    size_t count;
    int32_t starts[8];
} WrapCase;

static bool is_continuation(char c) {
    return ((unsigned char)c & 0xC0) == 0x80;
}

// Seek over every line forward, then back, comparing with the expected line starts
static void check_wrap(const WrapCase* wrap) {
    TextBoxModel model;
    model_init(&model, wrap->text);
    int32_t lines = (int32_t)wrap->count - 1;
    assert(wrap->starts[lines] == (int32_t)strlen(wrap->text));

    for(int32_t i = 1; i <= lines; i++) {
        text_box_seek_next_line(&test_canvas, &model);
        assert(model.text_offset == wrap->starts[i]);
        assert(!wrap->valid_utf8 || !is_continuation(wrap->text[model.text_offset]));
    }
    text_box_seek_next_line(&test_canvas, &model);
    assert(model.text_offset == wrap->starts[lines]);

    for(int32_t i = lines; i > 0; i--) {
        model.text_offset = wrap->starts[i];
        text_box_seek_prev_line(&test_canvas, &model);
        assert(model.text_offset == wrap->starts[i - 1]);
    }
    text_box_seek_prev_line(&test_canvas, &model);
    assert(model.text_offset == 0);

    text_box_move_line_offset(&test_canvas, &model, lines);
    assert(model.text_offset == wrap->starts[lines]);
    text_box_move_line_offset(&test_canvas, &model, -lines);
    assert(model.text_offset == 0);
}

static const WrapCase wrap_cases[] = {
"""

TEXT_BOX_MAIN = r"""
int main(void) {
    test_canvas.font_height = 8;
    for(size_t i = 0; i < sizeof(wrap_cases) / sizeof(wrap_cases[0]); i++) {
        fprintf(stderr, "wrap case %u\n", (unsigned)i);
        check_wrap(&wrap_cases[i]);
    }

    // BMP is measured as decoded, non-BMP as u8g2 draws it, malformed bytes as U+FFFD
    TextBoxModel model;
    model_init(&model, MEASURED);
    test_canvas.measured = 0;
    text_box_seek_next_line(&test_canvas, &model);
    assert(model.text_offset == 11 && test_canvas.measured == 5);
    assert(test_canvas.symbols[0] == 'a' && test_canvas.symbols[1] == 0xA9);
    assert(test_canvas.symbols[2] == 0x4E2D && test_canvas.symbols[3] == 0xF600);
    assert(test_canvas.symbols[4] == 0xFFFD);

    // Empty text, and a screen starting at the end of text, show one empty line
    model_init(&model, "");
    text_box_prepare_model(&test_canvas, &model);
    assert(model.text_offset == 0 && model.scroll_num == 0 && model.scroll_pos == 0);
    assert(strcmp(test_screen.data, "\n") == 0);
    model_init(&model, "abc");
    model.lines_on_screen = 7;
    model.text_offset = 3;
    text_box_update_screen_text(&test_canvas, &model);
    assert(model.text_offset == 3 && strcmp(test_screen.data, "\n") == 0);

    // ASCII focus and scrolling are unchanged
    model_init(&model, ASCII_TEXT);
    text_box_prepare_model(&test_canvas, &model);
    assert(model.lines_on_screen == 7 && model.scroll_num == 6 && model.scroll_pos == 0);
    assert(model.text_offset == 0 && strcmp(test_screen.data, ASCII_TOP) == 0);
    model_init(&model, ASCII_TEXT);
    model.focus = TextBoxFocusEnd;
    text_box_prepare_model(&test_canvas, &model);
    assert(model.scroll_num == 6 && model.scroll_pos == 5 && model.line_offset == 5);
    assert(model.text_offset == 20 && strcmp(test_screen.data, ASCII_BOTTOM) == 0);
    model.scroll_pos = 2;
    text_box_update_text_on_screen(&test_canvas, &model);
    assert(model.line_offset == 2 && model.text_offset == 8);
    assert(strcmp(test_screen.data, ASCII_MIDDLE) == 0);
    model.scroll_pos = 5;
    text_box_update_text_on_screen(&test_canvas, &model);
    assert(model.text_offset == 20 && strcmp(test_screen.data, ASCII_BOTTOM) == 0);

    // CJK screen lines are cut between characters, also after scrolling back
    model_init(&model, CJK_TEXT);
    model.focus = TextBoxFocusEnd;
    text_box_prepare_model(&test_canvas, &model);
    assert(model.scroll_num == 2 && model.scroll_pos == 1 && model.text_offset == 30);
    assert(strcmp(test_screen.data, CJK_BOTTOM) == 0);
    model.scroll_pos = 0;
    text_box_update_text_on_screen(&test_canvas, &model);
    assert(model.text_offset == 0 && strcmp(test_screen.data, CJK_TOP) == 0);

    // A glyph wider than the text area gets a line instead of stalling the layout
    model_init(&model, WIDE_TEXT);
    text_box_prepare_model(&test_canvas, &model);
    assert(model.scroll_num == 0 && strcmp(test_screen.data, WIDE_SCREEN) == 0);
    return 0;
}
"""


class TextBoxUtf8Tests(unittest.TestCase):
    def test_decoder_vectors_agree_with_python_codec(self):
        for data, size, codepoint in DECODER_VECTORS:
            with self.subTest(data=data):
                self.assertEqual(python_decode(data), (size, codepoint))

    def test_decoder_is_strict_and_stops_at_the_terminator(self):
        vectors = "".join(
            f"    check({c_string(data)}, {size}, 0x{codepoint:X});\n"
            for data, size, codepoint in DECODER_VECTORS
        )
        native_test(
            f'#include "{HEADER}"\n'
            + DECODER_HELPERS
            + "int main(void) {\n"
            + vectors
            + DECODER_SWEEPS
        )

    def test_text_box_seeks_and_scrolls_by_whole_codepoints(self):
        lines = [f"L{i:02}\n" for i in range(12)]
        cjk_line = "中" * 10 + "\n"
        constants = {
            "MEASURED": ("a" + chr(0xA9) + "中" + EMOJI).encode() + b"\xff",
            "ASCII_TEXT": "".join(lines).rstrip("\n"),
            "ASCII_TOP": "".join(lines[0:7]),
            "ASCII_MIDDLE": "".join(lines[2:9]),
            "ASCII_BOTTOM": "".join(lines[5:12]),
            "CJK_TEXT": "中" * 75,
            "CJK_TOP": cjk_line * 7,
            "CJK_BOTTOM": cjk_line * 6 + "中" * 5 + "\n",
            "WIDE_TEXT": "ab" + WIDE + "c",
            "WIDE_SCREEN": "ab\n" + WIDE + "\nc\n",
        }
        native_test(
            f'#include "{HEADER}"\n'
            + TEXT_BOX_STUBS
            + "".join(source_between(*part) for part in TEXT_BOX_PARTS)
            + TEXT_BOX_HARNESS
            + "".join(c_wrap_case(*case) for case in WRAP_CASES)
            + "};\n"
            + "".join(c_constant(*item) for item in constants.items())
            + TEXT_BOX_MAIN
        )


if __name__ == "__main__":
    unittest.main()
