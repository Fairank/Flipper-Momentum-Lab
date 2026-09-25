"""Host tests for scripts/generate_lab_font.py and the Flipper Lab sources.

Synthetic fonts, written by an encoder independent of the generator, exercise
the u8g2 format rules; the remaining tests read u8g2_font_wqy12_t_gb2312 from
lib/u8g2/u8g2_fonts.c. They do not replace a firmware build or looking at the
screen of a Flipper.
"""

import ast
import contextlib
import functools
import importlib.util
import io
import json
import os
import re
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "generate_lab_font.py"
LAB = ROOT / "applications" / "main" / "lab"

_spec = importlib.util.spec_from_file_location("generate_lab_font", SCRIPT)
gen = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = gen
_spec.loader.exec_module(gen)

PARAMS = gen.GlyphParams(3, 2, 4, 4, 5, 5, 5)  # bit widths used by the WenQuanYi font
BOX = ["####", "#..#", "#..#", "#..#", "#..#", "#..#", "####"]
HAN = ["###########"] + ["#.........#"] * 9 + ["###########"]
SYMBOL = "test_font"
LAYOUT = {
    "text_x": 2, "text_max_width": 120, "list_width": 124, "indicator_right": 126,
    "indicator_gap": 4, "title_baseline": 11, "rows_top": 14, "row_height": 12,
    "row_baseline": 10, "rows": 3, "footer_baseline": 62, "max_wide_chars": 10,
}  # fmt: skip


