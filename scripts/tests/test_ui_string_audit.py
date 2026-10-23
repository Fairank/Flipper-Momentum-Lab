"""Host tests for scripts/audit_ui_strings.py, the offline UI text inventory.

Synthetic sources exercise the lexer and the argument mapping; the repository
tests compare the mapping with this checkout's GUI headers and scan one real
scope. None of them shows what the firmware draws at run time.
"""

import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "audit_ui_strings.py"

_spec = importlib.util.spec_from_file_location("audit_ui_strings", SCRIPT)
ui_audit = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = ui_audit
_spec.loader.exec_module(ui_audit)

# The functions the inventory was asked to cover; UI_APIS lists more
REQUESTED = (
    "byte_input_set_header_text", "canvas_draw_str", "canvas_draw_str_aligned",
    "dialog_ex_set_center_button_text", "dialog_ex_set_header",
    "dialog_ex_set_left_button_text", "dialog_ex_set_right_button_text",
    "dialog_ex_set_text", "elements_button_center", "elements_button_left",
    "elements_button_right", "loading_set_text", "popup_set_header", "popup_set_text",
    "submenu_add_item", "submenu_set_header", "text_input_set_header_text",
    "variable_item_list_add", "variable_item_list_set_header",
    "variable_item_set_current_value_text", "widget_add_button_element",
    "widget_add_string_element", "widget_add_string_multiline_element",
    "widget_add_text_box_element", "widget_add_text_scroll_element",
)  # fmt: skip

REPLACEMENT = "\N{REPLACEMENT CHARACTER}"

# One-line sources for the tree tests; the literal of DRAW starts in column 46
DRAW = 'void f(Canvas* c) {{ canvas_draw_str(c, 0, 0, "{}"); }}\n'
POPUP = "void f(Popup* p) { popup_set_text(p, label, 0, 0, AlignLeft, AlignTop); }\n"
BUTTON_CRLF = 'void f(Canvas* c) {\r\n    elements_button_left(c, "返回");\r\n}\r\n'


def scan(source):
    """Entries of a C snippet; line 1 is the snippet's first line."""
    return ui_audit.scan_text(textwrap.dedent(source).lstrip("\n")).entries


def fields(items, *names):
    return [tuple(item[name] for name in names) for item in items]


