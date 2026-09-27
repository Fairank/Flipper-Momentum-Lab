// SPDX-License-Identifier: GPL-3.0-or-later
// Crypto1 recovery algorithm by bla <blapost@gmail.com> and Proxmark3 contributors.
// Based on common/crapto1 and tools/mfc/card_reader/mfkey32v2 in
// https://github.com/RfidResearchGroup/proxmark3
// Adapted with bounds/cancellation, no global tables, RF access or startup constructor.
#include "ClassicRecovery.h"
#include <stdlib.h>

#define ODD_POLY       0x29ce5cu
#define EVEN_POLY      0x870804u
#define TABLE_CAPACITY (1u << 21)
#define WORK_LIMIT     200000000u

typedef struct {
    uint32_t odd, even;
} Cipher;
typedef struct {
    uint32_t *odd, *even;
    uint8_t* filter;
    const uint32_t* words;
    uint64_t key;
    uint32_t work;
    int status;
    bool (*cancelled)(void*);
    void* context;
} Recovery;

static uint32_t parity(uint32_t x) {
    x ^= x >> 16;
    x ^= x >> 8;
    x ^= x >> 4;
    return (0x6996u >> (x & 15)) & 1;
}
static uint32_t filter(uint32_t x) {
    uint32_t f = (0xf22c0u >> (x & 15)) & 16;
    f |= (0x6c9c0u >> ((x >> 4) & 15)) & 8;
    f |= (0x3c8b0u >> ((x >> 8) & 15)) & 4;
    f |= (0x1e458u >> ((x >> 12) & 15)) & 2;
    f |= (0x0d938u >> ((x >> 16) & 15)) & 1;
    return (0xec57e80au >> f) & 1;
}
static bool checkpoint(Recovery* r, uint32_t work) {
    if(r->status) return false;
    if(work > WORK_LIMIT - r->work) {
        r->status = -3;
        return false;
    }
    r->work += work;
    if(r->cancelled && r->cancelled(r->context)) {
        r->status = -1;
        return false;
    }
    return true;
}
static uint32_t word(Cipher* s, uint32_t input, bool encrypted) {
    uint32_t out = 0;
    for(unsigned i = 0; i < 32; ++i) {
        unsigned p = i ^ 24;
        uint32_t bit = filter(s->odd);
        uint32_t feedback = (encrypted ? bit : 0) ^ ((input >> p) & 1) ^ (s->odd & ODD_POLY) ^
                            (s->even & EVEN_POLY);
        uint32_t next = (s->even << 1) | parity(feedback);
        s->even = s->odd;
        s->odd = next;
        out |= bit << p;
    }
    return out;
}
static void rollback(Cipher* s, uint32_t input, bool encrypted) {
    for(int i = 31; i >= 0; --i) {
        uint32_t old = s->odd & 0xffffffu;
        s->odd = s->even;
        s->even = old;
        uint32_t feedback = s->even & 1;
        s->even >>= 1;
        feedback ^= s->even & EVEN_POLY;
        feedback ^= s->odd & ODD_POLY;
        feedback ^= (input >> (i ^ 24)) & 1;
        if(encrypted) feedback ^= filter(s->odd);
        s->even |= parity(feedback) << 23;
    }
}
static uint32_t swap32(uint32_t x) {
    return x >> 24 | ((x >> 8) & 0xff00u) | ((x << 8) & 0xff0000u) | x << 24;
}
static uint32_t successor(uint32_t x) {
    x = swap32(x);
    for(unsigned i = 0; i < 64; ++i)
        x = x >> 1 | ((x >> 16) ^ (x >> 18) ^ (x >> 19) ^ (x >> 21)) << 31;
    return swap32(x);
}
static uint64_t key_from_state(Cipher s) {
    uint64_t key = 0;
    for(int i = 23; i >= 0; --i) {
        key = key << 1 | ((s.odd >> (i ^ 3)) & 1);
        key = key << 1 | ((s.even >> (i ^ 3)) & 1);
    }
    return key;
}
static bool verify(Cipher initial, const uint32_t* words, unsigned nonce) {
    word(&initial, words[0] ^ words[nonce], false);
    word(&initial, words[nonce + 1], true);
    return (word(&initial, 0, false) ^ successor(words[nonce])) == words[nonce + 2];
}
static void check_state(Recovery* r, Cipher state) {
    rollback(&state, 0, false);
    rollback(&state, r->words[2], true);
    rollback(&state, r->words[0] ^ r->words[1], false);
    if(verify(state, r->words, 1) && verify(state, r->words, 4)) {
        r->key = key_from_state(state);
        r->status = 1;
    }
}
static uint32_t contribution(uint32_t value, uint32_t mask1, uint32_t mask2) {
    uint32_t p = value >> 25;
    p = p << 1 | parity(value & mask1);
    p = p << 1 | parity(value & mask2);
    return p << 24 | (value & 0xffffffu);
}

