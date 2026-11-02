"""Exercise the imported clock's real time conversion, stopwatch and alarm state."""

from pathlib import Path
import unittest

from test_unleashed_integration import native_test

ROOT = Path(__file__).resolve().parents[2]


def section(text, start, end):
    begin = text.index(start)
    return text[begin : text.index(end, begin)]


class ClockPortTests(unittest.TestCase):
    def test_alarm_rearm_stopwatch_and_12_hour_boundaries(self):
        source = (ROOT / "applications/main/clock_app/clock_app.c").read_text(
            encoding="utf-8"
        )
        header = (ROOT / "applications/main/clock_app/clock_app.h").read_text(
            encoding="utf-8"
        )
        types = header[header.index("typedef enum {") :]
        native_test(
            r"""
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
typedef void Gui;
typedef void ViewDispatcher;
typedef void View;
typedef void VariableItemList;
typedef void VariableItem;
typedef int LocaleDateFormat;
typedef enum {LocaleTimeFormat24h,LocaleTimeFormat12h} LocaleTimeFormat;
typedef struct {uint8_t hour,minute;} DateTime;
static DateTime now;
static uint32_t timestamp;
static void furi_hal_rtc_get_datetime(DateTime* result) {*result=now;}
static uint32_t furi_hal_rtc_get_timestamp(void) {return timestamp;}
"""
            + types
            + section(
                source, "static void to_12h(", "static void\n    format_alarm_time("
            )
            + section(
                source, "static void timer_start_stop(", "static void ns_settings_save("
            )
            + section(source, "static void ns_check_alarm(", "static void ns_tick(")
            + r"""
int main(void) {
    for(uint8_t hour=0;hour<24;hour++) {
        uint8_t display; bool pm;
        to_12h(hour,&display,&pm);
        assert(display>=1 && display<=12 && pm==(hour>=12));
        assert(to_24h(display,pm)==hour);
    }
    AppState app={0};
    timestamp=1000; timer_start_stop(&app);
    assert(app.timer_running && app.timer_start_timestamp==1000);
    timestamp=1037; timer_start_stop(&app);
    assert(!app.timer_running && app.timer_stopped_seconds==37);
    timestamp=1100; timer_start_stop(&app);
    assert(app.timer_running && app.timer_start_timestamp==1063);
    timestamp=1110; timer_start_stop(&app);
    assert(!app.timer_running && app.timer_stopped_seconds==47);
    timer_reset_seconds(&app);
    assert(!app.timer_running && !app.timer_start_timestamp && !app.timer_stopped_seconds);
    app.settings=(NsSettings){.alarm_enabled=true,.alarm_hour=7,.alarm_minute=30};
    now=(DateTime){7,29}; ns_check_alarm(&app); assert(!app.alarm_firing);
    now.minute=30; ns_check_alarm(&app);
    assert(app.alarm_firing && app.alarm_consumed && app.alarm_flash_on);
    app.alarm_firing=false; ns_check_alarm(&app); assert(!app.alarm_firing);
    now.minute=31; ns_check_alarm(&app); assert(!app.alarm_consumed);
    now.minute=30; ns_check_alarm(&app); assert(app.alarm_firing);
    app.alarm_firing=false; app.settings.alarm_enabled=false;
    ns_check_alarm(&app); assert(!app.alarm_firing && !app.alarm_consumed);
    ClockModel published={.snapshot=app};
    app.settings.alarm_hour=22;
    assert(published.snapshot.settings.alarm_hour==7);
    return 0;
}
"""
        )