class LexerTests(unittest.TestCase):
    def test_comments_and_quotes_neither_hide_nor_invent_calls(self):
        entries = scan(
            r"""
            // canvas_draw_str(canvas, 0, 0, "line comment");
            /* canvas_draw_str(canvas, 0, 0, "block comment"); */
            void draw(Canvas* canvas) {
                char quote = '"', apostrophe = '\'';
                canvas_draw_str(canvas, 0, 0, /* "not this" */ "Shown" /* , "nor" */);
                canvas_draw_str(canvas, 0, 10, "// not a comment");
                canvas_draw_str(canvas, 0, 20, "/* nor this */");
                canvas_draw_str(canvas, 0, 30, "a\"b"); // canvas_draw_str(c, 0, 0, "x");
            }
            """
        )
        self.assertEqual(
            fields(entries, "line", "column", "text", "enclosing_function"),
            [
                (5, 52, "Shown", "draw"),
                (6, 36, "// not a comment", "draw"),
                (7, 36, "/* nor this */", "draw"),
                (8, 36, 'a"b', "draw"),
            ],
        )
        self.assertEqual(entries[0]["source"], '"Shown"')

    def test_escapes_decode_to_utf8_text(self):
        entries = scan(
            r"""
            void f(Canvas* c) {
                canvas_draw_str(c, 0, 0, "Tab\tNew\nQuote\"Back\\slash\?");
                canvas_draw_str(c, 0, 0, "\x41\102\e#Bold\0");
                canvas_draw_str(c, 0, 0, "\xe4\xb8\xad\U00006587");
                canvas_draw_str(c, 0, 0, "\xe4" "\xb8\xad");
                canvas_draw_str(c, 0, 0, "\xff");
                canvas_draw_str(c, 0, 0, "\q");
            }
            """
        )
        self.assertEqual(
            fields(entries, "text", "classification", "notes"),
            [
                ('Tab\tNew\nQuote"Back\\slash?', "needing-review", []),
                ("AB\x1b#Bold\x00", "needing-review", []),
                ("中文", "chinese", []),
                ("中", "chinese", []),
                (REPLACEMENT, "neutral", ["not valid UTF-8"]),
                ("q", "neutral", ["unknown escape \\q"]),
            ],
        )

    def test_four_digit_universal_character_name(self):
        # "中文" written as two four-digit universal character names in the C source
        backslash = "\\"
        source = f'canvas_draw_str(c, 0, 0, "{backslash}u4e2d{backslash}u6587");'
        entries = ui_audit.scan_text(source).entries
        self.assertEqual(fields(entries, "text", "notes"), [("中文", [])])

    def test_adjacent_literals_join_across_lines_and_splices(self):
        entries = scan(
            r"""
            void f(Widget* widget, Popup* popup) {
                widget_add_text_scroll_element(
                    widget,
                    0,
                    0,
                    128,
                    64,
                    "First line\n"
                    "Second " // not part of the text
                    "line");
                popup_set_text(popup, "Spliced \
            text", 64, 32, AlignCenter, AlignCenter);
                popup_set_header(popup, "After", 64, 10, AlignCenter, AlignTop);
            }
            """
        )
        self.assertEqual(
            fields(entries, "function", "argument_index", "line", "column", "text"),
            [
                ("widget_add_text_scroll_element", 5, 8, 9, "First line\nSecond line"),
                ("popup_set_text", 1, 11, 27, "Spliced text"),
                ("popup_set_header", 1, 13, 29, "After"),
            ],
        )

    def test_cpp_raw_strings_digit_separators_and_prefixes(self):
        entries = scan(
            r"""
            namespace ui {
            void Screen::draw(Canvas* canvas) const {
                int big = 1'000; canvas_draw_str(canvas, 0, 0, "it's");
                canvas_draw_str(canvas, 0, 10, R"x(raw "quoted" \n)x");
                canvas_draw_str(canvas, 0, 20, u8"中文");
            }
            }
            """
        )
        self.assertEqual(
            fields(entries, "text", "enclosing_function"),
            [
                ("it's", "Screen::draw"),
                ('raw "quoted" \\n', "Screen::draw"),
                ("中文", "Screen::draw"),
            ],
        )

    def test_unterminated_block_comment_is_reported(self):
        result = ui_audit.scan_text('canvas_draw_str(c, 0, 0, "Kept");\n/* open\n')
        self.assertEqual(fields(result.entries, "text"), [("Kept",)])
        self.assertEqual(result.problems, [(2, "unterminated block comment")])


