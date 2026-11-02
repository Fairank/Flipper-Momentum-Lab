#!/usr/bin/env python3
"""Render representative native submenu layouts from source labels and font pixels.

These are source layout previews, not firmware execution or device screenshots.
The 16 px rows, baseline, label width and rounded selection follow submenu.c;
Latin glyphs use FontSecondary and Chinese glyphs use native_zh_font.h.
"""

import argparse
import html
import json
from pathlib import Path
import re

from generate_lab_font import extract_font, parse_font, Metrics
from render_lab_preview import Frame, png_document

ROOT = Path(__file__).resolve().parents[1]
GUI = ROOT / "applications/services/gui"


def fonts():
    header = (GUI / "native_zh_font.h").read_text(encoding="utf-8")
    body = header.split("native_zh_font[] = {", 1)[1].split("};", 1)[0]
    cjk = Metrics(
        parse_font(bytes(int(v, 16) for v in re.findall(r"0x([0-9a-f]{2})", body)))
    )
    source = (ROOT / "lib/u8g2/u8g2_fonts.c").read_text(encoding="utf-8")
    latin, _ = extract_font(source, "u8g2_font_haxrcorp4089_tr")
    return Metrics(parse_font(latin)), cjk


def menu_labels(path):
    source = path.read_text(encoding="utf-8")
    # The preview takes the first four literal entries of these simple start scenes.
    # It does not evaluate state-dependent or dynamically named menu entries.
    labels = re.findall(
        r'submenu_add_(?:lockable_)?item\(\s*[^,]+,\s*("(?:\\.|[^"\\])*")', source
    )
    return [json.loads(label) for label in labels]


def render(labels, latin, cjk):
    frame = Frame(128, 64)

    def glyph(char):
        code = ord(char)
        return (latin if latin.font.payload(code) is not None else cjk).glyph(code)

    def width(text):
        drawn = [glyph(char) for char in text]
        if not drawn:
            return 0
        last = drawn[-1]
        return sum(g.advance for g in drawn[:-1]) + (
            last.width + last.x if last.width else last.advance
        )

    for row, label in enumerate(labels[:4]):
        top = row * 16
        if row == 0:
            # elements_slightly_rounded_box: one-pixel cut corners.
            frame.box(1, top + 1, 121, 14)
            frame.box(0, top + 2, 123, 12)
            frame.color = 0
        text = label
        if width(text) > 112:
            while text and width(text) > 112 - width("..."):
                text = text[:-1]
            text += "..."
        pen = 6
        baseline = top + 12
        for char in text:
            g = glyph(char)
            for col, y in g.pixels:
                frame.dot(pen + g.x + col, baseline - g.height - g.y + y)
            pen += g.advance
        frame.color = 1
    # elements_scrollbar, with the first item selected.
    for y in range(0, 64, 2):
        frame.dot(126, y)
    frame.box(125, 0, 3, max(1, int(64 / len(labels))))
    return frame


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    latin, cjk = fonts()
    entries = []
    for app, title, relative_path in (
        ("nfc", "NFC", "applications/main/nfc/scenes/nfc_scene_start.c"),
        (
            "infrared",
            "红外遥控",
            "applications/main/infrared/scenes/infrared_scene_start.c",
        ),
        ("subghz", "Sub-GHz", "applications/main/subghz/scenes/subghz_scene_start.c"),
        ("lfrfid", "低频 RFID", "applications/main/lfrfid/scenes/lfrfid_scene_start.c"),
        (
            "ibutton",
            "iButton",
            "applications/main/ibutton/scenes/ibutton_scene_start.c",
        ),
        (
            "hid",
            "蓝牙 / USB 遥控",
            "applications/system/hid_app/scenes/hid_scene_start.c",
        ),
    ):
        path = ROOT / relative_path
        labels = menu_labels(path)
        if not labels:
            raise ValueError(f"No literal submenu labels in {path}")
        frame = render(labels, latin, cjk)
        (args.output_dir / f"{app}.png").write_bytes(png_document(frame, 6))
        entries.append(
            {
                "title": title,
                "file": f"{app}.png",
                "source": path.relative_to(ROOT).as_posix(),
                "labels": labels,
            }
        )
    # A contact sheet uses the same rendered pixels; it is not a device capture.
    sheet = Frame(128 * 3 + 8 * 2, 64 * 2 + 8)
    for i, entry in enumerate(entries):
        frame = render(entry["labels"], latin, cjk)
        x, y = (i % 3) * 136, (i // 3) * 72
        for row in range(64):
            for col in range(128):
                sheet.color = frame.bits[row * 128 + col]
                sheet.dot(x + col, y + row)
    (args.output_dir / "native-contact-sheet.png").write_bytes(png_document(sheet, 3))
    (args.output_dir / "manifest.json").write_text(
        json.dumps(entries, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    cards = "".join(
        f'<section><h2>{html.escape(item["title"])}</h2><img src="{item["file"]}" alt="{html.escape(item["title"])} 中文菜单"><p>{html.escape(item["source"])}</p></section>'
        for item in entries
    )
    (args.output_dir / "index.html").write_text(
        """<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Flipper 原生中文预览</title><style>body{background:#f5f5f7;color:#202020;font:16px/1.6 system-ui;max-width:1000px;margin:32px auto;padding:0 20px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:24px}section{background:white;border-radius:16px;padding:20px}img{width:100%;image-rendering:pixelated}p{overflow-wrap:anywhere;color:#555}</style><h1>Flipper 原生中文菜单</h1><p>源码布局预览，非真机截图。按当前菜单文案、16 像素行高和实际字库像素渲染；不执行固件，不验证硬件操作，也不模拟条件分支或自定义主题。</p><main>"""
        + cards
        + "</main></html>",
        encoding="utf-8",
    )
    print(f"Rendered {len(entries)} native source previews: {args.output_dir}")


if __name__ == "__main__":
    main()
