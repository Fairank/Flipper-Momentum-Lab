#include "../infrared_app_i.h"

#include "common/infrared_scene_universal_common.h"

void infrared_scene_universal_leds_on_enter(void* context) {
    InfraredApp* infrared = context;
    infrared_brute_force_set_db_filename(
        infrared->brute_force, EXT_PATH("infrared/assets/leds.ir"));
    infrared_buttons_set_header(infrared->button_panel, "LEDs");

    infrared_scene_universal_common_add_button(infrared, 0, "Power_on");
    infrared_scene_universal_common_add_button(infrared, 1, "Power_off");
    infrared_scene_universal_common_add_button(infrared, 2, "Brightness_up");
    infrared_scene_universal_common_add_button(infrared, 3, "Brightness_dn");
    infrared_scene_universal_common_add_button(infrared, 4, "Red");
    infrared_scene_universal_common_add_button(infrared, 5, "Green");
    infrared_scene_universal_common_add_button(infrared, 6, "Blue");
    infrared_scene_universal_common_add_button(infrared, 7, "White");

    infrared_scene_universal_common_on_enter(context);
}

bool infrared_scene_universal_leds_on_event(void* context, SceneManagerEvent event) {
    return infrared_scene_universal_common_on_event(context, event);
}

void infrared_scene_universal_leds_on_exit(void* context) {
    infrared_scene_universal_common_on_exit(context);
}