class CallTests(unittest.TestCase):
    def test_only_mapped_positions_of_known_functions_are_reported(self):
        entries = scan(
            r"""
            void f(App* app) {
                FURI_LOG_I(TAG, "Log %s", "not UI");
                storage_simply_mkdir(app->storage, "/ext/apps_data/demo");
                widget_add_string_element(
                    app->widget, MAX(1, (2)), get(a, (b, c)), AlignLeft, AlignTop, FontPrimary, "Title");
                widget_add_text_box_element(
                    app->widget, 0, 0, 128, 64, AlignLeft, AlignTop, "\e#Body", false);
                menu_add_item(app->menu, "Label", &I_icon, 0, callback, "context");
                submenu_add_lockable_item(app->submenu, "Locked", 0, cb, app, true, "Unlock");
                dialog_message_set_buttons(app->message, "Back", NULL, "Next");
                widget_add_button_element(app->widget, GuiButtonTypeRight, "More", cb, app);
            }
            """
        )
        self.assertEqual(
            fields(entries, "function", "argument_index", "parameter", "kind", "text"),
            [
                ("widget_add_string_element", 6, "text", "literal", "Title"),
                ("widget_add_text_box_element", 7, "text", "literal", "\x1b#Body"),
                ("menu_add_item", 1, "label", "literal", "Label"),
                ("submenu_add_lockable_item", 1, "label", "literal", "Locked"),
                ("submenu_add_lockable_item", 6, "locked_message", "literal", "Unlock"),
                ("dialog_message_set_buttons", 1, "left", "literal", "Back"),
                ("dialog_message_set_buttons", 2, "center", "null", None),
                ("dialog_message_set_buttons", 3, "right", "literal", "Next"),
                ("widget_add_button_element", 2, "text", "literal", "More"),
            ],
        )
        self.assertEqual(entries[6]["classification"], "neutral")

    def test_calls_after_keywords_casts_and_labels_are_found(self):
        entries = scan(
            r"""
            static void draw(Canvas* canvas, bool on) {
                if(on) canvas_draw_str(canvas, 0, 0, "A1");
                else elements_button_left(canvas, "A2");
                (void)elements_button_right(canvas, "A3");
                switch(on) {
                case true: elements_button_center(canvas, "A4"); break;
                default: return elements_button_up(canvas, "A5");
                }
            }
            """
        )
        self.assertEqual(
            fields(entries, "text", "enclosing_function"),
            [(text, "draw") for text in ("A1", "A2", "A3", "A4", "A5")],
        )

    def test_non_literal_arguments_are_dynamic(self):
        entries = scan(
            r"""
            void f(App* app, bool enabled, size_t index) {
                canvas_draw_str(canvas, 0, 0, furi_string_get_cstr(app->text));
                variable_item_set_current_value_text(item, labels[index]);
                popup_set_header(app->popup, enabled ? "On" : "关", 64, 10, AlignCenter, AlignTop);
                canvas_draw_str(canvas, 0, 0, "Version " VERSION);
                dialog_ex_set_left_button_text(app->dialog, NULL);
                elements_button_center(canvas, ("OK"));
            }
            """
        )
        self.assertEqual(
            fields(
                entries, "kind", "classification", "text", "source", "embedded_literals"
            ),
            [
                ("expression", "dynamic", None, "furi_string_get_cstr(app->text)", []),
                ("expression", "dynamic", None, "labels[index]", []),
                ("expression", "dynamic", None, 'enabled ? "On" : "关"', ["On", "关"]),
                ("expression", "dynamic", None, '"Version " VERSION', ["Version "]),
                ("null", "neutral", None, "NULL", []),
                ("literal", "needing-review", "OK", '("OK")', []),
            ],
        )
        self.assertEqual(
            fields(entries[:3], "has_latin_words", "has_chinese"),
            [(False, False), (False, False), (True, True)],
        )

    def test_declarations_are_skipped_and_macro_bodies_scanned(self):
        entries = scan(
            r"""
            void canvas_draw_str(Canvas* canvas, int32_t x, int32_t y, const char* str);
            VariableItem* variable_item_list_add(
                VariableItemList* list, const char* label, uint8_t count, void* cb, void* ctx);
            #define submenu_add_item(submenu, label, index, callback, context) \
                my_add_item(submenu, label, index, callback, context)
            #define SHOW_HINT canvas_draw_str(canvas, 0, 0, "Hint")
            #define SHOW(text) popup_set_text(popup, text, 0, 0, AlignLeft, AlignTop)
            void canvas_draw_str(Canvas* canvas, int32_t x, int32_t y, const char* str) {
                (void)canvas_draw_str_aligned(canvas, x, y, AlignLeft, AlignBottom, str);
            }
            """
        )
        self.assertEqual(
            fields(entries, "function", "line", "kind", "text", "enclosing_function"),
            [
                ("canvas_draw_str", 6, "literal", "Hint", None),
                ("popup_set_text", 7, "expression", None, None),
                ("canvas_draw_str_aligned", 9, "expression", None, "canvas_draw_str"),
            ],
        )
        self.assertEqual(
            [entry["notes"] for entry in entries],
            [["in #define SHOW_HINT"], ["in #define SHOW"], []],
        )

    def test_calls_that_do_not_match_the_header_stay_visible(self):
        entries = scan(
            r"""
            void f(Canvas* canvas) {
                canvas_draw_str(canvas, POSITION, "Moved");
                canvas_draw_str(canvas, 0, 0,
            #ifdef BIG
                    "Big"
            #else
                    "Small"
            #endif
                );
            }
            void g(Canvas* canvas) {
                canvas_draw_str(canvas, 0, 0, "Broken";
            }
            """
        )
        self.assertEqual(
            fields(entries, "line", "column", "kind", "classification"),
            [
                (2, 5, "arity-mismatch", "dynamic"),
                (3, 5, "conditional", "dynamic"),
                (12, 5, "unparsed", "dynamic"),
            ],
        )
        self.assertEqual(
            fields(entries, "embedded_literals", "enclosing_function"),
            [(["Moved"], "f"), (["Big", "Small"], "f"), (["Broken"], "g")],
        )
        self.assertEqual(
            [entry["notes"] for entry in entries],
            [
                ["3 arguments, the header declares 4"],
                ["preprocessor lines inside the call"],
                ["the brackets do not close before ';' or the end of the file"],
            ],
        )
        self.assertEqual(entries[0]["source"], 'canvas, POSITION, "Moved"')

    def test_classification_by_script(self):
        entries = scan(
            r"""
            void f(Canvas* c) {
                canvas_draw_str(c, 0, 0, "设置");
                canvas_draw_str(c, 0, 0, "NFC 读取");
                canvas_draw_str(c, 0, 0, "Settings");
                canvas_draw_str(c, 0, 0, "Größe");
                canvas_draw_str(c, 0, 0, "12:30 / -");
                canvas_draw_str(c, 0, 0, "X");
                canvas_draw_str(c, 0, 0, "");
            }
            """
        )
        self.assertEqual(
            fields(entries, "classification", "has_latin_words", "has_chinese"),
            [
                ("chinese", False, True),
                ("chinese", True, True),
                ("needing-review", True, False),
                ("needing-review", True, False),
                ("neutral", False, False),
                ("neutral", False, False),
                ("neutral", False, False),
            ],
        )


class CommandLineTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.root = self.base / "repo"
        self.write("applications/main/a/z.c", POPUP)
        self.write("applications/main/a/notes.txt", DRAW.format("Not C"))
        self.write("applications/main/b.c", BUTTON_CRLF)
        self.write("applications/main/blob.c", DRAW.format("Bin") + "\0")
        self.write("applications/main/build/gen.c", DRAW.format("Built"))
        self.write("applications/services/gui/tiny_font.h", DRAW.format("Font"))
        self.write("applications/system/latin1.c", DRAW.format("caf\xe9"), "latin-1")
        self.write("applications_user/demo/demo.c", DRAW.format("User"))

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, path, text, encoding="utf-8"):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(text.encode(encoding))

    def run_main(self, *argv):
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            status = ui_audit.main([str(arg) for arg in argv])
        return status, stdout.getvalue(), stderr.getvalue()

    def test_inventory_of_a_tree(self):
        output = self.base / "inventory.json"
        status, stdout, _ = self.run_main("--root", self.root, "--output", output)
        self.assertEqual(status, 0)
        self.assertIn("not a translation coverage percentage", stdout)
        report = json.loads(output.read_text(encoding="utf-8"))
        self.assertEqual(
            fields(report["entries"], "file", "line", "column", "classification"),
            [
                ("applications/main/a/z.c", 1, 38, "dynamic"),
                ("applications/main/b.c", 2, 29, "chinese"),
                ("applications/system/latin1.c", 1, 46, "needing-review"),
                ("applications_user/demo/demo.c", 1, 46, "needing-review"),
            ],
        )
        self.assertEqual(
            [entry["text"] for entry in report["entries"]],
            [None, "返回", "caf" + REPLACEMENT, "User"],
        )
        self.assertEqual(report["entries"][2]["notes"], ["not valid UTF-8"])
        self.assertEqual(
            fields(report["skipped"], "path", "reason"),
            [
                ("applications/main/blob.c", "binary"),
                ("applications/main/build", "build-tree"),
                ("applications/services/gui/tiny_font.h", "generated-font"),
            ],
        )
        self.assertEqual(
            fields(report["warnings"], "file", "line", "message"),
            [("applications/system/latin1.c", None, "not valid UTF-8")],
        )
        self.assertEqual(
            fields(report["scopes"], "path", "present"),
            [
                ("applications/main", True),
                ("applications/settings", False),
                ("applications/services", True),
                ("applications/system", True),
                ("applications/external", False),
                ("applications/union", False),
                ("applications_user", True),
            ],
        )
        totals = report["totals"]
        # files_scanned, skipped, calls, entries, then the four classifications
        keys = ("files_scanned", "skipped", "calls", "entries")
        keys += ui_audit.CLASSIFICATIONS
        by_scope = {
            scope: [counts[key] for key in keys]
            for scope, counts in totals["by_scope"].items()
        }
        self.assertEqual(
            by_scope,
            {
                "applications/main": [2, 2, 2, 2, 0, 1, 0, 1],
                "applications/settings": [0, 0, 0, 0, 0, 0, 0, 0],
                "applications/union": [0, 0, 0, 0, 0, 0, 0, 0],
                "applications/services": [0, 1, 0, 0, 0, 0, 0, 0],
                "applications/system": [1, 0, 1, 1, 1, 0, 0, 0],
                "applications/external": [0, 0, 0, 0, 0, 0, 0, 0],
                "applications_user": [1, 0, 1, 1, 1, 0, 0, 0],
            },
        )
        self.assertEqual(
            [totals["overall"][key] for key in keys], [4, 3, 4, 4, 2, 1, 0, 1]
        )
        self.assertEqual(totals["by_function"]["canvas_draw_str"]["entries"], 2)
        self.assertEqual(
            {api["signature"] for api in report["apis"]}, {"header-missing"}
        )

    def test_output_is_byte_stable(self):
        outputs = []
        for seed in ("0", "1"):
            output = self.base / f"seed{seed}.json"
            env = dict(os.environ, PYTHONHASHSEED=seed, PYTHONIOENCODING="utf-8")
            command = [sys.executable, str(SCRIPT), "--root", str(self.root)]
            command += ["--output", str(output)]
            subprocess.run(command, check=True, capture_output=True, env=env)
            outputs.append(output.read_bytes())
        output = self.base / "in_process.json"
        self.assertEqual(self.run_main("--root", self.root, "--output", output)[0], 0)
        outputs.append(output.read_bytes())
        status, stdout, _ = self.run_main("--root", self.root)
        self.assertEqual(status, 0)
        outputs.append(stdout.encode("utf-8"))
        self.assertEqual(len(set(outputs)), 1)
        text = outputs[0].decode("utf-8")
        self.assertTrue(text.endswith("}\n"))
        self.assertNotIn("\r", text)
        self.assertNotIn(self.base.name, text)
        # One line per entry, so the inventory diffs and greps by entry
        entry_lines = [
            line
            for line in text.split("\n")
            if '"file": ' in line and '"argument_index": ' in line
        ]
        self.assertEqual(len(entry_lines), 4)

    def test_invalid_roots_and_outputs_fail_without_writing(self):
        empty = self.base / "empty"
        empty.mkdir()
        readme_only = self.base / "readme_only" / "applications" / "main"
        readme_only.mkdir(parents=True)
        (readme_only / "readme.md").write_text("canvas_draw_str\n", encoding="utf-8")
        output = self.base / "out.json"
        inside = self.root / "applications_user" / "out.json"
        cases = (
            ("--root", self.base / "missing", "--output", output),
            ("--root", self.root / "applications_user/demo/demo.c", "--output", output),
            ("--root", empty, "--output", output),
            ("--root", self.base / "readme_only", "--output", output),
            ("--root", self.root, "--output", self.base),
            ("--root", self.root, "--output", self.base / "missing" / "out.json"),
            ("--root", self.root, "--output", inside),
        )
        for argv in cases:
            with self.subTest(argv=argv):
                with self.assertRaises(SystemExit) as caught:
                    self.run_main(*argv)
                self.assertEqual(caught.exception.code, 2)
        self.assertFalse(output.exists())
        self.assertFalse(inside.exists())

    def test_header_mismatch_fails_after_writing(self):
        self.write(
            "applications/services/gui/canvas.h",
            "#pragma once\n"
            "void canvas_draw_str(Canvas* canvas, int32_t x, const char* str);\n"
            "void canvas_draw_str_aligned(\n"
            "Canvas* c, int32_t x, int32_t y, Align h, Align v, const char* text);\n",
        )
        output = self.base / "inventory.json"
        status, _, stderr = self.run_main("--root", self.root, "--output", output)
        self.assertEqual(status, 1)
        self.assertIn("canvas_draw_str: mismatch (3 parameters", stderr)
        report = json.loads(output.read_text(encoding="utf-8"))
        apis = {api["function"]: api for api in report["apis"]}
        self.assertEqual(apis["canvas_draw_str"]["signature"], "mismatch")
        self.assertEqual(
            apis["canvas_draw_str"]["signature_detail"],
            "3 parameters, the mapping expects 4",
        )
        self.assertEqual(
            apis["canvas_draw_str_aligned"]["signature_detail"],
            "parameter 5 is 'const char * text', "
            "the mapping expects 'const char* str'",
        )
        self.assertEqual(apis["submenu_add_item"]["signature"], "header-missing")
        self.assertNotIn(
            "applications/services/gui/canvas.h",
            [entry["file"] for entry in report["entries"]],
        )


