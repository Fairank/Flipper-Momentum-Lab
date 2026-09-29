"""Host regressions for native CJK text in the GUI service.

The C tests compile the production text functions of canvas.c, elements.c and
text_box.c unchanged, against small stand-ins for u8g2, FuriString and the
Canvas drawing calls that record what would be drawn. Stub fonts have fixed
metrics (stock ASCII 6 px, native CJK 12 px). They do not replace a firmware
build or a look at a Flipper screen, and they do not check the generated font
data itself except through the Python test at the end, which only runs once
scripts/generate_native_zh_font.py has written native_zh_font.h.
"""

import importlib.util
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
GUI = "applications/services/gui"
HEADER = f"{GUI}/utf8_internal.h"
CANVAS_C = f"{GUI}/canvas.c"
CANVAS_H = f"{GUI}/canvas.h"
ELEMENTS_C = f"{GUI}/elements.c"
ELEMENTS_H = f"{GUI}/elements.h"
TEXT_BOX = f"{GUI}/modules/text_box.c"
TEXT_BOX_H = f"{GUI}/modules/text_box.h"
NATIVE_FONT_H = f"{GUI}/native_zh_font.h"
CORE_DEFINES_H = "furi/core/core_defines.h"
GENERATOR = ROOT / "scripts" / "generate_lab_font.py"

ESC = "\x1b"


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


def c_constant(name, value):
    # Shared vectors are used by different harnesses; macros avoid unused-object
    # warnings without disabling compiler diagnostics for production code.
    return f"#define {name} {c_string(value)}\n"


def c_constants(items):
    return "".join(c_constant(name, value) for name, value in items.items())


def native_test(source, link_math=False):
    compiler = shutil.which("cc")
    if compiler is None:
        raise unittest.SkipTest("A host C compiler is required")
    with tempfile.TemporaryDirectory() as folder:
        src = Path(folder) / "regression.c"
        exe = Path(folder) / "regression"
        src.write_text(source, encoding="utf-8")
        command = [compiler, "-std=c11", "-Wall", "-Wextra", "-Werror", "-I."]
        if sys.platform.startswith("linux"):
            command += [
                "-fsanitize=address,undefined",
                "-fno-omit-frame-pointer",
                "-O1",
            ]
        command += [str(src), "-o", str(exe)]
        if link_math:
            command.append("-lm")
        # Run from the repository root so the production header resolves
        build = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        if build.returncode != 0:
            raise AssertionError(f"Native regression failed to build:\n{build.stderr}")
        result = subprocess.run([str(exe)], capture_output=True, text=True, timeout=120)
        if result.returncode != 0:
            raise AssertionError(
                f"Native regression returned {result.returncode}:\n"
                f"{result.stdout}{result.stderr}"
            )


def canvas_enums():
    """Color, Font, Align and the other plain types of canvas.h."""
    return source_between(
        CANVAS_H, "/** Color enumeration */", "\n/** Canvas anonymous structure */"
    )


COMMON_INCLUDES = r"""
#undef NDEBUG
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
"""

HELPERS_MAIN = r"""
int main(void) {
    // ASCII detection and the codepoint ranges scripts/generate_native_zh_font.py collects
    assert(gui_utf8_is_ascii("") && gui_utf8_is_ascii("plain ASCII\n\x7f"));
    assert(!gui_utf8_is_ascii(ZHONG) && !gui_utf8_is_ascii(LATIN));
    assert(!gui_utf8_is_cjk(0x2FFF) && gui_utf8_is_cjk(0x3000));
    assert(gui_utf8_is_cjk(0x9FFF) && !gui_utf8_is_cjk(0xA000));
    assert(!gui_utf8_is_cjk(0xFF00) && gui_utf8_is_cjk(0xFF01));
    assert(gui_utf8_is_cjk(0xFFEF) && !gui_utf8_is_cjk(0xFFF0));
    assert(!gui_utf8_is_cjk('A') && !gui_utf8_is_cjk(0x2190) && !gui_utf8_is_cjk(0xFFFD));
    assert(gui_utf8_has_cjk(A_ZHONG_B) && !gui_utf8_has_cjk("abc") && !gui_utf8_has_cjk(LATIN));

    // A_ZHONG_B is 'a', the three bytes of U+4E2D, 'b'
    for(size_t offset = 0; offset <= 5; offset++) {
        size_t expected = offset <= 1 ? offset : offset <= 3 ? 1 : offset;
        assert(gui_utf8_floor(A_ZHONG_B, offset) == expected);
    }
    assert(gui_utf8_prev_start(A_ZHONG_B, 0) == 0 && gui_utf8_prev_start(A_ZHONG_B, 1) == 0);
    assert(gui_utf8_prev_start(A_ZHONG_B, 2) == 1 && gui_utf8_prev_start(A_ZHONG_B, 4) == 1);
    assert(gui_utf8_prev_start(A_ZHONG_B, 5) == 4);
    assert(gui_utf8_offset(A_ZHONG_B, 0) == 0 && gui_utf8_offset(A_ZHONG_B, 1) == 1);
    assert(gui_utf8_offset(A_ZHONG_B, 2) == 4 && gui_utf8_offset(A_ZHONG_B, 3) == 5);
    assert(gui_utf8_offset(A_ZHONG_B, 9) == 5);

    // Row spacing grows to the CJK minimum only for Chinese text and small fonts
    assert(gui_utf8_line_height(8, "abc") == 8 && gui_utf8_line_height(8, LATIN) == 8);
    assert(gui_utf8_line_height(8, ZHONG) == GUI_CJK_LINE_HEIGHT);
    assert(gui_utf8_line_height(15, ZHONG) == 15);
    assert(GUI_CJK_LINE_HEIGHT >= 12 && GUI_CJK_LINE_LEADING > GUI_CJK_LINE_HEIGHT);
    assert(GUI_CJK_GLYPH_ASCENT + GUI_CJK_GLYPH_DESCENT <= GUI_CJK_LINE_HEIGHT);
    return 0;
}
"""

