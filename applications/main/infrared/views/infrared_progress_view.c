#include "infrared_progress_view.h"

#include <assets_icons.h>
#include <gui/canvas.h>
#include <gui/view.h>
#include <gui/elements.h>
#include <input/input.h>

#include <furi.h>
#include <furi_hal_resources.h>
#include <core/check.h>
#include <stdint.h>

struct InfraredProgressView {
    View* view;
    InfraredProgressViewInputCallback input_callback;
    void* context;
};

typedef struct {
    size_t progress;
    size_t progress_total;
    bool is_paused;
} InfraredProgressViewModel;

static void infrared_progress_view_draw_callback(Canvas* canvas, void* _model) {
    InfraredProgressViewModel* model = (InfraredProgressViewModel*)_model;

    canvas_clear(canvas);
    canvas_set_color(canvas, ColorBlack);
    canvas_set_font(canvas, FontPrimary);
    canvas_draw_str(canvas, 4, 11, model->is_paused ? "Paused" : "Trying codes");
    canvas_set_font(canvas, FontSecondary);
    char progress_string[24];
    snprintf(
        progress_string,
        sizeof(progress_string),
        "%zu/%zu",
        model->progress,
        model->progress_total);
    canvas_draw_str_aligned(canvas, 124, 11, AlignRight, AlignBottom, progress_string);
    canvas_draw_line(canvas, 2, 14, 125, 14);
    const float value = model->progress_total ? (float)model->progress / model->progress_total : 0;
    elements_progress_bar(canvas, 5, 22, 118, value);
    if(model->is_paused) {
        canvas_draw_str(canvas, 4, 46, "OK Send 1 | Back Resume");
        canvas_draw_str(canvas, 4, 60, "< > Select | Down Save");
    } else {
        canvas_draw_str(canvas, 4, 46, "Point at the appliance");
        canvas_draw_str(canvas, 4, 60, "OK Pause | Back Stop");
    }
}

bool infrared_progress_view_set_progress(InfraredProgressView* instance, uint16_t progress) {
    bool result;
    with_view_model(
        instance->view,
        InfraredProgressViewModel * model,
        {
            result = progress <= model->progress_total;
            if(result) model->progress = progress;
        },
        true);
    return result;
}

void infrared_progress_view_set_progress_total(
    InfraredProgressView* progress,
    uint16_t progress_total) {
    furi_assert(progress);
    InfraredProgressViewModel* model = view_get_model(progress->view);
    model->progress = 0;
    model->progress_total = progress_total;
    view_commit_model(progress->view, false);
}

void infrared_progress_view_set_paused(InfraredProgressView* instance, bool is_paused) {
    with_view_model(
        instance->view, InfraredProgressViewModel * model, { model->is_paused = is_paused; }, true);
}

bool infrared_progress_view_input_callback(InputEvent* event, void* context) {
    InfraredProgressView* instance = context;

    if(event->type == InputTypePress || event->type == InputTypeRelease) {
        return false;
    }

    if(!instance->input_callback) return false;

    with_view_model(
        instance->view,
        InfraredProgressViewModel * model,
        {
            if(model->is_paused) {
                if(event->key == InputKeyLeft)
                    instance->input_callback(
                        instance->context, InfraredProgressViewInputPreviousSignal);
                else if(event->key == InputKeyRight)
                    instance->input_callback(
                        instance->context, InfraredProgressViewInputNextSignal);
                else if(event->key == InputKeyOk)
                    instance->input_callback(
                        instance->context, InfraredProgressViewInputSendSingle);
                else if(event->key == InputKeyDown)
                    instance->input_callback(instance->context, InfraredProgressViewInputSave);
                else if(event->key == InputKeyBack)
                    instance->input_callback(instance->context, InfraredProgressViewInputResume);
            } else {
                if(event->key == InputKeyOk)
                    instance->input_callback(instance->context, InfraredProgressViewInputPause);
                else if(event->key == InputKeyBack)
                    instance->input_callback(instance->context, InfraredProgressViewInputStop);
            }
        },
        false);

    return true;
}

InfraredProgressView* infrared_progress_view_alloc(void) {
    InfraredProgressView* instance = malloc(sizeof(InfraredProgressView));
    instance->view = view_alloc();
    view_allocate_model(instance->view, ViewModelTypeLocking, sizeof(InfraredProgressViewModel));
    InfraredProgressViewModel* model = view_get_model(instance->view);
    model->progress = 0;
    model->progress_total = 0;
    view_commit_model(instance->view, false);
    view_set_draw_callback(instance->view, infrared_progress_view_draw_callback);
    view_set_input_callback(instance->view, infrared_progress_view_input_callback);
    view_set_context(instance->view, instance);

    return instance;
}

void infrared_progress_view_free(InfraredProgressView* progress) {
    view_free(progress->view);
    free(progress);
}

void infrared_progress_view_set_input_callback(
    InfraredProgressView* instance,
    InfraredProgressViewInputCallback callback,
    void* context) {
    furi_assert(instance);
    instance->input_callback = callback;
    instance->context = context;
}

View* infrared_progress_view_get_view(InfraredProgressView* instance) {
    furi_assert(instance);
    furi_assert(instance->view);
    return instance->view;
}
