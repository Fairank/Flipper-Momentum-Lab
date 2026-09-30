#!/usr/bin/env python3
"""Compile production C draw calls and replay them as Chinese layout previews.

These pictures are source previews, not device or simulator captures. The dice
history and FlipNote keyboard use the full production draw functions. Brainfuck
shows its operator/action section, without the program textbox. Font pixels and
keyboard icons come from repository assets; no existing image is edited.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from PIL import Image
from generate_lab_font import extract_font, parse_font, Metrics
from render_lab_preview import Frame, png_document

ROOT = Path(__file__).resolve().parents[1]
UNION = ROOT / "applications/union"

STUBS = r"""
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include <stdarg.h>
typedef int Canvas;
typedef int View;
typedef int FuriTimer;
typedef int FuriMutex;
typedef void (*FzNoteTextInputCallback)(void*);
typedef bool (*FzNoteTextInputValidatorCallback)(const char*, void*, void*);
typedef enum { InputKeyUp, InputKeyDown, InputKeyRight, InputKeyLeft, InputKeyOk, InputKeyBack } InputKey;
typedef struct {int type; InputKey key;} InputEvent;
enum {FontPrimary, FontSecondary, FontKeyboard, FontBatteryPercent};
enum {ColorWhite,ColorBlack};
enum {AlignLeft, AlignRight, AlignCenter, AlignTop, AlignBottom};
#define COUNT_OF(a) (sizeof(a)/sizeof((a)[0]))
#define UNUSED(x) ((void)(x))
#define furi_crash(x) abort()
typedef struct {char text[64];} FuriString;
static FuriString* furi_string_alloc(void){return calloc(1,sizeof(FuriString));}
static void furi_string_free(FuriString* s){free(s);}
static const char* furi_string_get_cstr(const FuriString* s){return s->text;}
static void furi_string_set(FuriString* s,const char* t){snprintf(s->text,sizeof(s->text),"%s",t);}
static void furi_string_printf(FuriString* s,const char* f,...){va_list a;va_start(a,f);vsnprintf(s->text,sizeof(s->text),f,a);va_end(a);}
static size_t strlcpy(char* d,const char* s,size_t n){size_t l=strlen(s);if(n){size_t c=l<n-1?l:n-1;memcpy(d,s,c);d[c]=0;}return l;}
static int color=ColorBlack, font=FontSecondary;
static void hex_text(const char* t){for(;*t;t++)printf("%02x",(unsigned char)*t);puts("");}
static void canvas_set_color(Canvas* c,int v){UNUSED(c);color=v;}
static void canvas_invert_color(Canvas* c){UNUSED(c);color=!color;}
static void canvas_set_font(Canvas* c,int v){UNUSED(c);font=v;}
static void canvas_clear(Canvas* c){UNUSED(c);puts("C");}
static unsigned canvas_width(Canvas* c){UNUSED(c);return 128;}
static void canvas_draw_str(Canvas* c,int x,int y,const char* t){UNUSED(c);printf("T %d %d %d %d ",color,font,x,y);hex_text(t);}
static void canvas_draw_glyph(Canvas* c,int x,int y,uint16_t ch){char s[2]={(char)ch,0};canvas_draw_str(c,x,y,s);}
static void canvas_draw_box(Canvas* c,int x,int y,int w,int h){UNUSED(c);printf("B %d %d %d %d %d\n",color,x,y,w,h);}
static void canvas_draw_rbox(Canvas* c,int x,int y,int w,int h,int r){UNUSED(c);printf("O %d %d %d %d %d %d\n",color,x,y,w,h,r);}
static void canvas_draw_rframe(Canvas* c,int x,int y,int w,int h,int r){UNUSED(c);printf("R %d %d %d %d %d %d\n",color,x,y,w,h,r);}
static void elements_slightly_rounded_frame(Canvas* c,int x,int y,int w,int h){canvas_draw_rframe(c,x,y,w,h,1);}
static void elements_slightly_rounded_box(Canvas* c,int x,int y,int w,int h){canvas_draw_rbox(c,x,y,w,h,1);}
static void elements_multiline_text(Canvas* c,int x,int y,const char* t){canvas_draw_str(c,x,y,t);}
typedef struct {const char* name;} Icon;
#define ICON(n) static const Icon I_##n={#n}
ICON(KeyBackspace_16x9); ICON(KeyBackspaceSelected_16x9);
ICON(KeyKeyboard_10x11); ICON(KeyKeyboardSelected_10x11);
ICON(WarningDolphin_45x42); ICON(ButtonRightSmall_3x5);
static void canvas_draw_icon(Canvas* c,int x,int y,const Icon* i){UNUSED(c);printf("I %d %d %d %s\n",color,x,y,i->name);}
"""


def text_fonts():
    source = (ROOT / "lib/u8g2/u8g2_fonts.c").read_text(encoding="utf-8")
    data, _ = extract_font(source, "u8g2_font_wqy12_t_gb2312")
    cjk = Metrics(parse_font(data))
    metrics = []
    for symbol in (
        "u8g2_font_helvB08_tr",
        "u8g2_font_haxrcorp4089_tr",
        "u8g2_font_profont11_mf",
        "u8g2_font_5x7_tr",
    ):
        data, _ = extract_font(source, symbol)
        metrics.append(Metrics(parse_font(data)))
    return metrics, cjk


def glyph(metrics, cjk, font, char):
    code = ord(char)
    return (
        metrics[font] if metrics[font].font.payload(code) is not None else cjk
    ).glyph(code)


def metric_table(metrics, cjk):
    codes = set(range(32, 127))
    for path in UNION.rglob("*.c"):
        codes.update(
            ord(c)
            for c in path.read_text(encoding="utf-8", errors="ignore")
            if 0x3000 <= ord(c) <= 0x9FFF or 0xFF01 <= ord(c) <= 0xFFEF
        )
    rows = []
    for code in sorted(codes):
        try:
            gs = [glyph(metrics, cjk, f, chr(code)) for f in range(4)]
        except Exception:
            continue
        rows.append(
            "{"
            + str(code)
            + ",{"
            + ",".join(str(g.advance) for g in gs)
            + "},{"
            + ",".join(str(g.width + g.x if g.width else g.advance) for g in gs)
            + "}},"
        )
    return (
        """
