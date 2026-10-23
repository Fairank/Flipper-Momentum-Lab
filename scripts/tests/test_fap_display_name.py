"""FAP display names use bounded UTF-8 while retaining the binary layout."""

from pathlib import Path
import struct
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from fbt.elfmanifest import ElfManifestV1, ElfManifestV1Ext


class FapDisplayNameTests(unittest.TestCase):
    def test_ascii_manifest_bytes_stay_identical(self):
        for cls, fmt, flags in (
            (ElfManifestV1, "<hI32s?32s", ()),
            (ElfManifestV1Ext, "<hI32s?32sB", (0,)),
        ):
            for name in ("Clock", "A" * 32, "Example Event Loop Stream Buffer"):
                self.assertEqual(
                    cls(2048, 1, name).as_bytes(),
                    struct.pack(fmt, 2048, 1, name.encode("ascii"), False, b"", *flags),
                )

    def test_chinese_round_trip_and_exact_byte_limit(self):
        for cls in (ElfManifestV1, ElfManifestV1Ext):
            for name in ("番茄钟", "SD 卡信息", "钟" * 10 + "A"):
                raw = cls(2048, 1, name).as_bytes()
                field = raw[6:38]
                self.assertEqual(field.split(b"\0", 1)[0].decode("utf-8"), name)
                self.assertEqual(field[-1], 0)

    def test_overlong_and_embedded_nul_fail_before_packing(self):
        for cls in (ElfManifestV1, ElfManifestV1Ext):
            for name in ("钟" * 11, "Clock\0hidden"):
                with self.subTest(cls=cls.__name__, name=name), self.assertRaises(
                    ValueError
                ):
                    cls(2048, 1, name).as_bytes()
