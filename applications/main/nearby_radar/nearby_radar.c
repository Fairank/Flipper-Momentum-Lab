#include "radar_core.h"
#include <furi.h>
#include <furi_hal.h>
#include <gui/gui.h>
#include <gui/view_dispatcher.h>
#include <gui/modules/text_input.h>
#include <expansion/expansion.h>
#include <momentum/momentum.h>
#include <rpc/rpc_app.h>
#include <stdio.h>
#include <string.h>

typedef struct {
    RadarCore core;
    char filter[33];
    char status[40];
    char kind;
    uint8_t focus;
    uint8_t port;
    uint32_t now;
    bool detail;
    bool info;
    bool paused;
    bool opened;
} RadarModel;
typedef struct {
    Gui* gui;
    Expansion* expansion;
    ViewDispatcher* dispatcher;
    View* view;
    TextInput* input;
    FuriStreamBuffer* stream;
    FuriHalSerialHandle* serial;
    FuriMutex* rpc_mutex;
    RpcAppSystem* rpc;
    char filter[33];
    uint8_t port;
    uint32_t ping;
    uint32_t opened_at;
    uint32_t start_at;
    volatile uint32_t dropped;
    bool scan_sent;
} RadarApp;
static uint32_t now_ms(void) {
    return (uint32_t)((uint64_t)furi_get_tick() * 1000u / furi_kernel_get_tick_frequency());
}
static void command(RadarApp* app, const char* text) {
    if(!app->serial) return;
    furi_hal_serial_tx(app->serial, (const uint8_t*)text, strlen(text));
    furi_hal_serial_tx_wait_complete(app->serial);
}
static void scan_command(RadarApp* app, char kind) {
    command(app, kind == 'B' ? "NR1,SCAN,B\n" : kind == 'W' ? "NR1,SCAN,W\n" : "NR1,SCAN,A\n");
    app->start_at = now_ms();
}
static void filter_command(RadarApp* app) {
    char text[80] = "NR1,FILTER,";
    size_t offset = strlen(text);
    for(size_t i = 0; app->filter[i]; i++)
        snprintf(text + offset + i * 2, 3, "%02X", (unsigned char)app->filter[i]);
    strcat(text, "\n");
    command(app, text);
}
static void rx(FuriHalSerialHandle* handle, FuriHalSerialRxEvent event, void* context) {
    RadarApp* app = context;
    if(event & FuriHalSerialRxEventData) {
        uint8_t b = furi_hal_serial_async_rx(handle);
        if(furi_stream_buffer_send(app->stream, &b, 1, 0) != 1 && app->dropped != UINT32_MAX)
            app->dropped++;
    }
    if((event & FuriHalSerialRxEventOverrunError) && app->dropped != UINT32_MAX) app->dropped++;
}
static void open_serial(RadarApp* app) {
    app->serial =
        furi_hal_serial_control_acquire(app->port ? FuriHalSerialIdLpuart : FuriHalSerialIdUsart);
    with_view_model(
        app->view,
        RadarModel * m,
        {
            radar_init(&m->core);
            m->focus = UINT8_MAX;
            m->paused = false;
            m->detail = false;
            m->info = false;
            m->opened = app->serial != NULL;
            m->port = app->port;
            snprintf(
                m->status,
                sizeof(m->status),
                "%s",
                app->serial ? "Waiting for ESP32" : "UART busy");
        },
        true);
    if(!app->serial) return;
    furi_stream_buffer_reset(app->stream);
    app->scan_sent = false;
    app->dropped = 0;
    furi_hal_serial_init(app->serial, 115200);
    furi_hal_serial_async_rx_start(app->serial, rx, app, true);
    app->opened_at = app->ping = now_ms();
    command(app, "NR1,HELLO\n");
}
static void close_serial(RadarApp* app) {
    if(!app->serial) return;
    command(app, "NR1,STOP\n");
    furi_hal_serial_async_rx_stop(app->serial);
    furi_hal_serial_deinit(app->serial);
    furi_hal_serial_control_release(app->serial);
    app->serial = NULL;
}
static void label(Canvas* canvas, int x, int y, const char* text, unsigned width) {
    char cut[40];
    snprintf(cut, sizeof(cut), "%s", text);
    while(*cut && canvas_string_width(canvas, cut) > width) {
        size_t n = strlen(cut) - 1;
        while(n && ((unsigned char)cut[n] & 0xc0) == 0x80)
            n--;
        cut[n] = 0;
    }
    canvas_draw_str(canvas, x, y, cut);
}
static const char* device_name(const RadarDevice* d) {
    return d->name[0] ? d->name : d->kind == 'B' ? "Unnamed BLE" : "Unnamed WiFi";
}
static void draw(Canvas* canvas, void* context) {
    RadarModel* m = context;
    char text[64];
    canvas_set_font(canvas, FontSecondary);
    if(!m->opened || !m->core.ready) {
        canvas_set_font(canvas, FontPrimary);
        canvas_draw_str(canvas, 3, 12, "Nearby");
        canvas_set_font(canvas, FontSecondary);
        label(canvas, 3, 35, m->status, 123);
        snprintf(text, sizeof(text), "%s | Hold R:Port", m->port ? "LPUART" : "USART");
        canvas_draw_str(canvas, 3, 63, m->opened ? text : "OK:Retry  R:Port");
        return;
    }
    if(m->detail && m->core.pinned >= 0) {
        const RadarDevice* d = &m->core.devices[m->core.pinned];
        canvas_set_font(canvas, FontPrimary);
        label(canvas, 2, 11, device_name(d), 124);
        canvas_set_font(canvas, FontSecondary);
        if(m->info) {
            canvas_draw_str(canvas, 3, 25, d->kind == 'B' ? "Bluetooth LE" : "WiFi access point");
            canvas_draw_str(canvas, 3, 37, d->id);
            if(d->kind == 'W')
                snprintf(text, sizeof(text), "CH%u  %d dBm", d->channel, d->average_q4 / 4);
            else
                snprintf(text, sizeof(text), "%d dBm", d->average_q4 / 4);
            canvas_draw_str(canvas, 3, 49, text);
            snprintf(text, sizeof(text), "%lus ago", (unsigned long)((m->now - d->seen) / 1000));
            label(canvas, 83, 49, text, 42);
            canvas_draw_str(canvas, 3, 63, "Back:Radar");
            return;
        }
        canvas_draw_circle(canvas, 27, 35, 9);
        canvas_draw_circle(canvas, 27, 35, 18);
        canvas_draw_dot(canvas, 27, 35);
        bool stale = radar_stale(d, m->now);
        if(!stale && !m->paused && m->core.running)
            canvas_draw_disc(canvas, 27, 35 - (int)radar_radius(d) * 17 / 28, 2);
        canvas_set_font(canvas, FontPrimary);
        if(stale)
            snprintf(text, sizeof(text), "-- dBm");
        else
            snprintf(text, sizeof(text), "%d dBm", d->average_q4 / 4);
        canvas_draw_str(canvas, 59, 30, text);
        canvas_set_font(canvas, FontSecondary);
        canvas_draw_str(
            canvas,
            59,
            45,
            m->paused        ? "Paused" :
            stale            ? "Lost signal" :
            !m->core.running ? "Starting" :
            d->trend > 0     ? "Stronger" :
            d->trend < 0     ? "Weaker" :
                               "Steady");
        canvas_draw_str(canvas, 3, 63, "OK:Info");
        return;
    }
    uint8_t indices[RADAR_CAPACITY];
    size_t n = radar_visible(&m->core, m->filter, m->kind, m->now, indices);
    canvas_set_font(canvas, FontPrimary);
    canvas_draw_str(canvas, 2, 11, m->paused ? "Paused" : "Nearby");
    canvas_set_font(canvas, FontSecondary);
    canvas_draw_str(canvas, 99, 10, m->kind == 'B' ? "BLE>" : m->kind == 'W' ? "WiFi>" : "All>");
    size_t selected = 0;
    for(size_t i = 0; i < n; i++)
        if(indices[i] == m->focus) selected = i;
    size_t start = selected / 3 * 3;
    for(size_t i = start; i < n && i < start + 3; i++) {
        const RadarDevice* d = &m->core.devices[indices[i]];
        int y = 25 + (int)(i - start) * 13;
        if(i == selected) {
            canvas_draw_box(canvas, 0, y - 9, 128, 11);
            canvas_invert_color(canvas);
        }
        text[0] = d->kind;
        text[1] = 0;
        canvas_draw_str(canvas, 2, y, text);
        label(canvas, 11, y, device_name(d), 82);
        snprintf(text, sizeof(text), "%d%s", d->average_q4 / 4, radar_stale(d, m->now) ? "?" : "");
        canvas_draw_str(canvas, 99, y, text);
        if(i == selected) canvas_invert_color(canvas);
    }
    if(!n)
        canvas_draw_str(
            canvas,
            3,
            35,
            m->filter[0] ? "No matching devices" :
            m->paused    ? "Scan paused" :
                           "Scanning...");
    canvas_draw_str(canvas, 3, 63, "OK:Find");
}
static void filter_done(void* context) {
    RadarApp* app = context;
    with_view_model(
        app->view,
        RadarModel * m,
        {
            memcpy(m->filter, app->filter, sizeof(m->filter));
            bool ready = m->core.ready;
            bool running = m->core.running;
            radar_init(&m->core);
            m->focus = UINT8_MAX;
            m->core.ready = ready;
            m->core.running = running;
            m->core.last_frame = now_ms();
        },
        true);
    filter_command(app);
    view_dispatcher_switch_to_view(app->dispatcher, 0);
}
static uint32_t filter_back(void* context) {
    UNUSED(context);
    return 0;
}
static bool input(InputEvent* event, void* context) {
    RadarApp* app = context;
    if(event->type == InputTypeLong && event->key == InputKeyRight) {
        bool ready = false;
        with_view_model(app->view, RadarModel * m, { ready = m->core.ready; }, false);
        if(!ready) {
            close_serial(app);
            app->port ^= 1;
            open_serial(app);
            return true;
        }
    }
    if(event->type == InputTypeLong && event->key == InputKeyOk && app->serial) {
        bool detail = false;
        with_view_model(app->view, RadarModel * m, { detail = m->detail; }, false);
        if(!detail) {
            text_input_set_header_text(app->input, "Find name / address");
            text_input_set_minimum_length(app->input, 0);
            text_input_set_result_callback(
                app->input, filter_done, app, app->filter, sizeof(app->filter), false);
            view_dispatcher_switch_to_view(app->dispatcher, 1);
        }
        return true;
    }
    if(event->type != InputTypeShort && event->type != InputTypeRepeat) return false;
    if(!app->serial && event->key == InputKeyOk) {
        open_serial(app);
        return true;
    }
    bool quit = false, toggle = false, changed = false;
    char kind = 0;
    bool paused = false;
    with_view_model(
        app->view,
        RadarModel * m,
        {
            uint8_t indices[RADAR_CAPACITY];
            size_t n = radar_visible(&m->core, m->filter, m->kind, now_ms(), indices);
            size_t selected = 0;
            for(size_t i = 0; i < n; i++)
                if(indices[i] == m->focus) selected = i;
            if(event->key == InputKeyBack) {
                if(m->info) {
                    m->info = false;
                } else if(m->detail) {
                    m->detail = false;
                    m->core.pinned = -1;
                } else
                    quit = true;
            } else if(!app->serial && (event->key == InputKeyLeft || event->key == InputKeyRight)) {
                app->port ^= 1;
                m->port = app->port;
            } else if(event->key == InputKeyLeft && m->core.ready) {
                m->paused = !m->paused;
                paused = m->paused;
                toggle = true;
                kind = m->kind;
            } else if(event->key == InputKeyRight && !m->detail && m->core.ready) {
                m->kind = m->kind == 0 ? 'B' : m->kind == 'B' ? 'W' : 0;
                kind = m->kind;
                changed = !m->paused;
            } else if(m->detail && event->key == InputKeyOk) {
                m->info = !m->info;
            } else if(!m->detail && n) {
                if(event->key == InputKeyUp) selected = selected ? selected - 1 : n - 1;
                if(event->key == InputKeyDown) selected = (selected + 1) % n;
                m->focus = indices[selected];
                if(event->key == InputKeyOk) {
                    m->core.pinned = (int8_t)m->focus;
                    m->detail = true;
                    m->info = false;
                }
            }
        },
        true);
    if(toggle) {
        if(paused)
            command(app, "NR1,STOP\n");
        else
            scan_command(app, kind);
    }
    if(changed) scan_command(app, kind);
    if(quit) view_dispatcher_stop(app->dispatcher);
    return true;
}
static void tick(void* context) {
    RadarApp* app = context;
    uint32_t now = now_ms();
    uint8_t bytes[1024];
    size_t size = furi_stream_buffer_receive(app->stream, bytes, sizeof(bytes), 0);
    bool start = false, ready = false;
    char kind = 0;
    with_view_model(
        app->view,
        RadarModel * m,
        {
            m->now = now;
            if(app->dropped) {
                m->core.overflow = true;
                m->core.malformed++;
                app->dropped = 0;
            }
            for(size_t i = 0; i < size; i++)
                radar_feed(&m->core, bytes[i], now);
            if(m->core.ready && (uint32_t)(now - m->core.last_frame) > 8000) {
                m->core.ready = false;
                app->scan_sent = false;
            }
            ready = m->core.ready;
            kind = m->kind;
            if(ready && !m->paused &&
               (!app->scan_sent || (!m->core.running && (uint32_t)(now - app->start_at) > 5000))) {
                start = true;
                app->scan_sent = true;
            }
            if(app->serial && !ready && (uint32_t)(now - app->opened_at) > 4000)
                snprintf(m->status, sizeof(m->status), "No ESP32 response");
        },
        true);
    if(start) {
        filter_command(app);
        scan_command(app, kind);
    }
    if(app->serial && (uint32_t)(now - app->ping) > 2000) {
        command(app, ready ? "NR1,PING\n" : "NR1,HELLO\n");
        app->ping = now;
    }
}
static bool custom(void* context, uint32_t event) {
    RadarApp* app = context;
    if(event == 1) {
        view_dispatcher_stop(app->dispatcher);
        return true;
    }
    return false;
}
static void rpc_event(const RpcAppSystemEvent* event, void* context) {
    RadarApp* app = context;
    furi_mutex_acquire(app->rpc_mutex, FuriWaitForever);
    if(event->type == RpcAppEventTypeSessionClose || event->type == RpcAppEventTypeAppExit) {
        if(event->type == RpcAppEventTypeAppExit) {
            rpc_system_app_confirm(app->rpc, true);
            rpc_system_app_send_exited(app->rpc);
        }
        rpc_system_app_set_callback(app->rpc, NULL, NULL);
        app->rpc = NULL;
        view_dispatcher_send_custom_event(app->dispatcher, 1);
    } else
        rpc_system_app_confirm(app->rpc, false);
    furi_mutex_release(app->rpc_mutex);
}
int32_t nearby_radar_app(void* args) {
    RadarApp* app = calloc(1, sizeof(RadarApp));
    app->port = momentum_settings.uart_esp_channel == FuriHalSerialIdLpuart;
    app->rpc_mutex = furi_mutex_alloc(FuriMutexTypeNormal);
    app->stream = furi_stream_buffer_alloc(4096, 1);
    app->expansion = furi_record_open(RECORD_EXPANSION);
    expansion_disable(app->expansion);
    app->gui = furi_record_open(RECORD_GUI);
    app->dispatcher = view_dispatcher_alloc();
    app->view = view_alloc();
    app->input = text_input_alloc();
    view_allocate_model(app->view, ViewModelTypeLocking, sizeof(RadarModel));
    with_view_model(
        app->view,
        RadarModel * m,
        {
            radar_init(&m->core);
            m->port = app->port;
            snprintf(m->status, sizeof(m->status), "Connect a compatible ESP32");
        },
        false);
    view_set_context(app->view, app);
    view_set_draw_callback(app->view, draw);
    view_set_input_callback(app->view, input);
    view_set_previous_callback(text_input_get_view(app->input), filter_back);
    view_dispatcher_add_view(app->dispatcher, 0, app->view);
    view_dispatcher_add_view(app->dispatcher, 1, text_input_get_view(app->input));
    view_dispatcher_set_event_callback_context(app->dispatcher, app);
    view_dispatcher_set_tick_event_callback(app->dispatcher, tick, 100);
    view_dispatcher_set_custom_event_callback(app->dispatcher, custom);
    view_dispatcher_attach_to_gui(app->dispatcher, app->gui, ViewDispatcherTypeFullscreen);
    uint32_t address = 0;
    if(args && sscanf(args, "RPC %lX", &address) == 1 && address) {
        app->rpc = (RpcAppSystem*)address;
        rpc_system_app_set_callback(app->rpc, rpc_event, app);
        rpc_system_app_send_started(app->rpc);
    }
    view_dispatcher_switch_to_view(app->dispatcher, 0);
    open_serial(app);
    view_dispatcher_run(app->dispatcher);
    furi_mutex_acquire(app->rpc_mutex, FuriWaitForever);
    if(app->rpc) {
        rpc_system_app_set_callback(app->rpc, NULL, NULL);
        rpc_system_app_send_exited(app->rpc);
        app->rpc = NULL;
    }
    furi_mutex_release(app->rpc_mutex);
    close_serial(app);
    view_dispatcher_remove_view(app->dispatcher, 1);
    view_dispatcher_remove_view(app->dispatcher, 0);
    text_input_free(app->input);
    view_free(app->view);
    view_dispatcher_free(app->dispatcher);
    furi_record_close(RECORD_GUI);
    expansion_enable(app->expansion);
    furi_record_close(RECORD_EXPANSION);
    furi_stream_buffer_free(app->stream);
    furi_mutex_free(app->rpc_mutex);
    free(app);
    return 0;
}
