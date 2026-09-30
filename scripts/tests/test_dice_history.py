"""Compile the dice app's real history buffer, paging and drawing code on the host."""

from pathlib import Path
import re
import unittest

from test_unleashed_integration import native_test

ROOT = Path(__file__).resolve().parents[2]
DICE = ROOT / "applications/union/dice"

# Host substitutes for furi/gui: strings are real buffers, drawn text is recorded.
# canvas_draw_icon is deliberately absent, so a bitmap in draw_history fails to compile.
STUBS = r"""
#include <assert.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef int Canvas;
typedef int FuriMutex;
typedef enum { InputKeyUp, InputKeyDown, InputKeyRight, InputKeyLeft, InputKeyOk, InputKeyBack } InputKey;
typedef enum { InputTypePress, InputTypeRelease, InputTypeShort, InputTypeLong, InputTypeRepeat } InputType;
typedef struct { InputKey key; InputType type; } InputEvent;
enum { FontPrimary, FontSecondary };
enum { AlignLeft, AlignRight, AlignCenter, AlignTop, AlignBottom };
typedef struct { char text[32]; } FuriString;
static FuriString* furi_string_alloc(void) { FuriString* s = calloc(1, sizeof *s); assert(s); return s; }
static void furi_string_free(FuriString* s) { free(s); }
static const char* furi_string_get_cstr(const FuriString* s) { return s->text; }
static void furi_string_set(FuriString* s, const char* text) { assert(strlen(text) < sizeof s->text); strcpy(s->text, text); }
static void furi_string_printf(FuriString* s, const char* format, ...) {
    va_list args; va_start(args, format);
    int length = vsnprintf(s->text, sizeof s->text, format, args);
    va_end(args); assert(length >= 0 && (size_t)length < sizeof s->text);
}
enum { CJK_LINE_HEIGHT = 12, SCREEN_HEIGHT = 64 };
typedef struct { int x, y, h; char text[16]; } Drawn;
static Drawn drawn[24];
static size_t drawn_count;
static void canvas_set_font(Canvas* canvas, int font) { (void)canvas; (void)font; }
static void canvas_draw_str_aligned(Canvas* canvas, int x, int y, int h, int v, const char* text) {
    (void)canvas;
    /* Bottom-aligned CJK text needs a full 12px line above its baseline to stay on screen. */
    assert(v == AlignBottom && x >= 0 && x <= 128 && y >= CJK_LINE_HEIGHT && y <= SCREEN_HEIGHT);
    assert(drawn_count < sizeof drawn / sizeof drawn[0] && strlen(text) < sizeof drawn[0].text);
    Drawn* d = &drawn[drawn_count++];
    d->x = x; d->y = y; d->h = h; strcpy(d->text, text);
}
"""

HELPERS = r"""
static void fresh_state(State* state) { memset(state, 0, sizeof *state); init(state); }
static void render(const State* state) { Canvas canvas = 0; drawn_count = 0; draw_history(state, &canvas); }
/* "7." -> 7; entries, "--" and the footer -> 0. */
static int label_number(const Drawn* d) {
    size_t n = strlen(d->text);
    if(d->y == SCREEN_HEIGHT || n < 2 || d->text[n - 1] != '.') return 0;
    return atoi(d->text);
}
"""


def dice_program(main):
    constants = (DICE / "constants.h").read_text(encoding="utf-8")
    app = (DICE / "dice_app.c").read_text(encoding="utf-8")
    return "\n".join(
        [
            STUBS,
            *re.findall(r"^#define .*$", constants, re.M),
            # Dice/History/State, init, add_to_history and the paging helpers; the icon
            # tables above the first typedef stay out, so no icons need stubbing.
            constants[
                constants.index("typedef struct {") : constants.index(
                    "\nvoid coin_set_start("
                )
            ],
            constants[constants.index("\nbool isResultVisible(") :],
            app[
                app.index("static void draw_history(") : app.index(
                    "\nstatic void draw_dice("
                )
            ],
            HELPERS,
            main,
        ]
    )