def encode_glyph(rows=(), x=0, y=0, advance=6):
    """Encode '#' pixels in u8g2's run-length glyph format, as bdfconv does."""
    width = len(rows[0]) if rows else 0
    bits = []

    def put(value, count):
        bits.extend((value >> i) & 1 for i in range(count))

    put(width, PARAMS.width)
    put(len(rows), PARAMS.height)
    for value, count in ((x, PARAMS.x), (y, PARAMS.y), (advance, PARAMS.advance)):
        put(value + (1 << (count - 1)), count)
    ink = [char == "#" for row in rows for char in row]
    i = 0
    while i < len(ink):
        zeros = ones = 0
        while i < len(ink) and not ink[i] and zeros < (1 << PARAMS.bits_0) - 1:
            zeros, i = zeros + 1, i + 1
        while i < len(ink) and ink[i] and ones < (1 << PARAMS.bits_1) - 1:
            ones, i = ones + 1, i + 1
        put(zeros, PARAMS.bits_0)
        put(ones, PARAMS.bits_1)
        put(0, 1)  # no repeat
    data = bytearray((len(bits) + 7) // 8)
    for i, bit in enumerate(bits):
        data[i >> 3] |= bit << (i & 7)
    return bytes(data)


def synthetic_glyphs():
    glyphs = {code: encode_glyph(BOX) for code in range(0x21, 0x7F)}
    glyphs[0x20] = encode_glyph()
    glyphs[ord("/")] = encode_glyph(["#"] * 12, y=-1)  # 11 rows above the baseline
    glyphs[ord("g")] = encode_glyph(BOX, y=-2)
    for char in "一三中二文":
        glyphs[ord(char)] = encode_glyph(HAN, y=-1, advance=12)
    return glyphs


def make_font(ascii_items, unicode_items, block=2, lasts=None):
    """Assemble a u8g2 font from (code, payload) pairs kept in the given order,
    with a multi-block Unicode lookup table like bdfconv writes."""
    body, upper, lower = bytearray(), None, None
    for code, payload in ascii_items:
        if code >= ord("A") and upper is None:
            upper = len(body)
        if code >= ord("a") and lower is None:
            lower = len(body)
        body += bytes((code, 2 + len(payload))) + payload
    terminator = len(body)
    body += b"\0\0"
    chunks = [unicode_items[i : i + block] for i in range(0, len(unicode_items), block)]
    blocks = [
        b"".join(
            struct.pack(">HB", code, 3 + len(payload)) + payload
            for code, payload in chunk
        )
        for chunk in chunks
    ]
    lasts = lasts or [chunk[-1][0] for chunk in chunks[:-1]] + [0xFFFF]
    table, step = bytearray(), 4 * len(chunks)
    for last, data in zip(lasts, blocks):
        table += struct.pack(">HH", step, last)
        step = len(data)
    count = (len(ascii_items) + len(unicode_items)) & 0xFF
    header = (
        bytes((count, 0)) + bytes(PARAMS) + bytes((12, 13, 0, 0xFE, 8, 0xFE, 10, 0xFF))
    )
    starts = (
        terminator if upper is None else upper,
        terminator if lower is None else lower,
    )
    header += struct.pack(">HHH", *starts, len(body))
    return header + bytes(body) + bytes(table) + b"".join(blocks) + b"\0\0"


def font_from(glyphs):
    items = sorted(glyphs.items())
    return make_font(
        [i for i in items if i[0] <= 0xFF], [i for i in items if i[0] > 0xFF]
    )


def c_source(
    data, symbol=SYMBOL, comment=("Fontname: test", "Copyright: (null)", "Glyphs: 1/1")
):
    """Write a font the way u8g2_fonts.c does: octal escapes, digits escaped
    after an escape, and the literal's own NUL as the last zero byte."""
    tokens, octal = [], False
    for byte in data[:-1]:
        char = chr(byte)
        if (
            " " <= char <= "~"
            and char not in '"\\?'
            and not (octal and char in "01234567")
        ):
            tokens.append(char)
            octal = False
        else:
            tokens.append(f"\\{byte:o}")
            octal = True
    literal = "\n".join(
        '    "' + "".join(tokens[i : i + 24]) + '"' for i in range(0, len(tokens), 24)
    )
    notes = "".join(f"  {line}\n" for line in comment)
    return (
        f"/*\n{notes}*/\n#ifdef U8G2_USE_LARGE_FONTS\n"
        f'const uint8_t {symbol}[{len(data)}] U8G2_FONT_SECTION("{symbol}") =\n{literal};\n'
        "#endif\n"
    )


def sample_content():
    return {
        "schema_version": 1,
        "layout": dict(LAYOUT),
        "ui": {
            "menu_title": "中文",
            "menu_footer": "OK",
            "detail_footer": "文",
            "detail_footer_launch": "OK 文",
            "indicator": "{index}/{count}",
        },
        "topics": [
            {
                "id": "one",
                "menu": "中文",
                "title": "一",
                "launch": None,
                "pages": [["中文 OK", "g"]],
            },
            {
                "id": "two",
                "menu": "二",
                "title": "三",
                "launch": "Demo",
                "pages": [["中"], ["文"]],
            },
        ],
    }


def header_bytes(text):
    body = text[text.index("lab_font[] = {") :]
    return bytes(
        int(value, 16)
        for value in re.findall(r"0x([0-9a-f]{2})", body[: body.index("};")])
    )


def set_word(data, offset, value):
    out = bytearray(data)
    out[offset : offset + 2] = struct.pack(">H", value)
    return bytes(out)


@functools.lru_cache(maxsize=None)
def real_font():
    source = gen.DEFAULT_SOURCE.read_text(encoding="latin-1")
    data, comment = gen.extract_font(source, gen.DEFAULT_SYMBOL)
    return data, comment, gen.parse_font(data)


def real_content():
    return gen.load_content(json.loads(gen.DEFAULT_CONTENT.read_text(encoding="utf-8")))


class CLiteralTests(unittest.TestCase):
    def test_decodes_u8g2_escapes(self):
        self.assertEqual(
            gen.decode_c_string(r"\0\60Z\42\134\77\x41\n\1234"),
            bytes([0, 0x30, 0x5A, 0x22, 0x5C, 0x3F, 0x41, 0x0A, 0x53, 0x34]),
        )

    def test_rejects_invalid_literals(self):
        for body in (r"\400", r"\q", "abc\\", r"\x", "é", '"', "\t"):
            with self.subTest(body=body), self.assertRaises(gen.FontError):
                gen.decode_c_string(body)

    def test_extracts_the_named_font_and_its_comment(self):
        data = font_from(synthetic_glyphs())
        decoy = font_from(
            {0x41: encode_glyph(BOX), 0x4E2D: encode_glyph(HAN, y=-1, advance=12)}
        )
        extracted, comment = gen.extract_font(
            c_source(decoy, SYMBOL + "_b") + c_source(data), SYMBOL
        )
        self.assertEqual(extracted, data)
        self.assertIn("Copyright: (null)", comment)
        self.assertIn("(definition guarded by: #ifdef U8G2_USE_LARGE_FONTS)", comment)

    def test_rejects_inconsistent_definitions(self):
        data = font_from(synthetic_glyphs())
        good = c_source(data)
        cases = {
            "declared size": good.replace(f"[{len(data)}]", f"[{len(data) + 5}]"),
            "missing": good.replace(SYMBOL, "other_font"),
            "defined twice": good + good,
            "unterminated literal": good.replace('";\n#endif', "\n;\n#endif"),
            "stray token": good.replace('"\n    "', '" x "', 1),
            "no copyright field": good.replace("Copyright: (null)", "Licence: none"),
        }
        for name, source in cases.items():
            with self.subTest(name), self.assertRaises(gen.FontError):
                gen.extract_font(source, SYMBOL)


class FormatTests(unittest.TestCase):
    def setUp(self):
        self.glyphs = synthetic_glyphs()
        items = sorted(self.glyphs.items())
        self.ascii = [item for item in items if item[0] <= 0xFF]
        self.unicode = [item for item in items if item[0] > 0xFF]
        self.data = make_font(self.ascii, self.unicode)

    def test_parses_a_multi_block_font(self):
        font = gen.parse_font(self.data)
        self.assertEqual({**font.ascii, **font.unicode}, self.glyphs)
        for code, payload in self.glyphs.items():
            self.assertEqual(gen.u8g2_lookup(self.data, code), payload)
        for code in (0x10, 0x7F, 0x4E01, 0x9FA5):
            self.assertIsNone(gen.u8g2_lookup(self.data, code))

    def test_every_truncation_is_rejected(self):
        for cut in range(len(self.data)):
            with self.assertRaises(gen.FontError, msg=f"cut at {cut}"):
                gen.parse_font(self.data[:cut])

    def test_rejects_malformed_tables(self):
        a, u = self.ascii, self.unicode
        upper, unicode_start = gen.be16(self.data, 17), gen.be16(self.data, 21)
        zero_bits = bytearray(self.data)
        zero_bits[4] = 0
        cases = {
            "unsorted 8-bit glyphs": make_font(a[::-1], u),
            "duplicate 8-bit glyph": make_font(a + a[-1:], u),
            "record shorter than a glyph header": make_font([(0x21, b"\0")], u),
            "unsorted Unicode glyphs": make_font(a, u[::-1]),
            "duplicate Unicode glyph": make_font(a, u + u[-1:]),
            "8-bit code in Unicode section": make_font(a, [(0x7F, u[0][1])] + u),
            "unsorted lookup table": make_font(a, u, lasts=[0x4E2D, 0x4E09, 0xFFFF]),
            "block unreachable by lookup": make_font(
                a, u, lasts=[0x4E05, 0x4E8C, 0xFFFF]
            ),
            "lookup table without 0xFFFF": make_font(
                a, u, lasts=[0x4E09, 0x4E8C, 0x6587]
            ),
            "'A' start inside a record": set_word(self.data, 17, upper + 1),
            "Unicode start misplaced": set_word(self.data, 21, unicode_start + 1),
            "zero bit width": bytes(zero_bits),
            "bytes after sentinel": self.data + b"\0",
        }
        for name, data in cases.items():
            with self.subTest(name), self.assertRaises(gen.FontError):
                gen.parse_font(data)

    def test_glyph_decoder_matches_encoder(self):
        rows = ["#..#.", ".##..", "....#", "#####"]
        glyph = gen.decode_glyph(PARAMS, encode_glyph(rows, x=1, y=-2, advance=7))
        self.assertEqual(glyph[:5], (5, 4, 1, -2, 7))
        ink = {
            (col, row)
            for row, line in enumerate(rows)
            for col, c in enumerate(line)
            if c == "#"
        }
        self.assertEqual(glyph.pixels, ink)

    def test_decoder_rejects_damaged_glyphs(self):
        payload = encode_glyph(HAN, y=-1, advance=12)
        for damaged in (payload[:-1], payload + b"\0\0"):
            with self.assertRaises(gen.FontError):
                gen.decode_glyph(PARAMS, damaged)


class SubsetTests(unittest.TestCase):
    def setUp(self):
        self.font = gen.parse_font(font_from(synthetic_glyphs()))
        self.codes = set(range(0x20, 0x7F)) | {ord("中"), ord("文")}

    def test_subset_keeps_payloads_and_rebuilds_lookup(self):
        data = gen.build_subset(self.font, self.codes)
        subset = gen.verify_subset(self.font, data, self.codes)
        self.assertEqual(set(subset.ascii) | set(subset.unicode), self.codes)
        for code in self.codes:
            self.assertEqual(subset.payload(code), self.font.payload(code))
            self.assertEqual(gen.u8g2_lookup(data, code), self.font.payload(code))
        self.assertIsNone(gen.u8g2_lookup(data, ord("一")))
        self.assertEqual(data[0], len(self.codes) & 0xFF)
        self.assertEqual(
            data[1:17], self.font.header[1:17]
        )  # bit widths and metrics kept
        table = gen.HEADER_SIZE + gen.be16(data, 21)
        self.assertEqual(data[table : table + 4], b"\x00\x04\xff\xff")
        self.assertEqual(data[-2:], b"\0\0")
        self.assertEqual(data[gen.HEADER_SIZE + gen.be16(data, 17)], ord("A"))
        self.assertEqual(data[gen.HEADER_SIZE + gen.be16(data, 19)], ord("a"))

    def test_subset_is_deterministic(self):
        forward = gen.build_subset(self.font, sorted(self.codes))
        backward = gen.build_subset(self.font, sorted(self.codes, reverse=True))
        self.assertEqual(forward, backward)

    def test_missing_glyph_is_an_error(self):
        with self.assertRaisesRegex(gen.FontError, r"U\+3400"):
            gen.build_subset(self.font, self.codes | {0x3400})


class ContentTests(unittest.TestCase):
    def setUp(self):
        self.font = gen.parse_font(font_from(synthetic_glyphs()))

    def measure(self, data):
        content = gen.load_content(data)
        subset = gen.parse_font(
            gen.build_subset(self.font, gen.required_codes(content))
        )
        gen.check_layout(content, gen.Metrics(subset))
        return content

    def test_expands_indicators_footers_and_blank_lines(self):
        one, two = self.measure(sample_content()).topics
        self.assertEqual((one.indicator, two.indicator), ("1/2", "2/2"))
        self.assertEqual([page.indicator for page in two.pages], ["1/2", "2/2"])
        self.assertEqual((one.footer, two.footer), ("文", "OK 文"))
        self.assertEqual(one.pages[0].lines, ("中文 OK", "g", ""))

    def test_rejects_text_that_does_not_fit(self):
        def line(text):
            return lambda data: data["topics"][0]["pages"][0].__setitem__(0, text)

        cases = {
            "eleven Chinese characters": line("中" * 11),
            "wider than 120 px": line("W" * 21),
            "slash taller than a row": line("中/文"),
            "control character": line("中\n文"),
            "leading space": line(" 中"),
            "title against indicator": lambda d: d["topics"][0].__setitem__(
                "title", "中" * 9
            ),
            "four lines": lambda d: d["topics"][0]["pages"][0].extend(["一", "二"]),
            "unknown key": lambda d: d["topics"][0].__setitem__("icon", "x"),
            "duplicate id": lambda d: d["topics"][1].__setitem__("id", "one"),
            "bad indicator": lambda d: d["ui"].__setitem__("indicator", "{page}"),
            "rows past footer": lambda d: d["layout"].__setitem__("rows", 5),
        }
        for name, change in cases.items():
            data = sample_content()
            change(data)
            with self.subTest(name), self.assertRaises(gen.ContentError):
                self.measure(data)

    def test_launch_target_must_be_a_known_app(self):
        content = gen.load_content(sample_content())
        gen.check_launch_targets(content, {"Demo"})
        with self.assertRaises(gen.ContentError):
            gen.check_launch_targets(content, {"Other"})


class CliTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.source = self.dir / "fonts.c"
        self.content = self.dir / "content.json"
        self.source.write_text(
            c_source(font_from(synthetic_glyphs())), encoding="utf-8"
        )
        self.write_content(sample_content())

    def tearDown(self):
        self.tmp.cleanup()

    def write_content(self, data):
        self.content.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")

    def args(self, out, *extra):
        return [
            "--source", str(self.source), "--symbol", SYMBOL, "--content", str(self.content),
            "--font-out", str(out / "lab_font.h"), "--content-out", str(out / "lab_content.h"),
            "--no-app-check", *extra,
        ]  # fmt: skip

    def main(self, *argv):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(
            io.StringIO()
        ):
            return gen.main(list(argv))

    def test_check_detects_stale_and_missing_outputs(self):
        font_h = self.dir / "lab_font.h"
        self.assertEqual(self.main(*self.args(self.dir)), 0)
        self.assertEqual(self.main(*self.args(self.dir, "--check")), 0)
        original = font_h.read_bytes()
        font_h.write_bytes(original.replace(b"0x", b"0X", 1))
        self.assertEqual(self.main(*self.args(self.dir, "--check")), 1)
        self.assertNotEqual(font_h.read_bytes(), original)  # --check writes nothing
        (self.dir / "lab_content.h").unlink()
        self.assertEqual(self.main(*self.args(self.dir, "--check")), 1)
        self.assertEqual(self.main(*self.args(self.dir)), 0)
        self.assertEqual(font_h.read_bytes(), original)
        self.assertEqual(self.main(*self.args(self.dir, "--check")), 0)

        changed = sample_content()
        changed["topics"][1]["pages"][1] = [
            "一"
        ]  # edited JSON, headers not regenerated
        self.write_content(changed)
        self.assertEqual(self.main(*self.args(self.dir, "--check")), 1)
        self.content.write_text("{", encoding="utf-8")
        self.assertEqual(self.main(*self.args(self.dir, "--check")), 2)

    def test_headers_describe_the_inputs(self):
        self.assertEqual(self.main(*self.args(self.dir)), 0)
        content_h = (self.dir / "lab_content.h").read_text(encoding="utf-8")
        defines = dict(re.findall(r"#define (LAB_\w+)\s+(\d+)", content_h))
        self.assertEqual(defines["LAB_TOPIC_COUNT"], "2")
        self.assertEqual(defines["LAB_ROWS"], "3")
        self.assertEqual(
            defines["LAB_TEXT_MAX_BYTES"], str(len("中文 OK".encode("utf-8")))
        )
        self.assertEqual(defines["LAB_RULE_BOTTOM"], "50")
        self.assertIn('.launch = "Demo",', content_h)
        self.assertIn(".launch = NULL,", content_h)
        self.assertIn('{"1/1", {"中文 OK", "g", ""}},', content_h)

        font = gen.parse_font(font_from(synthetic_glyphs()))
        codes = set(range(0x20, 0x7F)) | {
            ord("中"),
            ord("文"),
            ord("一"),
            ord("二"),
            ord("三"),
        }
        font_h = (self.dir / "lab_font.h").read_text(encoding="utf-8")
        self.assertEqual(header_bytes(font_h), gen.build_subset(font, codes))
        self.assertIn(f"#define LAB_FONT_GLYPHS {len(codes)}", font_h)

    def test_output_does_not_depend_on_hash_seed(self):
        outputs = set()
        for seed in ("0", "1", "4242"):
            out = self.dir / f"seed{seed}"
            out.mkdir()
            subprocess.run(
                [sys.executable, str(SCRIPT), *self.args(out)],
                check=True,
                capture_output=True,
                env={**os.environ, "PYTHONHASHSEED": seed, "PYTHONIOENCODING": "utf-8"},
            )
            outputs.add(
                (
                    (out / "lab_font.h").read_bytes(),
                    (out / "lab_content.h").read_bytes(),
                )
            )
        self.assertEqual(len(outputs), 1)


class RealFontTests(unittest.TestCase):
    def setUp(self):
        self.data, self.comment, self.font = real_font()
        self.metrics = gen.Metrics(self.font)

    def test_structure_matches_the_upstream_comment(self):
        glyphs = next(line for line in self.comment if line.startswith("Glyphs:"))
        count = int(glyphs.split(":")[1].split("/")[0])
        self.assertEqual(len(self.font.ascii) + len(self.font.unicode), count)
        self.assertEqual(self.data[0], count & 0xFF)
        self.assertEqual(len(self.data), 208526)
        self.assertEqual(tuple(self.font.params), (3, 2, 4, 4, 5, 5, 5))
        self.assertIn("Copyright: (null)", self.comment)
        self.assertTrue(any("wenquanyi bitmap song" in line for line in self.comment))
        self.assertIn(
            "(definition guarded by: #ifdef U8G2_USE_LARGE_FONTS)", self.comment
        )

    def test_known_glyphs_decode_as_drawn(self):
        dash = self.metrics.glyph(ord("-"))
        self.assertEqual(dash[:5], (5, 1, 0, 4, 6))
        self.assertEqual(dash.pixels, {(col, 0) for col in range(5)})
        bang = self.metrics.glyph(ord("!"))
        self.assertEqual(bang[:5], (1, 9, 2, 0, 6))
        self.assertEqual(bang.pixels, {(0, row) for row in (0, 1, 2, 3, 4, 5, 8)})

    def test_metrics_behind_the_layout(self):
        self.assertEqual(self.metrics.width("OK"), 13)
        self.assertEqual(self.metrics.width(" "), 6)
        self.assertEqual(self.metrics.width("-"), 5)
        for char in "中文说明":
            self.assertEqual(self.metrics.glyph(ord(char)).advance, 12, char)
        self.assertLessEqual(self.metrics.width("中文功能指南使用说明"), 120)

    def test_device_lookup_agrees_with_parser(self):
        for char in " Aaz~中文：←":
            payload = self.font.payload(ord(char))
            self.assertIsNotNone(payload, char)
            self.assertEqual(gen.u8g2_lookup(self.data, ord(char)), payload, char)
        self.assertIsNone(gen.u8g2_lookup(self.data, 0x3400))

    def test_missing_chinese_glyph_is_reported(self):
        with self.assertRaisesRegex(gen.FontError, r"U\+3400"):
            gen.build_subset(self.font, {ord("中"), 0x3400})


class GeneratedHeaderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        names = gen.known_launch_names(gen.DEFAULT_APPS_ROOT)
        cls.headers = gen.generate(
            gen.DEFAULT_SOURCE, gen.DEFAULT_SYMBOL, gen.DEFAULT_CONTENT, names
        )

    def test_font_header_holds_exactly_the_needed_glyphs(self):
        font_h = self.headers[0]
        data = header_bytes(font_h)
        subset, source = gen.parse_font(data), real_font()[2]
        text = "".join(real_content().strings())
        wanted = set(range(0x20, 0x7F)) | {ord(char) for char in text}
        self.assertEqual(set(subset.ascii) | set(subset.unicode), wanted)
        for code in wanted:
            self.assertEqual(
                subset.payload(code), source.payload(code), gen.describe(code)
            )
            self.assertEqual(gen.u8g2_lookup(data, code), source.payload(code))
        self.assertLess(len(data), 32 * 1024)
        self.assertIn(f"#define LAB_FONT_GLYPHS {len(wanted)}", font_h)
        self.assertIn("Copyright: (null)", font_h)

    def test_content_header_matches_json(self):
        content_h, content = self.headers[1], real_content()
        defines = dict(re.findall(r"#define (LAB_\w+)\s+(\d+)", content_h))
        self.assertEqual(int(defines["LAB_TOPIC_COUNT"]), len(content.topics))
        for topic in content.topics:
            self.assertIn(f"static const LabPage lab_pages_{topic.id}[]", content_h)
            self.assertIn(f".page_count = {len(topic.pages)},", content_h)
            launch = gen.c_string(topic.launch) if topic.launch else "NULL"
            self.assertIn(f".launch = {launch},", content_h)

    def test_generation_is_repeatable(self):
        again = gen.generate(
            gen.DEFAULT_SOURCE, gen.DEFAULT_SYMBOL, gen.DEFAULT_CONTENT
        )
        self.assertEqual(again, self.headers)

    def test_committed_headers_are_current(self):
        stderr = io.StringIO()
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(
            stderr
        ):
            status = gen.main(["--check"])
        self.assertEqual(
            status, 0, "run python scripts/generate_lab_font.py\n" + stderr.getvalue()
        )


class AppSourceTests(unittest.TestCase):
    def test_manifest(self):
        tree = ast.parse((LAB / "application.fam").read_text(encoding="utf-8"))
        (call,) = [
            n
            for n in ast.walk(tree)
            if isinstance(n, ast.Call) and getattr(n.func, "id", "") == "App"
        ]
        args = {kw.arg: kw.value for kw in call.keywords}
        self.assertEqual(args["apptype"].attr, "MENUEXTERNAL")
        stack = ast.fix_missing_locations(ast.Expression(body=args["stack_size"]))
        self.assertEqual(
            eval(compile(stack, "application.fam", "eval"), {"__builtins__": {}}), 3072
        )
        fields = {
            key: ast.literal_eval(args[key])
            for key in args
            if key not in ("apptype", "stack_size")
        }
        expected = {
            "appid": "lab", "name": "Flipper Lab", "entry_point": "lab_app",
            "requires": ["gui", "loader"], "icon": "A_Infrared_14", "order": 5,
            "fap_category": "Tools",
        }  # fmt: skip
        self.assertEqual({key: fields[key] for key in expected}, expected)
        self.assertNotIn("fap_icon", args)

    def test_launch_targets_are_existing_apps(self):
        names = gen.known_launch_names(gen.DEFAULT_APPS_ROOT)
        wanted = {
            "Bluetooth",
            "Infrared",
            "Sub-GHz",
            "NFC",
            "125 kHz RFID",
            "iButton",
            "GPIO",
        }
        self.assertTrue(wanted <= names, wanted - names)
        content = real_content()
        gen.check_launch_targets(content, names)
        self.assertEqual(
            {topic.launch for topic in content.topics if topic.launch}, wanted
        )

    def test_app_source_uses_generated_constants_only(self):
        source = (LAB / "lab_app.c").read_text(encoding="utf-8")
        generated = set(
            re.findall(r"#define (LAB_\w+)", gen.render_content_header(real_content()))
        )
        generated |= {"LAB_FONT_GLYPHS"} | set(re.findall(r"#define (LAB_\w+)", source))
        self.assertEqual(
            set(re.findall(r"\bLAB_[A-Z0-9_]+\b", source)) - generated, set()
        )
        includes = set(re.findall(r'#include [<"]([^>"]+)[>"]', source))
        allowed = {
            "furi.h",
            "gui/gui.h",
            "gui/elements.h",
            "input/input.h",
            "loader/loader.h",
        }
        self.assertEqual(includes, allowed | {"lab_content.h", "lab_font.h"})
        self.assertNotIn("furi_hal", source)  # no direct hardware access
        self.assertIn("furi_message_queue_put(app->queue, event, 0)", source)
        self.assertIn("canvas_set_custom_u8g2_font(canvas, lab_font)", source)


if __name__ == "__main__":
    unittest.main()
