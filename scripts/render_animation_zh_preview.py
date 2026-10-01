#!/usr/bin/env python3
"""Render stock desktop captions from the production C draw calls and source font.

Requires a host C compiler and Pillow. Output is a source layout preview, not a
device screenshot: it does not execute FreeRTOS, the GUI cache, or animation timing.
The PNG assets are read as backgrounds and are never modified.
"""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from PIL import Image
from render_lab_preview import Frame, png_document
from render_native_zh_preview import fonts

ROOT = Path(__file__).resolve().parents[1]
VIEWS = ROOT / "applications/services/desktop/animations/views"
SCENES = [
    ("动画错误", "internal/L1_AnimationError_128x64", 1),
    ("插入存储卡", "internal/L1_NoSd_128x49", 2),
    ("电池异常", "internal/L1_BadBattery_128x47", 3),
    ("缺少数据库", "blocking/L0_NoDb_128x51", 4),
    ("存储卡错误", "blocking/L0_SdBad_128x51", 5),
    ("存储卡就绪", "blocking/L0_SdOk_128x51", 6),
    ("更新地址", "blocking/L0_Url_128x51", 7),
    ("新邮件", "blocking/L0_NewMail_128x51", 8),
    ("等级提升", None, 9),
]
STUBS = r"""
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
typedef int Canvas;
enum { FontSecondary, AlignCenter, AlignBottom, ColorWhite=0, ColorBlack=1 };
static int color=1;
static void canvas_set_color(Canvas* c,int v){(void)c;color=v;}
static void canvas_set_font(Canvas* c,int v){(void)c;(void)v;}
static void canvas_draw_box(Canvas* c,int x,int y,int w,int h){(void)c;printf("B %d %d %d %d %d\n",color,x,y,w,h);}
static void canvas_draw_rframe(Canvas* c,int x,int y,int w,int h,int r){(void)c;printf("R %d %d %d %d %d %d\n",color,x,y,w,h,r);}
static void canvas_draw_str_aligned(Canvas* c,int x,int y,int h,int v,const char* text){(void)c;(void)h;(void)v;printf("T %d %d %d %s\n",color,x,y,text);}
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    compiler = shutil.which("cc")
    if not compiler:
        parser.error("A host C compiler is required")
    clean = lambda text: re.sub(r"^#(?:include|pragma).*\n", "", text, flags=re.M)
    source = STUBS + clean((VIEWS / "animation_caption.h").read_text(encoding="utf-8"))
    source += "\n#include <string.h>\n" + clean(
        (VIEWS / "animation_caption.c").read_text(encoding="utf-8")
    )
    source += r"""
int main(int argc,char** argv){if(argc!=3)return 1;Canvas c=0;int code=atoi(argv[1]);
if(code==9)animation_caption_draw_levelup(&c);else animation_caption_draw(&c,(AnimationCaption)code,atoi(argv[2]));return 0;}
"""
    latin, cjk = fonts()

    def glyph(char):
        code = ord(char)
        return (latin if latin.font.payload(code) is not None else cjk).glyph(code)

    frames, entries = [], []
    with tempfile.TemporaryDirectory() as directory:
        code = Path(directory) / "caption.c"
        exe = Path(directory) / "caption.exe"
        code.write_text(source, encoding="utf-8")
        subprocess.run([compiler, "-std=c11", str(code), "-o", str(exe)], check=True)
        for title, asset, index in SCENES:
            path = (
                ROOT
                / "assets"
                / (
                    f"dolphin/{asset}/frame_0.png"
                    if asset
                    else "icons/Animations/Levelup_128x64/frame_09.png"
                )
            )
            with Image.open(path) as original:
                pixels = original.convert("1")
                width, height = pixels.size
                frame = Frame(128, 64)
                for y in range(height):
                    for x in range(width):
                        frame.color = int(pixels.getpixel((x, y)) == 0)
                        frame.dot(x, y + 64 - height)
            trace = subprocess.check_output(
                [str(exe), str(index), str(64 - height)], text=True, encoding="utf-8"
            )
            if not trace.strip():
                raise RuntimeError(f"Caption {index} emitted no draw calls")
            for line in trace.splitlines():
                kind, color, rest = line.split(" ", 2)
                frame.color = int(color)
                if kind == "T":
                    x, y, text = rest.split(" ", 2)
                    gs = [glyph(c) for c in text]
                    size = sum(g.advance for g in gs[:-1]) + gs[-1].width + gs[-1].x
                    pen, baseline = int(x) - size // 2, int(y)
                    for g in gs:
                        for dx, dy in g.pixels:
                            frame.dot(pen + g.x + dx, baseline - g.height - g.y + dy)
                        pen += g.advance
                else:
                    x, y, width, height, *radius = map(int, rest.split())
                    if kind == "B":
                        frame.box(x, y, width, height)
                    else:
                        # Radius-two stock button outline, one-pixel raster border.
                        frame.hline(x + 2, x + width - 3, y)
                        frame.hline(x + 2, x + width - 3, y + height - 1)
                        for py in range(y + 2, y + height - 2):
                            frame.dot(x, py)
                            frame.dot(x + width - 1, py)
                        for px, py in (
                            (x + 1, y + 1),
                            (x + width - 2, y + 1),
                            (x + 1, y + height - 2),
                            (x + width - 2, y + height - 2),
                        ):
                            frame.dot(px, py)
            frames.append(frame)
            entries.append(
                {
                    "title": title,
                    "file": f"{index:02d}.png",
                    "asset": path.relative_to(ROOT).as_posix(),
                    "draw_calls": trace.splitlines(),
                }
            )
    args.output_dir.mkdir(parents=True, exist_ok=True)
    sheet = Frame(400, 208)
    for i, frame in enumerate(frames):
        (args.output_dir / entries[i]["file"]).write_bytes(png_document(frame, 6))
        for y in range(64):
            for x in range(128):
                sheet.color = frame.bits[y * 128 + x]
                sheet.dot((i % 3) * 136 + x, (i // 3) * 72 + y)
    (args.output_dir / "animation-contact-sheet.png").write_bytes(
        png_document(sheet, 3)
    )
    (args.output_dir / "manifest.json").write_text(
        json.dumps(
            {"kind": "source layout preview, not hardware capture", "screens": entries},
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"Rendered {len(frames)} caption source previews")


if __name__ == "__main__":
    main()
