#pragma once
#include "gap.h"
#include <stddef.h>

/* Parse the bytes after LE Advertising Report's subevent code. Reject malformed
 * packets before delivering any reports. No pointers into HCI buffers escape.
 */
bool ble_scan_parse_reports(
    const uint8_t* data,
    size_t size,
    GapScanCallback callback,
    void* context);
