#include "ble_scan_parser.h"
#include <string.h>

bool ble_scan_parse_reports(
    const uint8_t* data,
    size_t size,
    GapScanCallback callback,
    void* context) {
    if(!data || !callback || size < 1 || !data[0]) return false;
    size_t offset = 1;
    for(unsigned i = 0; i < data[0]; i++) {
        if(size - offset < 10) return false;
        size_t length = data[offset + 8];
        if(length > 31 || size - offset < 10 + length || data[offset] > 4 || data[offset + 1] > 3)
            return false;
        offset += 10 + length;
    }
    if(offset != size) return false;
    offset = 1;
    for(unsigned i = 0; i < data[0]; i++) {
        GapScanReport report = {0};
        report.address_type = data[offset + 1];
        memcpy(report.address, data + offset + 2, 6);
        report.data_size = data[offset + 8];
        memcpy(report.data, data + offset + 9, report.data_size);
        report.rssi = (int8_t)data[offset + 9 + report.data_size];
        /* 127 means unavailable. Positive RSSI is valid for very strong signals. */
        if(report.rssi >= -127 && report.rssi <= 20) callback(&report, context);
        offset += 10 + report.data_size;
    }
    return true;
}
