#include "../infrared_app_i.h"

#include "common/infrared_scene_universal_common.h"

void infrared_scene_universal_fan_on_enter(void* context) {
    InfraredApp* infrared = context;
    infrared_brute_force_set_db_filename(
        infrared->brute_force, EXT_PATH("infrared/assets/fans.ir"));
    infrared_buttons_set_header(infrared->button_panel, "Fans");

    infrared_scene_universal_common_add_button(infrared, 0, "Power");
    infrared_scene_universal_common_add_button(infrared, 1, "Mode");
    infrared_scene_universal_common_add_button(infrared, 4, "Rotate");
    infrared_scene_universal_common_add_button(infrared, 2, "Speed_up");
    infrared_scene_universal_common_add_button(infrared, 5, "Timer");
    infrared_scene_universal_common_add_button(infrared, 3, "Speed_dn");

    infrared_scene_universal_common_on_enter(context);
}

bool infrared_scene_universal_fan_on_event(void* context, SceneManagerEvent event) {
    return infrared_scene_universal_common_on_event(context, event);
}

void infrared_scene_universal_fan_on_exit(void* context) {
    infrared_scene_universal_common_on_exit(context);
}