typedef struct {unsigned code, advance[4], extent[4];} Metric;
static const Metric metrics[]={
"""
        + "\n".join(rows)
        + r"""
};
static unsigned canvas_string_width(Canvas* c,const char* s){
    UNUSED(c);unsigned width=0,last_advance=0,last_extent=0;
    while(*s){unsigned code=(unsigned char)*s++;if(code>=128){unsigned n=0;
        if((code&0xe0)==0xc0){code&=31;n=1;}else if((code&0xf0)==0xe0){code&=15;n=2;}else if((code&0xf8)==0xf0){code&=7;n=3;}
        while(n-- && *s)code=(code<<6)|((unsigned char)*s++&63);}
        for(size_t i=0;i<COUNT_OF(metrics);i++)if(metrics[i].code==code){last_advance=metrics[i].advance[font];last_extent=metrics[i].extent[font];width+=last_advance;break;}
    }return width+last_extent-last_advance;
}
static void canvas_draw_str_aligned(Canvas* c,int x,int y,int h,int v,const char* s){
    unsigned w=canvas_string_width(c,s);if(h==AlignRight)x-=w;else if(h==AlignCenter)x-=w/2;
    int ascent=font==FontPrimary?8:7;for(const unsigned char* p=(const unsigned char*)s;*p;p++)if(*p>=128){ascent=10;break;}
    if(v==AlignTop)y+=ascent;else if(v==AlignCenter)y+=ascent/2;canvas_draw_str(c,x,y,s);
}
"""
    )


def source_program(kind, base):
    if kind.startswith("dice"):
        header = (UNION / "dice/constants.h").read_text(encoding="utf-8")
        source = (UNION / "dice/dice_app.c").read_text(encoding="utf-8")
        code = "\n".join(re.findall(r"^#define .*$", header, re.M))
        code += (
            "\n"
            + header[
                header.index("typedef struct {") : header.index(
                    "\nvoid coin_set_start("
                )
            ]
        )
        code += source[
            source.index("static void draw_history(") : source.index(
                "\nstatic void draw_dice("
            )
        ]
        page = 1 if kind.endswith("2") else 0
        code += f"""
int main(void){{Canvas c=0;State s={{0}};init(&s);unsigned indexes[]={{0,0,1,2,3,4,5,6,7,2}};
unsigned counts[]={{1,1,1,2,3,4,5,10,1,10}},results[]={{1,2,3,7,20,31,42,200,100,60}};
for(int i=0;i<10;i++)add_to_history(&s,indexes[i],counts[i],results[i]);s.history_page={page};draw_history(&s,&c);}}
"""
        paths = ["dice/constants.h", "dice/dice_app.c"]
    elif kind == "brainfuck":
        source = (UNION / "brainfuck/views/bf_dev_env.c").read_text(encoding="utf-8")
        code = "#define FONT_NAME FontBatteryPercent\nstatic int selectedButton=10,saveNotifyCountdown=0;\n"
        code += source[
            source.index("#define BT_X") : source.index("void bf_save_changes()")
        ]
        code += (
            source[
                source.index("static void bf_dev_draw_callback(") : source.index(
                    "    //textbox"
                )
            ]
            + "}\n"
        )
        code += "int main(void){Canvas c=0;bf_dev_draw_callback(&c,NULL);}\n"
        paths = ["brainfuck/views/bf_dev_env.c"]
    else:
        source = (UNION / "flipnote/fznote_text_input.c").read_text(encoding="utf-8")
        code = (
            (UNION / "flipnote/flipnote_utf8.h")
            .read_text(encoding="utf-8")
            .replace("#pragma once", "")
        )
        end = re.search(r"static void\s+fznote_text_input_handle_up\(", source).start()
        code += source[source.index("struct FzNoteTextInput {") : end]
        code = code.replace(
            "struct FzNoteTextInput {",
            "typedef struct FzNoteTextInput FzNoteTextInput;\nstruct FzNoteTextInput {",
            1,
        )
        code += r"""
