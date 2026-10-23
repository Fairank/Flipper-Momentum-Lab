"""Check the safety boundary and actual contents of the staged upgrade artifact."""

import struct
import unittest
import zlib
from scripts.prepare_native_ble_bootstrap import bootstrap_files, primary_extent


def image(size=512):
    data = bytearray(309 + size)
    struct.pack_into("<5sBIB", data, 0, b"DfuSe", 1, len(data) - 16, 1)
    struct.pack_into("<6sBI255sII", data, 11, b"Target", 0, 0, b"", size + 8, 1)
    struct.pack_into("<II", data, 285, 0x08000000, size)
    struct.pack_into("<II", data, 293, 0x20030000, 0x08000101)
    struct.pack_into("<I", data, len(data) - 4, ~zlib.crc32(data[:-4]) & 0xFFFFFFFF)
    return bytes(data)


def package(size=512, loader=b"verified loader"):
    crc = zlib.crc32(loader).to_bytes(4, "little").hex(" ").upper()
    return {
        "firmware.dfu": image(size),
        "updater.bin": loader,
        "radio.bin": b"must not be copied",
        "resources.tar.gz": b"must not be copied",
        "update.fuf": (
            "Target: 7\nInfo: test-build\nRadio version: 01 14 00 00 02 01\n"
            f"Radio address: 00 E0 0C 08\nLoader CRC: {crc}\n"
        ).encode(),
    }


class NativeBleBootstrapTests(unittest.TestCase):
    def test_primary_and_loader_preserved_without_radio_resources_or_ob(self):
        source = package()
        result = bootstrap_files(source)
        self.assertEqual(set(result), {"firmware.dfu", "updater.bin", "update.fuf"})
        self.assertEqual(result["firmware.dfu"], source["firmware.dfu"])
        self.assertEqual(result["updater.bin"], source["updater.bin"])
        fields = dict(
            line.split(":", 1) for line in result["update.fuf"].decode().splitlines()
        )
        for key in (
            "Radio",
            "Resources",
            "OB reference",
            "OB mask",
            "OB write mask",
            "Splashscreen",
        ):
            self.assertEqual(fields[key].strip(), "")

    def test_large_old_primary_is_detectable_but_never_packaged(self):
        self.assertGreater(primary_extent(image(869240)), 0x080CE000)
        with self.assertRaisesRegex(ValueError, "overlaps"):
            bootstrap_files(package(869240))

    def test_boundary_exact_fit_is_valid(self):
        self.assertEqual(primary_extent(image(0xCE000)), 0x080CE000)
        bootstrap_files(package(0xCE000))

    def test_corrupt_or_truncated_primary_is_rejected(self):
        damaged = bytearray(image())
        damaged[320] ^= 1
        for data in (bytes(damaged), image()[:-1], b"DfuSe"):
            with self.subTest(length=len(data)), self.assertRaises(ValueError):
                primary_extent(data)

    def test_invalid_loader_cannot_create_bootstrap(self):
        for loader in (b"", b"x" * 131073):
            with self.subTest(size=len(loader)), self.assertRaisesRegex(
                ValueError, "updater"
            ):
                bootstrap_files(package(loader=loader))
        files = package()
        files["updater.bin"] += b"changed"
        with self.assertRaisesRegex(ValueError, "updater"):
            bootstrap_files(files)


if __name__ == "__main__":
    unittest.main()