CANVAS_STUBS = r"""
#define furi_check(x) assert(x)
#define furi_crash() abort()

typedef uint16_t u8g2_uint_t;

// The u8g2 state canvas.c reads and writes
typedef struct {
    const uint8_t* font;
    struct {
        uint8_t dir;
        int8_t glyph_width;
    } font_decode;
    int8_t glyph_x_offset;
    int8_t font_ref_ascent;
} u8g2_t;

#define u8g2_GetAscent(u8g2) ((u8g2)->font_ref_ascent)

typedef struct {
    u8g2_t fb;
    size_t offset_x;
    size_t offset_y;
} Canvas;

// Stand-ins for the generated array and for two selectable fonts
static const uint8_t native_zh_font[] = {0xAC};
static const uint8_t font_stock[] = {1}; // ASCII only, like the stock fonts
static const uint8_t font_custom[] = {2}; // ASCII plus its own glyph for U+4E2D

typedef struct {
    uint8_t advance;
    uint8_t width;
    int8_t x;
} StubGlyph;

static bool stub_glyph(const uint8_t* font, uint16_t code, StubGlyph* glyph) {
    if(font == native_zh_font) {
        // ASCII metrics differ from the stock font, so a wrong fallback would show
        if(code >= 0x20 && code < 0x7F) {
            *glyph = (StubGlyph){7, 6, 0};
            return true;
        }
        if(code == 0x3400 || !gui_utf8_is_cjk(code)) return false;
        // U+4E2D is drawn 9 px wide at x offset 1, like the real glyph
        *glyph = (StubGlyph){12, code == 0x4E2D ? 9 : 11, code == 0x4E2D ? 1 : 0};
        return true;
    }
    if(code >= 0x20 && code < 0x7F) {
        *glyph = (StubGlyph){6, 5, 0};
        return true;
    }
    if(font == font_custom && code == 0x4E2D) {
        *glyph = (StubGlyph){10, 9, 0};
        return true;
    }
    return false;
}

static int8_t stub_ascent(const uint8_t* font) {
    if(font == font_stock) return 7;
    if(font == font_custom) return 9;
    return 8;
}

static const char* font_name(const uint8_t* font) {
    if(font == font_stock) return "stock";
    if(font == font_custom) return "custom";
    if(font == native_zh_font) return "native";
    return "unknown";
}

typedef struct {
    const uint8_t* font;
    int16_t x;
    int16_t y;
    uint16_t code;
} DrawEvent;

static DrawEvent events[64];
static size_t event_count;
static size_t set_font_calls, is_glyph_calls, draw_utf8_calls, width_utf8_calls;

static void u8g2_SetFont(u8g2_t* u8g2, const uint8_t* font) {
    set_font_calls++;
    if(u8g2->font != font) {
        u8g2->font = font;
        u8g2->font_ref_ascent = stub_ascent(font);
    }
}

static uint8_t u8g2_IsGlyph(u8g2_t* u8g2, uint16_t code) {
    StubGlyph glyph;
    is_glyph_calls++;
    return stub_glyph(u8g2->font, code, &glyph);
}

// Side effects as in lib/u8g2/u8g2_font.c: drawn width and x offset stay for the caller
static int8_t u8g2_GetGlyphWidth(u8g2_t* u8g2, uint16_t code) {
    StubGlyph glyph;
    if(!stub_glyph(u8g2->font, code, &glyph)) return 0;
    u8g2->font_decode.glyph_width = (int8_t)glyph.width;
    u8g2->glyph_x_offset = glyph.x;
    return (int8_t)glyph.advance;
}

static u8g2_uint_t u8g2_DrawGlyph(u8g2_t* u8g2, u8g2_uint_t x, u8g2_uint_t y, uint16_t code) {
    StubGlyph glyph;
    if(!stub_glyph(u8g2->font, code, &glyph)) return 0;
    assert(event_count < sizeof(events) / sizeof(events[0]));
    events[event_count++] = (DrawEvent){u8g2->font, (int16_t)x, (int16_t)y, code};
    return glyph.advance;
}

// Current font only, a newline ends the string: like u8g2_draw_string()
static u8g2_uint_t u8g2_DrawUTF8(u8g2_t* u8g2, u8g2_uint_t x, u8g2_uint_t y, const char* str) {
    u8g2_uint_t sum = 0;
    uint32_t codepoint;
    size_t size;
    draw_utf8_calls++;
    while((size = gui_utf8_decode(str, &codepoint)) > 0 && codepoint != '\n') {
        u8g2_uint_t delta = u8g2_DrawGlyph(u8g2, x, y, (uint16_t)codepoint);
        str += size;
        switch(u8g2->font_decode.dir) {
        case 1:
            y += delta;
            break;
        case 2:
            x -= delta;
            break;
        case 3:
            y -= delta;
            break;
        default:
            x += delta;
            break;
        }
        sum += delta;
    }
    return sum;
}

// Like u8g2_string_width(): advances, the last glyph by its drawn width and x offset
static u8g2_uint_t u8g2_GetUTF8Width(u8g2_t* u8g2, const char* str) {
    int32_t width = 0;
    int8_t advance = 0;
    uint32_t codepoint;
    size_t size;
    width_utf8_calls++;
    u8g2->font_decode.glyph_width = 0;
    while((size = gui_utf8_decode(str, &codepoint)) > 0 && codepoint != '\n') {
        str += size;
        advance = u8g2_GetGlyphWidth(u8g2, (uint16_t)codepoint);
        width += advance;
    }
    if(u8g2->font_decode.glyph_width != 0) {
        width += u8g2->font_decode.glyph_width + u8g2->glyph_x_offset - advance;
    }
    return (u8g2_uint_t)width;
}
"""

CANVAS_HARNESS = r"""
static Canvas canvas;

static void reset(const uint8_t* font) {
    memset(&canvas, 0, sizeof(canvas));
    canvas.fb.font = font;
    canvas.fb.font_ref_ascent = stub_ascent(font);
    event_count = 0;
    set_font_calls = is_glyph_calls = draw_utf8_calls = width_utf8_calls = 0;
}

static void expect_event(size_t index, const uint8_t* font, int x, int y, int code) {
    assert(index < event_count);
    const DrawEvent* event = &events[index];
    if(event->font != font || event->x != x || event->y != y || event->code != code) {
        fprintf(
            stderr,
            "event %u: %s font at (%d,%d) U+%04X, expected %s font at (%d,%d) U+%04X\n",
            (unsigned)index,
            font_name(event->font),
            event->x,
            event->y,
            (unsigned)event->code,
            font_name(font),
            x,
            y,
            (unsigned)code);
        abort();
    }
}

// The selected font and its ascent are back after every call
static void expect_restored(const uint8_t* font) {
    assert(canvas.fb.font == font && canvas.fb.font_ref_ascent == stub_ascent(font));
}
"""

