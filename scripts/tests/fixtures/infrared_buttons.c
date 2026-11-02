#include "infrared_layout.h"
#undef NDEBUG
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char** argv) {
    assert(argc == 2);
    const char* scenario = argv[1];
    if(!strcmp(scenario, "navigation")) {
        assert(infrared_grid_move(3, 10, InfraredDirectionRight) == 4);
        assert(infrared_grid_move(3, 10, InfraredDirectionDown) == 5);
        assert(infrared_grid_move(5, 10, InfraredDirectionDown) == 7);
        assert(infrared_grid_move(7, 10, InfraredDirectionUp) == 5);
        assert(infrared_grid_move(0, 10, InfraredDirectionLeft) == 9);
        assert(infrared_grid_move(9, 10, InfraredDirectionRight) == 0);
        assert(infrared_grid_move(0, 10, InfraredDirectionUp) == 8);
    } else if(!strcmp(scenario, "bounds")) {
        assert(infrared_grid_move(3, 5, InfraredDirectionDown) == 1);
        assert(infrared_grid_move(4, 5, InfraredDirectionDown) == 0);
        assert(infrared_grid_move(1, 5, InfraredDirectionUp) == 3);
        assert(infrared_grid_move(999, 0, InfraredDirectionRight) == 0);
        assert(infrared_grid_move(0, 1, InfraredDirectionDown) == 0);
        for(size_t n = 1; n < 200; ++n) {
            for(size_t p = 0; p < n; ++p) {
                for(int d = 0; d < 4; ++d)
                    assert(infrared_grid_move(p, n, d) < n);
            }
        }
    } else if(!strcmp(scenario, "geometry")) {
        for(size_t capacity = 4; capacity <= 6; capacity += 2) {
            for(size_t i = 0; i < capacity; ++i) {
                InfraredButtonRect r = infrared_grid_rect(i, capacity);
                assert(r.x >= 1 && r.y >= 14);
                assert(r.x + r.width <= 127 && r.y + r.height <= 58);
                assert(r.width >= 59 && r.height >= 13);
                for(size_t j = 0; j < i; ++j) {
                    InfraredButtonRect q = infrared_grid_rect(j, capacity);
                    assert(
                        r.x >= q.x + q.width || q.x >= r.x + r.width || r.y >= q.y + q.height ||
                        q.y >= r.y + r.height);
                }
            }
        }
    } else if(!strcmp(scenario, "labels")) {
        char label[32];
        infrared_button_label("Vol_up", label, sizeof(label));
        assert(!strcmp(label, "Vol +"));
        infrared_button_label("Cool_hi", label, sizeof(label));
        assert(!strcmp(label, "Cool max"));
        infrared_button_label("Custom_25C", label, sizeof(label));
        assert(!strcmp(label, "Custom 25C"));
        infrared_button_label("\xe4\xb8\xad\xe6\x96\x87", label, 5);
        assert(!strcmp(label, "\xe4\xb8\xad"));
        label[0] = 'x';
        infrared_button_label("Power", label, 1);
        assert(label[0] == '\0');
        infrared_button_label("Power", NULL, 0);
    } else {
        InfraredButtonHold state = {0};
        InfraredButtonAction action;
        if(!strcmp(scenario, "hold")) {
            action = infrared_button_action(&state, InfraredButtonPress, true, 23);
            assert(action.type == InfraredActionPress && action.id == 23 && state.held);
            action = infrared_button_action(&state, InfraredButtonPress, true, 99);
            assert(action.type == InfraredActionNone);
            action = infrared_button_action(&state, InfraredButtonRelease, true, 99);
            assert(action.type == InfraredActionRelease && action.id == 23 && !state.held);
            assert(
                infrared_button_action(&state, InfraredButtonCancel, true, 99).type ==
                InfraredActionNone);
            infrared_button_action(&state, InfraredButtonPress, true, 7);
            action = infrared_button_action(&state, InfraredButtonCancel, false, -1);
            assert(action.type == InfraredActionRelease && action.id == 7);
            assert(
                infrared_button_action(&state, InfraredButtonRelease, true, 7).type ==
                InfraredActionNone);
        } else if(!strcmp(scenario, "control")) {
            assert(
                infrared_button_action(&state, InfraredButtonPress, false, -2).type ==
                InfraredActionNone);
            assert(
                infrared_button_action(&state, InfraredButtonCancel, false, -2).type ==
                InfraredActionNone);
            assert(
                infrared_button_action(&state, InfraredButtonRelease, false, -2).type ==
                InfraredActionNone);
            action = infrared_button_action(&state, InfraredButtonShort, false, -2);
            assert(action.type == InfraredActionActivate && action.id == -2 && !state.held);
        } else {
            assert(!strcmp(scenario, "misordered"));
            infrared_button_action(&state, InfraredButtonPress, true, 1);
            assert(
                infrared_button_action(&state, InfraredButtonShort, true, 1).type ==
                InfraredActionRelease);
            assert(!state.held);
            assert(
                infrared_button_action(&state, InfraredButtonRelease, true, 1).type ==
                InfraredActionNone);
        }
    }
    puts("ok");
    return 0;
}
