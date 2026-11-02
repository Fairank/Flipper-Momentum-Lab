#include "../infrared_app_i.h"
#include "common/infrared_scene_universal_common.h"

#define TAG "InfraredUniversalBlurayDVD"

void infrared_scene_universal_bluray_on_enter(void* context) {
    InfraredApp* infrared = context;
    infrared_brute_force_set_db_filename(
        infrared->brute_force, EXT_PATH("infrared/assets/bluray_dvd.ir"));
    infrared_buttons_set_header(infrared->button_panel, "Blu-ray/DVD");

    infrared_scene_universal_common_add_button(infrared, 0, "Power");
    infrared_scene_universal_common_add_button(infrared, 1, "Eject");
    infrared_scene_universal_common_add_button(infrared, 2, "Play");
    infrared_scene_universal_common_add_button(infrared, 3, "Pause");
    infrared_scene_universal_common_add_button(infrared, 4, "Fast_ba");
    infrared_scene_universal_common_add_button(infrared, 5, "Fast_fo");
    infrared_scene_universal_common_add_button(infrared, 6, "Ok");
    infrared_scene_universal_common_add_button(infrared, 7, "Subtitle");

    infrared_scene_universal_common_on_enter(context);
    FURI_LOG_I(TAG, "Finished infrared_scene_universal_common_on_enter");
}

bool infrared_scene_universal_bluray_on_event(void* context, SceneManagerEvent event) {
    FURI_LOG_D(
        TAG, "Universal Blu-ray/DVD scene event: type=%d, event=%ld", event.type, event.event);

    bool result = infrared_scene_universal_common_on_event(context, event);

    FURI_LOG_D(TAG, "infrared_scene_universal_common_on_event result: %d", result);

    return result;
}

void infrared_scene_universal_bluray_on_exit(void* context) {
    FURI_LOG_D(TAG, "Exiting Universal Blu-ray/DVD scene");

    InfraredApp* infrared = context;
    FURI_LOG_D(
        TAG,
        "Brute force state before exit: started=%d",
        infrared_brute_force_is_started(infrared->brute_force));

    infrared_scene_universal_common_on_exit(context);

    FURI_LOG_D(TAG, "Finished exiting Universal Blu-ray/DVD scene");
}
