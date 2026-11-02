#include "../infrared_app_i.h" // IWYU pragma: keep

#include "common/infrared_scene_universal_common.h"

void infrared_scene_universal_ac_on_enter(void* context) {
    InfraredApp* infrared = context;
    infrared_brute_force_set_db_filename(infrared->brute_force, EXT_PATH("infrared/assets/ac.ir"));
    infrared_buttons_set_header(infrared->button_panel, "ACs");

    infrared_scene_universal_common_add_button(infrared, 0, "Off");
    infrared_scene_universal_common_add_button(infrared, 1, "Dh");
    infrared_scene_universal_common_add_button(infrared, 2, "Cool_hi");
    infrared_scene_universal_common_add_button(infrared, 3, "Heat_hi");
    infrared_scene_universal_common_add_button(infrared, 4, "Cool_lo");
    infrared_scene_universal_common_add_button(infrared, 5, "Heat_lo");

    infrared_scene_universal_common_on_enter(context);
}

bool infrared_scene_universal_ac_on_event(void* context, SceneManagerEvent event) {
    return infrared_scene_universal_common_on_event(context, event);
}

void infrared_scene_universal_ac_on_exit(void* context) {
    infrared_scene_universal_common_on_exit(context);
}