class RepositoryTests(unittest.TestCase):
    def setUp(self):
        if not (ROOT / "applications/services/gui/canvas.h").is_file():
            self.skipTest("the GUI headers are not in this checkout")

    def test_mapping_matches_the_gui_headers(self):
        results = ui_audit.verify_signatures(ROOT)
        self.assertEqual(sorted(results), sorted(ui_audit.UI_APIS))
        failures = {
            name: result for name, result in results.items() if result[0] != "verified"
        }
        self.assertEqual(failures, {})
        missing = [name for name in REQUESTED if name not in ui_audit.UI_APIS]
        self.assertEqual(missing, [])

    def test_header_declarations_are_not_calls(self):
        for header in sorted({api.header for api in ui_audit.UI_APIS.values()}):
            with self.subTest(header):
                text = (ROOT / header).read_text(encoding="utf-8")
                self.assertEqual(ui_audit.scan_text(text).entries, [])

    def test_positions_in_a_real_scope_point_at_the_arguments(self):
        scope = "applications/settings"
        report = ui_audit.inventory(ROOT, scopes=(scope,))
        self.assertEqual(report, ui_audit.inventory(ROOT, scopes=(scope,)))
        self.assertTrue(report["entries"])
        for entry in report["entries"]:
            data = (ROOT / entry["file"]).read_bytes()
            text = data.decode("utf-8-sig", "surrogateescape").replace("\r\n", "\n")
            line = text.replace("\r", "\n").split("\n")[entry["line"] - 1]
            expected = entry["source"][:1]
            if entry["kind"] in ("conditional", "arity-mismatch", "unparsed"):
                expected = entry["function"]
            with self.subTest(file=entry["file"], line=entry["line"]):
                self.assertTrue(entry["file"].startswith(scope + "/"))
                self.assertTrue(line[entry["column"] - 1 :].startswith(expected), line)


if __name__ == "__main__":
    unittest.main()
