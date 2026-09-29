#include "elements.h"
#include "utf8_internal.h"
#include <m-core.h>
#include <assets_icons.h>
#include <furi_hal_resources.h>
#include <furi_hal.h>

#include <gui/canvas.h>
#include <gui/icon_i.h>
#include <gui/icon_animation_i.h>

#include <furi.h>

#include <math.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

#include <momentum/settings.h>

typedef struct {
    int32_t x;
    int32_t y;
    int32_t leading_min;
    int32_t leading_default;
    size_t height;
    size_t descender;
    size_t len;
    const char* text;
    // Used by the UTF-8 layout only: advance of the line and the extra row that
    // inverted glyphs need above and below
    size_t width;
    int32_t pad;
} ElementTextBoxLine;

void elements_progress_bar(Canvas* canvas, int32_t x, int32_t y, size_t width, float progress) {
    furi_check(canvas);
    furi_check((progress >= 0.0f) && (progress <= 1.0f));
    size_t height = 9;

    float progress_width = roundf(progress * (width - 2));

    canvas_set_color(canvas, ColorWhite);
    canvas_draw_box(canvas, x + 1, y + 1, width - 2, height - 2);
    canvas_set_color(canvas, ColorBlack);
    canvas_draw_rframe(canvas, x, y, width, height, 3);

    canvas_draw_box(canvas, x + 1, y + 1, progress_width, height - 2);
}

void elements_progress_bar_with_text(
    Canvas* canvas,
    int32_t x,
    int32_t y,
    size_t width,
    float progress,
    const char* text) {
    furi_check(canvas);
    furi_check((progress >= 0.0f) && (progress <= 1.0f));
    size_t height = 11;

    float progress_width = roundf(progress * (width - 2));

    canvas_set_color(canvas, ColorWhite);
    canvas_draw_box(canvas, x + 1, y + 1, width - 2, height - 2);
    canvas_set_color(canvas, ColorBlack);
    canvas_draw_rframe(canvas, x, y, width, height, 3);

    canvas_draw_box(canvas, x + 1, y + 1, progress_width, height - 2);

    canvas_set_color(canvas, ColorXOR);
    canvas_set_font(canvas, FontSecondary);
    canvas_draw_str_aligned(canvas, x + width / 2, y + 2, AlignCenter, AlignTop, text);
}

void elements_scrollbar_pos(
    Canvas* canvas,
    int32_t x,
    int32_t y,
    size_t height,
    size_t pos,
    size_t total) {
    furi_check(canvas);

    // prevent overflows
    canvas_set_color(canvas, ColorWhite);
    canvas_draw_box(canvas, x - 3, y, 3, height);

    // dot line
    canvas_set_color(canvas, ColorBlack);
    for(int32_t i = y; i < (int32_t)height + y; i += 2) {
        canvas_draw_dot(canvas, x - 2, i);
    }

    // Position block
    if(total) {
        float block_h = ((float)height) / total;
        canvas_draw_box(canvas, x - 3, y + (block_h * pos), 3, MAX(block_h, 1));
    }
}

void elements_scrollbar_horizontal(
    Canvas* canvas,
    int32_t x,
    int32_t y,
    size_t width,
    size_t pos,
    size_t total) {
    furi_check(canvas);

    // prevent overflows
    canvas_set_color(canvas, ColorWhite);
    canvas_draw_box(canvas, x, y - 3, width, 3);

    // dot line
    canvas_set_color(canvas, ColorBlack);
    for(size_t i = x; i < width + x; i += 2) {
        canvas_draw_dot(canvas, i, y - 2);
    }

    // Position block
    if(total) {
        float block_w = ((float)width) / total;
        canvas_draw_box(canvas, x + (block_w * pos), y - 3, MAX(block_w, 1), 3);
    }
}

void elements_scrollbar(Canvas* canvas, size_t pos, size_t total) {
    furi_check(canvas);

    size_t width = canvas_width(canvas);
    size_t height = canvas_height(canvas);

    // prevent overflows
    canvas_set_color(canvas, ColorWhite);
    canvas_draw_box(canvas, width - 3, 0, 3, height);

    // dot line
    canvas_set_color(canvas, ColorBlack);
    for(size_t i = 0; i < height; i += 2) {
        canvas_draw_dot(canvas, width - 2, i);
    }

    // Position block
    if(total) {
        float block_h = ((float)height) / total;
        canvas_draw_box(canvas, width - 3, block_h * pos, 3, MAX(block_h, 1));
    }
}

void elements_frame(Canvas* canvas, int32_t x, int32_t y, size_t width, size_t height) {
    furi_check(canvas);

    canvas_draw_line(canvas, x + 2, y, x + width - 2, y);
    canvas_draw_line(canvas, x + 1, y + height - 1, x + width, y + height - 1);
    canvas_draw_line(canvas, x + 2, y + height, x + width - 1, y + height);

    canvas_draw_line(canvas, x, y + 2, x, y + height - 2);
    canvas_draw_line(canvas, x + width - 1, y + 1, x + width - 1, y + height - 2);
    canvas_draw_line(canvas, x + width, y + 2, x + width, y + height - 2);

    canvas_draw_dot(canvas, x + 1, y + 1);
}

void elements_button_left(Canvas* canvas, const char* str) {
    furi_check(canvas);

    const size_t button_height = 12;
    const size_t vertical_offset = 3;
    const size_t horizontal_offset = 3;
    const size_t string_width = canvas_string_width(canvas, str);
    const Icon* icon = &I_ButtonLeft_4x7;
    const int32_t icon_h_offset = 3;
    const int32_t icon_width_with_offset = icon->width + icon_h_offset;
    const int32_t icon_v_offset = icon->height + vertical_offset;
    const size_t button_width = string_width + horizontal_offset * 2 + icon_width_with_offset;

    const int32_t x = 0;
    const int32_t y = canvas_height(canvas);

    canvas_draw_box(canvas, x, y - button_height, button_width, button_height);
    canvas_draw_line(canvas, x + button_width + 0, y, x + button_width + 0, y - button_height + 0);
    canvas_draw_line(canvas, x + button_width + 1, y, x + button_width + 1, y - button_height + 1);
    canvas_draw_line(canvas, x + button_width + 2, y, x + button_width + 2, y - button_height + 2);

    canvas_invert_color(canvas);
    canvas_draw_icon(canvas, x + horizontal_offset, y - icon_v_offset, &I_ButtonLeft_4x7);
    canvas_draw_str(
        canvas, x + horizontal_offset + icon_width_with_offset, y - vertical_offset, str);
    canvas_invert_color(canvas);
}

