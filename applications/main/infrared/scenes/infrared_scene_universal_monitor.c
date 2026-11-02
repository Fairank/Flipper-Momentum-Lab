#include "../infrared_app_i.h"

#include "common/infrared_scene_universal_common.h"

void infrared_scene_universal_monitor_on_enter(void* context) {
    InfraredApp* infrared = context;
    infrared_brute_force_set_db_filename(
        infrared->brute_force, EXT_PATH("infrared/assets/monitor.ir"));
    infrared_buttons_set_header(infrared->button_panel, "Monitors");

    infrared_scene_universal_common_add_button(infrared, 0, "POWER");
    infrared_scene_universal_common_add_button(infrared, 1, "SOURCE");
    infrared_scene_universal_common_add_button(infrared, 2, "MENU");
    infrared_scene_universal_common_add_button(infrared, 3, "EXIT");

    infrared_scene_universal_common_on_enter(context);
}

bool infrared_scene_universal_monitor_on_event(void* context, SceneManagerEvent event) {
    return infrared_scene_universal_common_on_event(context, event);
}

void infrared_scene_universal_monitor_on_exit(void* context) {
    infrared_scene_universal_common_on_exit(context);
}
