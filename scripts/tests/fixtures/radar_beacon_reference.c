#undef NDEBUG
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "radar_ble.h"

static const uint8_t address[] = {1, 2, 3, 4, 5, 6};
/* One complete iBeacon AD: LE company 0x004c, 0x02/0x15, UUID, major/minor,
 * calibrated RSSI at one meter. It is not the ordinary AD Tx Power field. */
static const uint8_t beacon[] = {
    26,   0xff, 0x4c, 0x00, 0x02, 0x15, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
    0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x00, 0x01, 0x00, 0x02, 0xc5,
};

static void valid(void) {
    RadarCore core;
    radar_init(&core);
    uint8_t named[30] = {2, 9, 'T'};
    memcpy(named + 3, beacon, sizeof(beacon));
    assert(radar_ble_observe(&core, address, 1, -70, named, sizeof(named), 1000));
    const RadarDevice* target = &core.devices[0];
    assert(target->used && !strcmp(target->name, "T"));
    assert(!strcmp(target->id, "060504030201") && target->address_type == 1);
    assert(target->range.reference == RadarRangeReferenceBeacon);
    assert(target->range.reference_rssi == -59);
}

static void unrelated(void) {
    RadarCore core;
    uint8_t data[sizeof(beacon) + 1];
    const uint8_t tx_power[] = {2, 0x0a, 0xc5};
    radar_init(&core);
    assert(radar_ble_observe(&core, address, 1, -59, tx_power, sizeof(tx_power), 1000));
    assert(core.devices[0].used);
    assert(core.devices[0].range.reference == RadarRangeReferenceNone);
    for(unsigned type = 0; type < 5; type++) {
        memcpy(data, beacon, sizeof(beacon));
        size_t size = sizeof(beacon);
        switch(type) {
        case 0:
            data[2] = 0x00;
            data[3] = 0x4c;
            break; /* Wrong company endian. */
        case 1:
            data[4] = 0x12;
            break; /* Other Apple manufacturer subtype. */
        case 2:
            data[5] = 0x14;
            break;
        case 3:
            data[0] = 25;
            size--;
            break; /* Valid AD, incomplete iBeacon. */
        case 4:
            data[0] = 27;
            data[sizeof(beacon)] = 0;
            size++;
            break;
        }
        radar_init(&core);
        assert(radar_ble_observe(&core, address, 1, -59, data, size, 1000));
        assert(core.devices[0].used);
        assert(core.devices[0].range.reference == RadarRangeReferenceNone);
    }
}

static void malformed(void) {
    RadarCore core, before;
    radar_init(&core);
    assert(radar_ble_observe(&core, address, 1, -60, NULL, 0, 100));
    before = core;
    uint8_t data[30];
    memcpy(data, beacon, sizeof(beacon));
    data[27] = 4;
    data[28] = 9;
    data[29] = 'X';
    assert(!radar_ble_observe(&core, address, 1, -50, data, sizeof(data), 2000));
    assert(!memcmp(&core, &before, sizeof(core)));
    for(size_t size = 1; size < sizeof(beacon); size++) {
        assert(!radar_ble_observe(&core, address, 1, -50, beacon, size, 2000));
        assert(!memcmp(&core, &before, sizeof(core)));
    }
}

static void bounds(void) {
    RadarCore core;
    uint8_t data[sizeof(beacon)];
    const int invalid[] = {-128, -101, -14, 0, 20, 127};
    for(unsigned i = 0; i < sizeof(invalid) / sizeof(invalid[0]); i++) {
        radar_init(&core);
        memcpy(data, beacon, sizeof(beacon));
        data[26] = (uint8_t)invalid[i];
        assert(radar_ble_observe(&core, address, 1, -60, data, sizeof(data), 1000));
        assert(core.devices[0].used && core.devices[0].seen == 1000);
        assert(core.devices[0].range.reference == RadarRangeReferenceNone);
    }
    const int accepted[] = {-100, -15};
    for(unsigned i = 0; i < sizeof(accepted) / sizeof(accepted[0]); i++) {
        radar_init(&core);
        memcpy(data, beacon, sizeof(beacon));
        data[26] = (uint8_t)accepted[i];
        assert(radar_ble_observe(&core, address, 1, -60, data, sizeof(data), 1000));
        assert(core.devices[0].range.reference == RadarRangeReferenceBeacon);
        assert(core.devices[0].range.reference_rssi == accepted[i]);
    }
}

static void identity(void) {
    RadarCore core;
    uint8_t indices[RADAR_CAPACITY];
    radar_init(&core);
    strcpy(core.accept_filter, "wanted");
    assert(radar_ble_observe(&core, address, 1, -60, beacon, sizeof(beacon), 100));
    assert(!radar_visible(&core, "", 'B', 100, indices));
    uint8_t name[] = {7, 9, 'w', 'a', 'n', 't', 'e', 'd'};
    assert(radar_ble_observe(&core, address, 1, -60, name, sizeof(name), 200));
    assert(radar_ble_observe(&core, address, 0, -60, name, sizeof(name), 200));
    assert(radar_ble_observe(&core, address, 3, -60, beacon, sizeof(beacon), 300));
    assert(radar_visible(&core, "wanted", 'B', 300, indices) == 2);
    for(unsigned i = 0; i < 2; i++) {
        const RadarDevice* device = &core.devices[indices[i]];
        assert(
            device->range.reference ==
            (device->address_type == 1 ? RadarRangeReferenceBeacon : RadarRangeReferenceNone));
    }
    radar_init(&core);
    assert(radar_ble_observe(&core, address, 1, -60, NULL, 0, 400));
    strcpy(core.accept_filter, "different target");
    assert(radar_ble_observe(&core, address, 1, -60, beacon, sizeof(beacon), 400));
    assert(core.devices[0].range.reference == RadarRangeReferenceNone);
}

static void manual(void) {
    RadarCore core;
    radar_init(&core);
    assert(radar_ble_observe(&core, address, 1, -65, NULL, 0, 100));
    core.devices[0].range.reference = RadarRangeReferenceManual;
    core.devices[0].range.reference_rssi = -66;
    assert(radar_ble_observe(&core, address, 1, -60, beacon, sizeof(beacon), 1000));
    assert(core.devices[0].range.reference == RadarRangeReferenceManual);
    assert(core.devices[0].range.reference_rssi == -66);
    assert(core.devices[0].seen == 1000);
}

int main(int argc, char** argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    assert(argc == 2);
    if(!strcmp(argv[1], "valid"))
        valid();
    else if(!strcmp(argv[1], "unrelated"))
        unrelated();
    else if(!strcmp(argv[1], "malformed"))
        malformed();
    else if(!strcmp(argv[1], "bounds"))
        bounds();
    else if(!strcmp(argv[1], "identity"))
        identity();
    else if(!strcmp(argv[1], "manual"))
        manual();
    else
        return 2;
    puts("Beacon reference case passed");
    return 0;
}