void elements_button_right(Canvas* canvas, const char* str) {
    furi_check(canvas);

    const size_t button_height = 12;
    const size_t vertical_offset = 3;
    const size_t horizontal_offset = 3;
    const size_t string_width = canvas_string_width(canvas, str);
    const Icon* icon = &I_ButtonRight_4x7;
    const int32_t icon_h_offset = 3;
    const int32_t icon_width_with_offset = icon->width + icon_h_offset;
    const int32_t icon_v_offset = icon->height + vertical_offset;
    const size_t button_width = string_width + horizontal_offset * 2 + icon_width_with_offset;

    const int32_t x = canvas_width(canvas);
    const int32_t y = canvas_height(canvas);

    canvas_draw_box(canvas, x - button_width, y - button_height, button_width, button_height);
    canvas_draw_line(canvas, x - button_width - 1, y, x - button_width - 1, y - button_height + 0);
    canvas_draw_line(canvas, x - button_width - 2, y, x - button_width - 2, y - button_height + 1);
    canvas_draw_line(canvas, x - button_width - 3, y, x - button_width - 3, y - button_height + 2);

    canvas_invert_color(canvas);
    canvas_draw_str(canvas, x - button_width + horizontal_offset, y - vertical_offset, str);
    canvas_draw_icon(
        canvas, x - horizontal_offset - icon->width, y - icon_v_offset, &I_ButtonRight_4x7);
    canvas_invert_color(canvas);
}

void elements_button_up(Canvas* canvas, const char* str) {
    furi_check(canvas);

    const Icon* icon = &I_ButtonUp_7x4;

    const size_t button_height = 12;
    const size_t vertical_offset = 3;
    const size_t horizontal_offset = 3;
    const size_t string_width = canvas_string_width(canvas, str);
    const int32_t icon_h_offset = 3;
    const int32_t icon_width_with_offset = icon_get_width(icon) + icon_h_offset;
    const int32_t icon_v_offset = icon_get_height(icon) + (int32_t)vertical_offset;
    const size_t button_width = string_width + horizontal_offset * 2 + icon_width_with_offset;

    const int32_t x = 0;
    const int32_t y = 0 + button_height;

    int32_t line_x = x + button_width;
    int32_t line_y = y - button_height;

    canvas_draw_box(canvas, x, line_y, button_width, button_height);
    canvas_draw_line(canvas, line_x + 0, line_y, line_x + 0, y - 1);
    canvas_draw_line(canvas, line_x + 1, line_y, line_x + 1, y - 2);
    canvas_draw_line(canvas, line_x + 2, line_y, line_x + 2, y - 3);

    canvas_invert_color(canvas);
    canvas_draw_icon(canvas, x + horizontal_offset, y - icon_v_offset, icon);
    canvas_draw_str(
        canvas, x + horizontal_offset + icon_width_with_offset, y - vertical_offset, str);
    canvas_invert_color(canvas);
}

void elements_button_down(Canvas* canvas, const char* str) {
    furi_check(canvas);

    const Icon* icon = &I_ButtonDown_7x4;

    const size_t button_height = 12;
    const size_t vertical_offset = 3;
    const size_t horizontal_offset = 3;
    const size_t string_width = canvas_string_width(canvas, str);
    const int32_t icon_h_offset = 3;
    const int32_t icon_width_with_offset = icon_get_width(icon) + icon_h_offset;
    const int32_t icon_v_offset = icon_get_height(icon) + vertical_offset + 1;
    const size_t button_width = string_width + horizontal_offset * 2 + icon_width_with_offset;

    const int32_t x = canvas_width(canvas);
    const int32_t y = button_height;

    int32_t line_x = x - button_width;
    int32_t line_y = y - button_height;

    canvas_draw_box(canvas, line_x, line_y, button_width, button_height);
    canvas_draw_line(canvas, line_x - 1, line_y, line_x - 1, y - 1);
    canvas_draw_line(canvas, line_x - 2, line_y, line_x - 2, y - 2);
    canvas_draw_line(canvas, line_x - 3, line_y, line_x - 3, y - 3);

    canvas_invert_color(canvas);
    canvas_draw_str(canvas, x - button_width + horizontal_offset, y - vertical_offset, str);
    canvas_draw_icon(
        canvas, x - horizontal_offset - icon_get_width(icon), y - icon_v_offset, icon);
    canvas_invert_color(canvas);
}

void elements_button_center(Canvas* canvas, const char* str) {
    furi_check(canvas);

    const size_t button_height = 12;
    const size_t vertical_offset = 3;
    const size_t horizontal_offset = 1;
    const size_t string_width = canvas_string_width(canvas, str);
    const Icon* icon = &I_ButtonCenter_7x7;
    const int32_t icon_h_offset = 3;
    const int32_t icon_width_with_offset = icon->width + icon_h_offset;
    const int32_t icon_v_offset = icon->height + vertical_offset;
    const size_t button_width = string_width + horizontal_offset * 2 + icon_width_with_offset;

    const int32_t x = (canvas_width(canvas) - button_width) / 2;
    const int32_t y = canvas_height(canvas);

    canvas_draw_box(canvas, x, y - button_height, button_width, button_height);

    canvas_draw_line(canvas, x - 1, y, x - 1, y - button_height + 0);
    canvas_draw_line(canvas, x - 2, y, x - 2, y - button_height + 1);
    canvas_draw_line(canvas, x - 3, y, x - 3, y - button_height + 2);

    canvas_draw_line(canvas, x + button_width + 0, y, x + button_width + 0, y - button_height + 0);
    canvas_draw_line(canvas, x + button_width + 1, y, x + button_width + 1, y - button_height + 1);
    canvas_draw_line(canvas, x + button_width + 2, y, x + button_width + 2, y - button_height + 2);

    canvas_invert_color(canvas);
    canvas_draw_icon(canvas, x + horizontal_offset, y - icon_v_offset, &I_ButtonCenter_7x7);
    canvas_draw_str(
        canvas, x + horizontal_offset + icon_width_with_offset, y - vertical_offset, str);
    canvas_invert_color(canvas);
}

