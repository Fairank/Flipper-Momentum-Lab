"""Replay the actual Nearby Radar draw callback with labelled example observations.

This compiles the production drawing code against a recording canvas. The images
are source layout previews, not device screenshots or radio scan results.
Requires a host C compiler and Pillow.
"""

import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFont
from generate_lab_font import Metrics, extract_font, parse_font
from tests.test_storage_upgrade import build

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    source = (ROOT / "applications/main/nearby_radar/nearby_radar.c").read_text()
    model = re.search(r"typedef struct \{.*?\} RadarModel;", source, re.S)[0]
    drawing = source[
        source.index("static void label(") : source.index("static void filter_done(")
    ]
    font_source = (ROOT / "lib/u8g2/u8g2_fonts.c").read_text()
    fonts = [
        Metrics(parse_font(extract_font(font_source, name)[0]))
        for name in ("u8g2_font_helvB08_tr", "u8g2_font_haxrcorp4089_tr")
    ]
    tables = []
    for font in fonts:
        tables.append(
            "{"
            + ",".join(
                (
                    "{%d,%d,%d}"
                    % (font.glyph(i).advance, font.glyph(i).width, font.glyph(i).x)
                    if 32 <= i < 127
                    else "{0,0,0}"
                )
                for i in range(128)
            )
            + "}"
        )
    harness = (
        r"""
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "radar_core.h"
typedef struct { int font,color; } Canvas;
enum { FontPrimary,FontSecondary };
static const int metrics[2][128][3]=TABLES;
static void canvas_set_font(Canvas* c,int f){c->font=f;}
static unsigned canvas_string_width(Canvas* c,const char* s){
    int width=0;const int* last=NULL;
    while(*s){last=metrics[c->font][(unsigned char)*s++&127];width+=last[0];}
    if(last && last[1])width+=last[1]+last[2]-last[0];return width;
}
static void canvas_draw_str(Canvas*c,int x,int y,const char*s){printf("s %d %d %d %d %s\n",c->font,c->color,x,y,s);}
static void canvas_draw_box(Canvas*c,int x,int y,int w,int h){printf("b %d %d %d %d %d\n",c->color,x,y,w,h);}
static void canvas_draw_circle(Canvas*c,int x,int y,int r){printf("c %d %d %d %d\n",c->color,x,y,r);}
static void canvas_draw_disc(Canvas*c,int x,int y,int r){printf("d %d %d %d %d\n",c->color,x,y,r);}
static void canvas_draw_dot(Canvas*c,int x,int y){printf("p %d %d %d\n",c->color,x,y);}
static void canvas_invert_color(Canvas*c){c->color^=1;}
MODEL
DRAWING
static void feed(RadarCore*c,const char*s,unsigned now){while(*s)radar_feed(c,*s++,now);}
int main(int argc,char**argv){
    setvbuf(stdout,NULL,_IONBF,0);RadarModel m={0};Canvas c={FontSecondary,1};
    radar_init(&m.core);m.opened=true;m.now=5000;
    feed(&m.core,"NR1,R,ESP32,BW\nNR1,S,RUN\n",1000);
    feed(&m.core,"NR1,D,B,010203040506,-60,0,4B65792046696E646572\n",1000);
    feed(&m.core,"NR1,D,B,010203040506,-36,0,4B65792046696E646572\n",4000);
    feed(&m.core,"NR1,D,B,020304050607,-63,0,4465736B20537065616B6572\n",4000);
    feed(&m.core,"NR1,D,W,030405060708,-68,6,486F6D652057694669\n",4000);
    m.focus=UINT8_MAX;int state=argc>1?atoi(argv[1]):0;
    if(state==1 || state==2){m.detail=true;m.core.pinned=0;}
    if(state==2)m.now=18000;
    if(state==3)strcpy(m.filter,"Key");
    if(state==4)m.kind='B';
    draw(&c,&m);return 0;
}
""".replace(
            "TABLES", "{" + ",".join(tables) + "}"
        )
        .replace("MODEL", model)
        .replace("DRAWING", drawing)
    )
    pictures = []
    captions = [
        "Nearby list",
        "Track BLE target",
        "Target signal lost",
        "Name filter: Key",
        "BLE only",
    ]
    with tempfile.TemporaryDirectory(prefix="radar-preview-") as temp:
        folder = Path(temp)
        stub = folder / "draw.c"
        stub.write_text(harness)
        core = ROOT / "applications/main/nearby_radar"
        exe = build(
            folder, [stub, core / "radar_core.c"], "radar_draw", ["-I" + str(core)]
        )
        for state, caption in enumerate(captions):
            result = subprocess.run(
                [str(exe), str(state)],
                capture_output=True,
                text=True,
                check=True,
                timeout=20,
            )
            image = Image.new("1", (128, 64), 0)
            draw = ImageDraw.Draw(image)
            for line in result.stdout.splitlines():
                op = line.split(" ")
                if op[0] == "s":
                    font, color, x, y = map(int, op[1:5])
                    for char in " ".join(op[5:]):
                        glyph = fonts[font].glyph(ord(char))
                        for dx, dy in glyph.pixels:
                            px, py = x + glyph.x + dx, y - glyph.height - glyph.y + dy
                            if 0 <= px < 128 and 0 <= py < 64:
                                image.putpixel((px, py), color)
                        x += glyph.advance
                else:
                    color, x, y = map(int, op[1:4])
                    if op[0] == "b":
                        w, h = map(int, op[4:])
                        draw.rectangle((x, y, x + w - 1, y + h - 1), fill=color)
                    elif op[0] in ("c", "d"):
                        r = int(op[4])
                        draw.ellipse(
                            (x - r, y - r, x + r, y + r),
                            outline=color,
                            fill=color if op[0] == "d" else None,
                        )
                    else:
                        draw.point((x, y), fill=color)
            colored = Image.new("RGB", image.size, "#f4a63f")
            colored.paste("#191919", mask=image)
            colored.resize((768, 384), Image.Resampling.NEAREST).save(
                args.output_dir / f"radar-preview-{state}.png"
            )
            pictures.append(colored.resize((512, 256), Image.Resampling.NEAREST))
    sheet = Image.new("RGB", (1120, 450), "#f2f0eb")
    d = ImageDraw.Draw(sheet)
    font_path = Path("C:/Windows/Fonts/msyh.ttc")
    title_font = (
        ImageFont.truetype(str(font_path), 28)
        if font_path.exists()
        else ImageFont.load_default()
    )
    d.text(
        (36, 20),
        "附近设备雷达 · 简化版页面预览",
        fill="#202020",
        font=title_font,
    )
    d.text(
        (36, 65),
        "非实机扫描结果；圆点只表达 RSSI 强弱，没有方向或米数含义。",
        fill="#555555",
        font=title_font.font_variant(size=18) if font_path.exists() else title_font,
    )
    for i, pic in enumerate(pictures[:2]):
        x, y = 36 + (i % 2) * 548, 120 + (i // 2) * 292
        sheet.paste(pic, (x, y))
        d.text(
            (x, y + 262),
            ("① 自动扫描，选中设备名字", "② 按 OK 进入雷达，边走边找")[i],
            fill="#222222",
            font=title_font.font_variant(size=18) if font_path.exists() else title_font,
        )
    sheet.save(args.output_dir / "nearby-radar-review.png")
    print(
        json.dumps(
            {
                "preview": "nearby-radar-review.png",
                "source": "actual draw callback",
                "data": "example only",
                "screens": len(pictures),
            }
        )
    )


if __name__ == "__main__":
    main()
