"""Check the imported calendar's real date and drawing code against Python dates."""

import calendar
from pathlib import Path
import re
import unittest
from test_unleashed_integration import native_test

ROOT = Path(__file__).resolve().parents[2]


class CalendarUnionTests(unittest.TestCase):
    def test_all_months_across_leap_centuries_and_six_row_layout(self):
        source = (
            ROOT / "applications/union/calendar/views/calendar_month_browser.c"
        ).read_text(encoding="utf-8")
        constants = "\n".join(re.findall(r"^#define .*$", source, re.M))
        weekdays = source[
            source.index("static const char* const weekdays") : source.index(
                "struct MonthBrowser"
            )
        ]
        functions = source[
            source.index("static bool is_leap_year") : source.index(
                "void calendar_month_browser_alloc_enter_callback"
            )
        ]
        # Independent oracle includes 1800/1900/2000/2100/2200/2400 and every weekday.
        vectors = []
        for year in list(range(1799, 2402)) + [1, 4, 100, 400, 9999]:
            for month in range(1, 13):
                weekday, days = calendar.monthrange(year, month)
                vectors.append("{%d,%d,%d,%d}" % (year, month, (weekday + 1) % 7, days))
        native_test(
            r"""
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
typedef int Canvas;
typedef struct {int16_t year_selected;int8_t month_selected;} MonthBrowserViewModel;
enum {FontSecondary,FontKeyboard,AlignRight,AlignBottom};
#define furi_assert assert
static int day_count,seen[32];
static void canvas_set_font(Canvas* c,int font) {*c=font;}
static void canvas_draw_str_aligned(Canvas* c,int x,int y,int h,int v,const char* text) {
    (void)h;(void)v;assert(x<=128 && y<64);
    if(*c==FontSecondary) {assert(y>=11);return;}
    assert(y>=7);int day=atoi(text);assert(day>=1 && day<=31);
    assert(!seen[day]);seen[day]=1;day_count++;
}
"""
            + constants
            + "\n"
            + weekdays
            + functions
            + "\nstatic const int cases[][4]={"
            + ",".join(vectors)
            + r"""};
int main(void) {
    Canvas c=0;
    for(size_t i=0;i<sizeof(cases)/sizeof(cases[0]);i++) {
        MonthBrowserViewModel m={cases[i][0],cases[i][1]};
        assert(get_first_day_of_week(m.year_selected,m.month_selected)==cases[i][2]);
        assert(get_days_in_month(m.year_selected,m.month_selected)==cases[i][3]);
        day_count=0;for(int d=0;d<32;d++)seen[d]=0;
        calendar_month_browser_draw_callback(&c,&m);
        assert(day_count==cases[i][3]);
        for(int d=1;d<=cases[i][3];d++)assert(seen[d]);
    }
    return 0;
}
"""
        )
