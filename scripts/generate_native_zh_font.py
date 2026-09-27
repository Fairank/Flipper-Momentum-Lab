#!/usr/bin/env python3
"""Build the native UI's CJK fallback from literal characters in first-party source.

Reuses the checked u8g2 subset parser; never bundles the full 200 KiB font.
"""
import argparse
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
TOKEN = re.compile(r'/\*.*?\*/|//[^\n]*|"((?:\\.|[^"\\])*)"', re.S)


def required_characters():
    codes = set(range(32, 127))
    for directory in (
        "applications/main",
        "applications/settings",
        "applications/services/gui",
        "applications/services/desktop",
        "applications/services/loader",
        "applications/services/locale",
    ):
        for path in sorted((ROOT / directory).rglob("*")):
            if path.suffix not in (".c", ".h") or path.name.endswith("_font.h"):
                continue
            for match in TOKEN.finditer(path.read_text(encoding="utf-8")):
                literal = match.group(1)
                if literal is not None:
                    codes.update(
                        ord(c)
                        for c in literal
                        if 0x3000 <= ord(c) <= 0x9FFF or 0xFF01 <= ord(c) <= 0xFFEF
                    )
    return codes


def generate():
    source = ROOT / "lib/u8g2/u8g2_fonts.c"
    symbol = "u8g2_font_wqy12_t_gb2312"
    data, comment = extract_font(source.read_text(encoding="utf-8"), symbol)
    font = parse_font(data)
    codes = required_characters()
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
        "native UI: printable ASCII plus CJK literals in\n * first-party native app, settings, desktop and GUI sources",
    )
    header = header.replace(
        "see FONT_LICENSE.md beside this file",
        "see applications/main/lab/FONT_LICENSE.md",
    )
    header = header.replace("LAB_FONT_GLYPHS", "NATIVE_ZH_FONT_GLYPHS").replace(
        "lab_font[]", "native_zh_font[]"
    )
    return header


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    text = generate()
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != text:
            print(
                "Native Chinese font is stale; run scripts/generate_native_zh_font.py",
                file=sys.stderr,
            )
            return 1
    else:
        with OUTPUT.open("w", encoding="utf-8", newline="\n") as output:
            output.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