CANVAS_MAIN = r"""
int main(void) {
    // ASCII strings keep u8g2's own text calls: one DrawUTF8, no font switch, no lookup
    reset(font_stock);
    canvas_draw_str(&canvas, 2, 20, "OK");
    assert(draw_utf8_calls == 1 && set_font_calls == 0 && is_glyph_calls == 0);
    assert(event_count == 2);
    expect_event(0, font_stock, 2, 20, 'O');
    expect_event(1, font_stock, 8, 20, 'K');
    assert(canvas_string_width(&canvas, "OK") == 11 && width_utf8_calls == 1);
    assert(canvas_glyph_width(&canvas, 'K') == 6 && set_font_calls == 0);
    canvas_draw_str_aligned(&canvas, 100, 30, AlignLeft, AlignTop, "OK");
    assert(width_utf8_calls == 1); // left aligned ASCII is not measured
    expect_event(2, font_stock, 100, 37, 'O'); // stock ascent 7
    canvas_draw_str_aligned(&canvas, 100, 30, AlignRight, AlignBottom, "OK");
    expect_event(4, font_stock, 89, 30, 'O');
    expect_restored(font_stock);

    // Mixed text: ASCII from the selected font, CJK from the native font; the pen and
    // the measurement agree and the selected font comes back after every glyph
    reset(font_stock);
    canvas_draw_str(&canvas, 10, 20, MIXED);
    assert(draw_utf8_calls == 0 && event_count == 4);
    expect_event(0, font_stock, 10, 20, 'O');
    expect_event(1, font_stock, 16, 20, 'K');
    expect_event(2, native_zh_font, 22, 20, 0x4E2D);
    expect_event(3, native_zh_font, 34, 20, 0x6587);
    expect_restored(font_stock);
    assert(set_font_calls == 4);
    assert(canvas_string_width(&canvas, MIXED) == 6 + 6 + 12 + 11); // last glyph as drawn
    expect_restored(font_stock);
    int32_t pen = 10;
    const uint16_t mixed_codes[] = {'O', 'K', 0x4E2D, 0x6587};
    for(size_t i = 0; i < 4; i++) {
        assert(events[i].x == pen); // glyph widths add up to the pen positions
        pen += (int32_t)canvas_glyph_width(&canvas, mixed_codes[i]);
    }
    assert(pen == 46);

    // A newline ends drawing and measuring, as in u8g2
    reset(font_stock);
    canvas_draw_str(&canvas, 0, 0, ZHONG_NL_WEN);
    assert(event_count == 1);
    assert(canvas_string_width(&canvas, ZHONG_NL_WEN) == canvas_string_width(&canvas, ZHONG));
    assert(canvas_string_width(&canvas, ZHONG) == 12 - 12 + 9 + 1);

    // A custom font with its own CJK glyph is not overridden; glyphs it lacks fall back
    reset(font_custom);
    canvas_draw_str(&canvas, 0, 0, ZHONG_WEN);
    assert(event_count == 2 && set_font_calls == 2);
    expect_event(0, font_custom, 0, 0, 0x4E2D);
    expect_event(1, native_zh_font, 10, 0, 0x6587);
    expect_restored(font_custom);
    assert(canvas_string_width(&canvas, ZHONG_WEN) == 10 + 11);

    // With the native font selected nothing is looked up twice
    reset(native_zh_font);
    canvas_draw_str(&canvas, 0, 0, MIXED);
    assert(event_count == 4 && set_font_calls == 0 && is_glyph_calls == 0);
    expect_event(3, native_zh_font, 7 + 7 + 12, 0, 0x6587);

    // Missing in both fonts: nothing drawn, zero width, font restored
    reset(font_stock);
    assert(canvas_glyph_width(&canvas, 0x3400) == 0);
    expect_restored(font_stock);
    canvas_draw_str(&canvas, 0, 0, MISSING_ZHONG);
    assert(event_count == 1);
    expect_event(0, native_zh_font, 0, 0, 0x4E2D);

    // Non-ASCII outside the generated ranges never consults the native font
    reset(font_stock);
    canvas_draw_str(&canvas, 0, 0, LATIN_ARROW_A);
    assert(event_count == 1 && is_glyph_calls == 0 && set_font_calls == 0);
    expect_event(0, font_stock, 0, 0, 'A');
    assert(canvas_string_width(&canvas, LATIN_ARROW_A) == 5);

    // Alignment measures with the fallback and lifts the baseline for CJK glyphs
    reset(font_stock);
    canvas_draw_str_aligned(&canvas, 100, 30, AlignRight, AlignBottom, MIXED);
    expect_event(0, font_stock, 65, 30, 'O');
    canvas_draw_str_aligned(&canvas, 100, 30, AlignCenter, AlignTop, MIXED);
    expect_event(4, font_stock, 83, 30 + GUI_CJK_GLYPH_ASCENT, 'O');
    canvas_draw_str_aligned(&canvas, 100, 30, AlignLeft, AlignCenter, MIXED);
    expect_event(8, font_stock, 100, 30 + GUI_CJK_GLYPH_ASCENT / 2, 'O');
    expect_restored(font_stock);
    reset(font_custom);
    canvas_draw_str_aligned(&canvas, 0, 30, AlignLeft, AlignTop, ZHONG);
    expect_event(0, font_custom, 0, 39, 0x4E2D); // no fallback: custom ascent 9
    reset(font_stock);
    canvas_draw_str_aligned(&canvas, 0, 30, AlignLeft, AlignTop, ZHONG);
    expect_event(0, native_zh_font, 0, 30 + GUI_CJK_GLYPH_ASCENT, 0x4E2D);

    // Font direction moves the pen like u8g2_DrawUTF8()
    for(uint8_t dir = 0; dir < 4; dir++) {
        reset(font_stock);
        canvas.fb.font_decode.dir = dir;
        canvas_draw_str(&canvas, 5, 5, ZHONG_WEN);
        int x = 5;
        int y = 5;
        if(dir == 0) {
            x += 12;
        } else if(dir == 1) {
            y += 12;
        } else if(dir == 2) {
            x -= 12;
        } else {
            y -= 12;
        }
        expect_event(1, native_zh_font, x, y, 0x6587);
    }

    // Frame offsets apply to the UTF-8 path and to single glyphs
    reset(font_stock);
    canvas.offset_x = 3;
    canvas.offset_y = 4;
    canvas_draw_str(&canvas, 1, 2, ZHONG);
    expect_event(0, native_zh_font, 4, 6, 0x4E2D);
    canvas_draw_glyph(&canvas, 1, 2, 0x6587);
    expect_event(1, native_zh_font, 4, 6, 0x6587);
    canvas_draw_glyph(&canvas, 1, 2, 'A');
    expect_event(2, font_stock, 4, 6, 'A');
    expect_restored(font_stock);

    // Malformed bytes and codepoints outside the BMP draw nothing and do not crash
    reset(font_stock);
    canvas_draw_str(&canvas, 0, 0, TRUNCATED);
    canvas_draw_str(&canvas, 0, 0, EMOJI);
    assert(event_count == 0);
    assert(canvas_string_width(&canvas, TRUNCATED) == 0);
    assert(canvas_string_width(&canvas, EMOJI) == 0);
    expect_restored(font_stock);
    return 0;
}
"""

