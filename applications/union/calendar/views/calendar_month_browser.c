#include "calendar_month_browser.h"
#include <furi.h>
#include <core/check.h>
#include <core/record.h>
#include <core/log.h>
#include <furi_hal_rtc.h>

// A month can touch six weeks (30 days from a Saturday, 31 from a Friday or Saturday).
// FontKeyboard digits light the 7 rows above their baseline, so an 8 px pitch keeps a
// blank row between weeks: baselines 22..62, lit rows 15..61. The weekday labels come
// from the firmware's Chinese font, whose glyphs reach 11 rows above the baseline and
// include the baseline row, so baseline 11 keeps them in rows 0..11, three blank rows
// above the first week.
#define COLUMN_GAP_PX         17
#define ROW_GAP_PX            8
#define GRID_OFFSET_X         3
#define GRID_OFFSET_Y         14
#define GRID_TEMPLATE_COLUMNS 7
#define GRID_TEMPLATE_ROWS    6
#define HEADER_BASELINE_Y     11

// Sunday first, like the columns filled from get_first_day_of_week()
static const char* const weekdays[GRID_TEMPLATE_COLUMNS] =
    {"日", "一", "二", "三", "四", "五", "六"};

struct MonthBrowser {
    View* view;
    VariableSharedContext* variable_shared_context;
};

typedef struct {
    int16_t year_selected;
    int8_t month_selected;
} MonthBrowserViewModel;

static bool is_leap_year(int16_t year) {
    return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
}

static int8_t get_days_in_month(int16_t year, int8_t month) {
    int8_t month_days[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    if(month - 1 == 1) {
        bool leap_days = is_leap_year(year);
        return 28 + leap_days;
    } else {
        return month_days[month - 1];
    }
}

// Gregorian weekday of the 1st of the month, Sunday = 0 like the grid columns
int8_t get_first_day_of_week(int16_t year, int8_t month) {
    int32_t a = (14 - month) / 12;
    int32_t y = year - a;
    int32_t m = month + 12 * a - 2;
    int32_t day_of_week = (1 + y + y / 4 - y / 100 + y / 400 + 31 * m / 12) % 7;
    // C division truncates, so years before 1 can leave a negative remainder
    return day_of_week < 0 ? day_of_week + 7 : day_of_week;
}

static void calendar_month_browser_draw_callback(Canvas* canvas, MonthBrowserViewModel* model) {
    furi_assert(canvas);

    int8_t days_in_month = get_days_in_month(model->year_selected, model->month_selected);

    int8_t first_day_of_week = get_first_day_of_week(model->year_selected, model->month_selected);

    // One 12 px wide label per column, right-aligned like the day numbers below it
    canvas_set_font(canvas, FontSecondary);
    for(int8_t day_of_week = 1; day_of_week <= GRID_TEMPLATE_COLUMNS; day_of_week++) {
        canvas_draw_str_aligned(
            canvas,
            GRID_OFFSET_X + day_of_week * COLUMN_GAP_PX,
            HEADER_BASELINE_Y,
            AlignRight,
            AlignBottom,
            weekdays[day_of_week - 1]);
    }
    canvas_set_font(canvas, FontKeyboard);

    for(int8_t week = 1; week <= GRID_TEMPLATE_ROWS; week++) {
        for(int8_t day_of_week = 1; day_of_week <= GRID_TEMPLATE_COLUMNS; day_of_week++) {
            int8_t day = (week - 1) * GRID_TEMPLATE_COLUMNS + day_of_week - first_day_of_week;

            if(day > days_in_month) continue;

            if(week == 1 && day_of_week <= first_day_of_week) continue;

            char day_str[5] = {0};
            snprintf(day_str, sizeof(day_str), "%d", day);
            canvas_draw_str_aligned(
                canvas,
                GRID_OFFSET_X + day_of_week * COLUMN_GAP_PX,
                GRID_OFFSET_Y + week * ROW_GAP_PX,
                AlignRight,
                AlignBottom,
                day_str);
        }
    }
}

void calendar_month_browser_alloc_enter_callback(void* context) {
    furi_assert(context);

    MonthBrowser* calendar_month_browser = context;

    with_view_model(
        calendar_month_browser->view,
        MonthBrowserViewModel * model,
        {
            model->year_selected = calendar_month_browser->variable_shared_context->year_selected;
            model->month_selected =
                calendar_month_browser->variable_shared_context->month_selected;
        },
        true);
}

MonthBrowser* calendar_month_browser_alloc(VariableSharedContext* variable_shared_context) {
    furi_assert(variable_shared_context);

    MonthBrowser* calendar_month_browser = malloc(sizeof(MonthBrowser));
    calendar_month_browser->variable_shared_context = variable_shared_context;
    calendar_month_browser->view = view_alloc();

    view_allocate_model(
        calendar_month_browser->view, ViewModelTypeLocking, sizeof(MonthBrowserViewModel));
    view_set_context(calendar_month_browser->view, calendar_month_browser);
    view_set_draw_callback(
        calendar_month_browser->view, (ViewDrawCallback)calendar_month_browser_draw_callback);

    view_set_enter_callback(
        calendar_month_browser->view, calendar_month_browser_alloc_enter_callback);

    return calendar_month_browser;
}

void calendar_month_browser_free(MonthBrowser* calendar_month_browser) {
    furi_assert(calendar_month_browser);
    view_free(calendar_month_browser->view);
    free(calendar_month_browser);
}

View* calendar_month_browser_get_view(MonthBrowser* calendar_month_browser) {
    furi_assert(calendar_month_browser);
    return calendar_month_browser->view;
}
