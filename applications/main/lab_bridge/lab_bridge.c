#include "bridge_protocol.h"
#include <furi.h>
#include <furi_hal.h>
#include <gui/gui.h>
#include <gui/view_dispatcher.h>
#include <rpc/rpc_app.h>
#include <expansion/expansion.h>
#include <momentum/momentum.h>
#include <stdio.h>

typedef struct {
    uint32_t received;
    uint32_t dropped;
    uint32_t baud;
    uint8_t port;
    bool opened;
    bool remote;
    bool busy;
} LabBridgeModel;

typedef struct {
    Gui* gui;
    Expansion* expansion;
    ViewDispatcher* dispatcher;
    View* view;
    FuriMutex* mutex;
    FuriStreamBuffer* stream;
    FuriHalSerialHandle* serial;
    RpcAppSystem* rpc;
    volatile uint32_t dropped;
    uint32_t received;
    uint32_t baud;
    uint8_t port;
} LabBridge;

static void lab_bridge_rx(FuriHalSerialHandle* serial, FuriHalSerialRxEvent event, void* context) {
    LabBridge* app = context;
    if(event & FuriHalSerialRxEventData) {
        const uint8_t byte = furi_hal_serial_async_rx(serial);
        if(furi_stream_buffer_send(app->stream, &byte, 1, 0) != 1 && app->dropped != UINT32_MAX) {
            app->dropped++;
        }
    }
    if(event & FuriHalSerialRxEventOverrunError) {
        if(app->dropped != UINT32_MAX) app->dropped++;
    }
}

static void lab_bridge_close(LabBridge* app) {
    if(!app->serial) return;
    furi_hal_serial_async_rx_stop(app->serial);
    furi_hal_serial_tx_wait_complete(app->serial);
    furi_hal_serial_deinit(app->serial);
    furi_hal_serial_control_release(app->serial);
    app->serial = NULL;
}

static uint8_t lab_bridge_open(LabBridge* app, uint8_t port, uint32_t baud) {
    lab_bridge_close(app);
    app->port = port;
    app->serial =
        furi_hal_serial_control_acquire(port == 0 ? FuriHalSerialIdUsart : FuriHalSerialIdLpuart);
    if(!app->serial) return 2;
    if(!furi_hal_serial_is_baud_rate_supported(app->serial, baud)) {
        furi_hal_serial_control_release(app->serial);
        app->serial = NULL;
        return 1;
    }
    furi_stream_buffer_reset(app->stream);
    app->dropped = 0;
    app->received = 0;
    app->baud = baud;
    furi_hal_serial_init(app->serial, baud);
    furi_hal_serial_async_rx_start(app->serial, lab_bridge_rx, app, true);
    return 0;
}

static void lab_bridge_update(LabBridge* app, bool busy) {
    with_view_model(
        app->view,
        LabBridgeModel * model,
        {
            model->received = app->received;
            model->dropped = app->dropped;
            model->baud = app->baud;
            model->port = app->port;
            model->opened = app->serial != NULL;
            model->remote = app->rpc != NULL;
            model->busy = busy;
        },
        true);
}

/* RPC callbacks execute sequentially on the RPC session thread. Process each bounded
 * command here, before confirming it; no pointer to request memory survives the callback.
 * Reads are pulled by the phone so a stalled BLE client cannot grow a transmit queue. */
