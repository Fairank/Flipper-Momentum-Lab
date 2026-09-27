#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define LAB_BRIDGE_CHUNK 512
#define LAB_BRIDGE_REQUEST_HEADER 7
#define LAB_BRIDGE_REPLY_HEADER 12

typedef enum {
    LabBridgeHello = 0,
    LabBridgeOpen = 1,
    LabBridgeRead = 2,
    LabBridgeWrite = 3,
    LabBridgeClose = 4,
} LabBridgeOperation;

static inline uint32_t lab_bridge_read_u32(const uint8_t* data) {
    return (uint32_t)data[0] | (uint32_t)data[1] << 8 | (uint32_t)data[2] << 16 |
           (uint32_t)data[3] << 24;
}

static inline void lab_bridge_write_u32(uint8_t* data, uint32_t value) {
    for(size_t i = 0; i < 4; i++) data[i] = (uint8_t)(value >> (i * 8));
}

static inline bool lab_bridge_valid_request(const uint8_t* data, size_t size) {
    if(!data || size < LAB_BRIDGE_REQUEST_HEADER ||
       size > LAB_BRIDGE_REQUEST_HEADER + LAB_BRIDGE_CHUNK ||
       memcmp(data, "FLB\x01", 4) != 0) {
        return false;
    }
    const size_t payload_size = size - LAB_BRIDGE_REQUEST_HEADER;
    switch(data[6]) {
    case LabBridgeHello:
    case LabBridgeRead:
    case LabBridgeClose:
        return payload_size == 0;
    case LabBridgeOpen: {
        if(payload_size != 5 || data[7] > 1) return false;
        const uint32_t baud = lab_bridge_read_u32(data + 8);
        return baud == 9600 || baud == 19200 || baud == 38400 || baud == 57600 ||
               baud == 115200 || baud == 230400;
    }
    case LabBridgeWrite:
        return payload_size > 0;
    default:
        return false;
    }
}
