"""Private plugin imports must match explicit owner exports, never prefixes."""

from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from fbt.sdk.app_api import declared_api_symbols


class AppApiTests(unittest.TestCase):
    def test_exact_exports_ignore_comments(self):
        exports = declared_api_symbols(
            """
            API_METHOD(
                example_call, void, (int value)),
            API_VARIABLE(example_icon, const Icon),
            // API_METHOD(commented_function, void, ()),
            /* API_VARIABLE(commented_icon, const Icon), */
            void unrelated_function(void);
            """
        )
        self.assertEqual(exports, {"example_call", "example_icon"})
        unresolved = {"example_call", "example_call_missing", "unrelated_function"}
        self.assertEqual(
            unresolved - exports, {"example_call_missing", "unrelated_function"}
        )
