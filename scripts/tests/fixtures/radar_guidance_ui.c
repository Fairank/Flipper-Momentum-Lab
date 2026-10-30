/* Recording boundaries for the real production radar draw/input functions. */
#undef NDEBUG
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "radar_core.h"

typedef void Gui;
typedef void Expansion;
typedef void FuriStreamBuffer;
typedef void FuriHalSerialHandle;
typedef void FuriMutex;
typedef void RpcAppSystem;
typedef void FuriMessageQueue;
typedef struct {
    void* model;
} View;
typedef struct {
    unsigned view;
    unsigned quit;
} ViewDispatcher;
typedef struct {
    char header[80];
    void (*done)(void*);
    void* context;
    char* buffer;
    size_t size, minimum_length;
} TextInput;
typedef enum {
    FontPrimary,
    FontSecondary,
    FontKeyboard,
    FontBigNumbers
} Font;
typedef enum {
    AlignLeft,
    AlignRight,
    AlignTop,
    AlignBottom,
    AlignCenter
} Align;
typedef struct {
    int x, y;
    unsigned radius;
} RecordedCircle;
typedef struct {
    Font font;
    char text[8192];
    unsigned count, big_readings;
    RecordedCircle circles[8], discs[8], dots[8];
    unsigned circle_count, disc_count, dot_count;
} Canvas;
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
#define RADAR_WIFI_ONLY 0
#define RADAR_TITLE     "BLE Radar"
#define RADAR_KIND      'B'
#define UNUSED(x)       (void)(x)
#define with_view_model(v, declaration, body, update) \
    do {                                              \
        declaration = (v)->model;                     \
        body;                                         \
    } while(0)
/* PRODUCTION_TYPES */

static uint32_t clock_ms = 10000;
static unsigned scans, stops;
static uint32_t now_ms(void) {
    return clock_ms;
}
static bool backend_opened(const RadarApp* app) {
    return app->scan_open;
}
static void open_backend(RadarApp* app) {
    app->scan_open = true;
    scans++;
}
static void stop_scan(RadarApp* app) {
    UNUSED(app);
    stops++;
}
static void scan_command(RadarApp* app) {
    UNUSED(app);
    scans++;
}
static void view_dispatcher_stop(ViewDispatcher* dispatcher) {
    dispatcher->quit++;
}
static void view_dispatcher_switch_to_view(ViewDispatcher* dispatcher, uint32_t id) {
    dispatcher->view = id;
}
static void text_input_set_header_text(TextInput* input, const char* text) {
    snprintf(input->header, sizeof(input->header), "%s", text);
}
static void text_input_set_minimum_length(TextInput* input, size_t count) {
    input->minimum_length = count;
}
static void text_input_set_result_callback(
    TextInput* input,
    void (*done)(void*),
    void* ctx,
    char* buffer,
    size_t size,
    bool clear) {
    UNUSED(clear);
    input->done = done;
    input->context = ctx;
    input->buffer = buffer;
    input->size = size;
}
void canvas_set_font(Canvas* canvas, Font font) {
    canvas->font = font;
}
unsigned canvas_string_width(Canvas* canvas, const char* text) {
    return (unsigned)strlen(text) * (canvas->font == FontBigNumbers ? 12u : 5u);
}
void canvas_draw_str(Canvas* canvas, int x, int y, const char* text) {
    UNUSED(x);
    UNUSED(y);
    assert(strlen(canvas->text) + strlen(text) + 2 < sizeof(canvas->text));
    strcat(canvas->text, text);
    strcat(canvas->text, "\n");
    canvas->count++;
    if(canvas->font == FontBigNumbers && strpbrk(text, "0123456789")) canvas->big_readings++;
}
void canvas_draw_circle(Canvas* canvas, int x, int y, unsigned radius) {
    assert(canvas->circle_count < 8);
    assert(x >= (int)radius && y >= (int)radius && x + radius < 128 && y + radius < 64);
    canvas->circles[canvas->circle_count++] = (RecordedCircle){x, y, radius};
}
void canvas_draw_dot(Canvas* canvas, int x, int y) {
    assert(canvas->dot_count < 8 && x >= 0 && x < 128 && y >= 0 && y < 64);
    canvas->dots[canvas->dot_count++] = (RecordedCircle){x, y, 0};
}
void canvas_draw_disc(Canvas* canvas, int x, int y, unsigned radius) {
    assert(canvas->disc_count < 8);
    assert(x >= (int)radius && y >= (int)radius && x + radius < 128 && y + radius < 64);
    canvas->discs[canvas->disc_count++] = (RecordedCircle){x, y, radius};
}
void canvas_draw_box(Canvas* canvas, int x, int y, unsigned width, unsigned height) {
    UNUSED(canvas);
    UNUSED(x);
    UNUSED(y);
    UNUSED(width);
    UNUSED(height);
}
void canvas_draw_frame(Canvas* canvas, int x, int y, unsigned width, unsigned height) {
    UNUSED(canvas);
    assert(x >= 0 && y >= 0 && x + width <= 128 && y + height <= 64);
}
void canvas_draw_line(Canvas* canvas, int x1, int y1, int x2, int y2) {
    UNUSED(canvas);
    assert(x1 >= 0 && x1 < 128 && x2 >= 0 && x2 < 128 && y1 >= 0 && y1 < 64 && y2 >= 0 && y2 < 64);
}
void canvas_invert_color(Canvas* canvas) {
    UNUSED(canvas);
}

