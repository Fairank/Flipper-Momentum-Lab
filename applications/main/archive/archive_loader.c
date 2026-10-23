#include <furi.h>
#include <dialogs/dialogs.h>
#include <flipper_application/plugins/plugin_manager.h>
#include <loader/firmware_api/firmware_api.h>

/* Called by the same desktop thread and with the same FuriString directory
 * context as the former built-in UI. No nested loader session/thread is needed.
 */
int32_t archive_app(void* path) {
    PluginManager* manager = plugin_manager_alloc("archive_ui", 1, firmware_api_interface);
    int32_t result = -1;
    FlipperApplicationEntryPoint entry = NULL;
    if(plugin_manager_load_single(manager, "/ext/apps_data/archive/plugins/archive_ui.fal") ==
       PluginManagerErrorNone) {
        entry = (FlipperApplicationEntryPoint)plugin_manager_get_ep(manager, 0);
    }
    if(entry) {
        result = entry(path);
    } else {
        DialogsApp* dialogs = furi_record_open(RECORD_DIALOGS);
        dialog_message_show_storage_error(
            dialogs, "Archive module missing\nor incompatible.\nReinstall resources.");
        furi_record_close(RECORD_DIALOGS);
    }
    plugin_manager_free(manager);
    return result;
}