static size_t
    elements_get_max_chars_to_fit(Canvas* canvas, Align horizontal, const char* text, int32_t x) {
    const char* end = strchr(text, '\n');
    if(end == NULL) {
        end = text + strlen(text);
    }
    size_t text_size = end - text;
    FuriString* str;
    str = furi_string_alloc_set(text);
    furi_string_left(str, text_size);
    size_t result = 0;

    size_t len_px = canvas_string_width(canvas, furi_string_get_cstr(str));
    size_t px_left = 0;
    if(horizontal == AlignCenter) {
        if(x > (int32_t)(canvas_width(canvas) / 2)) {
            px_left = (canvas_width(canvas) - x) * 2;
        } else {
            px_left = x * 2;
        }
    } else if(horizontal == AlignLeft) {
        px_left = canvas_width(canvas) - x;
    } else if(horizontal == AlignRight) {
        px_left = x;
    } else {
        furi_crash();
    }

    if(len_px > px_left) {
        size_t excess_symbols_approximately =
            ceilf((float)(len_px - px_left) / ((float)len_px / (float)text_size));
        // reduce to 5 to be sure dash fit, and next line will be at least 5 symbols long
        if(excess_symbols_approximately > 0) {
            excess_symbols_approximately = MAX(excess_symbols_approximately, 5u);
            // Keep at least one symbol so the caller always advances
            if(excess_symbols_approximately + 1 < text_size) {
                result = text_size - excess_symbols_approximately - 1;
            } else {
                result = 1;
            }
        } else {
            result = text_size;
        }
    } else {
        result = text_size;
    }

    // Byte counts must not end inside a UTF-8 sequence; a line keeps its first
    // codepoint whole when even that is too wide
    result = gui_utf8_floor(text, result);
    if(result == 0 && text_size > 0) {
        uint32_t codepoint;
        result = gui_utf8_decode(text, &codepoint);
    }

    furi_string_free(str);
    return result;
}

void elements_multiline_text_aligned(
    Canvas* canvas,
    int32_t x,
    int32_t y,
    Align horizontal,
    Align vertical,
    const char* text) {
    furi_check(canvas);
    furi_check(text);

    size_t lines_count = 0;
    size_t font_height = gui_utf8_line_height(canvas_current_font_height(canvas), text);
    FuriString* line;

    /* go through text line by line and count lines */
    for(const char* start = text; start[0];) {
        size_t chars_fit = elements_get_max_chars_to_fit(canvas, horizontal, start, x);
        ++lines_count;
        start += chars_fit;
        start += start[0] == '\n' ? 1 : 0;
    }

    if(vertical == AlignBottom) {
        y -= font_height * (lines_count - 1);
    } else if(vertical == AlignCenter) {
        y -= (font_height * (lines_count - 1)) / 2;
    }

    /* go through text line by line and print them */
    for(const char* start = text; start[0];) {
        size_t chars_fit = elements_get_max_chars_to_fit(canvas, horizontal, start, x);

        if((start[chars_fit] == '\n') || (start[chars_fit] == 0)) {
            line = furi_string_alloc_printf("%.*s", (int)chars_fit, start);
        } else if((y + font_height) > canvas_height(canvas)) {
            line = furi_string_alloc_printf("%.*s...\n", (int)chars_fit, start);
        } else {
            // A Latin word broken here gets a dash; a break next to a CJK character
            // needs none, and a single character is never traded for the dash
            size_t dash_fit = gui_utf8_prev_start(start, chars_fit);
            uint32_t before;
            uint32_t after;
            gui_utf8_decode(&start[dash_fit], &before);
            gui_utf8_decode(&start[chars_fit], &after);
            if(dash_fit && !gui_utf8_is_cjk(before) && !gui_utf8_is_cjk(after)) {
                chars_fit = dash_fit; // account for the dash
                line = furi_string_alloc_printf("%.*s-\n", (int)chars_fit, start);
            } else {
                line = furi_string_alloc_printf("%.*s\n", (int)chars_fit, start);
            }
        }
        canvas_draw_str_aligned(canvas, x, y, horizontal, vertical, furi_string_get_cstr(line));
        furi_string_free(line);
        y += font_height;
        if(y > (int32_t)canvas_height(canvas)) {
            break;
        }

        start += chars_fit;
        start += start[0] == '\n' ? 1 : 0;
    }
}

void elements_multiline_text(Canvas* canvas, int32_t x, int32_t y, const char* text) {
    furi_check(canvas);
    furi_check(text);

    size_t font_height = gui_utf8_line_height(canvas_current_font_height(canvas), text);
    FuriString* str;
    str = furi_string_alloc();
    const char* start = text;
    char* end;
    do {
        end = strchr(start, '\n');
        if(end) {
            furi_string_set_strn(str, start, end - start);
            start = end + 1;
        } else {
            furi_string_set(str, start);
        }
        canvas_draw_str(canvas, x, y, furi_string_get_cstr(str));
        y += font_height;
    } while(end && y < 64);
    furi_string_free(str);
}

void elements_multiline_text_framed(Canvas* canvas, int32_t x, int32_t y, const char* text) {
    furi_check(canvas);
    furi_check(text);

    size_t font_height = gui_utf8_line_height(canvas_current_font_height(canvas), text);
    size_t str_width = canvas_string_width(canvas, text);

    // count \n's
    size_t lines = 1;
    const char* t = text;
    while(*t != '\0') {
        if(*t == '\n') {
            lines++;
            size_t temp_width = canvas_string_width(canvas, t + 1);
            str_width = temp_width > str_width ? temp_width : str_width;
        }
        t++;
    }

    canvas_set_color(canvas, ColorWhite);
    canvas_draw_box(canvas, x, y - font_height, str_width + 8, font_height * lines + 4);
    canvas_set_color(canvas, ColorBlack);
    elements_multiline_text(canvas, x + 4, y - 1, text);
    elements_frame(canvas, x, y - font_height, str_width + 8, font_height * lines + 4);
}

void elements_slightly_rounded_frame(
    Canvas* canvas,
    int32_t x,
    int32_t y,
    size_t width,
    size_t height) {
    furi_check(canvas);
    canvas_draw_rframe(canvas, x, y, width, height, 1);
}

void elements_slightly_rounded_box(
    Canvas* canvas,
    int32_t x,
    int32_t y,
    size_t width,
    size_t height) {
    furi_check(canvas);
    canvas_draw_rbox(canvas, x, y, width, height, 1);
}

