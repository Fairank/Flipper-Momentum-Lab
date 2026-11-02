"""Run the actual version builder without requiring SCons or a Git checkout."""

import ast
from pathlib import Path
import re
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ProtoVersionBuilderTests(unittest.TestCase):
    def generate(self, changelog):
        tree = ast.parse((ROOT / "scripts/fbt_tools/fbt_assets.py").read_text())
        function = next(
            n
            for n in tree.body
            if isinstance(n, ast.FunctionDef) and n.name == "_proto_ver_generator"
        )
        namespace = {"re": re, "StopError": RuntimeError}
        exec(
            compile(
                ast.Module(body=[function], type_ignores=[]), "version-builder", "exec"
            ),
            namespace,
        )
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            source, target = folder / "Changelog", folder / "protobuf_version.h"
            source.write_text(changelog, encoding="utf-8")
            namespace["_proto_ver_generator"]([target], [source], {})
            return target.read_text()

    def test_current_untagged_schema_advertises_its_actual_version_offline(self):
        result = self.generate((ROOT / "assets/protobuf/Changelog").read_text())
        self.assertIn("#define PROTOBUF_MAJOR_VERSION 0\n", result)
        self.assertIn("#define PROTOBUF_MINOR_VERSION 30\n", result)

    def test_first_release_wins_over_older_headers(self):
        result = self.generate("# Changelog\n\n## [2.4]\n### Added\n## [0.29]\n")
        self.assertIn("#define PROTOBUF_MAJOR_VERSION 2\n", result)
        self.assertIn("#define PROTOBUF_MINOR_VERSION 4\n", result)

    def test_missing_release_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "release header"):
            self.generate("# Changelog\n### Added\n")

    def test_malformed_latest_release_cannot_fall_back_to_old_version(self):
        with self.assertRaisesRegex(RuntimeError, "release header"):
            self.generate("## [Unreleased]\n## [0.29]\n")


if __name__ == "__main__":
    unittest.main()