// Exclusive ends avoid pointer-before-allocation arithmetic for empty tables.
static bool extend(
    Recovery* r,
    uint32_t* table,
    size_t begin,
    size_t* end,
    unsigned bit,
    bool track,
    uint32_t mask1,
    uint32_t mask2) {
    size_t i = begin;
    while(i < *end) {
        if((i & 4095) == 0 && !checkpoint(r, 4096)) return false;
        uint32_t value = table[i] << 1;
        unsigned zero = r->filter[value & 0xfffffu];
        unsigned one = r->filter[(value | 1) & 0xfffffu];
        if(zero != one) {
            value |= zero ^ bit;
            table[i++] = track ? contribution(value, mask1, mask2) : value;
        } else if(zero == bit) {
            if(*end >= TABLE_CAPACITY) {
                r->status = -3;
                return false;
            }
            if(i + 1 < *end) table[*end] = table[i + 1];
            ++*end;
            table[i++] = track ? contribution(value, mask1, mask2) : value;
            table[i++] = track ? contribution(value | 1, mask1, mask2) : value | 1;
        } else {
            table[i] = table[--*end];
        }
    }
    return checkpoint(r, 1);
}
static int compare_u32(const void* a, const void* b) {
    uint32_t x = *(const uint32_t*)a, y = *(const uint32_t*)b;
    return (x > y) - (x < y);
}
static size_t group_begin(const uint32_t* values, size_t begin, size_t end) {
    uint32_t prefix = values[end - 1] >> 24;
    size_t lo = begin, hi = end;
    while(lo < hi) {
        size_t mid = lo + (hi - lo) / 2;
        if((values[mid] >> 24) < prefix)
            lo = mid + 1;
        else
            hi = mid;
    }
    return lo;
}
static void recover(
    Recovery* r,
    size_t ob,
    size_t oe,
    uint32_t oks,
    size_t eb,
    size_t ee,
    uint32_t eks,
    int remaining) {
    if(!checkpoint(r, 1) || ob == oe || eb == ee) return;
    if(remaining == -1) {
        for(size_t e = eb; e < ee && !r->status; ++e) {
            uint32_t even = (r->even[e] << 1) ^ parity(r->even[e] & EVEN_POLY);
            for(size_t o = ob; o < oe && !r->status; ++o) {
                if(!checkpoint(r, 1)) return;
                Cipher state = {even ^ parity(r->odd[o] & ODD_POLY), r->odd[o]};
                check_state(r, state);
            }
        }
        return;
    }
    for(int i = 0; i < 4 && remaining--; ++i) {
        oks >>= 1;
        eks >>= 1;
        if(!extend(r, r->odd, ob, &oe, oks & 1, true, (EVEN_POLY << 1) | 1, ODD_POLY << 1) ||
           ob == oe)
            return;
        if(!extend(r, r->even, eb, &ee, eks & 1, true, ODD_POLY, (EVEN_POLY << 1) | 1) || eb == ee)
            return;
    }
    qsort(r->odd + ob, oe - ob, sizeof(uint32_t), compare_u32);
    qsort(r->even + eb, ee - eb, sizeof(uint32_t), compare_u32);
    // Higher groups first: expansion cannot overwrite lower groups still awaiting processing.
    while(oe > ob && ee > eb && !r->status) {
        uint32_t op = r->odd[oe - 1] >> 24, ep = r->even[ee - 1] >> 24;
        if(op > ep)
            oe = group_begin(r->odd, ob, oe);
        else if(ep > op)
            ee = group_begin(r->even, eb, ee);
        else {
            size_t og = group_begin(r->odd, ob, oe), eg = group_begin(r->even, eb, ee);
            recover(r, og, oe, oks, eg, ee, eks, remaining);
            oe = og;
            ee = eg;
        }
    }
}

int fl_classic_recover(
    const uint32_t words[7],
    uint64_t* key,
    bool (*cancelled)(void*),
    void* context) {
    if(!words || !key || (words[1] == words[4] && words[2] == words[5])) return -3;
    *key = 0;
    Recovery r = {.words = words, .cancelled = cancelled, .context = context};
    if(!checkpoint(&r, 0)) return r.status;
    r.odd = calloc(TABLE_CAPACITY, sizeof(uint32_t));
    r.even = calloc(TABLE_CAPACITY, sizeof(uint32_t));
    r.filter = malloc(1u << 20);
    if(!r.odd || !r.even || !r.filter) {
        r.status = -2;
        goto done;
    }
    uint32_t stream = words[3] ^ successor(words[1]);
    uint32_t oks = 0, eks = 0;
    for(int i = 31; i >= 0; i -= 2)
        oks = oks << 1 | ((stream >> (i ^ 24)) & 1);
    for(int i = 30; i >= 0; i -= 2)
        eks = eks << 1 | ((stream >> (i ^ 24)) & 1);
    size_t oe = 0, ee = 0;
    for(uint32_t i = 0; i < (1u << 20); ++i)
        r.filter[i] = filter(i);
    for(int i = 1 << 20; i >= 0; --i) {
        if((i & 4095) == 0 && !checkpoint(&r, 4096)) goto done;
        unsigned bit = r.filter[i & 0xfffff];
        if(bit == (oks & 1)) r.odd[oe++] = i;
        if(bit == (eks & 1)) r.even[ee++] = i;
    }
    for(int i = 0; i < 4; ++i) {
        oks >>= 1;
        eks >>= 1;
        if(!extend(&r, r.odd, 0, &oe, oks & 1, false, 0, 0)) goto done;
        if(!extend(&r, r.even, 0, &ee, eks & 1, false, 0, 0)) goto done;
    }
    recover(&r, 0, oe, oks, 0, ee, eks, 11);
done:
    if(r.status == 1) *key = r.key;
    free(r.filter);
    free(r.even);
    free(r.odd);
    return r.status;
}