void elements_bold_rounded_frame(Canvas* canvas, int32_t x, int32_t y, size_t width, size_t height) {
    furi_check(canvas);

    canvas_set_color(canvas, ColorWhite);
    canvas_draw_box(canvas, x + 2, y + 2, width - 3, height - 3);
    canvas_set_color(canvas, ColorBlack);

    canvas_draw_line(canvas, x + 3, y, x + width - 3, y);
    canvas_draw_line(canvas, x + 2, y + 1, x + width - 2, y + 1);

    canvas_draw_line(canvas, x, y + 3, x, y + height - 3);
    canvas_draw_line(canvas, x + 1, y + 2, x + 1, y + height - 2);

    canvas_draw_line(canvas, x + width, y + 3, x + width, y + height - 3);
    canvas_draw_line(canvas, x + width - 1, y + 2, x + width - 1, y + height - 2);

    canvas_draw_line(canvas, x + 3, y + height, x + width - 3, y + height);
    canvas_draw_line(canvas, x + 2, y + height - 1, x + width - 2, y + height - 1);

    canvas_draw_dot(canvas, x + 2, y + 2);
    canvas_draw_dot(canvas, x + 3, y + 2);
    canvas_draw_dot(canvas, x + 2, y + 3);

    canvas_draw_dot(canvas, x + width - 2, y + 2);
    canvas_draw_dot(canvas, x + width - 3, y + 2);
    canvas_draw_dot(canvas, x + width - 2, y + 3);

    canvas_draw_dot(canvas, x + 2, y + height - 2);
    canvas_draw_dot(canvas, x + 3, y + height - 2);
    canvas_draw_dot(canvas, x + 2, y + height - 3);

    canvas_draw_dot(canvas, x + width - 2, y + height - 2);
    canvas_draw_dot(canvas, x + width - 3, y + height - 2);
    canvas_draw_dot(canvas, x + width - 2, y + height - 3);
}

void elements_bubble(Canvas* canvas, int32_t x, int32_t y, size_t width, size_t height) {
    furi_check(canvas);
    canvas_draw_rframe(canvas, x + 4, y, width, height, 3);
    int32_t y_corner = y + height * 2 / 3;
    canvas_draw_line(canvas, x, y_corner, x + 4, y_corner - 4);
    canvas_draw_line(canvas, x, y_corner, x + 4, y_corner + 4);
    canvas_set_color(canvas, ColorWhite);
    canvas_draw_line(canvas, x + 4, y_corner - 3, x + 4, y_corner + 3);
    canvas_set_color(canvas, ColorBlack);
}

void elements_bubble_str(
    Canvas* canvas,
    int32_t x,
    int32_t y,
    const char* text,
    Align horizontal,
    Align vertical) {
    furi_check(canvas);
    furi_check(text);

    size_t font_height = gui_utf8_line_height(canvas_current_font_height(canvas), text);
    size_t str_width = canvas_string_width(canvas, text);

    // count \n's
    size_t lines = 1;
    const char* t = text;
    while(*t != '\0') {
        if(*t == '\n') {
            lines++;
            size_t temp_width = canvas_string_width(canvas, t + 1);
            str_width = temp_width > str_width ? temp_width : str_width;
        }
        t++;
    }

    int32_t frame_x = x;
    int32_t frame_y = y;
    size_t frame_width = str_width + 8;
    size_t frame_height = font_height * lines + 4;

    canvas_set_color(canvas, ColorWhite);
    canvas_draw_box(canvas, frame_x + 1, frame_y + 1, frame_width - 2, frame_height - 2);
    canvas_set_color(canvas, ColorBlack);
    canvas_draw_rframe(canvas, frame_x, frame_y, frame_width, frame_height, 1);
    elements_multiline_text(canvas, x + 4, y - 1 + font_height, text);

    int32_t x1 = 0;
    int32_t x2 = 0;
    int32_t x3 = 0;
    int32_t y1 = 0;
    int32_t y2 = 0;
    int32_t y3 = 0;
    if((horizontal == AlignLeft) && (vertical == AlignTop)) {
        x1 = frame_x;
        y1 = frame_y;
        x2 = frame_x - 4;
        y2 = frame_y;
        x3 = frame_x;
        y3 = frame_y + 4;
        canvas_set_color(canvas, ColorWhite);
        canvas_draw_box(canvas, x2 + 2, y2 + 1, 2, 2);
        canvas_set_color(canvas, ColorBlack);
    } else if((horizontal == AlignLeft) && (vertical == AlignCenter)) {
        x1 = frame_x;
        y1 = frame_y + (frame_height - 1) / 2 - 4;
        x2 = frame_x - 4;
        y2 = frame_y + (frame_height - 1) / 2;
        x3 = frame_x;
        y3 = frame_y + (frame_height - 1) / 2 + 4;
        canvas_set_color(canvas, ColorWhite);
        canvas_draw_box(canvas, x2 + 2, y2 - 2, 2, 5);
        canvas_draw_dot(canvas, x2 + 1, y2);
        canvas_set_color(canvas, ColorBlack);
    } else if((horizontal == AlignLeft) && (vertical == AlignBottom)) {
        x1 = frame_x;
        y1 = frame_y + (frame_height - 1) - 4;
        x2 = frame_x - 4;
        y2 = frame_y + (frame_height - 1);
        x3 = frame_x;
        y3 = frame_y + (frame_height - 1);
        canvas_set_color(canvas, ColorWhite);
        canvas_draw_box(canvas, x2 + 2, y2 - 2, 2, 2);
        canvas_set_color(canvas, ColorBlack);
    } else if((horizontal == AlignRight) && (vertical == AlignTop)) {
        x1 = frame_x + (frame_width - 1);
        y1 = frame_y;
        x2 = frame_x + (frame_width - 1) + 4;
        y2 = frame_y;
        x3 = frame_x + (frame_width - 1);
        y3 = frame_y + 4;
        canvas_set_color(canvas, ColorWhite);
        canvas_draw_box(canvas, x2 - 3, y2 + 1, 2, 2);
        canvas_set_color(canvas, ColorBlack);
    } else if((horizontal == AlignRight) && (vertical == AlignCenter)) {
        x1 = frame_x + (frame_width - 1);
        y1 = frame_y + (frame_height - 1) / 2 - 4;
        x2 = frame_x + (frame_width - 1) + 4;
        y2 = frame_y + (frame_height - 1) / 2;
        x3 = frame_x + (frame_width - 1);
        y3 = frame_y + (frame_height - 1) / 2 + 4;
        canvas_set_color(canvas, ColorWhite);
        canvas_draw_box(canvas, x2 - 3, y2 - 2, 2, 5);
        canvas_draw_dot(canvas, x2 - 1, y2);
        canvas_set_color(canvas, ColorBlack);
    } else if((horizontal == AlignRight) && (vertical == AlignBottom)) {
        x1 = frame_x + (frame_width - 1);
        y1 = frame_y + (frame_height - 1) - 4;
        x2 = frame_x + (frame_width - 1) + 4;
        y2 = frame_y + (frame_height - 1);
        x3 = frame_x + (frame_width - 1);
        y3 = frame_y + (frame_height - 1);
        canvas_set_color(canvas, ColorWhite);
        canvas_draw_box(canvas, x2 - 3, y2 - 2, 2, 2);
        canvas_set_color(canvas, ColorBlack);
    } else if((horizontal == AlignCenter) && (vertical == AlignTop)) {
        x1 = frame_x + (frame_width - 1) / 2 - 4;
        y1 = frame_y;
        x2 = frame_x + (frame_width - 1) / 2;
        y2 = frame_y - 4;
        x3 = frame_x + (frame_width - 1) / 2 + 4;
        y3 = frame_y;
        canvas_set_color(canvas, ColorWhite);
        canvas_draw_box(canvas, x2 - 2, y2 + 2, 5, 2);
        canvas_draw_dot(canvas, x2, y2 + 1);
        canvas_set_color(canvas, ColorBlack);
    } else if((horizontal == AlignCenter) && (vertical == AlignBottom)) {
        x1 = frame_x + (frame_width - 1) / 2 - 4;
        y1 = frame_y + (frame_height - 1);
        x2 = frame_x + (frame_width - 1) / 2;
        y2 = frame_y + (frame_height - 1) + 4;
        x3 = frame_x + (frame_width - 1) / 2 + 4;
        y3 = frame_y + (frame_height - 1);
        canvas_set_color(canvas, ColorWhite);
        canvas_draw_box(canvas, x2 - 2, y2 - 3, 5, 2);
        canvas_draw_dot(canvas, x2, y2 - 1);
        canvas_set_color(canvas, ColorBlack);
    }

    canvas_set_color(canvas, ColorWhite);
    canvas_draw_line(canvas, x3, y3, x1, y1);
    canvas_set_color(canvas, ColorBlack);
    canvas_draw_line(canvas, x1, y1, x2, y2);
    canvas_draw_line(canvas, x2, y2, x3, y3);
}

