"""Exercise the imported Sudoku's actual portable and legacy save decoder."""

from pathlib import Path
import unittest

from test_unleashed_integration import native_test

ROOT = Path(__file__).resolve().parents[2]


def production():
    source = (ROOT / "applications/union/sudoku/sudoku.c").read_text(encoding="utf-8")
    definitions = source[
        source.index("#define BOARD_SIZE ") : source.index("const char* MENU_ITEMS")
    ]
    header = (ROOT / "applications/union/sudoku/sudoku_save.h").read_text(
        encoding="utf-8"
    )
    return (
        """
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
typedef void FuriMutex;
#undef static_assert
#define static_assert(x) _Static_assert(x, #x)
"""
        + definitions
        + header.replace("#pragma once", "")
    )


class SudokuSaveTests(unittest.TestCase):
    def test_portable_record_roundtrip_and_pointer_ownership(self):
        native_test(
            production()
            + r"""
int main(void) {
    int owner=0;
    SudokuState in={.mutex=&owner,.cursorX=8,.cursorY=4,.menuCursor=4,
        .lastGameMode=2,.state=GameStatePaused,.blockInputUntilRelease=true,
        .horizontalFlags=0x1ff,.vertivalFlags=0x1ff};
    for(int x=0;x<9;x++)for(int y=0;y<9;y++)
        in.board[x][y]=(uint8_t)((x+y)%10)|((x+y)%2?USER_INPUT_FLAG:0);
    uint8_t record[SUDOKU_SAVE_SIZE]; sudoku_save_encode(&in,record);
    assert(sizeof(record)==89 && record[0]==3 && record[1]==0);
    assert(record[83]==8 && record[84]==4 && record[85]==1);
    assert(record[86]==4 && record[87]==2 && record[88]==1);
    assert(memcmp(record+2,in.board,81)==0);
    SudokuState out={.mutex=&owner};
    assert(sudoku_save_decode(&out,record,sizeof(record)));
    assert(out.mutex==&owner && out.cursorX==8 && out.cursorY==4);
    assert(out.state==GameStatePaused && out.menuCursor==4 && out.lastGameMode==2);
    assert(out.blockInputUntilRelease && !out.horizontalFlags && !out.vertivalFlags);
    assert(memcmp(out.board,in.board,81)==0);
    uint8_t again[SUDOKU_SAVE_SIZE]; sudoku_save_encode(&out,again);
    assert(memcmp(record,again,sizeof(record))==0);
    return 0;
}
"""
        )

    def test_arm_v2_migration_ignores_saved_mutex_and_padding(self):
        native_test(
            production()
            + r"""
int main(void) {
    int owner=0;
    // Independent original ARM layout: v2 header + 100-byte raw state.
    uint8_t old[102]; memset(old,0xff,sizeof(old)); old[0]=2;old[1]=0;
    for(int i=0;i<81;i++)old[6+i]=(uint8_t)(i%10);
    old[87]=8;old[88]=7;
    old[94]=3;old[95]=old[96]=old[97]=0;
    old[98]=4;old[99]=2;old[100]=0;
    SudokuState state={.mutex=&owner};
    assert(sudoku_save_decode(&state,old,sizeof(old)));
    assert(state.mutex==&owner && state.state==GameStateRestart);
    assert(state.cursorX==8 && state.cursorY==7 && state.lastGameMode==2);
    uint8_t upgraded[89]; sudoku_save_encode(&state,upgraded);
    assert(upgraded[0]==3 && upgraded[1]==0);
    assert(memcmp(upgraded+2,old+6,81)==0);
    assert(sudoku_save_decode(&state,upgraded,sizeof(upgraded)));
    old[95]=1; assert(!sudoku_save_decode(&state,old,sizeof(old)));
    return 0;
}
"""
        )

    def test_malformed_records_leave_live_state_unchanged(self):
        native_test(
            production()
            + r"""
static void reject(const uint8_t* bytes,size_t count) {
    int owner=0;
    SudokuState state={.mutex=&owner,.cursorX=4,.cursorY=3,.state=GameStateVictory,
        .lastGameMode=1,.horizontalFlags=2,.vertivalFlags=4};
    state.board[0][0]=7; SudokuState before=state;
    assert(!sudoku_save_decode(&state,bytes,count));
    assert(memcmp(&state,&before,sizeof(state))==0);
}
int main(void) {
    SudokuState blank={0}; uint8_t valid[103]={0}; sudoku_save_encode(&blank,valid);
    for(size_t n=0;n<89;n++)reject(valid,n);
    reject(valid,90); reject(valid,102); reject(valid,103);
    for(int pos=0;pos<2;pos++){uint8_t bad[89];memcpy(bad,valid,89);bad[pos]=255;reject(bad,89);}
    const int positions[]={83,84,85,86,87,88};
    const uint8_t invalid[]={9,9,4,5,3,2};
    for(int i=0;i<6;i++){uint8_t bad[89];memcpy(bad,valid,89);bad[positions[i]]=invalid[i];reject(bad,89);}
    for(int pos=2;pos<83;pos++)for(int value=0;value<256;value++) {
        uint8_t bad[89];memcpy(bad,valid,89);bad[pos]=(uint8_t)value;
        if((value&15)>9 || (value&0x70))reject(bad,89);
        else {SudokuState state={0};assert(sudoku_save_decode(&state,bad,89));}
    }
    return 0;
}
"""
        )


if __name__ == "__main__":
    unittest.main()
