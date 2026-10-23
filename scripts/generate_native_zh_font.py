#!/usr/bin/env python3
"""Build the native UI's CJK fallback from literal characters in application source.

Reuses the checked u8g2 subset parser; never bundles the full 200 KiB font.
"""
import argparse
import ast
from pathlib import Path
import re
import sys

from generate_lab_font import (
    extract_font,
    parse_font,
    build_subset,
    verify_subset,
    render_font_header,
)

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "applications/services/gui/native_zh_font.h"
UPDATER_OUTPUT = ROOT / "applications/services/gui/updater_zh_font.h"
UPDATER_DIRECTORIES = (
    "applications/system/updater",
    "applications/services/gui",
    "applications/services/dialogs",
)
TOKEN = re.compile(r'/\*.*?\*/|//[^\n]*|"((?:\\.|[^"\\])*)"', re.S)


def required_characters(updater=False):
    # canvas_glyph_needs_fallback() only selects this font for CJK. ASCII always
    # uses the selected stock/asset font; duplicating it here wastes flash space.
    # The updater additionally restricts the CJK subset to its own source scopes.
    codes = set()
    directories = (
        UPDATER_DIRECTORIES if updater else ("applications", "applications_user")
    )
    for directory in directories:
        for path in sorted((ROOT / directory).rglob("*")):
            if path.suffix == ".fam":
                # Manifest identifiers are not labels. Collect only literal app
                # names, including adjacent strings, without executing manifests.
                tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
                for node in ast.walk(tree):
                    if isinstance(node, ast.keyword) and node.arg == "name":
                        if isinstance(node.value, ast.Constant) and isinstance(
                            node.value.value, str
                        ):
                            codes.update(
                                ord(c)
                                for c in node.value.value
                                if 0x3000 <= ord(c) <= 0x9FFF
                                or 0xFF01 <= ord(c) <= 0xFFEF
                            )
                continue
            if path.suffix not in (
                ".c",
                ".cc",
                ".cpp",
                ".cxx",
                ".h",
                ".hh",
                ".hpp",
                ".hxx",
            ) or path.name.endswith("_font.h"):
                continue
            # Some vendored apps have legacy encoded comments. Preserve their
            # bytes as surrogates, without losing valid UTF-8 UI literals.
            for match in TOKEN.finditer(
                path.read_text(encoding="utf-8", errors="surrogateescape")
            ):
                literal = match.group(1)
                if literal is not None:
                    codes.update(
                        ord(c)
                        for c in literal
                        if 0x3000 <= ord(c) <= 0x9FFF or 0xFF01 <= ord(c) <= 0xFFEF
                    )
    return codes


def generate(updater=False):
    source = ROOT / "lib/u8g2/u8g2_fonts.c"
    symbol = "u8g2_font_wqy12_t_gb2312"
    data, comment = extract_font(source.read_text(encoding="utf-8"), symbol)
    font = parse_font(data)
    codes = required_characters(updater)
    subset_data = build_subset(font, codes)
    subset = verify_subset(font, subset_data, codes)
    header = render_font_header(
        subset_data, subset, comment, "lib/u8g2/u8g2_fonts.c", symbol, data
    )
    header = header.replace(
        "scripts/generate_lab_font.py", "scripts/generate_native_zh_font.py"
    )
    header = header.replace(
        "Flipper Lab: printable ASCII plus every character in\n * lab_content.json",
        (
            "RAM updater: CJK literals in updater and shared GUI/dialog sources"
            if updater
            else "native UI: CJK literals in\n * native, system, service, external and user application sources"
        ),
    )
    header = header.replace(
        "see FONT_LICENSE.md beside this file",
        "see applications/main/lab/FONT_LICENSE.md",
    )
    header = header.replace(
        "LAB_FONT_GLYPHS",
        "UPDATER_ZH_FONT_GLYPHS" if updater else "NATIVE_ZH_FONT_GLYPHS",
    ).replace("lab_font[]", "updater_zh_font[]" if updater else "native_zh_font[]")
    if updater:
        header = header.replace(
            "scripts/generate_native_zh_font.py",
            "scripts/generate_native_zh_font.py --updater",
        )
    return header


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument(
        "--updater", action="store_true", help="Generate the small RAM updater subset"
    )
    args = parser.parse_args()
    text = generate(args.updater)
    output_path = UPDATER_OUTPUT if args.updater else OUTPUT
    if args.check:
        if not output_path.exists() or output_path.read_text(encoding="utf-8") != text:
            print(
                "Chinese font is stale; run scripts/generate_native_zh_font.py"
                + (" --updater" if args.updater else ""),
                file=sys.stderr,
            )
            return 1
    else:
        with output_path.open("w", encoding="utf-8", newline="\n") as output:
            output.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
