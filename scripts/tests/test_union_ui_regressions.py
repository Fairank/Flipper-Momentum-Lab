"""Production C regressions for CJK buttons and always-on display timers."""

from pathlib import Path
import unittest

from test_unleashed_integration import native_test

ROOT = Path(__file__).resolve().parents[2]


class UnionUIRegressions(unittest.TestCase):
    def test_chinese_button_text_has_a_complete_background(self):
        source = (ROOT / "applications/services/gui/elements.c").read_text(
            encoding="utf-8"
        )
        source = source[
            source.index("void elements_button_left(") : source.index(
                "static size_t\n    elements_get_max_chars_to_fit("
            )
        ]
        header = (
            (ROOT / "applications/services/gui/utf8_internal.h")
            .read_text(encoding="utf-8")
            .replace("#pragma once", "")
        )
        native_test(
            r"""
#include <assert.h>
#include <string.h>
"""
            + header
            + r"""
typedef int Canvas;
typedef struct { int width, height; } Icon;
static const Icon I_ButtonLeft_4x7 = {4,7}, I_ButtonRight_4x7 = {4,7},
    I_ButtonCenter_7x7 = {7,7}, I_ButtonUp_7x4 = {7,4}, I_ButtonDown_7x4 = {7,4};
#define furi_check assert
static int box_top, box_bottom, box_height, strings;
static size_t canvas_string_width(Canvas* c, const char* s) {(void)c; return !s ? 0 : gui_utf8_has_cjk(s) ? 24 : strlen(s)*5;}
static size_t canvas_height(Canvas* c) {(void)c; return 64;}
static size_t canvas_width(Canvas* c) {(void)c; return 128;}
static int icon_get_width(const Icon* i) {return i->width;}
static int icon_get_height(const Icon* i) {return i->height;}
static void canvas_draw_box(Canvas* c,int x,int y,size_t w,size_t h) {(void)c;(void)x;(void)w;box_top=y;box_bottom=y+h;box_height=h;}
static void canvas_draw_line(Canvas* c,int x,int y,int x2,int y2) {(void)c;(void)x;(void)y;(void)x2;(void)y2;}
static void canvas_invert_color(Canvas* c) {(void)c;}
static void canvas_draw_icon(Canvas* c,int x,int y,const Icon* i) {(void)c;(void)x;assert(y>=box_top && y+i->height<=box_bottom);}
static void canvas_draw_str(Canvas* c,int x,int y,const char* s) {
    (void)c;(void)x; if(!s) return; ++strings;
    int ascent=gui_utf8_has_cjk(s) ? GUI_CJK_GLYPH_ASCENT : 8;
    assert(y-ascent>=box_top && y+GUI_CJK_GLYPH_DESCENT<box_bottom);
}
"""
            + source
            + r"""
int main(void) {
    Canvas c=0;
    assert(!gui_utf8_is_ascii("保存"));
    assert(gui_utf8_prev_start("保存",6)==3);
    assert(gui_utf8_offset("保存",1)==3);
    assert(gui_utf8_line_height(8,"保存")==12);
    void (*buttons[])(Canvas*,const char*)={elements_button_left,elements_button_right,elements_button_center,elements_button_up,elements_button_down};
    for(size_t i=0;i<sizeof(buttons)/sizeof(buttons[0]);i++) {
        buttons[i](&c,"Save"); assert(box_height==12);
        buttons[i](&c,"保存"); assert(box_height==15);
        buttons[i](&c,NULL); assert(box_height==12);
    }
    assert(strings==10);
    return 0;
}
"""
        )

    def test_always_on_cancels_an_old_timeout_without_starting_zero_timer(self):
        source = (
            ROOT / "applications/services/notification/notification_app.c"
        ).read_text(encoding="utf-8")
        start = source.index("static void notification_reset_notification_layer(")
        source = source[
            start : source.index(
                "static void notification_apply_notification_leds(", start
            )
        ]
        native_test(
            r"""
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
typedef struct {struct {float display_brightness;} settings; int* display_timer; int led[3];} NotificationApp;
enum {reset_blink_mask=1, reset_red_mask=2, reset_green_mask=4, reset_blue_mask=8,
      reset_vibro_mask=16,reset_sound_mask=32,reset_display_mask=64,LightBacklight=0};
static unsigned delay,starts,stops,last_delay;
static bool float_is_equal(float a,float b) {return a==b;}
static void furi_hal_light_blink_stop(void) {}
static void notification_reset_notification_led_layer(int* p) {(void)p;}
static void notification_vibro_off(void) {}
static void notification_sound_off(void) {}
static void furi_hal_light_set(int light,float level) {(void)light;(void)level;}
static uint32_t notification_settings_display_off_delay_ticks(NotificationApp* app) {(void)app;return delay;}
static void furi_timer_start(int* timer,uint32_t ticks) {(void)timer;assert(ticks>0);starts++;last_delay=ticks;}
static void furi_timer_stop(int* timer) {(void)timer;stops++;}
"""
            + source
            + r"""
int main(void) {
    NotificationApp app={.settings.display_brightness=0.5f};
    delay=1000;
    notification_reset_notification_layer(&app,reset_display_mask,0.5f);
    assert(starts==1 && stops==0 && last_delay==1000);
    delay=0;
    notification_reset_notification_layer(&app,reset_display_mask,0.5f);
    assert(starts==1 && stops==1);
    notification_reset_notification_layer(&app,reset_sound_mask,0.5f);
    assert(starts==1 && stops==1);
    delay=1;
    notification_reset_notification_layer(&app,reset_display_mask,0.5f);
    assert(starts==2 && stops==1 && last_delay==1);
    return 0;
}
"""
        )
