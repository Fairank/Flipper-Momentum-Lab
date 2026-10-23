"""Run real FatFs on a RAM disk and the real RPC read handler with recording I/O.

These host regressions do not replace device, USB/BLE or SD-card acceptance.
The RAM disk is isolated from all physical drives.
"""

from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).parent / "fixtures"


def compiler():
    found = next((x for n in ("cc", "gcc", "clang") if (x := shutil.which(n))), None)
    if not found and sys.platform == "win32":
        shim = ROOT.parent / "flipper-tools/cc.cmd"
        if shim.is_file():
            found = str(shim)
    if not found:
        raise AssertionError("A host C compiler is required; these tests must not skip")
    return found


def build(folder, sources, name, flags=()):
    output = folder / (name + (".exe" if sys.platform == "win32" else ""))
    cmd = [compiler(), "-std=c11", "-O1", "-g"]
    if sys.platform.startswith("linux"):
        cmd += ["-fsanitize=address,undefined", "-fno-sanitize-recover=all"]
    cmd += list(flags) + [str(p) for p in sources] + ["-o", str(output)]
    env = os.environ.copy()
    env["ZIG_GLOBAL_CACHE_DIR"] = str(folder / "zig-global")
    env["ZIG_LOCAL_CACHE_DIR"] = str(folder / "zig-local")
    result = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=180)
    if result.returncode:
        raise AssertionError(f"{name} build failed:\n{result.stdout}{result.stderr}")
    return output


def build_fatfs(folder, source=None):
    config = (ROOT / "lib/fatfs/ffconf_template.h").read_text(encoding="utf-8")
    switches = {
        "_FS_EXFAT": 1,
        "_FS_NORTC": 1,
        "_FS_REENTRANT": 0,
        "_FS_LOCK": 0,
        "_VOLUMES": 1,
    }
    for key, value in switches.items():
        config, count = re.subn(
            r"(^#define\s+" + key + r"\s+)\d+",
            lambda m: m[1] + str(value),
            config,
            flags=re.M,
        )
        if count != 1:
            raise AssertionError(f"Missing configuration switch: {key}")
    (folder / "ffconf.h").write_text(config, encoding="utf-8")
    return build(
        folder,
        [
            source or ROOT / "lib/fatfs/ff.c",
            ROOT / "lib/fatfs/option/ccsbcs.c",
            FIXTURES / "fatfs_exfat.c",
        ],
        "fatfs_exfat",
        [
            "-I" + str(folder),
            "-I" + str(ROOT / "lib/fatfs"),
            "-include",
            "stdlib.h",
            "-ftrivial-auto-var-init=pattern",
        ],
    )


def build_rpc(folder, source=None):
    production = (source or ROOT / "applications/services/rpc/rpc_storage.c").read_text(
        encoding="utf-8"
    )
    handler = re.search(
        r"static void rpc_system_storage_read_process\([^)]*\)\s*\{.*?^\}",
        production,
        re.S | re.M,
    )
    if handler is None:
        raise AssertionError("Production storage read handler missing")
    text = (FIXTURES / "rpc_storage_read.c").read_text(encoding="utf-8")
    source = folder / "rpc_storage_read.c"
    source.write_text(
        text.replace("/* PRODUCTION_HANDLER */", handler[0]), encoding="utf-8"
    )
    return build(folder, [source], "rpc_storage_read", ["-Wall", "-Wextra", "-Werror"])


class StorageUpgradeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temporary = tempfile.TemporaryDirectory(prefix="flipper-storage-")
        cls.addClassCleanup(temporary.cleanup)
        folder = Path(temporary.name)
        cls.fatfs = build_fatfs(folder)
        cls.rpc = build_rpc(folder)

    def scenario(self, executable, value, marker):
        result = subprocess.run(
            [str(executable), str(value)], capture_output=True, text=True, timeout=45
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(marker, result.stdout)

    def test_exfat_fragmented_root_directory_persists_file_sizes_and_contents(self):
        self.scenario(self.fatfs, "root", "FatFs scenario passed")

    def test_exfat_fragmented_subdirectory_persists_after_remount(self):
        self.scenario(self.fatfs, "directory", "FatFs scenario passed")

    def test_exfat_existing_fragmented_file_ignores_poisoned_previous_object(self):
        self.scenario(self.fatfs, "reopen", "FatFs scenario passed")

    def test_exfat_truncation_restores_contiguous_chain_state(self):
        self.scenario(self.fatfs, "truncate", "FatFs scenario passed")

    def test_rpc_ranges_legacy_full_reads_boundaries_and_errors(self):
        for case in range(12):
            with self.subTest(case=case):
                self.scenario(self.rpc, case, "RPC read scenario passed")


if __name__ == "__main__":
    unittest.main()