class DiceHistoryTests(unittest.TestCase):
    def test_paging_stays_inside_the_ten_slots(self):
        native_test(
            dice_program(
                r"""
_Static_assert(HISTORY_SIZE == 10 && HISTORY_COL == 4 && HISTORY_PAGE_SIZE == 8 && HISTORY_PAGES == 2, "10 rolls, 8 then 2");
int main(void) {
    State state;
    fresh_state(&state);
    assert(state.app_state == SelectState && state.history_page == 0);
    /* Up/Down only page on the history screen; other keys never page. */
    for(int s = SelectState; s < HistoryState; s++) {
        state.app_state = (AppState)s;
        assert(!history_navigate(&state, InputKeyUp) && !history_navigate(&state, InputKeyDown));
        assert(state.history_page == 0);
    }
    state.app_state = HistoryState;
    InputKey others[] = {InputKeyLeft, InputKeyRight, InputKeyOk, InputKeyBack};
    for(size_t i = 0; i < sizeof others / sizeof others[0]; i++) {
        assert(!history_navigate(&state, others[i]) && state.history_page == 0);
    }
    /* While paging, the event loop's dice-count and dice-type handlers stay closed. */
    for(uint8_t d = 0; d < DICE_TYPES; d++) assert(isDiceSettingsDisabled(HistoryState, d));
    assert(!isDiceButtonsVisible(HistoryState));
    /* Repeated Up on the first page and Down on the last page clamp. */
    for(int i = 0; i < 5; i++) assert(history_navigate(&state, InputKeyUp) && state.history_page == 0);
    assert(history_navigate(&state, InputKeyDown) && state.history_page == 1);
    for(int i = 0; i < 5; i++) assert(history_navigate(&state, InputKeyDown) && state.history_page == 1);
    assert(history_navigate(&state, InputKeyUp) && state.history_page == 0);
    /* The page/column/row map visits each of the ten slots once: eight, then two. */
    int seen[HISTORY_SIZE] = {0}, per_page[HISTORY_PAGES] = {0};
    for(uint8_t page = 0; page < HISTORY_PAGES; page++) {
        for(uint8_t col = 0; col < 2; col++) {
            for(uint8_t row = 0; row < HISTORY_COL; row++) {
                uint8_t index = history_visible_index(page, col, row);
                if(index < HISTORY_SIZE) { seen[index]++; per_page[page]++; }
            }
        }
    }
    for(int i = 0; i < HISTORY_SIZE; i++) assert(seen[i] == 1);
    assert(per_page[0] == 8 && per_page[1] == 2);
    /* Whatever value the page holds, even a corrupt one, no slot outside 1..10 is drawn. */
    for(unsigned page = 0; page < 256; page++) {
        state.history_page = (uint8_t)page;
        render(&state);
        for(size_t i = 0; i < drawn_count; i++) assert(label_number(&drawn[i]) <= HISTORY_SIZE);
    }
    return 0;
}
"""
            )
        )

    def test_history_buffer_fills_in_order_then_evicts_the_oldest(self):
        native_test(
            dice_program(
                r"""
static const struct { uint8_t index, count, result; } rolls[] = {
    {0, 1, 1}, {0, 1, 2}, {1, 1, 3}, {2, 2, 7}, {3, 3, 20},
    {4, 4, 31}, {5, 5, 42}, {6, 10, 200}, {7, 1, 100}, {2, 10, 60},
    {1, 1, 4}, {6, 2, 33},
};
static void expect_slot(const History* slot, int roll) {
    assert(slot->index == rolls[roll].index && slot->count == rolls[roll].count && slot->result == rolls[roll].result);
}
int main(void) {
    State state;
    fresh_state(&state);
    for(int i = 0; i < HISTORY_SIZE; i++) assert(state.history[i].index == -1);
    /* The first ten rolls fill the slots in order and leave later slots empty. */
    for(int n = 0; n < HISTORY_SIZE; n++) {
        add_to_history(&state, rolls[n].index, rolls[n].count, rolls[n].result);
        for(int i = 0; i <= n; i++) expect_slot(&state.history[i], i);
        for(int i = n + 1; i < HISTORY_SIZE; i++) assert(state.history[i].index == -1);
    }
    /* Each further roll evicts the oldest; the newest always sits in the last slot. */
    for(int n = HISTORY_SIZE; n < HISTORY_SIZE + 2; n++) {
        add_to_history(&state, rolls[n].index, rolls[n].count, rolls[n].result);
        for(int i = 0; i < HISTORY_SIZE; i++) expect_slot(&state.history[i], n - HISTORY_SIZE + 1 + i);
    }
    /* After two evictions the second page shows the two newest rolls as 9. and 10. */
    state.app_state = HistoryState;
    assert(history_navigate(&state, InputKeyDown));
    render(&state);
    assert(label_number(&drawn[0]) == 9 && strcmp(drawn[1].text, "1d4:4") == 0);
    assert(label_number(&drawn[2]) == 10 && strcmp(drawn[3].text, "2d20:33") == 0);
    return 0;
}
"""
            )
        )

    def test_two_pages_draw_every_entry_once_with_chinese_coin_faces(self):
        native_test(
            dice_program(
                r"""
/* Row-major draw order: label then entry, left column then right, 12px per row. */
static const Drawn first_page[] = {
    {2, 12, AlignLeft, "1."}, {18, 12, AlignLeft, "正面"}, {66, 12, AlignLeft, "5."}, {82, 12, AlignLeft, "3d8:20"},
    {2, 24, AlignLeft, "2."}, {18, 24, AlignLeft, "反面"}, {66, 24, AlignLeft, "6."}, {82, 24, AlignLeft, "4d10:31"},
    {2, 36, AlignLeft, "3."}, {18, 36, AlignLeft, "1d4:3"}, {66, 36, AlignLeft, "7."}, {82, 36, AlignLeft, "5d12:42"},
    {2, 48, AlignLeft, "4."}, {18, 48, AlignLeft, "2d6:7"}, {66, 48, AlignLeft, "8."}, {82, 48, AlignLeft, "10d20:200"},
    {0, 64, AlignLeft, "返回"}, {64, 64, AlignCenter, "1/2"}, {128, 64, AlignRight, "上下翻页"},
};
static const Drawn second_page[] = {
    {2, 12, AlignLeft, "9."}, {18, 12, AlignLeft, "1d100:100"},
    {2, 24, AlignLeft, "10."}, {18, 24, AlignLeft, "10d6:60"},
    {0, 64, AlignLeft, "返回"}, {64, 64, AlignCenter, "2/2"}, {128, 64, AlignRight, "上下翻页"},
};
static void expect(const Drawn* expected, size_t count) {
    assert(drawn_count == count);
    for(size_t i = 0; i < count; i++) {
        assert(drawn[i].x == expected[i].x && drawn[i].y == expected[i].y && drawn[i].h == expected[i].h);
        assert(strcmp(drawn[i].text, expected[i].text) == 0);
    }
}
static const char* text_at(int x, int y) {
    for(size_t i = 0; i < drawn_count; i++) if(drawn[i].x == x && drawn[i].y == y) return drawn[i].text;
    return "";
}
int main(void) {
    State state;
    fresh_state(&state);
    /* Coin heads, coin tails, then dice sums; roll order is slot order. */
    add_to_history(&state, 0, 1, 1);
    add_to_history(&state, 0, 1, 2);
    add_to_history(&state, 1, 1, 3);
    add_to_history(&state, 2, 2, 7);
    add_to_history(&state, 3, 3, 20);
    add_to_history(&state, 4, 4, 31);
    add_to_history(&state, 5, 5, 42);
    add_to_history(&state, 6, 10, 200);
    add_to_history(&state, 7, 1, 100);
    add_to_history(&state, 2, 10, 60);
    state.app_state = HistoryState;
    render(&state);
    expect(first_page, sizeof first_page / sizeof first_page[0]);
    assert(history_navigate(&state, InputKeyDown));
    render(&state);
    expect(second_page, sizeof second_page / sizeof second_page[0]);
    /* Across both pages each slot label appears exactly once, four 12px rows fill a column,
       and the footer's CJK line starts no higher than the last row's baseline. */
    int seen[HISTORY_SIZE + 1] = {0}, last_row = 0;
    for(int pass = 0; pass < 2; pass++) {
        render(&state);
        for(size_t i = 0; i < drawn_count; i++) {
            int n = label_number(&drawn[i]);
            assert(n >= 0 && n <= HISTORY_SIZE);
            seen[n]++;
            if(drawn[i].y != SCREEN_HEIGHT && drawn[i].y > last_row) last_row = drawn[i].y;
        }
        assert(history_navigate(&state, InputKeyUp));
    }
    for(int i = 1; i <= HISTORY_SIZE; i++) assert(seen[i] == 1);
    assert(last_row == 4 * CJK_LINE_HEIGHT && last_row + CJK_LINE_HEIGHT <= SCREEN_HEIGHT);
    /* Empty and corrupt slots keep their label and show "--"; page one is showing again. */
    state.history[1].index = -1;
    state.history[2].index = DICE_TYPES;
    state.history[3].index = INT8_MAX;
    render(&state);
    assert(strcmp(text_at(18, 12), "正面") == 0 && strcmp(text_at(2, 24), "2.") == 0);
    assert(strcmp(text_at(18, 24), "--") == 0 && strcmp(text_at(18, 36), "--") == 0);
    assert(strcmp(text_at(18, 48), "--") == 0);
    return 0;
}
"""
            )
        )