void elements_string_fit_width(Canvas* canvas, FuriString* string, size_t width) {
    furi_check(canvas);
    furi_check(string);

    size_t len_px = canvas_string_width(canvas, furi_string_get_cstr(string));
    if(len_px > width) {
        size_t dots_px = canvas_string_width(canvas, "...");
        width = width > dots_px ? width - dots_px : 0;
        // Drop whole UTF-8 characters from the end until the rest leaves room for the dots
        while(len_px > width && furi_string_size(string)) {
            const char* text = furi_string_get_cstr(string);
            furi_string_left(string, gui_utf8_prev_start(text, furi_string_size(string)));
            len_px = canvas_string_width(canvas, furi_string_get_cstr(string));
        }
        furi_string_cat(string, "...");
    }
}

void elements_scrollable_text_line(
    Canvas* canvas,
    int32_t x,
    int32_t y,
    size_t width,
    FuriString* string,
    size_t scroll,
    bool ellipsis) {
    elements_scrollable_text_line_centered(canvas, x, y, width, string, scroll, ellipsis, false);
}

void elements_scrollable_text_line_centered(
    Canvas* canvas,
    int32_t x,
    int32_t y,
    size_t width,
    FuriString* string,
    size_t scroll,
    bool ellipsis,
    bool centered) {
    furi_check(canvas);
    furi_check(string);

    FuriString* line = furi_string_alloc_set(string);

    size_t len_px = canvas_string_width(canvas, furi_string_get_cstr(line));
    bool marquee = momentum_settings.scroll_marquee;
    if(len_px > width) {
        if(centered && !marquee) {
            centered = false;
            x -= width / 2;
        }

        if(ellipsis) {
            size_t dots_px = canvas_string_width(canvas, "...");
            width = width > dots_px ? width - dots_px : 0;
        }

        // Calculate scroll size: the number of leading characters (whole UTF-8
        // codepoints, so a scroll position never starts inside a sequence) that must
        // scroll away before the rest of the line fits. Same result as counting
        // glyph widths from the right, one byte per glyph, for ASCII.
        const char* text = furi_string_get_cstr(line);
        size_t symbols = 0;
        size_t total_width = 0;
        uint32_t codepoint;
        size_t size;
        for(const char* p = text; (size = gui_utf8_decode(p, &codepoint)) > 0; p += size) {
            symbols++;
            total_width += canvas_glyph_width(canvas, (uint16_t)codepoint);
        }
        size_t scroll_size = symbols;
        size_t left_width = 0;
        size_t index = 0;
        for(const char* p = text; (size = gui_utf8_decode(p, &codepoint)) > 0; p += size) {
            if(index > 0 && total_width - left_width <= width) {
                scroll_size = index;
                break;
            }
            left_width += canvas_glyph_width(canvas, (uint16_t)codepoint);
            index++;
        }

        // Ensure that we have something to scroll
        if(scroll_size) {
            size_t position;
            if(marquee) {
                const size_t delay = 3; // positions before/after scroll to delay
                size_t total_scroll = (scroll_size * 2) + (delay * 2);
                size_t use_scroll = scroll % total_scroll;

                if(use_scroll < scroll_size) {
                    position = use_scroll;
                } else if(use_scroll < (scroll_size + delay)) {
                    // Delay right
                    position = scroll_size;
                } else if(use_scroll < (scroll_size * 2 + delay)) {
                    position = scroll_size - (use_scroll - (scroll_size + delay));
                } else {
                    // Delay left
                    position = 0;
                }
            } else {
                scroll_size += 3;
                position = scroll % scroll_size;
            }
            furi_string_right(line, gui_utf8_offset(text, position));
        }

        len_px = canvas_string_width(canvas, furi_string_get_cstr(line));
        while(len_px > width && furi_string_size(line)) {
            text = furi_string_get_cstr(line);
            furi_string_left(line, gui_utf8_prev_start(text, furi_string_size(line)));
            len_px = canvas_string_width(canvas, furi_string_get_cstr(line));
        }

        if(ellipsis) {
            furi_string_cat(line, "...");
        }
    }

    if(centered) {
        canvas_draw_str_aligned(
            canvas, x, y, AlignCenter, AlignBottom, furi_string_get_cstr(line));
    } else {
        canvas_draw_str(canvas, x, y, furi_string_get_cstr(line));
    }
    furi_string_free(line);
}

