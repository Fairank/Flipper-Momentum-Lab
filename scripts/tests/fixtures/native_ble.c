#undef NDEBUG
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "ble_scan_parser.h"
#include "radar_ble.h"

static unsigned reports;
static GapScanReport latest;
static void capture(const GapScanReport* report, void* context) {
    assert(context == &reports);
    latest = *report;
    reports++;
}

int main(void) {
    uint8_t packet[] = {1, 0, 1, 6, 5, 4, 3, 2, 1, 6, 5, 9, 'T', 'e', 's', 't', 0xc4};
    assert(ble_scan_parse_reports(packet, sizeof(packet), capture, &reports));
    assert(reports == 1 && latest.rssi == -60 && latest.address_type == 1);
    assert(latest.data_size == 6 && !memcmp(latest.address, packet + 3, 6));
    for(size_t i = 0; i < sizeof(packet); i++) {
        unsigned previous = reports;
        assert(!ble_scan_parse_reports(packet, i, capture, &reports));
        assert(reports == previous);
    }
    uint8_t multiple[35];
    multiple[0] = 2;
    memcpy(multiple + 1, packet + 1, 16);
    memcpy(multiple + 17, packet + 1, 16);
    assert(ble_scan_parse_reports(multiple, 33, capture, &reports));
    unsigned previous = reports;
    assert(!ble_scan_parse_reports(multiple, 32, capture, &reports));
    assert(reports == previous); /* No partial delivery before a malformed tail. */
    assert(!ble_scan_parse_reports(multiple, 34, capture, &reports));
    packet[9] = 32;
    assert(!ble_scan_parse_reports(packet, sizeof(packet), capture, &reports));
    packet[9] = 6;
    packet[16] = 127;
    assert(ble_scan_parse_reports(packet, sizeof(packet), capture, &reports));
    assert(reports == previous); /* RSSI not available is not a target. */
    packet[16] = 12;
    assert(ble_scan_parse_reports(packet, sizeof(packet), capture, &reports));
    assert(latest.rssi == 12);

    RadarCore core;
    radar_init(&core);
    assert(radar_ble_observe(&core, latest.address, 1, -60, packet + 10, 6, 100));
    assert(!strcmp(core.devices[0].id, "010203040506"));
    assert(!strcmp(core.devices[0].name, "Test"));
    assert(radar_ble_observe(&core, latest.address, 0, -40, NULL, 0, 101));
    uint8_t indices[RADAR_CAPACITY];
    assert(radar_visible(&core, "", 'B', 101, indices) == 2);
    assert(core.devices[indices[0]].address_type == 0); /* Public != random. */
    assert(radar_visible(&core, "test", 'B', 101, indices) == 1);
    core.pinned = indices[0];
    uint8_t names[] = {3, 8, 'S', 'h', 5, 9, 'F', 'u', 'l', 'l', 2, 8, 'X'};
    assert(radar_ble_observe(&core, latest.address, 3, -30, names, sizeof(names), 3000));
    assert(!strcmp(core.devices[core.pinned].name, "Full"));
    assert(core.devices[core.pinned].trend == 1 && core.devices[core.pinned].seen == 3000);
    uint32_t seen = core.devices[core.pinned].seen;
    names[4] = 31;
    assert(!radar_ble_observe(&core, latest.address, 1, -10, names, sizeof(names), 4000));
    assert(core.devices[core.pinned].seen == seen);
    assert(radar_stale(&core.devices[core.pinned], 15001));
    assert(radar_ble_observe(&core, latest.address, 1, 20, NULL, 0, 16000));
    assert(!strcmp(core.devices[core.pinned].name, "Full"));
    assert(core.devices[core.pinned].trend == 0); /* Stale recovery resets trend. */
    assert(!radar_ble_observe(&core, latest.address, 1, 127, NULL, 0, 16000));
    assert(!radar_ble_observe(&core, latest.address, 4, -60, NULL, 0, 16000));
    radar_init(&core);
    strcpy(core.accept_filter, "Test");
    assert(radar_ble_observe(&core, latest.address, 1, -60, NULL, 0, 1));
    assert(!radar_visible(&core, "", 'B', 1, indices));
    assert(radar_ble_observe(&core, latest.address, 1, -60, packet + 10, 6, 2));
    assert(radar_visible(&core, "Test", 'B', 2, indices) == 1);
    assert(radar_ble_observe(&core, latest.address, 1, -30, NULL, 0, 3));
    assert(core.devices[indices[0]].seen == 3); /* Unnamed updates retain known name. */
    radar_init(&core);
    for(unsigned i = 0; i < RADAR_CAPACITY; i++) {
        char id[13];
        snprintf(id, sizeof(id), "%012X", i);
        assert(radar_observe(&core, 'B', id, 0, -100, 0, NULL, 0, 10));
    }
    core.pinned = 0;
    assert(radar_observe(&core, 'B', "AABBCCDDEEFF", 0, -30, 0, NULL, 0, 11));
    assert(!strcmp(core.devices[0].id, "000000000000"));
    assert(radar_visible(&core, "", 'B', 11, indices) == RADAR_CAPACITY);
    assert(!strcmp(core.devices[indices[0]].id, "AABBCCDDEEFF"));
    /* Deterministic malformed HCI/AD corpus exercises production bounds checks. */
    uint32_t seed = 42;
    uint8_t random[256];
    for(unsigned round = 0; round < 12000; round++) {
        for(size_t i = 0; i < sizeof(random); i++) {
            seed = seed * 1664525u + 1013904223u;
            random[i] = seed >> 24;
        }
        ble_scan_parse_reports(random, round % sizeof(random), capture, &reports);
        radar_ble_observe(&core, latest.address, round % 4, -60, random, round % 32, round);
    }
    puts("Native BLE parser and tracking passed");
    return 0;
}