# Test strings, emitted as C macros by c_constants() for each program
HELPER_CONSTANTS = {
    "ZHONG": "中",
    "A_ZHONG_B": "a中b",
    "LATIN": "é",
}

CANVAS_CONSTANTS = {
    "ZHONG": "中",
    "ZHONG_WEN": "中文",
    "ZHONG_NL_WEN": "中\n文",
    "MIXED": "OK中文",
    "LATIN_ARROW_A": "é←A",
    "MISSING_ZHONG": "㐀中",
    "TRUNCATED": b"\xe4\xb8",
    "EMOJI": "\U0001f600",
}


class Utf8HelperTests(unittest.TestCase):
    def test_helpers_classify_and_step_by_codepoint(self):
        native_test(
            f'#include "{HEADER}"\n'
            + COMMON_INCLUDES
            + c_constants(HELPER_CONSTANTS)
            + HELPERS_MAIN
        )


class CanvasFallbackTests(unittest.TestCase):
    def test_canvas_text_falls_back_to_the_native_font(self):
        production = source_between(
            CANVAS_C,
            "static bool canvas_glyph_needs_fallback(",
            "\nvoid canvas_draw_bitmap(",
        ) + source_between(
            CANVAS_C, "void canvas_draw_glyph(", "\nvoid canvas_set_bitmap_mode("
        )
        native_test(
            f'#include "{HEADER}"\n'
            + COMMON_INCLUDES
            + canvas_enums()
            + CANVAS_STUBS
            + production
            + c_constants(CANVAS_CONSTANTS)
            + CANVAS_HARNESS
            + CANVAS_MAIN
        )


ELEMENTS_STUBS = r"""
#include <math.h>
#include <stdarg.h>

#define furi_check(x) assert(x)
#define furi_crash() abort()

// Drawing is recorded instead of rasterised
typedef struct {
    Font font;
    bool inverted;
    size_t set_font_calls;
} Canvas;

typedef struct {
    int32_t x;
    int32_t y;
    uint16_t code;
    Font font;
    bool inverted;
} GlyphEvent;

typedef struct {
    int32_t x;
    int32_t y;
    int32_t width;
    int32_t height;
} BoxEvent;

typedef struct {
    int32_t x;
    int32_t y;
    bool aligned;
    Align horizontal;
    Align vertical;
    char text[128];
} StrEvent;

static GlyphEvent glyphs[256];
static BoxEvent boxes[32];
static StrEvent strings[32];
static size_t glyph_count, box_count, string_count;

static struct {
    bool scroll_marquee;
} momentum_settings;

// Test font: ASCII 6 px, '.' 3 px, ' ' 4 px, CJK 12 px, nothing else has a glyph
static size_t canvas_glyph_width(Canvas* canvas, uint16_t symbol) {
    (void)canvas;
    if(symbol == '.') return 3;
    if(symbol == ' ') return 4;
    if(symbol >= 0x20 && symbol < 0x7F) return 6;
    if(gui_utf8_is_cjk(symbol)) return 12;
    return 0;
}

// Advances up to a newline, like u8g2_GetUTF8Width() without its last glyph correction
static uint16_t canvas_string_width(Canvas* canvas, const char* str) {
    size_t width = 0;
    uint32_t codepoint;
    size_t size;
    while((size = gui_utf8_decode(str, &codepoint)) > 0 && codepoint != '\n') {
        str += size;
        width += canvas_glyph_width(canvas, (uint16_t)codepoint);
    }
    return (uint16_t)width;
}

static size_t canvas_width(const Canvas* canvas) {
    (void)canvas;
    return 128;
}

static size_t canvas_height(const Canvas* canvas) {
    (void)canvas;
    return 64;
}

static size_t canvas_current_font_height(const Canvas* canvas) {
    (void)canvas;
    return 8;
}

static void canvas_set_font(Canvas* canvas, Font font) {
    canvas->font = font;
    canvas->set_font_calls++;
}

static const CanvasFontParameters* canvas_get_font_params(const Canvas* canvas, Font font) {
    (void)canvas;
    return &canvas_font_params[font];
}

static void canvas_invert_color(Canvas* canvas) {
    canvas->inverted = !canvas->inverted;
}

// A code without a glyph draws nothing, as in u8g2
static void canvas_draw_glyph(Canvas* canvas, int32_t x, int32_t y, uint16_t code) {
    if(canvas_glyph_width(canvas, code) == 0) return;
    assert(glyph_count < sizeof(glyphs) / sizeof(glyphs[0]));
    glyphs[glyph_count++] = (GlyphEvent){x, y, code, canvas->font, canvas->inverted};
}

static void canvas_draw_box(Canvas* canvas, int32_t x, int32_t y, size_t width, size_t height) {
    (void)canvas;
    assert(box_count < sizeof(boxes) / sizeof(boxes[0]));
    boxes[box_count++] = (BoxEvent){x, y, (int32_t)width, (int32_t)height};
}

static void
    record_str(int32_t x, int32_t y, bool aligned, Align horizontal, Align vertical, const char* str) {
    assert(string_count < sizeof(strings) / sizeof(strings[0]));
    StrEvent* event = &strings[string_count++];
    *event = (StrEvent){x, y, aligned, horizontal, vertical, {0}};
    assert(strlen(str) < sizeof(event->text));
    strcpy(event->text, str);
}

static void canvas_draw_str(Canvas* canvas, int32_t x, int32_t y, const char* str) {
    (void)canvas;
    record_str(x, y, false, AlignLeft, AlignBottom, str);
}

static void canvas_draw_str_aligned(
    Canvas* canvas,
    int32_t x,
    int32_t y,
    Align horizontal,
    Align vertical,
    const char* str) {
    (void)canvas;
    record_str(x, y, true, horizontal, vertical, str);
}

typedef struct {
    char data[512];
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

static void furi_string_set_strn(FuriString* s, const char str[], size_t length) {
    assert(length < sizeof(s->data));
    memcpy(s->data, str, length);
    s->size = length;
    s->data[length] = '\0';
}

static void furi_string_set(FuriString* s, const char str[]) {
    furi_string_set_strn(s, str, strlen(str));
}

static FuriString* furi_string_alloc_set_str(const char str[]) {
    FuriString* s = furi_string_alloc();
    furi_string_set(s, str);
    return s;
}

static FuriString* furi_string_alloc_set_furi(const FuriString* other) {
    return furi_string_alloc_set_str(other->data);
}

// furi/core/string.h picks the overload by argument type the same way
#define furi_string_alloc_set(a)                          \
    _Generic(                                             \
        (a),                                              \
        const char*: furi_string_alloc_set_str,           \
        char*: furi_string_alloc_set_str,                 \
        default: furi_string_alloc_set_furi)(a)

static FuriString* furi_string_alloc_printf(const char format[], ...) {
    FuriString* s = furi_string_alloc();
    va_list args;
    va_start(args, format);
    int written = vsnprintf(s->data, sizeof(s->data), format, args);
    va_end(args);
    assert(written >= 0 && (size_t)written < sizeof(s->data));
    s->size = (size_t)written;
    return s;
}

static size_t furi_string_size(const FuriString* s) {
    return s->size;
}

static const char* furi_string_get_cstr(const FuriString* s) {
    return s->data;
}

static void furi_string_left(FuriString* s, size_t index) {
    if(index < s->size) {
        s->size = index;
        s->data[index] = '\0';
    }
}

static void furi_string_right(FuriString* s, size_t index) {
    if(index >= s->size) {
        s->size = 0;
        s->data[0] = '\0';
        return;
    }
    memmove(s->data, &s->data[index], s->size - index + 1);
    s->size -= index;
}

static void furi_string_cat(FuriString* s, const char str[]) {
    size_t length = strlen(str);
    assert(s->size + length < sizeof(s->data));
    memcpy(&s->data[s->size], str, length + 1);
    s->size += length;
}
"""

