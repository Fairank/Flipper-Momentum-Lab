"""Check imported ring geometry, transition endpoints and opening duration."""

from pathlib import Path
import unittest

from test_unleashed_integration import native_test

ROOT = Path(__file__).resolve().parents[2]


class MenuAnimationTests(unittest.TestCase):
    def test_actual_geometry_and_timing(self):
        header = (
            (ROOT / "applications/services/gui/modules/menu_animations.h")
            .read_text(encoding="utf-8")
            .replace("#pragma once", "")
        )
        native_test(
            "#include <assert.h>\n"
            + header
            + r"""
int main(void) {
    assert(menu_window_frame(0) == 0);
    assert(menu_window_frame(47) == 0);
    assert(menu_window_frame(48) == 1);
    assert(menu_window_frame(383) == 7);
    assert(menu_window_frame(384) == 8);
    assert(menu_window_frame(UINT32_MAX) == 8);
    assert(menu_ring_phase(1, 0) == 30);
    assert(menu_ring_phase(-1, 0) == -30);
    assert(menu_ring_phase(1, 320) == 0);
    assert(menu_ring_phase(-1, UINT32_MAX) == 0);
    MenuRingPoint front = menu_ring_point(0, 0);
    assert(front.x == 64 && front.y == 37 && front.scale == 200);
    for(int direction = -1; direction <= 1; direction += 2) {
        for(int slot = -2; slot <= 2; ++slot) {
            MenuRingPoint start = menu_ring_point(slot, menu_ring_phase(direction, 0));
            MenuRingPoint previous = menu_ring_point(slot + direction, 0);
            assert(start.x == previous.x && start.y == previous.y && start.scale == previous.scale);
            for(unsigned elapsed = 0; elapsed <= 321; ++elapsed) {
                MenuRingPoint p = menu_ring_point(slot, menu_ring_phase(direction, elapsed));
                assert(p.x >= 0 && p.x < 128 && p.y >= 0 && p.y < 64);
                assert(p.scale >= 100 && p.scale <= 200);
            }
        }
    }
    for(int slot = 1; slot <= 2; ++slot) {
        MenuRingPoint left = menu_ring_point(-slot, 0);
        MenuRingPoint right = menu_ring_point(slot, 0);
        assert(left.x + right.x == 128 && left.y == right.y);
    }
    return 0;
}
"""
        )