typedef struct {
    bool bold;
    bool mono;
    bool inverse;
    Font font;
} ElementTextBoxStyle;

// Applies the byte that follows an ESC marker; returns true when the font changed
static bool elements_text_box_style_apply(ElementTextBoxStyle* style, char marker) {
    if(marker == ELEMENTS_BOLD_MARKER) {
        style->bold = !style->bold;
        style->font = style->bold ? FontPrimary : FontSecondary;
        return true;
    }
    if(marker == ELEMENTS_MONO_MARKER) {
        style->mono = !style->mono;
        style->font = style->mono ? FontKeyboard : FontSecondary;
        return true;
    }
    if(marker == ELEMENTS_INVERSE_MARKER) {
        style->inverse = !style->inverse;
    }
    return false;
}

// Widens a line's metrics to those of a font
static void
    elements_text_box_merge_font(ElementTextBoxLine* line, const CanvasFontParameters* params) {
    line->leading_min = MAX(line->leading_min, (int32_t)params->leading_min);
    line->leading_default = MAX(line->leading_default, (int32_t)params->leading_default);
    line->height = MAX(line->height, (size_t)params->height);
    line->descender = MAX(line->descender, (size_t)params->descender);
}

// Rows from the previous baseline to the baseline of `current`: the previous line's
// leading, and never less than the glyph rows that meet between the two lines (plus
// one blank row for the default spacing). Without a previous line, the rows from
// the top of the box to the first baseline.
static int32_t elements_text_box_step(
    const ElementTextBoxLine* prev,
    const ElementTextBoxLine* current,
    bool default_spacing) {
    int32_t ascent = (int32_t)current->height + current->pad;
    if(!prev) return ascent;
    int32_t meet = (int32_t)prev->descender + prev->pad + ascent;
    if(default_spacing) {
        return MAX(prev->leading_default, meet + 1);
    }
    return MAX(prev->leading_min, meet);
}

