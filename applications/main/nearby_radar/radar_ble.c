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
    int rssi_1m = 0;
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
        /* iBeacon's measured power is RSSI at one meter. AD type 0x0a is
         * transmitter output power, so it must never serve as this reference.
         * Check the entire exact manufacturer layout before reading its tail. */
        if(type == 0xff && length == 26 && data[i + 1] == 0x4c && data[i + 2] == 0x00 &&
           data[i + 3] == 0x02 && data[i + 4] == 0x15) {
            int measured = data[i + 25] < 128 ? data[i + 25] : (int)data[i + 25] - 256;
            if(measured >= -100 && measured <= -15) rssi_1m = measured;
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
    /* Nothing is delivered before the complete AD sequence has been checked. */
    bool observed = radar_observe(core, 'B', id, address_type & 1, rssi, 0, name, name_size, now);
    if(observed && rssi_1m) radar_set_beacon_reference(core, id, address_type & 1, rssi_1m);
    return observed;
}
