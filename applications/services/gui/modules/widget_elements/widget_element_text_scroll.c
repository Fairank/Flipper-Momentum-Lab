#include "widget_element_i.h"
#include <gui/elements.h>
#include <gui/utf8_internal.h>
#include <m-array.h>

#define WIDGET_ELEMENT_TEXT_SCROLL_BAR_OFFSET (4)

typedef struct {
    Font font;
    Align horizontal;
    FuriString* text;
    uint8_t height;
    uint8_t leading;
} TextScrollLineArray;

ARRAY_DEF(TextScrollLineArray, TextScrollLineArray, M_POD_OPLIST) //-V658

typedef struct {
    TextScrollLineArray_t line_array;
    uint8_t x;
    uint8_t y;
    uint8_t width;
    uint8_t height;
    FuriString* text;
    uint16_t scroll_pos_total;
    uint16_t scroll_pos_current;
    bool text_formatted;
} WidgetElementTextScrollModel;

static bool
    widget_element_text_scroll_process_ctrl_symbols(TextScrollLineArray* line, FuriString* text) {
    bool processed = false;

    do {
        if(furi_string_get_char(text, 0) != '\e') break;
        char ctrl_symbol = furi_string_get_char(text, 1);
        if(ctrl_symbol == 'c') {
            line->horizontal = AlignCenter;
        } else if(ctrl_symbol == 'r') {
            line->horizontal = AlignRight;
        } else if(ctrl_symbol == '#') {
            line->font = FontPrimary;
        } else if(ctrl_symbol == '*') {
            line->font = FontKeyboard;
        }
        furi_string_right(text, 2);
        processed = true;
    } while(false);

    return processed;
}

void widget_element_text_scroll_add_line(WidgetElement* element, TextScrollLineArray* line) {
    WidgetElementTextScrollModel* model = element->model;
    TextScrollLineArray new_line;
    new_line.font = line->font;
    new_line.horizontal = line->horizontal;
    new_line.text = furi_string_alloc_set(line->text);
    new_line.height = line->height;
    new_line.leading = line->leading;
    TextScrollLineArray_push_back(model->line_array, new_line);
}

static void widget_element_text_scroll_fill_lines(Canvas* canvas, WidgetElement* element) {
    WidgetElementTextScrollModel* model = element->model;
    TextScrollLineArray line_tmp;
    line_tmp.text = furi_string_alloc();
    bool reached_new_line = true;

    while(true) {
        if(reached_new_line) {
            // Set default line properties
            line_tmp.font = FontSecondary;
            line_tmp.horizontal = AlignLeft;
            // Process control symbols
            while(widget_element_text_scroll_process_ctrl_symbols(&line_tmp, model->text))
                ;
        }
        // Set canvas font
        canvas_set_font(canvas, line_tmp.font);
        const CanvasFontParameters* params = canvas_get_font_params(canvas, line_tmp.font);
        furi_string_reset(line_tmp.text);
        size_t line_width = 0;
        size_t char_i = 0;
        const char* remaining = furi_string_get_cstr(model->text);
        bool finished = false;
        while(true) {
            uint32_t codepoint;
            size_t bytes = gui_utf8_decode(remaining + char_i, &codepoint);
            if(!bytes) {
                finished = true;
                break;
            } else if(codepoint == '\n') {
                char_i += bytes;
                reached_new_line = true;
                break;
            } else {
                // Keep whole UTF-8 sequences. An oversized first glyph must still
                // advance, otherwise a narrow widget would loop forever.
                char glyph[5] = {0};
                memcpy(glyph, remaining + char_i, bytes);
                size_t advance = canvas_glyph_width(canvas, (uint16_t)codepoint);
                if(line_width + advance > model->width && char_i > 0) {
                    reached_new_line = false;
                    break;
                }
                furi_string_cat_str(line_tmp.text, glyph);
                line_width += advance;
                char_i += bytes;
            }
        }
        bool cjk = gui_utf8_has_cjk(furi_string_get_cstr(line_tmp.text));
        uint8_t glyph_height = params->height + params->descender;
        line_tmp.height = cjk ? MAX(glyph_height, GUI_CJK_LINE_HEIGHT) : glyph_height;
        line_tmp.leading = cjk ? MAX(params->leading_default, GUI_CJK_LINE_LEADING) :
                                 params->leading_default;
        widget_element_text_scroll_add_line(element, &line_tmp);
        if(finished) break;
        furi_string_right(model->text, char_i);
    }

    // The last scroll position is the earliest suffix that completely fits.
    // Count actual heights, including mixed Chinese and ASCII rows.
    size_t last = TextScrollLineArray_size(model->line_array) - 1;
    size_t height = TextScrollLineArray_get(model->line_array, last)->height;
    while(last > 0) {
        TextScrollLineArray* previous = TextScrollLineArray_get(model->line_array, last - 1);
        if(height + previous->leading > model->height) break;
        height += previous->leading;
        last--;
    }
    model->scroll_pos_total = last + 1;
    furi_string_free(line_tmp.text);
}

