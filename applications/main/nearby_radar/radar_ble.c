#include "radar_ble.h"

bool radar_ble_observe(
    RadarCore* core,
    const uint8_t address[6],
    uint8_t address_type,
    int rssi,
    const uint8_t* data,
    size_t size,
    uint32_t now) {
    if(!address || address_type > 3 || size > 31 || (size && !data)) return false;
    const uint8_t* name = NULL;
    size_t name_size = 0;
    bool complete = false;
    for(size_t i = 0; i < size;) {
        size_t length = data[i++];
        if(!length) break;
        if(length > size - i) return false;
        uint8_t type = data[i];
        if((type == 0x09 || (type == 0x08 && !complete)) && length > 1) {
            name = data + i + 1;
            name_size = length - 1;
            complete = type == 0x09;
        }
        i += length;
    }
    char id[13] = {0};
    const char* hex = "0123456789ABCDEF";
    for(size_t i = 0; i < 6; i++) {
        uint8_t byte = address[5 - i];
        id[i * 2] = hex[byte >> 4];
        id[i * 2 + 1] = hex[byte & 15];
    }
    return radar_observe(core, 'B', id, address_type & 1, rssi, 0, name, name_size, now);
}
