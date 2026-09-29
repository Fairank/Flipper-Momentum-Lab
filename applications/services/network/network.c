#include "network_i.h"

#include <furi.h>
#include <string.h>
#include <storage/storage.h>

struct Network {
    FuriMutex* mutex;

    NetworkRpcSend rpc_send;
    void* rpc_send_context;

    NetworkEventCallback event_callback;
    void* event_context;
};

static Network* network_alloc(void) {
    Network* network = malloc(sizeof(Network));
    network->mutex = furi_mutex_alloc(FuriMutexTypeRecursive);
    network->rpc_send = NULL;
    network->rpc_send_context = NULL;
    network->event_callback = NULL;
    network->event_context = NULL;
    return network;
}

static bool network_dispatch(
    Network* network,
    NetworkRpcCommand command,
    const NetworkRpcRequest* request) {
    furi_mutex_acquire(network->mutex, FuriWaitForever);
    bool sent = false;
    if(network->rpc_send) {
        network->rpc_send(command, request, network->rpc_send_context);
        sent = true;
    }
    furi_mutex_release(network->mutex);
    return sent;
}

bool network_connect(
    Network* network,
    uint32_t connection_id,
    const char* host,
    uint16_t port,
    NetworkProtocol protocol,
    uint32_t timeout_ms) {
    furi_check(network);
    furi_check(host);
    if(strlen(host) > NETWORK_MAX_HOST_LENGTH) return false;

    const NetworkRpcRequest request = {
        .connection_id = connection_id,
        .host = host,
        .port = port,
        .protocol = protocol,
        .timeout_ms = timeout_ms,
    };
    return network_dispatch(network, NetworkRpcCommandConnect, &request);
}

bool network_send(Network* network, uint32_t connection_id, const uint8_t* data, size_t size) {
    return network_websocket_send(network, connection_id, data, size, false);
}

bool network_websocket_send(
    Network* network,
    uint32_t connection_id,
    const uint8_t* data,
    size_t size,
    bool binary) {
    furi_check(network);
    furi_check(data);
    if(size == 0 || size > NETWORK_MAX_DATA_SIZE) return false;

    const NetworkRpcRequest request = {
        .connection_id = connection_id,
        .data = data,
        .size = size,
        .binary = binary,
    };
    return network_dispatch(network, NetworkRpcCommandSend, &request);
}

bool network_close(Network* network, uint32_t connection_id) {
    furi_check(network);

    const NetworkRpcRequest request = {
        .connection_id = connection_id,
    };
    return network_dispatch(network, NetworkRpcCommandClose, &request);
}

bool network_http_request(Network* network, uint32_t request_id, const NetworkHttpRequest* request) {
    furi_check(network);
    furi_check(request);
    furi_check(request->url);
    if(strlen(request->url) > NETWORK_MAX_URL_LENGTH) return false;
    if(request->body_size > NETWORK_MAX_DATA_SIZE) return false;
    if(request->body_size && !request->body) return false;

    // /data belongs to the calling app, not the RPC service thread. Resolve it
    // here before crossing to the phone, while the application ID is available.
    FuriString* send_path = request->send_path ? furi_string_alloc_set(request->send_path) : NULL;
    FuriString* save_path = request->save_path ? furi_string_alloc_set(request->save_path) : NULL;
    if(send_path || save_path) {
        Storage* storage = furi_record_open(RECORD_STORAGE);
        if(send_path) storage_common_resolve_path_and_ensure_app_directory(storage, send_path);
        if(save_path) storage_common_resolve_path_and_ensure_app_directory(storage, save_path);
        furi_record_close(RECORD_STORAGE);
    }

    const NetworkRpcRequest rpc = {
        .connection_id = request_id,
        .timeout_ms = request->timeout_ms,
        .data = request->body,
        .size = request->body_size,
        .method = request->method,
        .url = request->url,
        .headers = request->headers,
        .send_path = send_path ? furi_string_get_cstr(send_path) : NULL,
        .save_path = save_path ? furi_string_get_cstr(save_path) : NULL,
        .include_headers = request->include_headers,
    };
    bool result = network_dispatch(network, NetworkRpcCommandHttpRequest, &rpc);
    if(send_path) furi_string_free(send_path);
    if(save_path) furi_string_free(save_path);
    return result;
}

bool network_websocket_open(
    Network* network,
    uint32_t connection_id,
    const char* url,
    const char* headers,
    uint32_t timeout_ms) {
    furi_check(network);
    furi_check(url);
    if(strlen(url) > NETWORK_MAX_URL_LENGTH) return false;

    const NetworkRpcRequest request = {
        .connection_id = connection_id,
        .timeout_ms = timeout_ms,
        .url = url,
        .headers = headers,
    };
    return network_dispatch(network, NetworkRpcCommandWebSocketOpen, &request);
}

void network_set_event_callback(Network* network, NetworkEventCallback callback, void* context) {
    furi_check(network);
    furi_mutex_acquire(network->mutex, FuriWaitForever);
    network->event_callback = callback;
    network->event_context = context;
    furi_mutex_release(network->mutex);
}

void network_set_rpc_bridge(Network* network, NetworkRpcSend send, void* context) {
    furi_check(network);
    furi_mutex_acquire(network->mutex, FuriWaitForever);
    // An older USB/BLE session must not clear a newer session's bridge.
    if(send || network->rpc_send_context == context) {
        network->rpc_send = send;
        network->rpc_send_context = send ? context : NULL;
    }
    furi_mutex_release(network->mutex);
}

void network_on_event(Network* network, const NetworkEvent* event, void* bridge_context) {
    furi_check(network);
    furi_check(event);
    furi_mutex_acquire(network->mutex, FuriWaitForever);
    NetworkEventCallback callback = network->event_callback;
    void* context = network->event_context;
    // Keep callback context alive until delivery completes. Recursive locking lets
    // callbacks send a reply or unregister themselves without deadlocking.
    if(callback && network->rpc_send && network->rpc_send_context == bridge_context) {
        callback(event, context);
    }
    furi_mutex_release(network->mutex);
}

void network_on_system_start(void* p) {
    UNUSED(p);
    furi_record_create(RECORD_NETWORK, network_alloc());
}