ELEMENTS_HARNESS = r"""
static Canvas canvas;

static void reset(void) {
    memset(&canvas, 0, sizeof(canvas));
    canvas.font = FontSecondary;
    glyph_count = box_count = string_count = 0;
}

static bool valid_utf8(const char* text) {
    uint32_t codepoint;
    size_t size;
    while((size = gui_utf8_decode(text, &codepoint)) > 0) {
        if(codepoint == GUI_UTF8_REPLACEMENT_CHARACTER) return false;
        text += size;
    }
    return true;
}

static void expect_glyph(size_t index, int x, int y, int code, Font font, bool inverted) {
    assert(index < glyph_count);
    const GlyphEvent* glyph = &glyphs[index];
    if(glyph->x != x || glyph->y != y || glyph->code != code || glyph->font != font ||
       glyph->inverted != inverted) {
        fprintf(
            stderr,
            "glyph %u: U+%04X at (%d,%d) font %d%s, expected U+%04X at (%d,%d) font %d%s\n",
            (unsigned)index,
            (unsigned)glyph->code,
            (int)glyph->x,
            (int)glyph->y,
            (int)glyph->font,
            glyph->inverted ? " inverted" : "",
            (unsigned)code,
            x,
            y,
            (int)font,
            inverted ? " inverted" : "");
        abort();
    }
}

static void expect_str(size_t index, int x, int y, const char* text) {
    assert(index < string_count);
    const StrEvent* event = &strings[index];
    if(event->x != x || event->y != y || strcmp(event->text, text) != 0) {
        fprintf(
            stderr,
            "string %u: \"%s\" at (%d,%d), expected \"%s\" at (%d,%d)\n",
            (unsigned)index,
            event->text,
            (int)event->x,
            (int)event->y,
            text,
            x,
            y);
        abort();
    }
}

// What elements_scrollable_text_line() draws for one scroll position
static const char* scrolled(const char* text, size_t width, size_t scroll, bool ellipsis) {
    FuriString* string = furi_string_alloc_set_str(text);
    string_count = 0;
    elements_scrollable_text_line(&canvas, 0, 10, width, string, scroll, ellipsis);
    furi_string_free(string);
    assert(string_count == 1 && !strings[0].aligned && valid_utf8(strings[0].text));
    return strings[0].text;
}
"""

