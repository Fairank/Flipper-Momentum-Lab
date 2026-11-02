/* Real app view logic with recording GUI/OS boundaries; screenshots own visual QA. */
#undef NDEBUG
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "infrared_layout.h"

typedef enum {
    InputKeyUp,
    InputKeyDown,
    InputKeyRight,
    InputKeyLeft,
    InputKeyOk,
    InputKeyBack
} InputKey;
typedef enum {
    InputTypePress,
    InputTypeRelease,
    InputTypeShort,
    InputTypeLong,
    InputTypeRepeat
} InputType;
typedef struct {
    InputKey key;
    InputType type;
} InputEvent;
typedef struct {
    char* value;
} FuriString;
typedef struct {
    char text[64][128];
    size_t count;
    int button_x, button_width;
} Canvas;
typedef struct View {
    void* model;
    void* context;
    bool locked;
    void (*draw)(Canvas*, void*);
    bool (*input)(InputEvent*, void*);
    void (*enter)(void*);
    void (*exit)(void*);
} View;
typedef struct {
    void (*callback)(void*);
    void* context;
    bool running;
} FuriTimer;
enum {
    ColorBlack,
    ColorWhite,
    FontPrimary,
    FontSecondary,
    AlignRight,
    AlignBottom,
    AlignCenter,
    ViewModelTypeLocking,
    ViewOrientationHorizontal,
    FuriTimerTypePeriodic
};
#define furi_check assert
static int views, timers;
static FuriString* furi_string_alloc(void) {
    FuriString* s = calloc(1, sizeof(*s));
    s->value = calloc(1, 1);
    return s;
}
static void furi_string_set(FuriString* s, const char* v) {
    s->value = realloc(s->value, strlen(v) + 1);
    strcpy(s->value, v);
}
static void furi_string_reset(FuriString* s) {
    s->value[0] = 0;
}
static const char* furi_string_get_cstr(FuriString* s) {
    return s->value;
}
static void furi_string_free(FuriString* s) {
    free(s->value);
    free(s);
}
static View* view_alloc(void) {
    ++views;
    return calloc(1, sizeof(View));
}
static void view_allocate_model(View* v, int type, size_t size) {
    (void)type;
    v->model = calloc(1, size);
}
static void* view_get_model(View* v) {
    assert(!v->locked);
    v->locked = true;
    return v->model;
}
static void view_commit_model(View* v, bool redraw) {
    (void)redraw;
    assert(v->locked);
    v->locked = false;
}
#define with_view_model(view, type, code, update) \
    {                                             \
        type = view_get_model(view);              \
        {code};                                   \
        view_commit_model(view, update);          \
    }
static void view_set_context(View* v, void* c) {
    v->context = c;
}
static void view_set_orientation(View* v, int o) {
    (void)v;
    assert(o == ViewOrientationHorizontal);
}
static void view_set_draw_callback(View* v, void (*f)(Canvas*, void*)) {
    v->draw = f;
}
static void view_set_input_callback(View* v, bool (*f)(InputEvent*, void*)) {
    v->input = f;
}
static void view_set_enter_callback(View* v, void (*f)(void*)) {
    v->enter = f;
}
static void view_set_exit_callback(View* v, void (*f)(void*)) {
    v->exit = f;
}
static void view_free(View* v) {
    assert(!v->locked);
    free(v->model);
    free(v);
    --views;
}
static FuriTimer* furi_timer_alloc(void (*f)(void*), int type, void* c) {
    (void)type;
    ++timers;
    FuriTimer* t = calloc(1, sizeof(*t));
    t->callback = f;
    t->context = c;
    return t;
}
static void furi_timer_start(FuriTimer* t, int period) {
    assert(period > 0);
    t->running = true;
}
static void furi_timer_stop(FuriTimer* t) {
    t->running = false;
}
static void furi_timer_free(FuriTimer* t) {
    assert(!t->running);
    free(t);
    --timers;
}
static int furi_ms_to_ticks(int ms) {
    return ms;
}
static void canvas_clear(Canvas* c) {
    c->count = 0;
}
static void canvas_set_color(Canvas* c, int color) {
    (void)c;
    (void)color;
}
static void canvas_set_font(Canvas* c, int font) {
    (void)c;
    (void)font;
}
static void record(Canvas* c, const char* s) {
    assert(c->count < 64);
    snprintf(c->text[c->count++], 128, "%s", s);
}
static void canvas_draw_str(Canvas* c, int x, int y, const char* s) {
    assert(x >= 0 && y >= 0 && x < 128 && y < 64);
    record(c, s);
}
static void canvas_draw_str_aligned(Canvas* c, int x, int y, int h, int v, const char* s) {
    (void)h;
    (void)v;
    canvas_draw_str(c, x, y, s);
}
static void canvas_draw_line(Canvas* c, int x, int y, int a, int b) {
    (void)c;
    assert(x >= 0 && y >= 0 && a < 128 && b < 64);
}
static void canvas_draw_rbox(Canvas* c, int x, int y, int w, int h, int r) {
    c->button_x = x;
    c->button_width = w;
    (void)r;
    assert(x >= 0 && y >= 0 && x + w <= 128 && y + h <= 64);
}
static void canvas_draw_rframe(Canvas* c, int x, int y, int w, int h, int r) {
    canvas_draw_rbox(c, x, y, w, h, r);
}
static void elements_string_fit_width(Canvas* c, FuriString* s, int width) {
    (void)c;
    size_t n = width / 5;
    if(strlen(s->value) > n) s->value[n] = 0;
}
static void elements_scrollable_text_line(
    Canvas* c,
    int x,
    int y,
    int w,
    FuriString* s,
    size_t scroll,
    bool ellipsis) {
    (void)w;
    (void)scroll;
    (void)ellipsis;
    canvas_draw_str(c, x, y, s->value);
}
static void elements_scrollable_text_line_centered(
    Canvas* c,
    int x,
    int y,
    int w,
    FuriString* s,
    size_t scroll,
    bool ellipsis,
    bool centered) {
    (void)scroll;
    (void)ellipsis;
    int text_width = strlen(s->value) * 5;
    if(text_width > w) {
        // The real GUI API treats x as the center, including when it clips long text.
        x -= centered ? w / 2 : 0;
        text_width = w;
        centered = false;
    }
    const int left = centered ? x - text_width / 2 : x;
    assert(left >= c->button_x + 2);
    assert(left + text_width <= c->button_x + c->button_width - 2);
    canvas_draw_str(c, left, y, s->value);
}

