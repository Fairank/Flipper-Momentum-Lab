"""Imported remotes must load on the existing firmware without fabricated signals."""

import importlib
import json
from pathlib import Path
import tempfile
import unittest
import zipfile


HEADER = b"Filetype: IR signals file\nVersion: 1\n#\n"
POWER = b"name: Power\ntype: parsed\nprotocol: NEC\naddress: 01 00 00 00\ncommand: 15 00 00 00\n"
RAW = b"name: Cool_24\ntype: raw\nfrequency: 38000\nduty_cycle: 0.33\ndata: 9000 4500 560 560\n"
LIMITS = {"NEC": (8, 8), "NECext": (16, 16)}


class InfraredLibraryTests(unittest.TestCase):
    def setUp(self):
        try:
            self.library = importlib.import_module("scripts.build_infrared_library")
        except ModuleNotFoundError:
            self.fail("The compatible IR library importer has not been implemented")

    def test_parsed_little_endian_payload_is_preserved(self):
        data, report = self.library.normalise_remote(
            HEADER + b"# Captured model note  \n" + POWER, LIMITS
        )
        self.assertIn(b"# Captured model note\n", data)
        self.assertFalse(any(line.rstrip() != line for line in data.splitlines()))
        self.assertIn(b"address: 01 00 00 00\ncommand: 15 00 00 00\n", data)
        self.assertEqual(report["signals"], 1)
        self.assertEqual(report["rejected"], [])

    def test_raw_waveform_is_not_decoded_or_truncated(self):
        data, report = self.library.normalise_remote(HEADER + RAW, LIMITS)
        self.assertIn(b"data: 9000 4500 560 560\n", data)
        self.assertEqual(report["raw"], 1)
        self.assertEqual(report["signals"], 1)

    def test_overlong_and_nonfinite_raw_records_are_excluded(self):
        long_raw = RAW.replace(b"9000 4500 560 560", b" ".join([b"560"] * 1025))
        nan_raw = RAW.replace(b"0.33", b"nan")
        data, report = self.library.normalise_remote(
            HEADER + long_raw + nan_raw + POWER, LIMITS
        )
        self.assertEqual(data.count(b"name:"), 1)
        self.assertEqual(report["signals"], 1)
        self.assertEqual(len(report["rejected"]), 2)

    def test_unknown_protocol_and_out_of_range_payload_are_excluded(self):
        unknown = POWER.replace(b"protocol: NEC", b"protocol: ImaginaryAC")
        bad = POWER.replace(b"address: 01 00 00 00", b"address: 00 01 00 00")
        data, report = self.library.normalise_remote(
            HEADER + unknown + bad + RAW, LIMITS
        )
        self.assertEqual(data.count(b"name:"), 1)
        self.assertEqual(len(report["rejected"]), 2)

    def test_duplicate_names_are_unambiguous_without_losing_distinct_payloads(self):
        data, report = self.library.normalise_remote(
            HEADER + POWER + POWER.replace(b"15 00", b"16 00") + POWER, LIMITS
        )
        names = [line for line in data.splitlines() if line.startswith(b"name:")]
        self.assertEqual(len(names), 2)
        self.assertEqual(len(set(names)), 2)
        self.assertIn(b"command: 15 00 00 00", data)
        self.assertIn(b"command: 16 00 00 00", data)
        self.assertEqual(report["duplicates_removed"], 1)

    def test_universal_library_cannot_be_mislabelled_as_a_saved_remote(self):
        with self.assertRaises(ValueError):
            self.library.normalise_remote(
                HEADER.replace(b"IR signals file", b"IR library file") + POWER, LIMITS
            )

    def test_manifest_preserves_origin_and_case_collisions_keep_both_files(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source.zip"
            with zipfile.ZipFile(source, "w") as archive:
                archive.writestr("snapshot/LICENSE", "CC0 1.0 Universal\n")
                archive.writestr("snapshot/TVs/LG/Remote.ir", HEADER + POWER)
                archive.writestr("snapshot/TVs/LG/remote.ir", HEADER + RAW)
                archive.writestr("snapshot/_Converted_/no.ir", HEADER + POWER)
            output = root / "More_Remotes"
            report = self.library.build_library(source, output, "0" * 40, LIMITS)
            files = list(output.rglob("*.ir"))
            self.assertEqual(len(files), 2)
            self.assertEqual(
                len({str(p.relative_to(output)).casefold() for p in files}), 2
            )
            self.assertEqual(report["files"], 2)
            self.assertEqual(report["signals"], 2)
            manifest = json.loads((output / "catalog.json").read_text())
            self.assertEqual(
                {e["source_path"] for e in manifest["entries"]},
                {"TVs/LG/Remote.ir", "TVs/LG/remote.ir"},
            )
            self.assertEqual(
                (output / "LICENSE-CC0.txt").read_text(), "CC0 1.0 Universal\n"
            )
            self.assertFalse(any("Converted" in str(p) for p in files))

    def test_archive_traversal_is_rejected_before_creating_output(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source.zip"
            with zipfile.ZipFile(source, "w") as archive:
                archive.writestr("snapshot/TVs/../../escape.ir", HEADER + POWER)
                archive.writestr("snapshot/LICENSE", "CC0 1.0 Universal\n")
            with self.assertRaises(ValueError):
                self.library.build_library(source, root / "out", "0" * 40, LIMITS)
            self.assertFalse((root / "out").exists())

    def test_existing_library_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / "out"
            output.mkdir()
            marker = output / "mine.ir"
            marker.write_bytes(HEADER + POWER)
            with self.assertRaises(FileExistsError):
                self.library.build_library(
                    Path(temp) / "unused.zip", output, "0" * 40, LIMITS
                )
            self.assertEqual(marker.read_bytes(), HEADER + POWER)

    def test_long_model_name_keeps_extension_visible_to_the_device(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source.zip"
            with zipfile.ZipFile(source, "w") as archive:
                archive.writestr("snapshot/LICENSE", "CC0 1.0 Universal\n")
                archive.writestr("snapshot/TVs/LG/" + "x" * 120 + ".ir", HEADER + POWER)
            self.library.build_library(source, root / "out", "0" * 40, LIMITS)
            self.assertEqual(len(list((root / "out").rglob("*.ir"))), 1)

    def test_long_brand_series_and_model_fit_the_firmware_resource_tar(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source.zip"
            with zipfile.ZipFile(source, "w") as archive:
                archive.writestr("snapshot/LICENSE", "CC0 1.0 Universal\n")
                archive.writestr(
                    "snapshot/Audio_and_Video_Receivers/"
                    + "Brand" * 16
                    + "/Series/"
                    + "Model" * 24
                    + ".ir",
                    HEADER + POWER,
                )
            self.library.build_library(source, root / "out", "0" * 40, LIMITS)
            files = list((root / "out").rglob("*.ir"))
            self.assertEqual(len(files), 1)
            self.assertLessEqual(
                len(
                    "infrared/More_Remotes/"
                    + files[0].relative_to(root / "out").as_posix()
                ),
                100,
            )


if __name__ == "__main__":
    unittest.main()
