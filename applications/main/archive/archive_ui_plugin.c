#include <flipper_application/flipper_application.h>

int32_t archive_ui_app(void* path);

static const FlipperAppPluginDescriptor descriptor = {
    .appid = "archive_ui",
    .ep_api_version = 1,
    .entry_point = archive_ui_app,
};

const FlipperAppPluginDescriptor* archive_ui_plugin_entry(void) {
    return &descriptor;
}