int main(void){Canvas c=0;char text[128]="中文笔记：甲乙丙丁";FzNoteTextInputModel m={0};
m.header="编辑行";m.text_buffer=text;m.text_buffer_size=sizeof(text);m.cursor_pos=strlen(text);
m.selected_row=2;m.selected_column=9;fznote_text_input_view_draw_callback(&c,&m);}
"""
        paths = ["flipnote/fznote_text_input.c", "flipnote/flipnote_utf8.h"]
    return base + code, paths


def replay(lines, metrics, cjk):
    frame = Frame(128, 64)
    for line in lines:
        p = line.split()
        if p[0] == "C":
            frame.bits[:] = bytes(len(frame.bits))
            continue
        frame.color = int(p[1])
        if p[0] == "T":
            font, x, y = map(int, p[2:5])
            text = bytes.fromhex(p[5] if len(p) > 5 else "").decode("utf-8")
            for char in text:
                g = glyph(metrics, cjk, font, char)
                for dx, dy in g.pixels:
                    frame.dot(x + g.x + dx, y - g.height - g.y + dy)
                x += g.advance
        elif p[0] == "I":
            x, y = map(int, p[2:4])
            path = UNION / "flipnote/icons" / (p[4] + ".png")
            with Image.open(path) as original:
                pixels = original.convert("1")
                for py in range(pixels.height):
                    for px in range(pixels.width):
                        if pixels.getpixel((px, py)) == 0:
                            frame.dot(x + px, y + py)
        else:
            x, y, w, h = map(int, p[2:6])
            if p[0] == "B":
                frame.box(x, y, w, h)
            else:
                radius = min(int(p[6]), w // 2, h // 2)
                # Source preview: rounded corners are a raster approximation.
                for py in range(h):
                    inset = max(0, radius - 1 - min(py, h - 1 - py))
                    if p[0] == "O" or py in (0, h - 1):
                        frame.hline(x + inset, x + w - 1 - inset, y + py)
                    else:
                        frame.dot(x + inset, y + py)
                        frame.dot(x + w - 1 - inset, y + py)
    return frame


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    compiler = next(
        (shutil.which(name) for name in ("cc", "gcc", "clang") if shutil.which(name)),
        None,
    )
    if not compiler:
        parser.error("A host C compiler is required")
    metrics, cjk = text_fonts()
    base = STUBS + metric_table(metrics, cjk)
    scenes = [
        ("dice1", "掷骰历史 第一页"),
        ("dice2", "掷骰历史 第二页"),
        ("brainfuck", "Brainfuck 控制区"),
        ("flipnote", "记事本文字编辑"),
    ]
    args.output_dir.mkdir(parents=True, exist_ok=True)
    entries, frames = [], []
    with tempfile.TemporaryDirectory() as directory:
        for key, title in scenes:
            code, paths = source_program(key, base)
            src, exe = Path(directory) / "draw.c", Path(directory) / "draw.exe"
            src.write_text(code, encoding="utf-8")
            result = subprocess.run(
                [compiler, "-std=c11", "-funsigned-char", str(src), "-o", str(exe)],
                capture_output=True,
                text=True,
            )
            if result.returncode:
                raise RuntimeError(result.stderr)
            trace = subprocess.check_output(
                [str(exe)], text=True, encoding="utf-8"
            ).splitlines()
            frame = replay(trace, metrics, cjk)
            frames.append(frame)
            (args.output_dir / (key + ".png")).write_bytes(png_document(frame, 6))
            entries.append(
                {
                    "title": title,
                    "file": key + ".png",
                    "source_sha256": {
                        p: hashlib.sha256((UNION / p).read_bytes()).hexdigest()
                        for p in paths
                    },
                    "draw_calls": trace,
                }
            )
    sheet = Frame(264, 136)
    for i, frame in enumerate(frames):
        for y in range(64):
            for x in range(128):
                sheet.color = frame.bits[y * 128 + x]
                sheet.dot((i % 2) * 136 + x, (i // 2) * 72 + y)
    (args.output_dir / "union-contact-sheet.png").write_bytes(png_document(sheet, 3))
    (args.output_dir / "manifest.json").write_text(
        json.dumps(
            {
                "kind": "production C source layout preview, not hardware capture",
                "note": "Corner raster is approximate; no RTOS, SD cache, input timing, or device is executed.",
                "screens": entries,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"Rendered {len(entries)} production C source previews")


if __name__ == "__main__":
    main()
