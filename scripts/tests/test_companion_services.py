"""Run the real proxy service C with small mutex/record substitutes.

These checks cover session ownership, callback lifetimes and bounded payloads;
they are not a Bluetooth, phone proxy or concurrent RTOS acceptance test.
"""

from pathlib import Path
import re
import unittest

from test_unleashed_integration import native_test

ROOT = Path(__file__).resolve().parents[2]
STUBS = r"""
#include <assert.h>
#include <stdlib.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#define furi_check assert
#define UNUSED(x) (void)(x)
#define FuriWaitForever 0
#define FuriMutexTypeRecursive 1
typedef struct { unsigned depth; } FuriMutex;
static FuriMutex* furi_mutex_alloc(int kind) {
    assert(kind == FuriMutexTypeRecursive);
    return calloc(1, sizeof(FuriMutex));
}
static void furi_mutex_acquire(FuriMutex* m, int timeout) {
    (void)timeout; ++m->depth;
}
static void furi_mutex_release(FuriMutex* m) { assert(m->depth); --m->depth; }
static void furi_record_create(const char* name, void* value) { (void)name; (void)value; }
"""


def implementation(service):
    folder = ROOT / "applications/services" / service
    text = "\n".join(
        (folder / name).read_text(encoding="utf-8")
        for name in (f"{service}.h", f"{service}_i.h", f"{service}.c")
    )
    return re.sub(
        r'^#(?:pragma once|include "[^"\n]+"|include <furi.h>)\s*$',
        "",
        text,
        flags=re.M,
    )


class CompanionServiceTests(unittest.TestCase):
    def test_network_session_replacement_and_payload_limits(self):
        native_test(
            STUBS
            + implementation("network")
            + r"""
static unsigned sent_a, sent_b, received;
static void send_request(NetworkRpcCommand command, const NetworkRpcRequest* req, void* ctx) {
    (void)command; (void)req; ++*(unsigned*)ctx;
}
static void receive_event(const NetworkEvent* event, void* ctx) {
    (void)event;
    Network* net = ctx;
    assert(net->mutex->depth > 0);
    ++received;
    assert(network_close(net, 1)); // Reentrant request is permitted.
    network_set_event_callback(net, NULL, NULL);
}
int main(void) {
    Network* net = network_alloc();
    assert(strcmp(network_error_to_string(NetworkErrorNone), "OK") == 0);
    assert(strcmp(network_state_to_string(NetworkStateConnected), "Connected") == 0);
    assert(network_state_is_terminal(NetworkStateDisconnected));
    assert(!network_state_is_terminal(NetworkStateConnected));
    assert(!network_close(net, 1));
    network_set_rpc_bridge(net, send_request, &sent_a);
    assert(network_connect(net, 1, "localhost", 1234, NetworkProtocolTcp, 100));
    assert(sent_a == 1);
    network_set_rpc_bridge(net, send_request, &sent_b);
    network_set_rpc_bridge(net, NULL, &sent_a);
    assert(network_close(net, 1));
    assert(sent_b == 1);
    NetworkEvent event = {.type = NetworkEventReceived};
    network_set_event_callback(net, receive_event, net);
    network_on_event(net, &event, &sent_a);
    assert(received == 0);
    network_on_event(net, &event, &sent_b);
    assert(received == 1 && sent_b == 2);
    network_on_event(net, &event, &sent_b);
    assert(received == 1);
    uint8_t bytes[NETWORK_MAX_DATA_SIZE + 1] = {0};
    assert(!network_send(net, 1, bytes, 0));
    assert(!network_send(net, 1, bytes, sizeof(bytes)));
    assert(network_send(net, 1, bytes, NETWORK_MAX_DATA_SIZE));
    NetworkHttpRequest request = {.url = "https://example.com", .body_size = 1};
    assert(!network_http_request(net, 1, &request));
    request.body = bytes;
    assert(network_http_request(net, 1, &request));
    network_set_rpc_bridge(net, NULL, &sent_b);
    assert(!network_close(net, 1));
    assert(net->mutex->depth == 0);
    free(net->mutex); free(net);
    return 0;
}
"""
        )

    def test_location_session_replacement_and_callback_reentry(self):
        native_test(
            STUBS
            + implementation("gps")
            + r"""
static unsigned sent_a, sent_b, received;
static void send_request(GpsRpcCommand command, uint8_t hz, const GpsLocation* loc, void* ctx) {
    (void)command; (void)hz; (void)loc; ++*(unsigned*)ctx;
}
static void receive_location(GpsStatus status, const GpsLocation* loc, void* ctx) {
    (void)status; (void)loc;
    Gps* gps = ctx;
    assert(gps->mutex->depth > 0);
    ++received;
    assert(gps_stop_stream(gps));
    gps_set_location_callback(gps, NULL, NULL);
}
int main(void) {
    Gps* gps = gps_alloc();
    char formatted[64];
    gps_location_format_coordinate(formatted, sizeof(formatted), INT32_MIN);
    assert(strcmp(formatted, "-214.7483648") == 0);
    gps_location_format_heading(formatted, sizeof(formatted), 1234);
    assert(strcmp(formatted, "12.3") == 0);
    gps_location_format_speed(formatted, sizeof(formatted), 1234);
    assert(strcmp(formatted, "1.23") == 0);
    gps_location_format_altitude(formatted, sizeof(formatted), -1234);
    assert(strcmp(formatted, "-12.3") == 0);
    gps_location_format_accuracy(formatted, sizeof(formatted), 1234);
    assert(strcmp(formatted, "1.2") == 0);
    assert(!gps_request_location(gps));
    gps_set_rpc_bridge(gps, send_request, &sent_a);
    assert(!gps_request_stream(gps, 0));
    assert(!gps_request_stream(gps, 11));
    assert(gps_request_stream(gps, 1));
    assert(gps_request_stream(gps, 10));
    assert(sent_a == 2);
    gps_set_rpc_bridge(gps, send_request, &sent_b);
    gps_set_rpc_bridge(gps, NULL, &sent_a);
    assert(gps_request_location(gps));
    assert(sent_b == 1);
    gps_set_location_callback(gps, receive_location, gps);
    GpsLocation location = {0};
    gps_on_location(gps, GpsStatusOk, &location, &sent_a);
    assert(received == 0);
    gps_on_location(gps, GpsStatusOk, &location, &sent_b);
    assert(received == 1 && sent_b == 2);
    gps_on_location(gps, GpsStatusOk, &location, &sent_b);
    assert(received == 1);
    gps_set_rpc_bridge(gps, NULL, &sent_b);
    assert(!gps_stop_stream(gps));
    assert(gps->mutex->depth == 0);
    free(gps->mutex); free(gps);
    return 0;
}
"""
        )


if __name__ == "__main__":
    unittest.main()
