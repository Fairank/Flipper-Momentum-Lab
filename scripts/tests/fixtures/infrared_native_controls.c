/* Native callback logic, with recording GUI and transmitter boundaries. */
#undef NDEBUG
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "infrared_custom_event.h"

typedef enum {
    InputTypePress,
    InputTypeRelease,
    InputTypeShort,
    InputTypeLong,
    InputTypeRepeat,
} InputType;

typedef struct {
    uint32_t events[8];
    size_t count;
} Dispatcher;

typedef struct {
    Dispatcher* view_dispatcher;
    void* button_menu;
    bool transmitting;
    unsigned stop_calls;
    unsigned reset_calls;
} InfraredApp;

static void view_dispatcher_send_custom_event(Dispatcher* dispatcher, uint32_t event) {
    assert(dispatcher->count < 8);
    dispatcher->events[dispatcher->count++] = event;
}

static void infrared_tx_stop(InfraredApp* app) {
    assert(!app->reset_calls);
    ++app->stop_calls;
    app->transmitting = false;
}

static void reset_buttons(void* context) {
    InfraredApp* app = context;
    assert(!app->transmitting && app->stop_calls == 1);
    ++app->reset_calls;
}

/* Both names model the same teardown boundary, before and after native restoration. */
#define button_menu_reset      reset_buttons
#define infrared_buttons_reset reset_buttons

/* PRODUCTION_CALLBACK */
/* PRODUCTION_REMOTE_EXIT */

static void assert_selected(Dispatcher* dispatcher, int16_t expected) {
    assert(dispatcher->count == 1);
    assert(
        infrared_custom_event_get_type(dispatcher->events[0]) ==
        InfraredCustomEventTypeButtonSelected);
    assert(infrared_custom_event_get_value(dispatcher->events[0]) == expected);
}

int main(int argc, char** argv) {
    assert(argc == 2);
    Dispatcher dispatcher = {0};
    InfraredApp app = {.view_dispatcher = &dispatcher};
    app.button_menu = &app;
    const char* scenario = argv[1];
    if(!strcmp(scenario, "exit")) {
        app.transmitting = true;
        infrared_scene_remote_on_exit(&app);
        assert(!app.transmitting && app.stop_calls == 1 && app.reset_calls == 1);
    } else if(!strcmp(scenario, "press")) {
        infrared_scene_universal_from_file_item_callback(&app, 37, InputTypePress);
        assert(dispatcher.count == 0);
    } else if(!strcmp(scenario, "short")) {
        infrared_scene_universal_from_file_item_callback(&app, 37, InputTypeShort);
        assert(dispatcher.count == 0);
    } else if(!strcmp(scenario, "release")) {
        infrared_scene_universal_from_file_item_callback(&app, 37, InputTypeRelease);
        assert_selected(&dispatcher, 37);
    } else {
        assert(!strcmp(scenario, "sequence"));
        infrared_scene_universal_from_file_item_callback(&app, 9, InputTypePress);
        assert(dispatcher.count == 0);
        infrared_scene_universal_from_file_item_callback(&app, 9, InputTypeShort);
        assert(dispatcher.count == 0);
        infrared_scene_universal_from_file_item_callback(&app, 9, InputTypeRelease);
        assert_selected(&dispatcher, 9);
    }
    puts("ok");
    return 0;
}
