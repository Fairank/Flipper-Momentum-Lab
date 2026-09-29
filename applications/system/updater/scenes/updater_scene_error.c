#include "../updater_i.h"
#include "updater_scene.h"
#include <update_util/update_operation.h>

// Display-only labels: the library keeps its existing CLI error descriptions.
static const char* updater_preparation_result_label(UpdatePrepareResult result) {
    static const char* const labels[] = {
        [UpdatePrepareResultOK] = "准备完成",
        [UpdatePrepareResultManifestPathInvalid] = "升级清单\n名称或位置无效",
        [UpdatePrepareResultManifestFolderNotFound] = "未找到升级目录",
        [UpdatePrepareResultManifestInvalid] = "升级清单数据无效",
        [UpdatePrepareResultStageMissing] = "缺少升级加载器",
        [UpdatePrepareResultStageIntegrityError] = "升级加载器已损坏",
        [UpdatePrepareResultManifestPointerCreateError] = "无法创建\n升级路径文件",
        [UpdatePrepareResultManifestPointerCheckError] = "升级路径文件错误",
        [UpdatePrepareResultTargetMismatch] = "硬件目标不匹配",
        [UpdatePrepareResultOutdatedManifestVersion] = "升级包版本过旧",
        [UpdatePrepareResultIntFull] = "内部存储空间不足",
        [UpdatePrepareResultUnspecifiedError] = "未知错误",
    };
    return (uint32_t)result < COUNT_OF(labels) ? labels[result] : "未知错误";
}

void updater_scene_error_callback(GuiButtonType result, InputType type, void* context) {
    furi_assert(context);
    Updater* updater = context;
    if(type != InputTypeShort) {
        return;
    }

    if(result == GuiButtonTypeLeft) {
        view_dispatcher_send_custom_event(
            updater->view_dispatcher, UpdaterCustomEventCancelUpdate);
    }
}

void updater_scene_error_on_enter(void* context) {
    Updater* updater = (Updater*)context;

    widget_add_button_element(
        updater->widget, GuiButtonTypeLeft, "退出", updater_scene_error_callback, updater);

    widget_add_string_multiline_element(
        updater->widget, 64, 13, AlignCenter, AlignCenter, FontPrimary, "错误");

    widget_add_string_multiline_element(
        updater->widget,
        64,
        33,
        AlignCenter,
        AlignCenter,
        FontPrimary,
        updater_preparation_result_label(updater->preparation_result));

    view_dispatcher_switch_to_view(updater->view_dispatcher, UpdaterViewWidget);
}

bool updater_scene_error_on_event(void* context, SceneManagerEvent event) {
    Updater* updater = (Updater*)context;
    bool consumed = false;

    if(event.type == SceneManagerEventTypeBack) {
        view_dispatcher_stop(updater->view_dispatcher);
        consumed = true;
    } else if(event.type == SceneManagerEventTypeCustom) {
        switch(event.event) {
        case UpdaterCustomEventCancelUpdate:
            view_dispatcher_stop(updater->view_dispatcher);
            consumed = true;
            break;
        default:
            break;
        }
    }

    return consumed;
}

void updater_scene_error_on_exit(void* context) {
    furi_assert(context);
    Updater* updater = (Updater*)context;

    widget_reset(updater->widget);

    if(updater->loaded_manifest) {
        update_manifest_free(updater->loaded_manifest);
    }
}
