#pragma once

#include <stdint.h>
#include <string.h>

// v3 is explicit bytes, independent of compiler padding and live pointers.
#define SUDOKU_SAVE_SIZE        89
#define SUDOKU_LEGACY_SAVE_SIZE 102

static bool sudoku_save_decode(SudokuState* state, const uint8_t* data, size_t size) {
    uint8_t fields[SUDOKU_SAVE_SIZE];
    if(size == SUDOKU_SAVE_SIZE && data[0] == 3 && data[1] == 0) {
        memcpy(fields, data, sizeof(fields));
    } else if(size == SUDOKU_LEGACY_SAVE_SIZE && data[0] == 2 && data[1] == 0) {
        // Original ARM v2: skip the mutex pointer and compiler padding entirely.
        uint32_t status = (uint32_t)data[94] | (uint32_t)data[95] << 8 | (uint32_t)data[96] << 16 |
                          (uint32_t)data[97] << 24;
        if(status > GameStateRestart) return false;
        fields[0] = 3;
        fields[1] = 0;
        memcpy(fields + 2, data + 6, 81);
        fields[83] = data[87];
        fields[84] = data[88];
        fields[85] = status;
        fields[86] = data[98];
        fields[87] = data[99];
        fields[88] = data[100];
    } else {
        return false;
    }
    if(fields[83] >= BOARD_SIZE || fields[84] >= BOARD_SIZE || fields[85] > GameStateRestart ||
       fields[86] >= MENU_ITEMS_COUNT || fields[87] > 2 || fields[88] > 1)
        return false;
    for(size_t i = 2; i < 83; i++) {
        if((fields[i] & VALUE_MASK) > 9 || (fields[i] & 0x70)) return false;
    }
    // Apply only after the whole record is valid. The caller owns the mutex.
    memcpy(state->board, fields + 2, sizeof(state->board));
    state->cursorX = fields[83];
    state->cursorY = fields[84];
    state->state = fields[85];
    state->menuCursor = fields[86];
    state->lastGameMode = fields[87];
    state->blockInputUntilRelease = fields[88];
    state->horizontalFlags = 0;
    state->vertivalFlags = 0;
    return true;
}

static void sudoku_save_encode(const SudokuState* state, uint8_t data[SUDOKU_SAVE_SIZE]) {
    data[0] = 3;
    data[1] = 0;
    memcpy(data + 2, state->board, sizeof(state->board));
    data[83] = state->cursorX;
    data[84] = state->cursorY;
    data[85] = state->state;
    data[86] = state->menuCursor;
    data[87] = state->lastGameMode;
    data[88] = state->blockInputUntilRelease;
}
