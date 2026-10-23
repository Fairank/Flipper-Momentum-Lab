"""Run FlipNote's production UTF-8 editor and text drawing code on the host."""

from pathlib import Path
import unittest

from test_unleashed_integration import native_test

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "applications/union/flipnote"
HEADER = (
    (APP / "flipnote_utf8.h").read_text(encoding="utf-8").replace("#pragma once", "")
)
INPUT = (APP / "fznote_text_input.c").read_text(encoding="utf-8")
NOTE = (APP / "flipnote.c").read_text(encoding="utf-8")

PREAMBLE = r"""
#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
typedef struct {
    const char* header;
    char* text_buffer;
    size_t text_buffer_size, cursor_pos;
    bool clear_default_text;
} FzNoteTextInputModel;
"""

DISPLAY = r"""
typedef int Canvas;
enum { FontSecondary, FontKeyboard, ColorBlack, ColorWhite };
static unsigned text_draws;
static bool valid_utf8(const char* text) {
    for(size_t i = 0; text[i];) {
        size_t next = flipnote_utf8_next(text, i);
        if((unsigned char)text[i] >= 128 && next == i + 1) return false;
        i = next;
    }
    return true;
}
static unsigned canvas_string_width(Canvas* c, const char* text) {
    (void)c; assert(valid_utf8(text));
    unsigned width = 0;
    for(size_t i = 0; text[i]; i = flipnote_utf8_next(text, i))
        width += (unsigned char)text[i] < 128 ? 5 : 12;
    return width;
}
static unsigned canvas_width(Canvas* c) {(void)c; return 128;}
static void canvas_clear(Canvas* c) {(void)c;}
static void canvas_set_color(Canvas* c, int v) {(void)c;(void)v;}
static void canvas_set_font(Canvas* c, int v) {(void)c;(void)v;}
static void elements_slightly_rounded_frame(Canvas* c, int x, int y, int w, int h) {(void)c;(void)x;(void)y;(void)w;(void)h;}
static void elements_slightly_rounded_box(Canvas* c, int x, int y, int w, int h) {(void)c;(void)x;(void)y;(void)w;(void)h;}
static void canvas_draw_str(Canvas* c, int x, int y, const char* text) {
    assert(valid_utf8(text));
    if(y == 26) {assert(x >= 4); assert(x + canvas_string_width(c, text) <= 124); text_draws++;}
}
static size_t strlcpy(char* dst, const char* src, size_t cap) {
    size_t n = strlen(src); if(cap) {size_t copy = n < cap - 1 ? n : cap - 1; memcpy(dst, src, copy); dst[copy] = 0;} return n;
}
"""


class FlipNoteUTF8Tests(unittest.TestCase):
    def test_cursor_boundaries_and_real_backspace_preserve_complete_characters(self):
        backspace = INPUT[
            INPUT.index("static void fznote_text_input_backspace_cb(") : INPUT.index(
                "// The save key used to be"
            )
        ]
        native_test(
            PREAMBLE
            + HEADER
            + backspace
            + r"""
int main(void) {
    const char* sample = "甲Aé😀乙";
    const size_t starts[] = {0,3,4,6,10,13};
    for(size_t n = 0; n < 5; n++) {
        assert(flipnote_utf8_next(sample, starts[n]) == starts[n+1]);
        assert(flipnote_utf8_prev(sample, starts[n+1]) == starts[n]);
        for(size_t i = starts[n]; i < starts[n+1]; i++) assert(flipnote_utf8_floor(sample, i) == starts[n]);
    }
    assert(flipnote_utf8_next(sample, 999) == 13 && flipnote_utf8_floor(sample, 999) == 13);
    char text[48]; strcpy(text, sample);
    FzNoteTextInputModel m = {.text_buffer=text, .cursor_pos=10};
    fznote_text_input_backspace_cb(&m);
    assert(strcmp(text,"甲Aé乙") == 0 && m.cursor_pos == 6);
    fznote_text_input_backspace_cb(&m);
    assert(strcmp(text,"甲A乙") == 0 && m.cursor_pos == 4);
    m.cursor_pos=2; fznote_text_input_backspace_cb(&m);
    assert(strcmp(text,"甲A乙") == 0 && m.cursor_pos == 0);
    m.clear_default_text=true; fznote_text_input_backspace_cb(&m);
    assert(text[0] == 0 && m.cursor_pos == 0);
    /* Malformed bytes always make progress, including truncated sequences. */
    const unsigned char bad[][5] = {{0xc0,0xaf,0}, {0xed,0xa0,0x80,0}, {0xf4,0x90,0x80,0x80,0}, {0xe4,0xb8,0}};
    for(size_t j=0;j<sizeof(bad)/sizeof(bad[0]);j++) {
        const char* s=(const char*)bad[j]; size_t n=strlen(s), i=0;
        while(i<n) {size_t next=flipnote_utf8_next(s,i); assert(next>i && next<=n); i=next;}
    }
    return 0;
}
"""
        )

    def test_real_text_draw_and_header_clip_keep_utf8_and_input_intact(self):
        # Only the text portion is compiled; the unchanged keyboard follows it.
        draw = (
            INPUT[
                INPUT.index(
                    "static void fznote_text_input_view_draw_callback("
                ) : INPUT.index(
                    "    for(uint8_t row = 0; row < keyboard_row_count; row++)"
                )
            ]
            + "    (void)text_length; /* used by the keyboard portion omitted here */\n}\n"
        )
        fit = NOTE[
            NOTE.index("static void header_fit(") : NOTE.index("static void draw_cb(")
        ]
        native_test(
            PREAMBLE
            + HEADER
            + DISPLAY
            + draw
            + fit
            + r"""
int main(void) {
    Canvas canvas=0;
    char input[128], original[128];
    const char* unit="甲é😀A";
    input[0]=0;
    for(int n=0;n<12;n++) strcat(input,unit);
    strcpy(original,input);
    FzNoteTextInputModel m={.header="编辑行", .text_buffer=input, .text_buffer_size=sizeof(input)};
    for(size_t i=0;i<=strlen(input)+4;i++) {
        m.cursor_pos=i;
        fznote_text_input_view_draw_callback(&canvas,&m);
        assert(strcmp(input,original)==0 && m.cursor_pos==flipnote_utf8_floor(input,i));
    }
    m.clear_default_text=true; fznote_text_input_view_draw_callback(&canvas,&m);
    assert(strcmp(input,original)==0 && text_draws>0);
    const char* names[]={"/中文文件名非常长.txt", "*abcdefghijklmnopqrstuvwxyz0123456789", "(新建)", ""};
    for(size_t n=0;n<sizeof(names)/sizeof(names[0]);n++) {
        for(int width=0;width<=128;width++) {
            struct {char label[128]; unsigned guard;} storage={.guard=0x12345678};
            strcpy(storage.label,names[n]); header_fit(&canvas,storage.label,width);
            assert(valid_utf8(storage.label));
            assert(canvas_string_width(&canvas,storage.label)<=(unsigned)width);
            assert(storage.guard==0x12345678);
        }
    }
    return 0;
}
"""
        )