/* PRODUCTION_HEADER */
/* PRODUCTION_VIEW */

typedef struct {
    InfraredButtons* buttons;
    int calls;
    int32_t id;
    InputType type;
    bool reset;
} Receiver;
static void callback(void* context, int32_t id, InputType type) {
    Receiver* r = context;
    assert(!infrared_buttons_get_view(r->buttons)->locked);
    ++r->calls;
    r->id = id;
    r->type = type;
    if(r->reset) infrared_buttons_reset(r->buttons);
}
static bool key(View* v, InputKey k, InputType type) {
    InputEvent e = {k, type};
    return v->input(&e, v->context);
}
static void short_key(View* v, InputKey k) {
    key(v, k, InputTypePress);
    key(v, k, InputTypeShort);
    key(v, k, InputTypeRelease);
}
static bool contains(Canvas* c, const char* text) {
    for(size_t i = 0; i < c->count; ++i)
        if(!strcmp(c->text[i], text)) return true;
    return false;
}
int main(int argc, char** argv) {
    assert(argc == 2);
    InfraredButtons* b = infrared_buttons_alloc(4);
    View* v = infrared_buttons_get_view(b);
    Receiver receiver = {.buttons = b};
    infrared_buttons_set_header(b, "Test model");
    for(int i = 0; i < 7; ++i)
        infrared_buttons_add(b, "Vol_up", 10 + i, true, callback, &receiver);
    infrared_buttons_add(b, "Edit", -1, false, callback, &receiver);
    v->enter(v->context);
    Canvas c = {0};
    if(!strcmp(argv[1], "display")) {
        v->draw(&c, v->model);
        assert(contains(&c, "Test model") && contains(&c, "Vol +") && contains(&c, "1/2"));
        short_key(v, InputKeyDown);
        short_key(v, InputKeyDown);
        v->draw(&c, v->model);
        assert(contains(&c, "2/2") && contains(&c, "Edit"));
        infrared_buttons_set_selected(b, -1);
        short_key(v, InputKeyOk);
        assert(receiver.calls == 1 && receiver.id == -1 && receiver.type == InputTypeShort);
    } else if(!strcmp(argv[1], "release")) {
        key(v, InputKeyOk, InputTypePress);
        short_key(v, InputKeyRight);
        key(v, InputKeyOk, InputTypeRelease);
        assert(receiver.calls == 2 && receiver.id == 10 && receiver.type == InputTypeRelease);
        key(v, InputKeyOk, InputTypePress);
        assert(!key(v, InputKeyBack, InputTypePress));
        key(v, InputKeyBack, InputTypeRelease);
        key(v, InputKeyBack, InputTypeShort);
        assert(receiver.calls == 4 && receiver.type == InputTypeRelease);
        key(v, InputKeyOk, InputTypeRelease);
        assert(receiver.calls == 4);
    } else if(!strcmp(argv[1], "reset")) {
        receiver.reset = true;
        infrared_buttons_set_selected(b, -1);
        short_key(v, InputKeyOk);
        assert(receiver.calls == 1);
        v->draw(&c, v->model);
        assert(contains(&c, "No buttons"));
    } else {
        assert(!strcmp(argv[1], "disabled"));
        infrared_buttons_set_selected(b, -1);
        infrared_buttons_set_hint(b, -1, "Enable System > Debug", false);
        short_key(v, InputKeyOk);
        assert(receiver.calls == 0);
        v->draw(&c, v->model);
        assert(contains(&c, "Enable System > Debug"));
    }
    v->exit(v->context);
    infrared_buttons_free(b);
    assert(!views && !timers);
    return 0;
}