static void widget_element_text_scroll_draw(Canvas* canvas, WidgetElement* element) {
    furi_assert(canvas);
    furi_assert(element);

    furi_mutex_acquire(element->model_mutex, FuriWaitForever);

    WidgetElementTextScrollModel* model = element->model;
    if(!model->text_formatted) {
        widget_element_text_scroll_fill_lines(canvas, element);
        model->text_formatted = true;
    }

    uint16_t y = model->y;
    uint16_t x = model->x;
    uint16_t curr_line = 0;
    if(TextScrollLineArray_size(model->line_array)) {
        TextScrollLineArray_it_t it;
        for(TextScrollLineArray_it(it, model->line_array); !TextScrollLineArray_end_p(it);
            TextScrollLineArray_next(it), curr_line++) {
            if(curr_line < model->scroll_pos_current) continue;
            TextScrollLineArray* line = TextScrollLineArray_ref(it);
            if(y + line->height > model->y + model->height) break;
            canvas_set_font(canvas, line->font);
            if(line->horizontal == AlignLeft) {
                x = model->x;
            } else if(line->horizontal == AlignCenter) {
                x = model->x + model->width / 2;
            } else if(line->horizontal == AlignRight) {
                x = model->x + model->width;
            }
            canvas_draw_str_aligned(
                canvas, x, y, line->horizontal, AlignTop, furi_string_get_cstr(line->text));
            y += line->leading;
        }
        // Draw scroll bar
        if(model->scroll_pos_total > 1) {
            elements_scrollbar_pos(
                canvas,
                model->x + model->width + WIDGET_ELEMENT_TEXT_SCROLL_BAR_OFFSET,
                model->y,
                model->height,
                model->scroll_pos_current,
                model->scroll_pos_total);
        }
    }

    furi_mutex_release(element->model_mutex);
}

static bool widget_element_text_scroll_input(InputEvent* event, WidgetElement* element) {
    furi_assert(event);
    furi_assert(element);

    furi_mutex_acquire(element->model_mutex, FuriWaitForever);

    WidgetElementTextScrollModel* model = element->model;
    bool consumed = false;

    if((event->type == InputTypeShort) || (event->type == InputTypeRepeat)) {
        if(event->key == InputKeyUp) {
            if(model->scroll_pos_current > 0) {
                model->scroll_pos_current--;
            }
            consumed = true;
        } else if(event->key == InputKeyDown) {
            if((model->scroll_pos_total > 1) &&
               (model->scroll_pos_current < model->scroll_pos_total - 1)) {
                model->scroll_pos_current++;
            }
            consumed = true;
        }
    }

    furi_mutex_release(element->model_mutex);

    return consumed;
}

static void widget_element_text_scroll_free(WidgetElement* text_scroll) {
    furi_assert(text_scroll);

    WidgetElementTextScrollModel* model = text_scroll->model;
    TextScrollLineArray_it_t it;
    for(TextScrollLineArray_it(it, model->line_array); !TextScrollLineArray_end_p(it);
        TextScrollLineArray_next(it)) {
        TextScrollLineArray* line = TextScrollLineArray_ref(it);
        furi_string_free(line->text);
    }
    TextScrollLineArray_clear(model->line_array);
    furi_string_free(model->text);
    free(text_scroll->model);
    furi_mutex_free(text_scroll->model_mutex);
    free(text_scroll);
}

WidgetElement* widget_element_text_scroll_create(
    uint8_t x,
    uint8_t y,
    uint8_t width,
    uint8_t height,
    const char* text) {
    furi_assert(text);

    // Allocate and init model
    WidgetElementTextScrollModel* model = malloc(sizeof(WidgetElementTextScrollModel));
    model->x = x;
    model->y = y;
    model->width = width > WIDGET_ELEMENT_TEXT_SCROLL_BAR_OFFSET ?
                       width - WIDGET_ELEMENT_TEXT_SCROLL_BAR_OFFSET :
                       1;
    model->height = height;
    model->scroll_pos_current = 0;
    model->scroll_pos_total = 1;
    model->text_formatted = false;
    TextScrollLineArray_init(model->line_array);
    model->text = furi_string_alloc_set(text);

    WidgetElement* text_scroll = malloc(sizeof(WidgetElement));
    text_scroll->parent = NULL;
    text_scroll->draw = widget_element_text_scroll_draw;
    text_scroll->input = widget_element_text_scroll_input;
    text_scroll->free = widget_element_text_scroll_free;
    text_scroll->model = model;
    text_scroll->model_mutex = furi_mutex_alloc(FuriMutexTypeNormal);

    return text_scroll;
} //-V773
