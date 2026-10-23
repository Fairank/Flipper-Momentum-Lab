#include "radar_core.h"
#include <stdlib.h>
#include <string.h>

void radar_init(RadarCore* core) {
    memset(core, 0, sizeof(*core));
    core->pinned = -1;
}
static int hex(char c) {
    if(c >= '0' && c <= '9') return c - '0';
    if(c >= 'a' && c <= 'f') return c - 'a' + 10;
    if(c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}
static unsigned char lower(unsigned char c) {
    return c >= 'A' && c <= 'Z' ? c + 32 : c;
}
static bool contains(const char* text, const char* filter) {
    if(!*filter) return true;
    for(; *text; text++) {
        size_t i = 0;
        while(filter[i] && text[i] &&
              lower((unsigned char)filter[i]) == lower((unsigned char)text[i]))
            i++;
        if(!filter[i]) return true;
    }
    return false;
}
/* Advertised names and SSIDs are arbitrary bytes, including truncated UTF-8. */
static void display_name(char name[33], const unsigned char* bytes, size_t size) {
    size_t i = 0;
    while(i < size) {
        unsigned char c = bytes[i];
        size_t length = c < 0x80               ? 1 :
                        c >= 0xc2 && c <= 0xdf ? 2 :
                        c >= 0xe0 && c <= 0xef ? 3 :
                        c >= 0xf0 && c <= 0xf4 ? 4 :
                                                 0;
        bool valid = length && i + length <= size;
        for(size_t j = 1; valid && j < length; j++)
            valid = (bytes[i + j] & 0xc0) == 0x80;
        if(valid && length >= 3)
            valid = !(c == 0xe0 && bytes[i + 1] < 0xa0) && !(c == 0xed && bytes[i + 1] >= 0xa0) &&
                    !(c == 0xf0 && bytes[i + 1] < 0x90) && !(c == 0xf4 && bytes[i + 1] >= 0x90);
        if(!valid || c < 32 || c == 127) {
            name[i++] = '?';
        } else {
            memcpy(name + i, bytes + i, length);
            i += length;
        }
    }
    name[size] = 0;
}
static bool frame(RadarCore* core, char* line, uint32_t now) {
    if(!strcmp(line, "NR1,R,ESP32,BW")) {
        core->ready = true;
        core->last_frame = now;
        return true;
    }
    if(!strcmp(line, "NR1,S,STOP")) {
        core->running = false;
        core->last_frame = now;
        return true;
    }
    if(!strcmp(line, "NR1,S,RUN")) {
        core->running = true;
        core->last_frame = now;
        return true;
    }
    char* fields[7];
    size_t count = 1;
    fields[0] = line;
    for(char* p = line; *p; p++)
        if(*p == ',') {
            if(count == 7) return false;
            *p = 0;
            fields[count++] = p + 1;
        }
    if(count != 7 || strcmp(fields[0], "NR1") || strcmp(fields[1], "D") ||
       strlen(fields[2]) != 1 || (fields[2][0] != 'B' && fields[2][0] != 'W') ||
       strlen(fields[3]) != 12)
        return false;
    RadarDevice next = {0};
    next.kind = fields[2][0];
    for(size_t i = 0; i < 12; i++) {
        int n = hex(fields[3][i]);
        if(n < 0) return false;
        next.id[i] = "0123456789ABCDEF"[n];
    }
    char* end;
    long rssi = strtol(fields[4], &end, 10);
    if(!*fields[4] || *end || rssi < -127 || rssi > -1) return false;
    long channel = strtol(fields[5], &end, 10);
    if(!*fields[5] || *end || channel < 0 || channel > 14 || (next.kind == 'B' && channel))
        return false;
    size_t size = strlen(fields[6]);
    if(size > 64 || (size & 1)) return false;
    unsigned char raw_name[32];
    for(size_t i = 0; i < size / 2; i++) {
        int a = hex(fields[6][i * 2]), b = hex(fields[6][i * 2 + 1]);
        if(a < 0 || b < 0) return false;
        raw_name[i] = (unsigned char)(a * 16 + b);
    }
    return radar_observe(
        core, next.kind, next.id, UINT8_MAX, rssi, channel, raw_name, size / 2, now);
}
bool radar_observe(
    RadarCore* core,
    char kind,
    const char* id,
    uint8_t address_type,
    int rssi,
    uint8_t channel,
    const uint8_t* name,
    size_t name_size,
    uint32_t now) {
    if((kind != 'B' && kind != 'W') || !id || strlen(id) != 12 || name_size > 32 ||
       (name_size && !name) || rssi < -127 || rssi > 20 || channel > 14 ||
       (kind == 'B' && channel) || (address_type != UINT8_MAX && address_type > 1))
        return false;
    RadarDevice next = {.kind = kind, .address_type = address_type};
    for(size_t i = 0; i < 12; i++) {
        int value = hex(id[i]);
        if(value < 0) return false;
        next.id[i] = "0123456789ABCDEF"[value];
    }
    display_name(next.name, name, name_size);
    int slot = -1;
    uint32_t oldest = 0;
    for(size_t i = 0; i < RADAR_CAPACITY; i++)
        if(core->devices[i].used && core->devices[i].kind == next.kind &&
           core->devices[i].address_type == next.address_type &&
           !strcmp(core->devices[i].id, next.id)) {
            slot = (int)i;
            break;
        }
    if(!contains(next.name, core->accept_filter) && !contains(next.id, core->accept_filter) &&
       !(slot >= 0 && contains(core->devices[slot].name, core->accept_filter)))
        return true;
    if(slot < 0) {
        for(size_t i = 0; i < RADAR_CAPACITY; i++)
            if(!core->devices[i].used) {
                slot = (int)i;
                break;
            }
        if(slot < 0)
            for(size_t i = 0; i < RADAR_CAPACITY; i++) {
                uint32_t age = now - core->devices[i].seen;
                if((int)i != core->pinned && age > 30000 && age > oldest) {
                    oldest = age;
                    slot = (int)i;
                }
            }
        /* In a dense environment retain strong nearby observations instead of
         * permanently filling with the first 32 devices. Never replace a pin.
         */
        if(slot < 0) {
            int weakest = rssi * 4 - 12;
            for(size_t i = 0; i < RADAR_CAPACITY; i++) {
                if((int)i != core->pinned && core->devices[i].average_q4 < weakest) {
                    weakest = core->devices[i].average_q4;
                    slot = (int)i;
                }
            }
        }
        if(slot < 0) {
            core->full++;
            return true;
        }
        core->devices[slot] = next;
        core->devices[slot].average_q4 = (int16_t)(rssi * 4);
        core->devices[slot].anchor_q4 = (int16_t)(rssi * 4);
        core->devices[slot].anchor_time = now;
    }
    RadarDevice* d = &core->devices[slot];
    if((uint32_t)(now - d->seen) > RADAR_STALE_MS) {
        d->average_q4 = (int16_t)(rssi * 4);
        d->anchor_q4 = d->average_q4;
        d->anchor_time = now;
        d->trend = 0;
    }
    d->average_q4 = (int16_t)((d->average_q4 * 3 + rssi * 4) / 4);
    if((uint32_t)(now - d->anchor_time) >= 2500) {
        int change = d->average_q4 - d->anchor_q4;
        d->trend = change >= 12 ? 1 : change <= -12 ? -1 : 0;
        d->anchor_q4 = d->average_q4;
        d->anchor_time = now;
    }
    if(next.name[0]) memcpy(d->name, next.name, sizeof(d->name));
    d->rssi = (int8_t)rssi;
    d->channel = (uint8_t)channel;
    d->seen = now;
    d->used = true;
    core->last_frame = now;
    return true;
}
bool radar_feed(RadarCore* core, uint8_t byte, uint32_t now) {
    if(byte == '\r') return false;
    if(byte == '\n') {
        bool valid = false;
        if(!core->overflow && core->line_size) {
            core->line[core->line_size] = 0;
            valid = frame(core, core->line, now);
        }
        if(!valid && (core->overflow || core->line_size)) core->malformed++;
        core->line_size = 0;
        core->overflow = false;
        return valid;
    }
    if(byte < 32 || byte > 126) {
        core->overflow = true;
        return false;
    }
    if(core->line_size >= RADAR_LINE_SIZE - 1)
        core->overflow = true;
    else if(!core->overflow)
        core->line[core->line_size++] = (char)byte;
    return false;
}
bool radar_stale(const RadarDevice* d, uint32_t now) {
    return !d->used || (uint32_t)(now - d->seen) > RADAR_STALE_MS;
}
unsigned radar_radius(const RadarDevice* d) {
    int strength = d->average_q4 / 4;
    if(strength < -95) strength = -95;
    if(strength > -35) strength = -35;
    return (unsigned)(28 - (strength + 95) * 22 / 60);
}
size_t radar_visible(
    const RadarCore* core,
    const char* filter,
    char kind,
    uint32_t now,
    uint8_t out[RADAR_CAPACITY]) {
    size_t n = 0;
    for(size_t i = 0; i < RADAR_CAPACITY; i++) {
        const RadarDevice* d = &core->devices[i];
        if(!d->used || (uint32_t)(now - d->seen) > 60000 || (kind && kind != d->kind) ||
           (!contains(d->name, filter) && !contains(d->id, filter)))
            continue;
        size_t j = n;
        while(j && core->devices[out[j - 1]].average_q4 < d->average_q4) {
            out[j] = out[j - 1];
            j--;
        }
        out[j] = (uint8_t)i;
        n++;
    }
    return n;
}