ELEMENTS_MAIN = r"""
int main(void) {
    FuriString* s;

    // elements_string_fit_width: whole characters, room for the dots, no underflow
    reset();
    s = furi_string_alloc_set_str(HELLO_WORLD);
    elements_string_fit_width(&canvas, s, 40);
    assert(strcmp(furi_string_get_cstr(s), "Hello...") == 0);
    furi_string_set(s, ZH7);
    elements_string_fit_width(&canvas, s, 40);
    assert(strcmp(furi_string_get_cstr(s), ZH2_DOTS) == 0);
    furi_string_set(s, ZH7);
    elements_string_fit_width(&canvas, s, 5); // narrower than the dots
    assert(strcmp(furi_string_get_cstr(s), "...") == 0);
    furi_string_set(s, "OK");
    elements_string_fit_width(&canvas, s, 40);
    assert(strcmp(furi_string_get_cstr(s), "OK") == 0);
    furi_string_set(s, UPPER_A_ZHONG_B);
    elements_string_fit_width(&canvas, s, 20);
    assert(strcmp(furi_string_get_cstr(s), "A...") == 0);
    furi_string_free(s);

    // elements_scrollable_text_line: English timing unchanged, CJK by whole characters
    reset();
    assert(strcmp(scrolled(ABC10, 30, 0, false), "ABCDE") == 0);
    assert(strcmp(scrolled(ABC10, 30, 1, false), "BCDEF") == 0);
    assert(strcmp(scrolled(ABC10, 30, 5, false), "FGHIJ") == 0);
    assert(strcmp(scrolled(ABC10, 30, 6, false), "GHIJ") == 0);
    assert(strcmp(scrolled(ABC10, 30, 7, false), "HIJ") == 0);
    assert(strcmp(scrolled(ABC10, 30, 8, false), "ABCDE") == 0);
    assert(strcmp(scrolled(NUM10, 36, 0, false), NUM_1_3) == 0);
    assert(strcmp(scrolled(NUM10, 36, 1, false), NUM_2_4) == 0);
    assert(strcmp(scrolled(NUM10, 36, 7, false), NUM_8_10) == 0);
    assert(strcmp(scrolled(NUM10, 36, 9, false), NUM_10) == 0);
    assert(strcmp(scrolled(NUM10, 36, 10, false), NUM_1_3) == 0);
    // The ellipsis takes its room; a box narrower than the dots shows only them
    assert(strcmp(scrolled(ABC10, 30, 0, true), "ABC...") == 0);
    assert(strcmp(scrolled(NUM10, 30, 3, true), NUM_4_DOTS) == 0);
    assert(strcmp(scrolled("ABCDEF", 5, 0, true), "...") == 0);
    // Marquee: forward, hold, back, hold
    momentum_settings.scroll_marquee = true;
    assert(strcmp(scrolled(ABC10, 30, 3, false), "DEFGH") == 0);
    assert(strcmp(scrolled(ABC10, 30, 6, false), "FGHIJ") == 0);
    assert(strcmp(scrolled(ABC10, 30, 12, false), "BCDEF") == 0);
    assert(strcmp(scrolled(ABC10, 30, 13, false), "ABCDE") == 0);
    assert(strcmp(scrolled(NUM10, 36, 8, false), NUM_8_10) == 0);
    momentum_settings.scroll_marquee = false;
    // Centered text that scrolls is drawn from the left edge of its width
    reset();
    s = furi_string_alloc_set_str(ABC10);
    elements_scrollable_text_line_centered(&canvas, 64, 10, 30, s, 0, false, true);
    assert(string_count == 1 && !strings[0].aligned && strings[0].x == 49);
    assert(strcmp(strings[0].text, "ABCDE") == 0);
    string_count = 0;
    furi_string_set(s, "OK");
    elements_scrollable_text_line_centered(&canvas, 64, 10, 30, s, 0, false, true);
    assert(string_count == 1 && strings[0].aligned && strings[0].horizontal == AlignCenter);
    assert(strings[0].x == 64);
    furi_string_free(s);

    // elements_text_box, UTF-8 layout: five 12 px glyphs per 60 px line, rows 13 px apart
    reset();
    elements_text_box(&canvas, 4, 2, 60, 40, AlignLeft, AlignTop, NUM10, false);
    assert(glyph_count == 10 && string_count == 0 && box_count == 0);
    for(size_t i = 0; i < 10; i++) {
        int x = 4 + (int)(i % 5) * 12;
        expect_glyph(i, x, i < 5 ? 13 : 26, NUM_CODES[i], FontSecondary, false);
    }
    assert(canvas.font == FontSecondary);

    // Newlines start lines
    reset();
    elements_text_box(&canvas, 0, 0, 60, 40, AlignLeft, AlignTop, ZHONG_NL_WEN, false);
    assert(glyph_count == 2);
    expect_glyph(0, 0, 11, 0x4E2D, FontSecondary, false);
    expect_glyph(1, 0, 24, 0x6587, FontSecondary, false);

    // The bold marker switches the font between the markers; markers are not drawn
    reset();
    elements_text_box(&canvas, 0, 0, 60, 40, AlignLeft, AlignTop, BOLD_ZHONG_WEN, false);
    assert(glyph_count == 2);
    expect_glyph(0, 0, 11, 0x4E2D, FontPrimary, false);
    expect_glyph(1, 12, 11, 0x6587, FontSecondary, false);
    assert(canvas.font == FontSecondary);

    // The inverse marker frames its glyph; the frame stays inside the box
    reset();
    elements_text_box(&canvas, 5, 3, 60, 40, AlignLeft, AlignTop, INV_ZHONG_WEN, false);
    assert(glyph_count == 2 && box_count == 1 && !canvas.inverted);
    expect_glyph(0, 5, 15, 0x4E2D, FontSecondary, true);
    expect_glyph(1, 17, 15, 0x6587, FontSecondary, false);
    assert(boxes[0].x == 4 && boxes[0].y == 3 && boxes[0].width == 13 && boxes[0].height == 14);

    // A box narrower than a glyph: one glyph per line, nothing drawn outside, no stall
    reset();
    elements_text_box(&canvas, 0, 0, 10, 40, AlignLeft, AlignTop, ZHONG_WEN, false);
    assert(glyph_count == 0);
    reset();
    elements_text_box(&canvas, 0, 0, 10, 40, AlignLeft, AlignTop, LOWER_A_ZHONG_B, false);
    assert(glyph_count == 2);
    expect_glyph(0, 0, 7, 'a', FontSecondary, false);
    expect_glyph(1, 0, 34, 'b', FontSecondary, false);

    // The height keeps whole lines; strip_to_dots marks the cut on the last shown line
    reset();
    elements_text_box(&canvas, 0, 0, 60, 12, AlignLeft, AlignTop, NUM10, true);
    assert(glyph_count == 4 && string_count == 1);
    expect_str(0, 48, 11, "...");
    reset();
    elements_text_box(&canvas, 0, 0, 60, 12, AlignLeft, AlignTop, NUM10, false);
    assert(glyph_count == 5 && string_count == 0);
    reset();
    elements_text_box(&canvas, 0, 0, 60, 40, AlignLeft, AlignTop, ZH5, true);
    assert(glyph_count == 5 && string_count == 0); // fits: no dots
    reset();
    elements_text_box(&canvas, 0, 0, 60, 200, AlignLeft, AlignTop, TEN_LINES, true);
    assert(glyph_count == ELEMENTS_MAX_LINES_NUM && string_count == 1);
    expect_str(0, 12, 11 + 6 * 13, "...");

    // Vertical and horizontal alignment
    reset();
    elements_text_box(&canvas, 0, 0, 60, 40, AlignCenter, AlignBottom, ZHONG, false);
    expect_glyph(0, 24, 39, 0x4E2D, FontSecondary, false);
    reset();
    elements_text_box(&canvas, 0, 0, 60, 40, AlignRight, AlignCenter, ZHONG, false);
    expect_glyph(0, 48, 25, 0x4E2D, FontSecondary, false);

    // A line mixing ASCII and CJK takes the CJK ascent
    reset();
    elements_text_box(&canvas, 0, 0, 60, 40, AlignLeft, AlignTop, AB_ZHONG, false);
    assert(glyph_count == 3);
    expect_glyph(0, 0, 11, 'a', FontSecondary, false);
    expect_glyph(2, 12, 11, 0x4E2D, FontSecondary, false);

    // ASCII text keeps the original layout: 7 px cap height, one byte per glyph ...
    reset();
    elements_text_box(&canvas, 0, 0, 60, 40, AlignLeft, AlignTop, "abc", false);
    assert(glyph_count == 3);
    expect_glyph(0, 0, 7, 'a', FontSecondary, false);
    expect_glyph(2, 12, 7, 'c', FontSecondary, false);
    // ... and stops at the end of the line array instead of writing past it
    reset();
    elements_text_box(&canvas, 0, 0, 60, 200, AlignLeft, AlignTop, ASCII_9_LINES, false);
    assert(glyph_count == ELEMENTS_MAX_LINES_NUM);

    // elements_multiline_text: 12 px rows for Chinese text, 8 px rows for ASCII
    reset();
    elements_multiline_text(&canvas, 0, 11, ZHONG_NL_WEN);
    assert(string_count == 2);
    expect_str(0, 0, 11, ZHONG);
    expect_str(1, 0, 23, WEN);
    reset();
    elements_multiline_text(&canvas, 0, 11, "a\nb");
    assert(string_count == 2);
    expect_str(1, 0, 19, "b");

    // elements_multiline_text_aligned: ASCII wrapping and its dash are unchanged
    reset();
    elements_multiline_text_aligned(&canvas, 0, 10, AlignLeft, AlignTop, LOREM);
    assert(string_count == 2);
    expect_str(0, 0, 10, "Lorem ipsum dolor si-\n");
    expect_str(1, 0, 18, "t amet consectetur");
    // Chinese wraps between characters, without a dash, 12 px apart
    reset();
    elements_multiline_text_aligned(&canvas, 0, 10, AlignLeft, AlignTop, ZH20);
    assert(string_count == 2);
    expect_str(0, 0, 10, ZH10_NL);
    expect_str(1, 0, 22, ZH10);
    assert(valid_utf8(strings[0].text) && valid_utf8(strings[1].text));
    // Text with no room at all still advances one character per line
    reset();
    elements_multiline_text_aligned(&canvas, 120, 10, AlignLeft, AlignTop, "Hello");
    assert(string_count == 5);
    expect_str(0, 120, 10, "H\n");
    expect_str(4, 120, 42, "o");
    return 0;
}
"""

