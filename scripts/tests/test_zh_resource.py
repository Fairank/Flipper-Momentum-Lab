"""Run the actual C glyph decoder and compare every SD glyph to the licensed source."""

from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import generate_zh_resource as resource
from generate_lab_font import extract_font, parse_font, decode_glyph

HARNESS = r"""
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "applications/services/gui/native_zh_resource_format.c"
int main(int argc, char** argv) {
    assert(argc == 3);
    FILE* input = fopen(argv[1], "rb");
    FILE* output = fopen(argv[2], "wb");
    assert(input && output);
    uint32_t offset;
    assert(!native_zh_record_offset(0x2fff, &offset));
    assert(!native_zh_record_offset(0xa000, &offset));
    assert(!native_zh_record_offset(0xfff0, &offset));
    assert(!native_zh_record_offset(0x4e00, NULL));
    uint8_t record[32], font[128];
    for(uint32_t code = 0x3000; code <= 0xffef; ++code) {
        if(!native_zh_record_offset(code, &offset)) continue;
        assert(fseek(input, offset, SEEK_SET) == 0 && fread(record, 1, 32, input) == 32);
        if(record[0] == 0 && record[1] == 0) continue;
        assert(native_zh_record_font(code, record, font));
        assert(fwrite(font, 1, 128, output) == 128);
        uint8_t extent;
        assert(native_zh_glyph_metrics(code, &extent) == record[6] - 128);
        assert(extent == (record[2] ? record[2] + record[4] - 128 : 0));
        uint8_t saved = record[2];
        record[2] = 13;
        assert(!native_zh_record_font(code, record, font));
        record[2] = saved;
        record[31] = 1;
        assert(!native_zh_record_font(code, record, font));
    }
    memset(record, 0, sizeof(record));
    record[0] = 0x4e; record[1] = 0x00;
    record[2] = record[3] = 12;
    record[4] = record[5] = 128; record[6] = 140;
    memset(record + 8, 0xaa, 18); // worst-case alternating pixels
    assert(native_zh_record_font(0x4e00, record, font));
    assert(fwrite(font, 1, 128, output) == 128);
    assert(!native_zh_record_font(0x4e01, record, font));
    assert(!native_zh_record_font(0x4e00, NULL, font));
    assert(!native_zh_record_font(0x4e00, record, NULL));
    fclose(input); fclose(output);
    return 0;
}
"""


class SDGlyphTests(unittest.TestCase):
    def test_every_resource_glyph_round_trips_through_production_c(self):
        compiler = shutil.which("cc")
        if not compiler:
            self.skipTest("host C compiler required")
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            source, executable, output = (
                folder / name for name in ("test.c", "test", "fonts.bin")
            )
            source.write_text(HARNESS)
            command = [compiler, "-std=c11", "-Wall", "-Wextra", "-Werror", "-I."]
            if sys.platform.startswith("linux"):
                command += [
                    "-fsanitize=address,undefined",
                    "-fno-omit-frame-pointer",
                    "-O1",
                ]
            command += [str(source), "-o", str(executable)]
            subprocess.run(command, cwd=ROOT, check=True, capture_output=True)
            subprocess.run(
                [str(executable), str(resource.RESOURCE), str(output)],
                check=True,
                timeout=60,
            )
            data = output.read_bytes()
        original, _ = extract_font(
            (ROOT / "lib/u8g2/u8g2_fonts.c").read_text(), "u8g2_font_wqy12_t_gb2312"
        )
        font = parse_font(original)
        codes = sorted(
            code
            for code in font.unicode
            if 0x3000 <= code <= 0x9FFF or 0xFF01 <= code <= 0xFFEF
        )
        self.assertEqual(len(data), (len(codes) + 1) * 128)
        for index, code in enumerate(codes):
            packed = data[index * 128 : (index + 1) * 128]
            rebuilt = parse_font(packed[: 31 + packed[31]])
            actual = decode_glyph(rebuilt.params, rebuilt.payload(code))
            expected = decode_glyph(font.params, font.payload(code))
            # The bounded renderer uses a different RLE bit width; pixels and
            # metrics, rather than compression length, must be identical.
            self.assertEqual(
                actual._replace(bits=expected.bits), expected, f"U+{code:04X}"
            )
        packed = data[-128:]
        rebuilt = parse_font(packed[: 31 + packed[31]])
        glyph = decode_glyph(rebuilt.params, rebuilt.payload(0x4E00))
        self.assertEqual(
            glyph.pixels,
            frozenset((x, y) for y in range(12) for x in range(12) if (y * 12 + x) % 2),
        )

    def test_generated_resources_are_current(self):
        data, meta, boot = resource.generate()
        self.assertEqual(resource.RESOURCE.read_bytes(), data)
        self.assertEqual(resource.META.read_text(), meta)
        self.assertEqual(resource.BOOT.read_text(), boot)


if __name__ == "__main__":
    unittest.main()
