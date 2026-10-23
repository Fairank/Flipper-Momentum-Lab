#pragma once
#include <stdbool.h>
#include <stdint.h>

// 1: verified key; 0: no match; -1: cancelled; -2: memory; -3: resource limit.
// words: CUID, NT0, encrypted NR0, encrypted AR0, NT1, encrypted NR1, encrypted AR1.
// No hardware access. Scratch memory is bounded and released before returning.
int fl_classic_recover(
    const uint32_t words[7],
    uint64_t* key,
    bool (*cancelled)(void*),
    void* context);