NUM10 = "一二三四五六七八九十"
ELEMENTS_CONSTANTS = {
    "HELLO_WORLD": "Hello World",
    "ZH7": "中文测试字符串",
    "ZH2_DOTS": "中文...",
    "UPPER_A_ZHONG_B": "A中B",
    "LOWER_A_ZHONG_B": "a中b",
    "AB_ZHONG": "ab中",
    "ABC10": "ABCDEFGHIJ",
    "NUM10": NUM10,
    "NUM_1_3": NUM10[0:3],
    "NUM_2_4": NUM10[1:4],
    "NUM_8_10": NUM10[7:10],
    "NUM_10": NUM10[9],
    "NUM_4_DOTS": NUM10[3] + "...",
    "ZH5": NUM10[0:5],
    "ZHONG": "中",
    "WEN": "文",
    "ZHONG_WEN": "中文",
    "ZHONG_NL_WEN": "中\n文",
    "BOLD_ZHONG_WEN": f"{ESC}#中{ESC}#文",
    "INV_ZHONG_WEN": f"{ESC}!中{ESC}!文",
    "TEN_LINES": "中\n" * 9 + "中",
    "ASCII_9_LINES": "a\n" * 8 + "a",
    "LOREM": "Lorem ipsum dolor sit amet consectetur",
    "ZH20": "中" * 20,
    "ZH10": "中" * 10,
    "ZH10_NL": "中" * 10 + "\n",
}

TEXT_BOX_STUBS = r"""
typedef struct {
    size_t font_height;
    Font font;
    size_t clears;
    size_t frames;
    size_t scrollbars;
} Canvas;

typedef struct {
    int32_t y;
    char text[64];
} DrawnLine;

static DrawnLine drawn[16];
static size_t drawn_count;

static size_t canvas_glyph_width(Canvas* canvas, uint16_t symbol) {
    (void)canvas;
    if(symbol >= 0x20 && symbol < 0x7F) return 6;
    if(gui_utf8_is_cjk(symbol)) return 12;
    return 0;
}

static size_t canvas_current_font_height(const Canvas* canvas) {
    return canvas->font_height;
}

static size_t canvas_height(const Canvas* canvas) {
    (void)canvas;
    return 64;
}

static void canvas_clear(Canvas* canvas) {
    canvas->clears++;
}

static void canvas_set_font(Canvas* canvas, Font font) {
    canvas->font = font;
}

static void
    elements_slightly_rounded_frame(Canvas* canvas, int32_t x, int32_t y, size_t width, size_t height) {
    (void)x;
    (void)y;
    (void)width;
    (void)height;
    canvas->frames++;
}

static void elements_scrollbar(Canvas* canvas, size_t pos, size_t total) {
    (void)pos;
    (void)total;
    canvas->scrollbars++;
}

static void canvas_draw_str(Canvas* canvas, int32_t x, int32_t y, const char* str) {
    (void)canvas;
    assert(x == 3 && drawn_count < sizeof(drawn) / sizeof(drawn[0]));
    assert(strlen(str) < sizeof(drawn[0].text));
    drawn[drawn_count].y = y;
    strcpy(drawn[drawn_count].text, str);
    drawn_count++;
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

static const char* furi_string_get_cstr(const FuriString* s) {
    return s->data;
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

TEXT_BOX_MAIN = r"""
static Canvas test_canvas;
static FuriString test_screen, test_line;

static void model_init(TextBoxModel* model, const char* text) {
    memset(model, 0, sizeof(*model));
    model->text = text;
    model->text_on_screen = &test_screen;
    model->text_line = &test_line;
    drawn_count = 0;
}

