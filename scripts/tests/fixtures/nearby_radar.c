#undef NDEBUG
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "radar_core.h"
static void feed(RadarCore* c, const char* text, uint32_t now) {
    while(*text)
        radar_feed(c, (uint8_t)*text++, now);
}
int main(void) {
    assert(setvbuf(stdout, NULL, _IONBF, 0) == 0);
    RadarCore c;
    uint8_t indices[RADAR_CAPACITY];
    radar_init(&c);
    assert(!c.ready && c.pinned == -1 && !radar_visible(&c, "", 0, 0, indices));
    feed(&c, "NR1,R,ESP32,BW\n", 0);
    assert(c.ready);
    feed(&c, "NR1,S,RUN\n", 0);
    assert(c.running);
    feed(&c, "NR1,S,STOP\n", 0);
    assert(!c.running);
    feed(&c, "NR1,D,B,AABBCCDDEEFF,-80,0,50686F6E65\n", 100);
    assert(radar_visible(&c, "phone", 'B', 100, indices) == 1);
    int slot = indices[0];
    assert(!strcmp(c.devices[slot].name, "Phone") && c.devices[slot].rssi == -80);
    feed(&c, "NR1,D,B,aabbccddeeff,-40,0,\n", 3000);
    assert(!strcmp(c.devices[slot].name, "Phone") && c.devices[slot].trend == 1);
    assert(radar_visible(&c, "AABB", 0, 3000, indices) == 1);
    assert(!radar_stale(&c.devices[slot], 3000) && radar_stale(&c.devices[slot], 16001));
    feed(&c, "NR1,D,W,AABBCCDDEEFF,-55,6,E6B58BE8AF95\n", 3100);
    assert(radar_visible(&c, "", 0, 3100, indices) == 2);
    assert(c.devices[indices[0]].kind == 'W'); /* Strongest observation appears first. */
    assert(
        radar_visible(&c, "", 0, 3100, indices) == 2 &&
        radar_visible(&c, "", 'W', 3100, indices) == 1);
    assert(!strcmp(c.devices[indices[0]].name, "\xe6\xb5\x8b\xe8\xaf\x95"));
    feed(&c, "NR1,D,W,AABBCCDDEEFF,-55,6,00C080EDA080F4908080E6B5\n", 3150);
    assert(!strcmp(c.devices[indices[0]].name, "????????????"));
    uint32_t bad = c.malformed;
    feed(
        &c,
        "NR1,D,B,INVALID,-50,0,00\nNR1,D,B,AABBCCDDEEFF,0,0,00\nNR1,D,B,AABBCCDDEEFF,-50,1,00\nNR1,D,B,AABBCCDDEEFF,-50,0,GG\n",
        3200);
    assert(c.malformed == bad + 4);
    for(unsigned i = 0; i < 1000; i++)
        radar_feed(&c, 'X', 3200);
    feed(&c, "NR1,R,ESP32,BW\n", 3200);
    assert(c.malformed == bad + 5);
    feed(&c, "NR1,R,ESP32,BW\n", 3200);
    assert(c.ready);
    c.pinned = (int8_t)slot;
    for(unsigned i = 0; i < 100; i++) {
        char text[100];
        snprintf(text, sizeof(text), "NR1,D,B,%012X,-65,0,\n", i);
        feed(&c, text, 3500);
    }
    assert(c.full && !strcmp(c.devices[slot].id, "AABBCCDDEEFF"));
    feed(&c, "NR1,D,B,112233445566,-65,0,\n", 40000);
    assert(!strcmp(c.devices[slot].id, "AABBCCDDEEFF"));
    assert(!radar_visible(&c, "Phone", 0, 65000, indices));
    RadarDevice d = {.used = true, .seen = UINT32_MAX - 100, .average_q4 = -400};
    assert(!radar_stale(&d, 20));
    assert(radar_radius(&d) == 28);
    d.average_q4 = -100;
    assert(radar_radius(&d) == 6);
    puts("Nearby radar core passed");
    return 0;
}
