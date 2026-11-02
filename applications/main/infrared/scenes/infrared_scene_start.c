#include "../infrared_app_i.h"

typedef enum {
    StartByBrand,
    StartUniversal,
    StartLearn,
    StartSaved,
    StartOutput,
    StartDebug,
} StartItem;

static void infrared_scene_start_callback(void* context, int32_t index, InputType type) {
    InfraredApp* infrared = context;
    if(type == InputTypeShort) {
        view_dispatcher_send_custom_event(infrared->view_dispatcher, index);
    }
}

void infrared_scene_start_on_enter(void* context) {
    InfraredApp* infrared = context;
    InfraredButtons* panel = infrared->home_panel;
    static const char* const labels[] = {
        "By brand", "Universal", "Learn", "Saved", "Output", "Debug RX"};
    static const char* const hints[] = {
        "Brand / model library",
        "Try codes by appliance",
        "Learn from a remote",
        "Open your saved remotes",
        "Internal / GPIO output",
        "Inspect received signals",
    };
    infrared_buttons_set_header(panel, "Infrared");
    for(size_t i = 0; i < COUNT_OF(labels); ++i) {
        infrared_buttons_add(panel, labels[i], i, false, infrared_scene_start_callback, infrared);
        infrared_buttons_set_hint(panel, i, hints[i], true);
    }
    if(!infrared->app_state.is_debug_enabled) {
        infrared_buttons_set_hint(panel, StartDebug, "Enable System > Debug", false);
    }
    infrared_buttons_set_selected(
        panel, scene_manager_get_scene_state(infrared->scene_manager, InfraredSceneStart));
    view_dispatcher_switch_to_view(infrared->view_dispatcher, InfraredViewHome);
}

bool infrared_scene_start_on_event(void* context, SceneManagerEvent event) {
    InfraredApp* infrared = context;
    SceneManager* manager = infrared->scene_manager;
    if(event.type != SceneManagerEventTypeCustom) return false;
    if(event.event > StartDebug) return false;
    scene_manager_set_scene_state(manager, InfraredSceneStart, event.event);
    switch(event.event) {
    case StartByBrand:
        furi_string_set(infrared->file_path, INFRARED_APP_FOLDER "/More_Remotes");
        scene_manager_next_scene(manager, InfraredSceneRemoteList);
        break;
    case StartUniversal:
        furi_string_set(infrared->file_path, INFRARED_APP_FOLDER);
        scene_manager_next_scene(manager, InfraredSceneUniversal);
        break;
    case StartLearn:
        infrared->app_state.is_learning_new_remote = true;
        infrared->app_state.current_button_index = 0;
        scene_manager_next_scene(manager, InfraredSceneLearn);
        break;
    case StartSaved:
        furi_string_set(infrared->file_path, INFRARED_APP_FOLDER);
        scene_manager_next_scene(manager, InfraredSceneRemoteList);
        break;
    case StartOutput:
        scene_manager_next_scene(manager, InfraredSceneGpioSettings);
        break;
    case StartDebug:
        if(infrared->app_state.is_debug_enabled)
            scene_manager_next_scene(manager, InfraredSceneDebug);
        break;
    }
    return true;
}

void infrared_scene_start_on_exit(void* context) {
    InfraredApp* infrared = context;
    infrared_buttons_reset(infrared->home_panel);
}
