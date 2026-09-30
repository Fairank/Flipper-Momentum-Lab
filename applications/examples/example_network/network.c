#include <furi.h>
#include <furi_hal.h>
#include <gui/gui.h>
#include <network/network.h>
#include <storage/storage.h>
#include <string.h>

/* Minimal Network service usage: a single HTTP GET.
 *
 * API used: furi_record_open(RECORD_NETWORK), network_set_event_callback(),
 * network_http_request(). save_path is set, so the companion writes the
 * response body to the SD card itself - no NetworkEventReceived chunks arrive,
 * the request ends with a single NetworkEventHttpResponse.
 */

#define NETWORK_TEST_URL        "https://example.com/"
#define NETWORK_TEST_TIMEOUT_MS 30000
#define NETWORK_TEST_SAVE_PATH  APP_DATA_PATH("networktest_response.txt")

typedef enum {
    AppStateInit,
    AppStateNoBridge,
    AppStateRequesting,
    AppStateDone,
    AppStateError,
} AppState;

typedef struct {
    FuriMutex* mutex;
    AppState state;
    NetworkError error;
    uint32_t http_status;
    uint32_t body_size;
    bool saved_to_file;
    uint32_t request_id;
    uint32_t started_at;
} NetworkTest;

/* Called from the RPC session thread, not from this app's thread. Events are
 * demuxed by connection_id - the id passed to network_http_request(). The
 * event and all its pointers are valid only for the duration of the call. */
static void network_test_event_callback(const NetworkEvent* event, void* context) {
    NetworkTest* test = context;
    furi_mutex_acquire(test->mutex, FuriWaitForever);
    if(event->connection_id != test->request_id || test->state != AppStateRequesting) {
        furi_mutex_release(test->mutex);
        return;
    }
    if(event->type == NetworkEventHttpResponse) {
        /* error covers the transport (DNS/TCP/TLS/timeout/file). On success
         * http_status is the HTTP code, size is the body size, saved_to_file
         * confirms the companion wrote the body to save_path. */
        if(event->error != NetworkErrorNone) {
            test->state = AppStateError;
            test->error = event->error;
        } else {
            test->state = AppStateDone;
            test->http_status = event->http_status;
            test->body_size = event->size;
            test->saved_to_file = event->saved_to_file;
        }
    }
    furi_mutex_release(test->mutex);
}

static void render_callback(Canvas* canvas, void* context) {
    NetworkTest* test = context;
    furi_mutex_acquire(test->mutex, FuriWaitForever);

    char buffer[64];

    canvas_set_font(canvas, FontPrimary);
    canvas_draw_str_aligned(canvas, 64, 11, AlignCenter, AlignBottom, "Internet test");

    canvas_set_font(canvas, FontSecondary);
    canvas_draw_str_aligned(canvas, 64, 21, AlignCenter, AlignBottom, NETWORK_TEST_URL);

    const char* status;
    switch(test->state) {
    case AppStateNoBridge:
        status = "No USB/BLE connection";
        break;
    case AppStateInit:
        status = "Press OK to start";
        break;
    case AppStateRequesting:
        status = "Requesting...";
        break;
    case AppStateDone:
        status = "Internet available";
        break;
    case AppStateError:
        status = "Failed, OK to retry";
        break;
    default:
        status = "";
        break;
    }
    canvas_draw_str_aligned(canvas, 64, 33, AlignCenter, AlignBottom, status);

    if(test->state == AppStateError) {
        snprintf(buffer, sizeof(buffer), "Error code: %u", (unsigned)test->error);
        canvas_draw_str_aligned(canvas, 64, 46, AlignCenter, AlignBottom, buffer);
    } else if(test->http_status) {
        snprintf(buffer, sizeof(buffer), "HTTP %lu", (unsigned long)test->http_status);
        canvas_draw_str_aligned(canvas, 64, 44, AlignCenter, AlignBottom, buffer);
    }

    if(test->state == AppStateDone) {
        const char* tail = test->saved_to_file ? "saved to SD" : "received";
        snprintf(buffer, sizeof(buffer), "%lu bytes %s", (unsigned long)test->body_size, tail);
        canvas_draw_str_aligned(canvas, 64, 59, AlignCenter, AlignBottom, buffer);
    }

    furi_mutex_release(test->mutex);
}

