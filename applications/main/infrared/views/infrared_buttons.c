#include "infrared_buttons.h"
#include "infrared_layout.h"

#include <furi.h>
#include <gui/elements.h>

typedef struct {
    const char* label;
    const char* hint;
    int32_t id;
    bool hold_to_send;
    bool enabled;
    InfraredButtonCallback callback;
    void* context;
} InfraredButton;

typedef struct {
    InfraredButton* items;
    size_t count;
    size_t selected;
    size_t page_size;
    size_t scroll;
    FuriString* title;
    FuriString* text;
    InfraredButtonHold hold;
} InfraredButtonsModel;

struct InfraredButtons {
    View* view;
    FuriTimer* timer;
};

static void infrared_buttons_dispatch(InfraredButton button, InfraredButtonAction action) {
    if(!button.callback || action.type == InfraredActionNone) return;
    const InputType type = action.type == InfraredActionPress   ? InputTypePress :
                           action.type == InfraredActionRelease ? InputTypeRelease :
                                                                  InputTypeShort;
    button.callback(button.context, action.id, type);
}

static void infrared_buttons_cancel(InfraredButtons* instance) {
    InfraredButton button = {0};
    InfraredButtonAction action = {0};
    with_view_model(
        instance->view,
        InfraredButtonsModel * model,
        {
            if(model->hold.held) {
                for(size_t i = 0; i < model->count; ++i) {
                    if(model->items[i].id == model->hold.id) {
                        button = model->items[i];
                        break;
                    }
                }
                action = infrared_button_action(
                    &model->hold, InfraredButtonCancel, false, model->hold.id);
            }
        },
        true);
    infrared_buttons_dispatch(button, action);
}

static void infrared_buttons_draw(Canvas* canvas, void* context) {
    InfraredButtonsModel* model = context;
    canvas_clear(canvas);
    canvas_set_color(canvas, ColorBlack);
    canvas_set_font(canvas, FontPrimary);
    elements_scrollable_text_line(canvas, 2, 10, 99, model->title, model->scroll, false);
    canvas_set_font(canvas, FontSecondary);
    char counter[24];
    const size_t pages = (model->count + model->page_size - 1) / model->page_size;
    snprintf(
        counter, sizeof(counter), "%zu/%zu", model->selected / model->page_size + 1, pages ?: 1);
    canvas_draw_str_aligned(canvas, 126, 10, AlignRight, AlignBottom, counter);
    canvas_draw_line(canvas, 1, 12, 126, 12);

    const size_t start = model->selected / model->page_size * model->page_size;
    for(size_t i = start; i < model->count && i < start + model->page_size; ++i) {
        const InfraredButton* item = &model->items[i];
        const InfraredButtonRect r = infrared_grid_rect(i - start, model->page_size);
        const bool selected = i == model->selected;
        if(selected) {
            canvas_draw_rbox(canvas, r.x, r.y, r.width, r.height, 3);
            canvas_set_color(canvas, ColorWhite);
        } else {
            canvas_draw_rframe(canvas, r.x, r.y, r.width, r.height, 3);
        }
        char label[128];
        infrared_button_label(item->label, label, sizeof(label));
        furi_string_set(model->text, label);
        const int baseline = r.y + (r.height + 7) / 2;
        if(selected) {
            elements_scrollable_text_line_centered(
                canvas,
                r.x + r.width / 2,
                baseline,
                r.width - 6,
                model->text,
                model->scroll,
                false,
                true);
        } else {
            elements_string_fit_width(canvas, model->text, r.width - 6);
            canvas_draw_str_aligned(
                canvas,
                r.x + r.width / 2,
                baseline,
                AlignCenter,
                AlignBottom,
                furi_string_get_cstr(model->text));
        }
        canvas_set_color(canvas, ColorBlack);
    }
    if(model->count) {
        const InfraredButton* selected = &model->items[model->selected];
        const char* hint = model->hold.held       ? "Sending - release OK" :
                           selected->hint         ? selected->hint :
                           selected->hold_to_send ? "Hold OK to send" :
                                                    "OK Select";
        furi_string_set(model->text, hint);
        elements_string_fit_width(canvas, model->text, 126);
        canvas_draw_str(canvas, 2, 63, furi_string_get_cstr(model->text));
    } else {
        canvas_draw_str_aligned(canvas, 64, 36, AlignCenter, AlignCenter, "No buttons");
    }
}