// elements_text_box() for text with bytes outside ASCII: the same markers, alignment
// and strip_to_dots, laid out codepoint by codepoint so UTF-8 sequences are never
// split, with rows tall enough for the glyphs of the native Chinese font
static void elements_text_box_utf8(
    Canvas* canvas,
    int32_t x,
    int32_t y,
    size_t width,
    size_t height,
    Align horizontal,
    Align vertical,
    const char* text,
    bool strip_to_dots) {
    ElementTextBoxLine line[ELEMENTS_MAX_LINES_NUM];
    ElementTextBoxStyle style = {.font = FontSecondary};
    size_t line_num = 0;
    bool truncated = false;
    // Baseline of the last stored line, counted from the top of the box, with the
    // smallest and with the default spacing
    int32_t baseline_min = 0;
    int32_t baseline_default = 0;

    canvas_set_font(canvas, FontSecondary);
    const CanvasFontParameters* params = canvas_get_font_params(canvas, style.font);
    size_t dots_width = canvas_string_width(canvas, "...");

    // Fill all lines
    const char* cursor = text;
    while(true) {
        // Metrics grow with the glyphs placed on the line: the selected font's for
        // ASCII, the native Chinese font's for CJK
        ElementTextBoxLine current = {.x = x, .text = cursor};
        bool inverse_present = style.inverse;
        bool has_glyph = false;
        const char* p = cursor;
        const char* next = NULL;

        while(true) {
            uint32_t codepoint;
            size_t size = gui_utf8_decode(p, &codepoint);
            if(size == 0) break;
            if(codepoint == '\e' && p[1]) {
                if(elements_text_box_style_apply(&style, p[1])) {
                    canvas_set_font(canvas, style.font);
                    params = canvas_get_font_params(canvas, style.font);
                }
                inverse_present = inverse_present || style.inverse;
                p += 2;
                continue;
            }
            if(codepoint == '\n') {
                next = p + 1;
                break;
            }
            size_t glyph_width = canvas_glyph_width(canvas, (uint16_t)codepoint);
            // The first glyph of a line stays on it even when wider than the box, so a
            // narrow box cannot stall the layout
            if(has_glyph && current.width + glyph_width > width) {
                next = p;
                break;
            }
            has_glyph = true;
            current.width += glyph_width;
            if(gui_utf8_is_cjk(codepoint)) {
                current.leading_min = MAX(current.leading_min, (int32_t)GUI_CJK_LINE_HEIGHT);
                current.leading_default =
                    MAX(current.leading_default, (int32_t)GUI_CJK_LINE_LEADING);
                current.height = MAX(current.height, (size_t)GUI_CJK_GLYPH_ASCENT);
                current.descender = MAX(current.descender, (size_t)GUI_CJK_GLYPH_DESCENT);
            } else {
                elements_text_box_merge_font(&current, params);
            }
            p += size;
        }
        current.len = (size_t)(p - cursor);
        if(!has_glyph) {
            // An empty line is as tall as the current font
            elements_text_box_merge_font(&current, params);
        }
        if(inverse_present) {
            // Room for the frame around inverted glyphs
            current.leading_min += 1;
            current.leading_default += 1;
            current.pad = 1;
        }

        // Keep the line only when its lowest row is still inside the box
        const ElementTextBoxLine* prev = line_num ? &line[line_num - 1] : NULL;
        int32_t step_min = elements_text_box_step(prev, &current, false);
        int32_t bottom = baseline_min + step_min + (int32_t)current.descender + current.pad;
        if(line_num == ELEMENTS_MAX_LINES_NUM || bottom > (int32_t)height) {
            truncated = has_glyph || next != NULL;
            break;
        }
        baseline_min += step_min;
        baseline_default += elements_text_box_step(prev, &current, true);

        int32_t spare = (int32_t)width - (int32_t)current.width;
        if(horizontal == AlignCenter && spare > 0) {
            current.x = x + spare / 2;
        } else if(horizontal == AlignRight && spare > 0) {
            current.x = x + spare;
        }
        line[line_num++] = current;

        if(next == NULL) break;
        cursor = next;
    }

    // Set vertical alignment for all lines
    if(line_num) {
        const ElementTextBoxLine* last = &line[line_num - 1];
        int32_t extent_default = baseline_default + (int32_t)last->descender + last->pad;
        if(extent_default <= (int32_t)height) {
            int32_t shift = 0;
            if(vertical == AlignCenter) {
                shift = ((int32_t)height - extent_default) / 2;
            } else if(vertical == AlignBottom) {
                shift = (int32_t)height - extent_default;
            }
            line[0].y = y + shift + elements_text_box_step(NULL, &line[0], true);
            for(size_t i = 1; i < line_num; i++) {
                line[i].y = line[i - 1].y + elements_text_box_step(&line[i - 1], &line[i], true);
            }
        } else {
            // The default spacing does not fit: start at the top with the smallest
            // spacing and spread the spare rows over the gaps, like the ASCII layout
            int32_t extent_min = baseline_min + (int32_t)last->descender + last->pad;
            int32_t spare = (int32_t)height - extent_min;
            int32_t gaps = (int32_t)line_num - 1;
            line[0].y = y + elements_text_box_step(NULL, &line[0], false);
            for(int32_t i = 1; i <= gaps; i++) {
                int32_t extra = spare / gaps + ((i - 1) < spare % gaps ? 1 : 0);
                line[i].y =
                    line[i - 1].y + elements_text_box_step(&line[i - 1], &line[i], false) + extra;
            }
        }
    }

    // Draw line by line
    canvas_set_font(canvas, FontSecondary);
    style = (ElementTextBoxStyle){.font = FontSecondary};
    int32_t right = x + (int32_t)width;
    for(size_t i = 0; i < line_num; i++) {
        const char* p = line[i].text;
        const char* end = p + line[i].len;
        int32_t pen = line[i].x;
        bool dots = strip_to_dots && truncated && (i == line_num - 1);
        while(p < end) {
            uint32_t codepoint;
            size_t size = gui_utf8_decode(p, &codepoint);
            if(size == 0) break;
            // Process format symbols
            if(codepoint == '\e' && p + 1 < end) {
                if(elements_text_box_style_apply(&style, p[1])) {
                    canvas_set_font(canvas, style.font);
                }
                p += 2;
                continue;
            }
            uint16_t symbol = (uint16_t)codepoint;
            int32_t glyph_width = (int32_t)canvas_glyph_width(canvas, symbol);
            if(dots && pen + glyph_width + (int32_t)dots_width > right) {
                break; // the dots below stand for this glyph and the rest of the text
            }
            // Nothing is drawn past the right edge of the box: a glyph wider than the
            // box is skipped, its line stays empty
            if(pen + glyph_width <= right) {
                if(style.inverse) {
                    canvas_draw_box(
                        canvas,
                        pen - 1,
                        line[i].y - (int32_t)line[i].height - 1,
                        (size_t)glyph_width + 1,
                        line[i].height + line[i].descender + 2);
                    canvas_invert_color(canvas);
                    canvas_draw_glyph(canvas, pen, line[i].y, symbol);
                    canvas_invert_color(canvas);
                } else {
                    canvas_draw_glyph(canvas, pen, line[i].y, symbol);
                }
            }
            pen += glyph_width;
            p += size;
        }
        // Text was cut off: say so at the end of the last line when the dots fit
        if(dots && pen + (int32_t)dots_width <= right) {
            canvas_draw_str(canvas, pen, line[i].y, "...");
        }
    }
    canvas_set_font(canvas, FontSecondary);
}