int main(void) {
    TextBoxModel model;
    test_canvas.font_height = 8;

    // Chinese text: 12 px rows, four per screen, cut between characters
    model_init(&model, CJK_TEXT);
    text_box_view_draw_callback(&test_canvas, &model);
    assert(model.formatted && model.line_height == 12 && model.lines_on_screen == 4);
    assert(model.scroll_num == 5 && model.scroll_pos == 0);
    assert(test_canvas.font == FontSecondary && test_canvas.frames == 1);
    assert(drawn_count == 4);
    for(size_t i = 0; i < 4; i++) {
        assert(drawn[i].y == 11 + 12 * (int32_t)i && strcmp(drawn[i].text, CJK_LINE) == 0);
    }
    // Scrolling redraws from the new offset with the same spacing
    model.scroll_pos = 4;
    drawn_count = 0;
    text_box_view_draw_callback(&test_canvas, &model);
    assert(model.line_offset == 4 && model.text_offset == 120 && drawn_count == 4);
    assert(drawn[3].y == 47 && strcmp(drawn[3].text, CJK_TAIL) == 0);

    // ASCII text: unchanged 8 px rows, seven per screen
    model_init(&model, ASCII_TEXT);
    text_box_view_draw_callback(&test_canvas, &model);
    assert(model.line_height == 8 && model.lines_on_screen == 7 && model.scroll_num == 6);
    assert(drawn_count == 7);
    for(size_t i = 0; i < 7; i++) {
        char expected[8];
        snprintf(expected, sizeof(expected), "L%02u", (unsigned)i);
        assert(drawn[i].y == 11 + 8 * (int32_t)i && strcmp(drawn[i].text, expected) == 0);
    }

    // A document with Chinese further down uses 12 px rows on its ASCII screens too
    model_init(&model, MIXED_TEXT);
    text_box_view_draw_callback(&test_canvas, &model);
    assert(model.line_height == 12 && model.lines_on_screen == 4 && drawn_count == 4);
    assert(drawn[3].y == 47 && strcmp(drawn[3].text, "L03") == 0);

    // Focus on the end shows the last four Chinese lines
    model_init(&model, CJK_TEXT);
    model.focus = TextBoxFocusEnd;
    text_box_view_draw_callback(&test_canvas, &model);
    assert(model.scroll_pos == 4 && model.text_offset == 120 && drawn_count == 4);
    assert(strcmp(drawn[3].text, CJK_TAIL) == 0);

    // Preparing the model without the draw callback keeps the font height
    model_init(&model, CJK_TEXT);
    text_box_prepare_model(&test_canvas, &model);
    assert(model.line_height == 8 && model.lines_on_screen == 7);

    // The hex font is taller: five rows; tiny fonts are capped by the offset cache size
    test_canvas.font_height = 11;
    model_init(&model, ASCII_TEXT);
    text_box_view_draw_callback(&test_canvas, &model);
    assert(model.line_height == 11 && model.lines_on_screen == 5 && drawn_count == 5);
    test_canvas.font_height = 3;
    model_init(&model, ASCII_TEXT);
    text_box_view_draw_callback(&test_canvas, &model);
    assert(model.lines_on_screen == TEXT_BOX_MAX_LINES_PER_SCREEN);
    return 0;
}
"""

TEXT_BOX_CONSTANTS = {
    "CJK_TEXT": "中" * 75,
    "CJK_LINE": "中" * 10,
    "CJK_TAIL": "中" * 5,
    "ASCII_TEXT": "\n".join(f"L{i:02}" for i in range(12)),
    "MIXED_TEXT": "".join(f"L{i:02}\n" for i in range(6)) + "中" * 5,
}


class ElementsTests(unittest.TestCase):
    def test_elements_truncate_scroll_and_lay_out_by_codepoint(self):
        codes = ", ".join(f"0x{ord(char):04X}" for char in NUM10)
        native_test(
            f'#include "{HEADER}"\n'
            + COMMON_INCLUDES
            + canvas_enums()
            + source_between(CORE_DEFINES_H, "#ifndef MAX", "\n#ifndef ABS")
            + source_between(
                CANVAS_C,
                "const CanvasFontParameters canvas_font_params[FontTotalNumber] = {",
                "\nCanvas* canvas_init(void)",
            )
            + ELEMENTS_STUBS
            + source_between(
                ELEMENTS_H,
                "void elements_scrollable_text_line_centered(",
                "\n/** Draw text box element",
            )
            + source_between(
                ELEMENTS_H, "#define ELEMENTS_MAX_LINES_NUM", "\n/** Draw progress bar."
            )
            + source_between(
                ELEMENTS_C,
                "typedef struct {\n    int32_t x;",
                "\nvoid elements_progress_bar(",
            )
            + source_between(
                ELEMENTS_C,
                "static size_t\n    elements_get_max_chars_to_fit(",
                "\nvoid elements_multiline_text_framed(",
            )
            + source_between(ELEMENTS_C, "void elements_string_fit_width(")
            + c_constants(ELEMENTS_CONSTANTS)
            + f"static const int NUM_CODES[] = {{{codes}}};\n"
            + ELEMENTS_HARNESS
            + ELEMENTS_MAIN,
            link_math=True,
        )


class TextBoxTests(unittest.TestCase):
    def test_text_box_rows_follow_the_text(self):
        native_test(
            f'#include "{HEADER}"\n'
            + COMMON_INCLUDES
            + canvas_enums()
            + TEXT_BOX_STUBS
            + source_between(
                TEXT_BOX, "#define TEXT_BOX_TEXT_WIDTH", "\nstruct TextBox {"
            )
            + source_between(TEXT_BOX_H, "typedef enum {", "\n/** Allocate")
            + source_between(
                TEXT_BOX, "typedef struct {", "\nstatic void text_box_process_down("
            )
            + source_between(
                TEXT_BOX,
                "static bool text_box_end_of_text_reached(",
                "\nTextBox* text_box_alloc(void)",
            )
            + c_constants(TEXT_BOX_CONSTANTS)
            + TEXT_BOX_MAIN
        )


class NativeFontSourceTests(unittest.TestCase):
    def test_font_header_is_included_by_canvas_only(self):
        including = sorted(
            path.relative_to(ROOT).as_posix()
            for path in (ROOT / GUI).rglob("*")
            if path.suffix in (".c", ".h")
            and '#include "native_zh_font.h"' in path.read_text(encoding="utf-8")
        )
        self.assertEqual(including, [CANVAS_C])

    def test_gui_text_sources_stay_ascii(self):
        # The font generator collects CJK literals from these files; none belong here
        for path in (CANVAS_C, ELEMENTS_C, HEADER, TEXT_BOX):
            with self.subTest(path):
                self.assertTrue((ROOT / path).read_bytes().isascii())

    def test_generated_font_metrics_fit_the_layout_constants(self):
        header = ROOT / NATIVE_FONT_H
        if not header.exists():
            self.skipTest(
                "native_zh_font.h is not generated; run scripts/generate_native_zh_font.py"
            )
        spec = importlib.util.spec_from_file_location("generate_lab_font", GENERATOR)
        gen = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = gen
        spec.loader.exec_module(gen)
        text = header.read_text(encoding="utf-8")
        body = text[text.index("native_zh_font[] = {") :]
        data = bytes(
            int(value, 16)
            for value in re.findall(r"0x([0-9a-f]{2})", body[: body.index("};")])
        )
        font = gen.parse_font(data)
        constants = {
            name: int(value)
            for name, value in re.findall(
                r"#define (GUI_CJK_\w+)\s+\((\d+)\)",
                (ROOT / HEADER).read_text(encoding="utf-8"),
            )
        }
        self.assertFalse(
            font.ascii, "ASCII uses the selected stock font; do not duplicate it"
        )
        self.assertTrue(font.unicode, "the header holds no CJK glyph")
        self.assertIn(
            f"#define NATIVE_ZH_FONT_GLYPHS {len(font.ascii) + len(font.unicode)}", text
        )
        above = below = 0
        for code, payload in sorted(font.unicode.items()):
            glyph = gen.decode_glyph(font.params, payload)
            with self.subTest(gen.describe(code)):
                self.assertTrue(0x3000 <= code <= 0x9FFF or 0xFF01 <= code <= 0xFFEF)
                # Rows above the baseline, rows at and below it, and the advance
                self.assertLessEqual(
                    glyph.height + glyph.y, constants["GUI_CJK_GLYPH_ASCENT"]
                )
                self.assertLessEqual(-glyph.y, constants["GUI_CJK_GLYPH_DESCENT"])
                self.assertLessEqual(glyph.advance, constants["GUI_CJK_LINE_HEIGHT"])
            above = max(above, glyph.height + glyph.y)
            below = max(below, -glyph.y)
        # Two rows of these glyphs never overlap at the minimum spacing
        self.assertLessEqual(above + below, constants["GUI_CJK_LINE_HEIGHT"])


if __name__ == "__main__":
    unittest.main()