static bool infrared_buttons_input(InputEvent* event, void* context) {
    InfraredButtons* instance = context;
    if(event->key == InputKeyBack) {
        // Cancel before the scene receives Back; a library/control button must not activate here.
        infrared_buttons_cancel(instance);
        return false;
    }
    InfraredButton button = {0};
    InfraredButtonAction action = {0};
    with_view_model(
        instance->view,
        InfraredButtonsModel * model,
        {
            if(model->count) {
                if(event->key == InputKeyOk) {
                    button = model->items[model->selected];
                    if(button.enabled) {
                        if(event->type == InputTypePress || event->type == InputTypeRelease ||
                           event->type == InputTypeShort) {
                            const InfraredButtonInput input =
                                event->type == InputTypePress   ? InfraredButtonPress :
                                event->type == InputTypeRelease ? InfraredButtonRelease :
                                                                  InfraredButtonShort;
                            action = infrared_button_action(
                                &model->hold, input, button.hold_to_send, button.id);
                        }
                    }
                } else if(
                    !model->hold.held &&
                    (event->type == InputTypeShort || event->type == InputTypeRepeat)) {
                    InfraredDirection direction;
                    bool move = true;
                    if(event->key == InputKeyLeft)
                        direction = InfraredDirectionLeft;
                    else if(event->key == InputKeyRight)
                        direction = InfraredDirectionRight;
                    else if(event->key == InputKeyUp)
                        direction = InfraredDirectionUp;
                    else if(event->key == InputKeyDown)
                        direction = InfraredDirectionDown;
                    else
                        move = false;
                    if(move) {
                        model->selected =
                            infrared_grid_move(model->selected, model->count, direction);
                        model->scroll = 0;
                    }
                }
            }
        },
        true);
    // Callbacks can switch scenes and reset this view, so never call them under the model lock.
    infrared_buttons_dispatch(button, action);
    return true;
}

static void infrared_buttons_tick(void* context) {
    InfraredButtons* instance = context;
    with_view_model(instance->view, InfraredButtonsModel * model, { ++model->scroll; }, true);
}

static void infrared_buttons_enter(void* context) {
    InfraredButtons* instance = context;
    furi_timer_start(instance->timer, furi_ms_to_ticks(333));
}

static void infrared_buttons_exit(void* context) {
    InfraredButtons* instance = context;
    furi_timer_stop(instance->timer);
    infrared_buttons_cancel(instance);
}

InfraredButtons* infrared_buttons_alloc(size_t page_size) {
    furi_check(page_size == 4 || page_size == 6);
    InfraredButtons* instance = malloc(sizeof(InfraredButtons));
    instance->view = view_alloc();
    view_allocate_model(instance->view, ViewModelTypeLocking, sizeof(InfraredButtonsModel));
    with_view_model(
        instance->view,
        InfraredButtonsModel * model,
        {
            model->page_size = page_size;
            model->title = furi_string_alloc();
            model->text = furi_string_alloc();
        },
        false);
    instance->timer = furi_timer_alloc(infrared_buttons_tick, FuriTimerTypePeriodic, instance);
    view_set_context(instance->view, instance);
    view_set_orientation(instance->view, ViewOrientationHorizontal);
    view_set_draw_callback(instance->view, infrared_buttons_draw);
    view_set_input_callback(instance->view, infrared_buttons_input);
    view_set_enter_callback(instance->view, infrared_buttons_enter);
    view_set_exit_callback(instance->view, infrared_buttons_exit);
    return instance;
}

void infrared_buttons_free(InfraredButtons* instance) {
    // Drain the timer before taking the model lock or freeing the view it accesses.
    furi_timer_stop(instance->timer);
    furi_timer_free(instance->timer);
    infrared_buttons_reset(instance);
    with_view_model(
        instance->view,
        InfraredButtonsModel * model,
        {
            furi_string_free(model->title);
            furi_string_free(model->text);
        },
        false);
    view_free(instance->view);
    free(instance);
}

View* infrared_buttons_get_view(InfraredButtons* instance) {
    return instance->view;
}

void infrared_buttons_reset(InfraredButtons* instance) {
    infrared_buttons_cancel(instance);
    with_view_model(
        instance->view,
        InfraredButtonsModel * model,
        {
            free(model->items);
            model->items = NULL;
            model->count = 0;
            model->selected = 0;
            model->scroll = 0;
            furi_string_reset(model->title);
        },
        true);
}

void infrared_buttons_set_header(InfraredButtons* instance, const char* title) {
    with_view_model(
        instance->view,
        InfraredButtonsModel * model,
        { furi_string_set(model->title, title); },
        true);
}

void infrared_buttons_set_selected(InfraredButtons* instance, int32_t id) {
    with_view_model(
        instance->view,
        InfraredButtonsModel * model,
        {
            for(size_t i = 0; i < model->count; ++i) {
                if(model->items[i].id == id) {
                    model->selected = i;
                    model->scroll = 0;
                    break;
                }
            }
        },
        true);
}

void infrared_buttons_add(
    InfraredButtons* instance,
    const char* label,
    int32_t id,
    bool hold_to_send,
    InfraredButtonCallback callback,
    void* context) {
    with_view_model(
        instance->view,
        InfraredButtonsModel * model,
        {
            model->items = realloc(model->items, (model->count + 1) * sizeof(InfraredButton));
            furi_check(model->items);
            model->items[model->count++] = ((InfraredButton){
                .label = label,
                .id = id,
                .hold_to_send = hold_to_send,
                .enabled = true,
                .callback = callback,
                .context = context,
            });
        },
        true);
}

void infrared_buttons_set_hint(
    InfraredButtons* instance,
    int32_t id,
    const char* hint,
    bool enabled) {
    with_view_model(
        instance->view,
        InfraredButtonsModel * model,
        {
            for(size_t i = 0; i < model->count; ++i) {
                if(model->items[i].id == id) {
                    model->items[i].hint = hint;
                    model->items[i].enabled = enabled;
                    break;
                }
            }
        },
        true);
}
