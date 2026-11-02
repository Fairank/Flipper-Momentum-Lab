#include "../infrared_app_i.h"

#include "common/infrared_scene_universal_common.h"

void infrared_scene_universal_tv_on_enter(void* context) {
    InfraredApp* infrared = context;
    infrared_brute_force_set_db_filename(infrared->brute_force, EXT_PATH("infrared/assets/tv.ir"));
    infrared_buttons_set_header(infrared->button_panel, "TVs");

    infrared_scene_universal_common_add_button(infrared, 0, "Power");
    infrared_scene_universal_common_add_button(infrared, 1, "Mute");
    infrared_scene_universal_common_add_button(infrared, 3, "Ch_next");
    infrared_scene_universal_common_add_button(infrared, 2, "Vol_up");
    infrared_scene_universal_common_add_button(infrared, 5, "Ch_prev");
    infrared_scene_universal_common_add_button(infrared, 4, "Vol_dn");

    infrared_scene_universal_common_on_enter(context);
}

bool infrared_scene_universal_tv_on_event(void* context, SceneManagerEvent event) {
    return infrared_scene_universal_common_on_event(context, event);
}

void infrared_scene_universal_tv_on_exit(void* context) {
    infrared_scene_universal_common_on_exit(context);
}