void elements_text_box(
    Canvas* canvas,
    int32_t x,
    int32_t y,
    size_t width,
    size_t height,
    Align horizontal,
    Align vertical,
    const char* text,
    bool strip_to_dots) {
    furi_check(canvas);

    // Text the stock fonts cannot draw byte by byte takes the UTF-8 layout; ASCII
    // text keeps the original one below
    if(!gui_utf8_is_ascii(text)) {
        elements_text_box_utf8(
            canvas, x, y, width, height, horizontal, vertical, text, strip_to_dots);
        return;
    }

    ElementTextBoxLine line[ELEMENTS_MAX_LINES_NUM];
    bool bold = false;
    bool mono = false;
    bool inverse = false;
    bool inverse_present = false;
    Font current_font = FontSecondary;
    Font prev_font = FontSecondary;
    const CanvasFontParameters* font_params = canvas_get_font_params(canvas, current_font);

    // Fill line parameters
    size_t line_leading_min = font_params->leading_min;
    size_t line_leading_default = font_params->leading_default;
    size_t line_height = font_params->height;
    size_t line_descender = font_params->descender;
    size_t line_num = 0;
    size_t line_width = 0;
    size_t line_len = 0;
    size_t total_height_min = 0;
    size_t total_height_default = 0;
    size_t i = 0;
    bool full_text_processed = false;
    size_t dots_width = canvas_string_width(canvas, "...");
    // Word-wrap bookkeeping: the last space on the current line, so an overflow can push the whole
    // word to the next line instead of breaking mid-word. Falls back to character wrap when a single
    // word is itself wider than the box, or when the trailing word contains an inline font marker
    // (\e#, \e*, \e!) -- rewinding across a marker would re-toggle the already-applied emphasis and
    // corrupt the measurement, so those words char-wrap as before.
    int last_space_i = -1;
    size_t line_start_i = 0;
    size_t line_width_at_space = 0;
    size_t line_len_at_space = 0;
    bool marker_since_space = false;

    canvas_set_font(canvas, FontSecondary);

    // Fill all lines
    line[0].text = text;
    for(i = 0; !full_text_processed; i++) {
        line_len++;
        // Identify line height
        if(prev_font != current_font) {
            font_params = canvas_get_font_params(canvas, current_font);
            line_leading_min = MAX(line_leading_min, font_params->leading_min);
            line_leading_default = MAX(line_leading_default, font_params->leading_default);
            line_height = MAX(line_height, font_params->height);
            line_descender = MAX(line_descender, font_params->descender);
            prev_font = current_font;
        }
        // Set the font
        if(text[i] == '\e' && text[i + 1]) {
            i++;
            line_len++;
            marker_since_space = true; // a marker in the current word blocks word wrap (see above)
            if(text[i] == ELEMENTS_BOLD_MARKER) {
                if(bold) {
                    current_font = FontSecondary;
                } else {
                    current_font = FontPrimary;
                }
                canvas_set_font(canvas, current_font);
                bold = !bold;
            }
            if(text[i] == ELEMENTS_MONO_MARKER) {
                if(mono) {
                    current_font = FontSecondary;
                } else {
                    current_font = FontKeyboard;
                }
                canvas_set_font(canvas, FontKeyboard);
                mono = !mono;
            }
            if(text[i] == ELEMENTS_INVERSE_MARKER) {
                inverse_present = true;
            }
            continue;
        }
        if(text[i] != '\n') {
            line_width += canvas_glyph_width(canvas, text[i]);
        }
        // Remember the last space so an overflow can wrap the whole trailing word.
        if(text[i] == ' ') {
            last_space_i = (int)i;
            line_width_at_space = line_width - canvas_glyph_width(canvas, ' ');
            line_len_at_space = line_len - 1;
            marker_since_space = false;
        }
        // Process new line
        if(text[i] == '\n' || text[i] == '\0' || line_width > width) {
            if(line_width > width) {
                if(last_space_i > (int)line_start_i && !marker_since_space) {
                    // Word wrap: break at the last space; its word moves to the next line.
                    i = (size_t)last_space_i;
                    line_width = line_width_at_space;
                    line_len = line_len_at_space;
                } else {
                    // A single word wider than the box: fall back to character wrap.
                    line_width -= canvas_glyph_width(canvas, text[i--]);
                    line_len--;
                }
            }
            if(text[i] == '\0') {
                full_text_processed = true;
            }
            if(inverse_present) {
                line_leading_min += 1;
                line_leading_default += 1;
                inverse_present = false;
            }
            line[line_num].leading_min = line_leading_min;
            line[line_num].leading_default = line_leading_default;
            line[line_num].height = line_height;
            line[line_num].descender = line_descender;
            if(total_height_min + line_leading_min > height) {
                break;
            }
            total_height_min += line_leading_min;
            total_height_default += line_leading_default;
            line[line_num].len = line_len;
            if(horizontal == AlignCenter) {
                line[line_num].x = x + (width - line_width) / 2;
            } else if(horizontal == AlignRight) {
                line[line_num].x = x + (width - line_width);
            } else {
                line[line_num].x = x;
            }
            line[line_num].y = total_height_min;
            line_num++;
            // Never index past line[]: a near-full-height box can fit the last slot's leading yet
            // still have text left, which would write line[ELEMENTS_MAX_LINES_NUM] otherwise.
            if(line_num >= ELEMENTS_MAX_LINES_NUM) {
                break;
            }
            if(!full_text_processed) {
                line[line_num].text = &text[i + 1];
                line_start_i = i + 1;
                last_space_i = -1;
                marker_since_space = false;
            }
            line_leading_min = font_params->leading_min;
            line_height = font_params->height;
            line_descender = font_params->descender;
            line_width = 0;
            line_len = 0;
        }
    }

    // Set vertical alignment for all lines
    if(total_height_default < height) {
        if(vertical == AlignTop) {
            line[0].y = y + line[0].height;
        } else if(vertical == AlignCenter) {
            line[0].y = y + line[0].height + (height - total_height_default) / 2;
        } else if(vertical == AlignBottom) {
            line[0].y = y + line[0].height + (height - total_height_default);
        }
        if(line_num > 1) {
            for(size_t i = 1; i < line_num; i++) {
                line[i].y = line[i - 1].y + line[i - 1].leading_default;
            }
        }
    } else if(line_num > 1) {
        size_t free_pixel_num = height - total_height_min;
        size_t fill_pixel = 0;
        size_t j = 1;
        line[0].y = y + line[0].height;
        while(fill_pixel < free_pixel_num) {
            line[j].y = line[j - 1].y + line[j - 1].leading_min + 1;
            fill_pixel++;
            j = j % (line_num - 1) + 1;
        }
    }

    // Draw line by line
    canvas_set_font(canvas, FontSecondary);
    bold = false;
    mono = false;
    inverse = false;
    for(size_t i = 0; i < line_num; i++) {
        for(size_t j = 0; j < line[i].len; j++) {
            // Process format symbols
            if(line[i].text[j] == '\e' && j < line[i].len - 1) { //-V781
                ++j;
                if(line[i].text[j] == ELEMENTS_BOLD_MARKER) {
                    if(bold) {
                        current_font = FontSecondary;
                    } else {
                        current_font = FontPrimary;
                    }
                    canvas_set_font(canvas, current_font);
                    bold = !bold;
                    continue;
                }
                if(line[i].text[j] == ELEMENTS_MONO_MARKER) {
                    if(mono) {
                        current_font = FontSecondary;
                    } else {
                        current_font = FontKeyboard;
                    }
                    canvas_set_font(canvas, current_font);
                    mono = !mono;
                    continue;
                }
                if(line[i].text[j] == ELEMENTS_INVERSE_MARKER) {
                    inverse = !inverse;
                    continue;
                }
            }
            if(inverse) {
                canvas_draw_box(
                    canvas,
                    line[i].x - 1,
                    line[i].y - line[i].height - 1,
                    canvas_glyph_width(canvas, line[i].text[j]) + 1,
                    line[i].height + line[i].descender + 2);
                canvas_invert_color(canvas);
                canvas_draw_glyph(canvas, line[i].x, line[i].y, line[i].text[j]);
                canvas_invert_color(canvas);
            } else {
                if((i == line_num - 1) && strip_to_dots) {
                    size_t next_symbol_width = canvas_glyph_width(canvas, line[i].text[j]);
                    if((line[i].x + (int32_t)next_symbol_width + (int32_t)dots_width) >
                       (x + (int32_t)width)) {
                        canvas_draw_str(canvas, line[i].x, line[i].y, "...");
                        break;
                    }
                }
                canvas_draw_glyph(canvas, line[i].x, line[i].y, line[i].text[j]);
            }
            line[i].x += canvas_glyph_width(canvas, line[i].text[j]);
        }
    }
    canvas_set_font(canvas, FontSecondary);
}