static void input_callback(InputEvent* input_event, void* context) {
    FuriMessageQueue* event_queue = context;
    furi_message_queue_put(event_queue, input_event, FuriWaitForever);
}

int32_t network_app(void* p) {
    UNUSED(p);

    NetworkTest* test = malloc(sizeof(NetworkTest));
    test->mutex = furi_mutex_alloc(FuriMutexTypeNormal);
    test->state = AppStateInit;
    test->error = NetworkErrorNone;
    test->http_status = 0;
    test->body_size = 0;
    test->saved_to_file = false;
    test->request_id = furi_hal_random_get();
    test->started_at = 0;

    FuriMessageQueue* event_queue = furi_message_queue_alloc(8, sizeof(InputEvent));

    Network* network = furi_record_open(RECORD_NETWORK);
    network_set_event_callback(network, network_test_event_callback, test);

    ViewPort* view_port = view_port_alloc();
    view_port_draw_callback_set(view_port, render_callback, test);
    view_port_input_callback_set(view_port, input_callback, event_queue);

    Gui* gui = furi_record_open(RECORD_GUI);
    gui_add_view_port(gui, view_port, GuiLayerFullscreen);

    /* Unset fields default to NULL/0: no extra headers, no request body,
     * timeout_ms = 0 would select the companion default. */
    const NetworkHttpRequest request = {
        .method = NetworkHttpMethodGet,
        .url = NETWORK_TEST_URL,
        .save_path = NETWORK_TEST_SAVE_PATH,
        .timeout_ms = NETWORK_TEST_TIMEOUT_MS,
    };

    InputEvent event;
    for(bool processing = true; processing;) {
        if(furi_message_queue_get(event_queue, &event, 100) == FuriStatusOk) {
            if(event.type == InputTypeShort && event.key == InputKeyBack) {
                processing = false;
            } else if(event.type == InputTypeShort && event.key == InputKeyOk) {
                furi_mutex_acquire(test->mutex, FuriWaitForever);
                bool start = test->state != AppStateRequesting;
                if(start) {
                    ++test->request_id;
                    test->state = AppStateRequesting;
                    test->http_status = test->body_size = 0;
                    test->saved_to_file = false;
                    test->started_at = furi_get_tick();
                }
                furi_mutex_release(test->mutex);
                // The service callback takes the opposite lock order. Never
                // call it while holding this application's display mutex.
                if(start && !network_http_request(network, test->request_id, &request)) {
                    furi_mutex_acquire(test->mutex, FuriWaitForever);
                    test->state = AppStateNoBridge;
                    furi_mutex_release(test->mutex);
                }
            }
        }
        furi_mutex_acquire(test->mutex, FuriWaitForever);
        bool expired = test->state == AppStateRequesting &&
                       furi_get_tick() - test->started_at > furi_ms_to_ticks(180000);
        if(expired) {
            test->state = AppStateError;
            test->error = NetworkErrorTimeout;
        }
        furi_mutex_release(test->mutex);
        if(expired) network_close(network, test->request_id);
        view_port_update(view_port);
    }

    /* Unsubscribe before closing the record: a late event must not reach a
     * freed context. */
    network_set_event_callback(network, NULL, NULL);
    network_close(network, test->request_id);
    furi_record_close(RECORD_NETWORK);

    view_port_enabled_set(view_port, false);
    gui_remove_view_port(gui, view_port);
    furi_record_close(RECORD_GUI);
    view_port_free(view_port);
    furi_message_queue_free(event_queue);
    furi_mutex_free(test->mutex);
    free(test);

    return 0;
}
