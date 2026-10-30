"""Exercise generated manifests against FUS-managed Full and Light layouts."""

from pathlib import Path
import struct
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from update import Main


class FullStackOptionBytesTests(unittest.TestCase):
    def generate(self, stack="BLE_FULL", obdata=None, include_radio=True):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        directory = Path(temporary.name)
        stage = directory / "stage.bin"
        stage.write_bytes(b"stage fixture")
        arguments = [
            "generate",
            "-d",
            str(directory / "output"),
            "-v",
            "test",
            "-t",
            "f7",
            "--stage",
            str(stage),
            "--radiotype",
            stack,
            "--obdata",
            str(obdata or ROOT / "scripts/ob.data"),
        ]
        if include_radio:
            name = "full" if stack == "BLE_FULL" else "light"
            arguments += [
                "--radio",
                str(
                    ROOT
                    / "lib/stm32wb_copro/firmware"
                    / f"stm32wb5x_BLE_Stack_{name}_fw.bin"
                ),
            ]
        self.assertEqual(Main(no_exit=True)(arguments), 0)
        fields = dict(
            line.split(":", 1)
            for line in (directory / "output/update.fuf").read_text().splitlines()
            if ":" in line and not line.startswith("#")
        )
        return {
            key: struct.unpack("<32I", bytes.fromhex(fields[key]))
            for key in ("OB reference", "OB mask", "OB write mask")
        }

    def test_full_manifest_accepts_fus_selected_flash_and_ram_layout(self):
        # Restoring any Light-only layout comparison would reject valid Full OBs.
        full = self.generate()
        masks = full["OB mask"]
        references = full["OB reference"]
        # Only FSD/DDS and C2OPT/BRSD/NBRSD remain fixed in these registers.
        self.assertEqual(masks[28:32], (0x1100, 0x1100, 0xC0800000, 0xC0800000))
        self.assertEqual(references[28:32], (0x1000, 0x100, 0x80000000, 0x40800000))
        # Independently encoded example layout; these are not device readbacks.
        for actual, index in ((0x10CE, 28), (0x9E2B3800, 30)):
            self.assertEqual(actual & masks[index], references[index])

    def test_full_retains_static_protection_checks_and_all_write_masks(self):
        full = self.generate()
        light = self.generate("BLE_LIGHT")
        self.assertEqual(full["OB write mask"], light["OB write mask"])
        for field in ("OB reference", "OB mask"):
            self.assertEqual(full[field][:28], light[field][:28])
        for wrong, index in ((0x11CE, 28), (0x00, 28), (0x1E2B3800, 30)):
            self.assertNotEqual(
                wrong & full["OB mask"][index], full["OB reference"][index]
            )

    def test_light_and_no_radio_keep_existing_layout_requirements(self):
        for options in ({"stack": "BLE_LIGHT"}, {"include_radio": False}):
            with self.subTest(options=options):
                result = self.generate(**options)
                self.assertEqual(
                    result["OB mask"][28:32],
                    (0x11FF, 0x11FF, 0xFEFFFFFF, 0xFEFFFFFF),
                )
                self.assertEqual(result["OB reference"][28], 0x10D7)
                self.assertEqual(result["OB reference"][30], 0x964B5C00)

    def test_full_rejects_mutable_fus_layout_instead_of_hiding_write_request(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "unsafe-ob.data"
            original = (ROOT / "scripts/ob.data").read_text()
            for definition in (
                "SFSA:0xD7:r",
                "SBRV:0x35C00:r",
                "SBRSA:0x12:r",
                "SNBRSA:0xB:r",
            ):
                with self.subTest(definition=definition):
                    path.write_text(original.replace(definition, definition + "w"))
                    with self.assertRaisesRegex(
                        ValueError, "FUS.*" + definition.split(":")[0]
                    ):
                        self.generate(obdata=path)


if __name__ == "__main__":
    unittest.main()