static void lab_bridge_rpc(const RpcAppSystemEvent* event, void* context) {
    LabBridge* app = context;
    furi_mutex_acquire(app->mutex, FuriWaitForever);
    if(event->type == RpcAppEventTypeSessionClose) {
        rpc_system_app_set_callback(app->rpc, NULL, NULL);
        app->rpc = NULL;
        lab_bridge_close(app);
        view_dispatcher_stop(app->dispatcher);
    } else if(event->type == RpcAppEventTypeAppExit) {
        lab_bridge_close(app);
        rpc_system_app_confirm(app->rpc, true);
        rpc_system_app_set_callback(app->rpc, NULL, NULL);
        rpc_system_app_send_exited(app->rpc);
        app->rpc = NULL;
        view_dispatcher_stop(app->dispatcher);
    } else if(event->type == RpcAppEventTypeDataExchange) {
        const uint8_t* request = event->data.bytes.ptr;
        const size_t size = event->data.bytes.size;
        if(event->data.type != RpcAppSystemEventDataTypeBytes ||
           !lab_bridge_valid_request(request, size)) {
            rpc_system_app_confirm(app->rpc, false);
        } else {
            uint8_t reply[LAB_BRIDGE_REPLY_HEADER + LAB_BRIDGE_CHUNK] = {0};
            memcpy(reply, request, LAB_BRIDGE_REQUEST_HEADER);
            size_t count = 0;
            switch(request[6]) {
            case LabBridgeHello: {
                const char identity[] = "FlipperLab.Serial/1";
                count = sizeof(identity) - 1;
                memcpy(reply + LAB_BRIDGE_REPLY_HEADER, identity, count);
                break;
            }
            case LabBridgeOpen:
                reply[7] = lab_bridge_open(app, request[7], lab_bridge_read_u32(request + 8));
                break;
            case LabBridgeRead:
                if(!app->serial)
                    reply[7] = 3;
                else {
                    count = furi_stream_buffer_receive(
                        app->stream, reply + LAB_BRIDGE_REPLY_HEADER, LAB_BRIDGE_CHUNK, 0);
                    app->received += count;
                }
                break;
            case LabBridgeWrite:
                if(!app->serial)
                    reply[7] = 3;
                else {
                    furi_hal_serial_tx(
                        app->serial,
                        request + LAB_BRIDGE_REQUEST_HEADER,
                        size - LAB_BRIDGE_REQUEST_HEADER);
                    furi_hal_serial_tx_wait_complete(app->serial);
                }
                break;
            case LabBridgeClose:
                lab_bridge_close(app);
                break;
            default:
                reply[7] = 1;
                break;
            }
            lab_bridge_write_u32(reply + 8, app->dropped);
            rpc_system_app_exchange_data(app->rpc, reply, LAB_BRIDGE_REPLY_HEADER + count);
            rpc_system_app_confirm(app->rpc, true);
            lab_bridge_update(app, reply[7] == 2);
        }
    } else {
        rpc_system_app_confirm(app->rpc, false);
    }
    furi_mutex_release(app->mutex);
}

static void lab_bridge_draw(Canvas* canvas, void* context) {
    LabBridgeModel* model = context;
    char line[48];
    canvas_set_font(canvas, FontPrimary);
    canvas_draw_str(canvas, 2, 12, "Expansion Serial");
    canvas_set_font(canvas, FontSecondary);
    canvas_draw_str(
        canvas,
        2,
        25,
        model->busy   ? "Serial port busy" :
        model->opened ? "Receiving" :
                        "Serial port closed");
    snprintf(
        line,
        sizeof(line),
        "%s %lu RX %lu",
        model->port == 0 ? "USART" : "LPUART",
        model->baud,
        model->received);
    canvas_draw_str(canvas, 2, 37, line);
    snprintf(line, sizeof(line), "Dropped: %lu", model->dropped);
    canvas_draw_str(canvas, 2, 49, line);
    canvas_draw_str(
        canvas,
        2,
        62,
        model->remote ? "Stop RX on phone" :
        model->opened ? "OK:Stop Back:Exit" :
                        "L/R:Port OK:Receive");
}

static bool lab_bridge_input(InputEvent* event, void* context) {
    LabBridge* app = context;
    if(event->type != InputTypeShort ||
       (event->key != InputKeyOk && event->key != InputKeyLeft && event->key != InputKeyRight))
        return false;
    furi_mutex_acquire(app->mutex, FuriWaitForever);
    if(!app->rpc) {
        uint8_t status = 0;
        if(event->key == InputKeyOk) {
            if(app->serial)
                lab_bridge_close(app);
            else
                status = lab_bridge_open(app, app->port, 115200);
            lab_bridge_update(app, status == 2);
        } else if(!app->serial) {
            app->port = app->port == 0 ? 1 : 0;
            lab_bridge_update(app, false);
        }
    }
    furi_mutex_release(app->mutex);
    return true;
}

