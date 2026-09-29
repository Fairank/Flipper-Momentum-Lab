"""Regression checks for imported upstream data correctness fixes."""

from pathlib import Path
import shutil
import unittest

from test_unleashed_integration import native_test, source_between

ROOT = Path(__file__).resolve().parents[2]


class UpstreamDataTests(unittest.TestCase):
    def test_release_logging_does_not_evaluate_arguments(self):
        self.assertIsNotNone(shutil.which("cc"), "Host C compiler is required")
        header = (ROOT / "furi/core/log.h").read_text(encoding="utf-8")
        header = header.replace("#pragma once", "")
        native_test(
            "#include <assert.h>\n#define LOGS_RELEASE_BUILD\n"
            "#define _ATTRIBUTE(attributes) __attribute__(attributes)\n"
            + header
            + r"""
static unsigned calls;
static int debug_only_argument(void) { ++calls; return 7; }
int main(void) {
    FURI_LOG_D("test", "%d", debug_only_argument());
    FURI_LOG_T("test", "%d", debug_only_argument());
    FURI_LOG_RAW_T("%d", debug_only_argument());
    assert(calls == 0);
    // Disabled macros must also be safe as a single branch statement.
    if(true) FURI_LOG_D("test", "no arguments"); else calls++;
    assert(calls == 0);
    return 0;
}
"""
        )

    def test_array_equality_checks_every_byte_of_every_element(self):
        self.assertIsNotNone(shutil.which("cc"), "Host C compiler is required")
        header = (ROOT / "lib/toolbox/simple_array.h").read_text(encoding="utf-8")
        header = header.replace("#pragma once", "")
        structure = source_between(
            "lib/toolbox/simple_array.c",
            "struct SimpleArray {",
            "\nSimpleArray* simple_array_alloc",
        )
        implementation = source_between(
            "lib/toolbox/simple_array.c",
            "bool simple_array_is_equal(",
            "\nuint32_t simple_array_get_count(",
        )
        native_test(
            "#include <assert.h>\n#include <string.h>\n#define furi_check assert\n"
            + header
            + structure
            + implementation
            + r"""
int main(void) {
    const SimpleArrayConfig words = {.type_size = 4};
    const SimpleArrayConfig same_width_other_type = {.type_size = 4};
    const SimpleArrayConfig bytes = {.type_size = 1};
    unsigned char left_data[12] = {0};
    unsigned char right_data[12] = {0};
    SimpleArray left = {.config = &words, .data = left_data, .count = 3};
    SimpleArray right = {.config = &words, .data = right_data, .count = 3};
    assert(simple_array_is_equal(&left, &right));
    for(unsigned int i = 0; i < sizeof(right_data); ++i) {
        right_data[i] = 1;
        assert(!simple_array_is_equal(&left, &right));
        assert(!simple_array_is_equal(&right, &left));
        right_data[i] = 0;
    }
    assert(simple_array_is_equal(&left, &left));
    right.count = 2;
    assert(!simple_array_is_equal(&left, &right));
    right.count = 3;
    right.config = &same_width_other_type;
    assert(!simple_array_is_equal(&left, &right));
    left.config = right.config = &bytes;
    left.count = right.count = sizeof(left_data);
    assert(simple_array_is_equal(&left, &right));
    right_data[11] = 1;
    assert(!simple_array_is_equal(&left, &right));
    left.data = right.data = NULL;
    left.count = right.count = 0;
    assert(simple_array_is_equal(&left, &right));
    return 0;
}
"""
        )


if __name__ == "__main__":
    unittest.main()
