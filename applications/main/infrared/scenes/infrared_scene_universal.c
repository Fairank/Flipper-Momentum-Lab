#include "../infrared_app_i.h"

typedef enum {
    SubmenuIndexUniversalTV,
    SubmenuIndexUniversalProjector,
    SubmenuIndexUniversalAudio,
    SubmenuIndexUniversalAirConditioner,
    SubmenuIndexUniversalLEDs,
    SubmenuIndexUniversalFan,
    SubmenuIndexUniversalBluray,
    SubmenuIndexUniversalMonitor,
    SubmenuIndexUniversalDigitalSign,
    SubmenuIndexUniversalFromFile,
} SubmenuIndex;

static void infrared_scene_universal_callback(void* context, int32_t index, InputType type) {
    InfraredApp* infrared = context;
    if(type == InputTypeShort) {
        view_dispatcher_send_custom_event(infrared->view_dispatcher, index);
    }
}

void infrared_scene_universal_on_enter(void* context) {
    InfraredApp* infrared = context;
    InfraredButtons* panel = infrared->home_panel;
    static const char* const labels[] = {
        "TVs",
        "Projectors",
        "Audio",
        "ACs",
        "LEDs",
        "Fans",
        "Blu-ray/DVD",
        "Monitors",
        "Signs",
        "Library file",
    };
    infrared_buttons_set_header(panel, "Universal");
    for(size_t i = 0; i < COUNT_OF(labels); ++i) {
        infrared_buttons_add(
            panel, labels[i], i, false, infrared_scene_universal_callback, infrared);
    }
    infrared_buttons_set_selected(
        panel, scene_manager_get_scene_state(infrared->scene_manager, InfraredSceneUniversal));
    view_dispatcher_switch_to_view(infrared->view_dispatcher, InfraredViewHome);
}

bool infrared_scene_universal_on_event(void* context, SceneManagerEvent event) {
    InfraredApp* infrared = context;
    SceneManager* scene_manager = infrared->scene_manager;
    bool consumed = false;

    if(event.type == SceneManagerEventTypeCustom) {
        if(event.event == SubmenuIndexUniversalTV) {
            scene_manager_next_scene(scene_manager, InfraredSceneUniversalTV);
            consumed = true;
        } else if(event.event == SubmenuIndexUniversalProjector) {
            scene_manager_next_scene(scene_manager, InfraredSceneUniversalProjector);
            consumed = true;
        } else if(event.event == SubmenuIndexUniversalAudio) {
            scene_manager_next_scene(scene_manager, InfraredSceneUniversalAudio);
            consumed = true;
        } else if(event.event == SubmenuIndexUniversalAirConditioner) {
            scene_manager_next_scene(scene_manager, InfraredSceneUniversalAC);
            consumed = true;
        } else if(event.event == SubmenuIndexUniversalLEDs) {
            scene_manager_next_scene(scene_manager, InfraredSceneUniversalLEDs);
            consumed = true;
        } else if(event.event == SubmenuIndexUniversalFan) {
            scene_manager_next_scene(scene_manager, InfraredSceneUniversalFan);
            consumed = true;
        } else if(event.event == SubmenuIndexUniversalBluray) {
            scene_manager_next_scene(scene_manager, InfraredSceneUniversalBluray);
            consumed = true;
        } else if(event.event == SubmenuIndexUniversalMonitor) {
            scene_manager_next_scene(scene_manager, InfraredSceneUniversalMonitor);
            consumed = true;
        } else if(event.event == SubmenuIndexUniversalDigitalSign) {
            scene_manager_next_scene(scene_manager, InfraredSceneUniversalDigitalSign);
            consumed = true;
        } else if(event.event == SubmenuIndexUniversalFromFile) {
            scene_manager_next_scene(scene_manager, InfraredSceneUniversalFromFile);
            consumed = true;
        }
        scene_manager_set_scene_state(scene_manager, InfraredSceneUniversal, event.event);
    }

    return consumed;
}

void infrared_scene_universal_on_exit(void* context) {
    InfraredApp* infrared = context;
    infrared_buttons_reset(infrared->home_panel);
}