static uint32_t lab_bridge_back(void* context) {
    LabBridge* app = context;
    // The RPC session detaches its own callback before stopping the dispatcher.
    // Back must not free the app while a callback is waiting on this mutex.
    furi_mutex_acquire(app->mutex, FuriWaitForever);
    const bool remote = app->rpc != NULL;
    furi_mutex_release(app->mutex);
    return remote ? VIEW_IGNORE : VIEW_NONE;
}

static void lab_bridge_tick(void* context) {
    LabBridge* app = context;
    furi_mutex_acquire(app->mutex, FuriWaitForever);
    if(!app->rpc && app->serial) {
        uint8_t bytes[LAB_BRIDGE_CHUNK];
        app->received += furi_stream_buffer_receive(app->stream, bytes, sizeof(bytes), 0);
        lab_bridge_update(app, false);
    }
    furi_mutex_release(app->mutex);
}

int32_t lab_bridge_app(void* args) {
    LabBridge* app = malloc(sizeof(LabBridge));
    memset(app, 0, sizeof(LabBridge));
    app->mutex = furi_mutex_alloc(FuriMutexTypeNormal);
    app->stream = furi_stream_buffer_alloc(8192, 1);
    app->baud = 115200;
    app->port = momentum_settings.uart_esp_channel == FuriHalSerialIdLpuart ? 1 : 0;
    app->expansion = furi_record_open(RECORD_EXPANSION);
    expansion_disable(app->expansion);
    app->gui = furi_record_open(RECORD_GUI);
    app->dispatcher = view_dispatcher_alloc();
    app->view = view_alloc();
    view_allocate_model(app->view, ViewModelTypeLocking, sizeof(LabBridgeModel));
    view_set_context(app->view, app);
    view_set_draw_callback(app->view, lab_bridge_draw);
    view_set_input_callback(app->view, lab_bridge_input);
    view_set_previous_callback(app->view, lab_bridge_back);
    view_dispatcher_set_event_callback_context(app->dispatcher, app);
    view_dispatcher_set_tick_event_callback(app->dispatcher, lab_bridge_tick, 100);
    view_dispatcher_add_view(app->dispatcher, 0, app->view);
    view_dispatcher_attach_to_gui(app->dispatcher, app->gui, ViewDispatcherTypeFullscreen);
    uint32_t rpc_address = 0;
    if(args && sscanf(args, "RPC %lX", &rpc_address) == 1 && rpc_address) {
        app->rpc = (RpcAppSystem*)rpc_address;
        rpc_system_app_set_callback(app->rpc, lab_bridge_rpc, app);
        rpc_system_app_send_started(app->rpc);
    }
    lab_bridge_update(app, false);
    view_dispatcher_switch_to_view(app->dispatcher, 0);
    view_dispatcher_run(app->dispatcher);
    furi_mutex_acquire(app->mutex, FuriWaitForever);
    if(app->rpc) {
        rpc_system_app_set_callback(app->rpc, NULL, NULL);
        rpc_system_app_send_exited(app->rpc);
        app->rpc = NULL;
    }
    lab_bridge_close(app);
    furi_mutex_release(app->mutex);
    view_dispatcher_remove_view(app->dispatcher, 0);
    view_free(app->view);
    view_dispatcher_free(app->dispatcher);
    furi_record_close(RECORD_GUI);
    expansion_enable(app->expansion);
    furi_record_close(RECORD_EXPANSION);
    furi_stream_buffer_free(app->stream);
    furi_mutex_free(app->mutex);
    free(app);
    return 0;
}