/* PRODUCTION_SCREEN_INPUT */

static void key(RadarApp* app, InputKey code, InputType type) {
    InputEvent event = {.key = code, .type = type};
    bool consumed = input(&event, app);
    if(type != InputTypeRepeat) assert(consumed);
}
static void show(RadarModel* model) {
    Canvas canvas = {0};
    draw(&canvas, model);
    puts(canvas.text);
    printf("large_numeric_readings=%u\n", canvas.big_readings);
    for(unsigned i = 0; i < canvas.circle_count; i++)
        printf(
            "circle=%d,%d,%u\n",
            canvas.circles[i].x,
            canvas.circles[i].y,
            canvas.circles[i].radius);
    for(unsigned i = 0; i < canvas.dot_count; i++)
        printf("dot=%d,%d\n", canvas.dots[i].x, canvas.dots[i].y);
    for(unsigned i = 0; i < canvas.disc_count; i++)
        printf("disc=%d,%d,%u\n", canvas.discs[i].x, canvas.discs[i].y, canvas.discs[i].radius);
}
static void range_target(
    RadarModel* model,
    bool reference,
    bool unstable,
    int signal_rssi,
    int reference_rssi,
    unsigned samples) {
    radar_init(&model->core);
    for(unsigned i = 0; i < samples; i++) {
        int rssi = unstable ? (i % 2 ? -40 : -90) : signal_rssi;
        clock_ms = 1000 + i * 250;
        assert(radar_observe(
            &model->core,
            'B',
            "AABBCCDDEEFF",
            0,
            rssi,
            0,
            (const uint8_t*)"Headphones",
            10,
            clock_ms));
    }
    bool accepted = reference &&
                    radar_set_beacon_reference(&model->core, "AABBCCDDEEFF", 0, reference_rssi);
    printf("reference_accepted=%d\n", accepted);
    model->now = clock_ms;
    model->core.ready = model->core.running = true;
    model->core.pinned = 0;
    model->detail = true;
}
int main(int argc, char** argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    assert(argc == 2);
    RadarModel model = {.opened = true, .detail = true, .kind = 'B', .focus = 0, .now = 10000};
    radar_init(&model.core);
    assert(radar_observe(
        &model.core, 'B', "AABBCCDDEEFF", 0, -50, 0, (const uint8_t*)"Headphones", 10, 10000));
    assert(radar_observe(
        &model.core, 'B', "010203040506", 1, -80, 0, (const uint8_t*)"Other", 5, 10000));
    model.core.ready = model.core.running = true;
    model.core.pinned = 0;
    View view = {.model = &model};
    ViewDispatcher dispatcher = {0};
    TextInput text_input = {0};
    RadarApp app = {
        .view = &view, .dispatcher = &dispatcher, .input = &text_input, .scan_open = true};
    assert(filter_back(&app) == 0);
    if(!strcmp(argv[1], "setup")) {
        key(&app, InputKeyOk, InputTypeLong);
        show(&model);
    } else if(!strcmp(argv[1], "cancel")) {
        key(&app, InputKeyOk, InputTypeLong);
        key(&app, InputKeyBack, InputTypeShort);
        printf(
            "after_cancel_detail=%d\nafter_cancel_pinned=%d\n", model.detail, model.core.pinned);
        key(&app, InputKeyBack, InputTypeShort);
        printf("after_second_back_detail=%d\n", model.detail);
    } else if(!strcmp(argv[1], "filter")) {
        model.detail = false;
        model.core.pinned = -1;
        key(&app, InputKeyOk, InputTypeLong);
        printf("input_view=%u\nminimum_length=%zu\n", dispatcher.view, text_input.minimum_length);
        assert(text_input.done && text_input.buffer && text_input.size > 7);
        strcpy(text_input.buffer, "nomatch");
        text_input.done(text_input.context);
        unsigned count = 0;
        for(size_t i = 0; i < RADAR_CAPACITY; i++)
            count += model.core.devices[i].used;
        printf("saved_filter=%s\nremaining_targets=%u\n", model.filter, count);
    } else if(!strcmp(argv[1], "info")) {
        key(&app, InputKeyOk, InputTypeShort);
        show(&model);
        key(&app, InputKeyBack, InputTypeShort);
        printf("after_back_detail=%d\nafter_back_info=%d\n", model.detail, model.info);
    } else if(!strncmp(argv[1], "range-", 6)) {
        const char* state = argv[1] + 6;
        int signal_rssi = !strcmp(state, "limit-high") ? -127 :
                          !strcmp(state, "limit-low")  ? 20 :
                                                         -60;
        int reference_rssi = !strcmp(state, "limit-high") ? -15 :
                             !strcmp(state, "limit-low")  ? -100 :
                                                            -60;
        range_target(
            &model,
            strcmp(state, "uncalibrated") != 0,
            !strcmp(state, "unstable"),
            signal_rssi,
            reference_rssi,
            !strcmp(state, "collecting") ? 1 : 16);
        if(!strcmp(state, "paused")) model.paused = true;
        if(!strcmp(state, "aging")) model.now = clock_ms + 4000;
        if(!strcmp(state, "lost")) model.now = clock_ms + 13000;
        show(&model);
    } else if(!strncmp(argv[1], "circle-", 7)) {
        char mode[8], proximity[8];
        assert(sscanf(argv[1], "circle-%7[^-]-%7s", mode, proximity) == 2);
        bool calibrated = !strcmp(mode, "cal");
        int signal = !strcmp(proximity, "close") ? (calibrated ? -50 : -45) :
                     !strcmp(proximity, "far")   ? -80 :
                                                   -60;
        range_target(&model, calibrated, false, signal, -60, 16);
        show(&model);
    } else if(!strcmp(argv[1], "calibrate-pause")) {
        key(&app, InputKeyOk, InputTypeLong);
        key(&app, InputKeyOk, InputTypeShort);
        printf(
            "collecting_before_pause=%d\n",
            model.core.devices[0].range.calibration == RadarRangeCalibrationCollecting);
        key(&app, InputKeyLeft, InputTypeShort);
        printf(
            "collecting_after_pause=%d\npaused=%d\npinned=%d\n",
            model.core.devices[0].range.calibration == RadarRangeCalibrationCollecting,
            model.paused,
            model.core.pinned);
    } else if(!strcmp(argv[1], "repeat-setup")) {
        key(&app, InputKeyOk, InputTypeLong);
        key(&app, InputKeyOk, InputTypeRepeat);
        printf(
            "collecting_after_repeat=%d\n",
            model.core.devices[0].range.calibration == RadarRangeCalibrationCollecting);
        key(&app, InputKeyOk, InputTypeShort);
        printf(
            "collecting_after_short=%d\n",
            model.core.devices[0].range.calibration == RadarRangeCalibrationCollecting);
    } else if(!strcmp(argv[1], "repeat-actions")) {
        key(&app, InputKeyLeft, InputTypeRepeat);
        printf("paused_after_repeat=%d\nstops_after_repeat=%u\n", model.paused, stops);
        key(&app, InputKeyOk, InputTypeRepeat);
        printf("info_after_repeat=%d\n", model.info);
        key(&app, InputKeyBack, InputTypeRepeat);
        printf(
            "detail_after_repeat_back=%d\npinned_after_repeat_back=%d\n",
            model.detail,
            model.core.pinned);
        model.detail = false;
        model.info = false;
        model.core.pinned = -1;
        model.focus = 0;
        key(&app, InputKeyDown, InputTypeRepeat);
        printf("focus_after_repeat_down=%u\n", model.focus);
    } else {
        assert(!"Unknown scenario");
    }
    printf("quit=%u\n", dispatcher.quit);
    return 0;
}
