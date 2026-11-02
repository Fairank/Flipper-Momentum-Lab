#include "../infrared_app_i.h"

#include "common/infrared_scene_universal_common.h"

void infrared_scene_universal_audio_on_enter(void* context) {
    InfraredApp* infrared = context;
    infrared_brute_force_set_db_filename(
        infrared->brute_force, EXT_PATH("infrared/assets/audio.ir"));
    infrared_buttons_set_header(infrared->button_panel, "Audio");

    infrared_scene_universal_common_add_button(infrared, 0, "Power");
    infrared_scene_universal_common_add_button(infrared, 1, "Mute");
    infrared_scene_universal_common_add_button(infrared, 2, "Play");
    infrared_scene_universal_common_add_button(infrared, 7, "Vol_up");
    infrared_scene_universal_common_add_button(infrared, 3, "Pause");
    infrared_scene_universal_common_add_button(infrared, 6, "Vol_dn");
    infrared_scene_universal_common_add_button(infrared, 4, "Prev");
    infrared_scene_universal_common_add_button(infrared, 5, "Next");

    infrared_scene_universal_common_on_enter(context);
}

bool infrared_scene_universal_audio_on_event(void* context, SceneManagerEvent event) {
    return infrared_scene_universal_common_on_event(context, event);
}

void infrared_scene_universal_audio_on_exit(void* context) {
    infrared_scene_universal_common_on_exit(context);
}
