"""Stock desktop captions fit the screen and recovery text does not need an SD."""

from pathlib import Path
import re
import sys
import tempfile
import unittest
from unittest.mock import patch

from test_native_ui_utf8 import native_test, COMMON_INCLUDES

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from generate_lab_font import parse_font
from flipper.utils.fff import FlipperFormatFile


class AnimationChineseTests(unittest.TestCase):
    def test_production_captions_stay_inside_stock_canvas(self):
        directory = ROOT / "applications/services/desktop/animations/views"
        header = (directory / "animation_caption.h").read_text(encoding="utf-8")
        source = (directory / "animation_caption.c").read_text(encoding="utf-8")
        clean = lambda text: re.sub(r"^#(?:include|pragma).*\n", "", text, flags=re.M)
        native_test(
            COMMON_INCLUDES
            + r"""
typedef struct { int calls; } Canvas;
typedef enum { FontSecondary } Font;
typedef enum { ColorWhite, ColorBlack } Color;
typedef enum { AlignCenter, AlignBottom } Align;
static void canvas_set_color(Canvas* c, Color v) {(void)c;(void)v;}
static void canvas_set_font(Canvas* c, Font v) {(void)c;(void)v;}
static void canvas_draw_box(Canvas* c, int x, int y, int w, int h) {
    ++c->calls; assert(x>=0 && y>=0 && w>0 && h>0 && x+w<=128 && y+h<=64);
}
static void canvas_draw_rframe(Canvas* c, int x, int y, int w, int h, int radius) {
    (void)radius; canvas_draw_box(c,x,y,w,h);
}
static void canvas_draw_str_aligned(Canvas* c, int x, int y, Align h, Align v, const char* text) {
    (void)h;(void)v; ++c->calls;
    int width=0;
    for(const unsigned char* p=(const unsigned char*)text; *p; ++p) {
        if(*p<128) width+=6; else if((*p&0xC0)!=0x80) width+=12;
    }
    assert(x-width/2>=0 && x+(width+1)/2<=128 && y>=11 && y<64);
}
"""
            + clean(header)
            + clean(source)
            + r"""
int main(void) {
    Canvas c={0};
    assert(animation_caption_for_builtin(NULL)==AnimationCaptionNone);
    assert(animation_caption_for_builtin("custom_animation")==AnimationCaptionNone);
    animation_caption_draw(&c, AnimationCaptionNone, 17);
    assert(c.calls==0);
    assert(animation_caption_for_builtin("L1_NoSd_128x49")==AnimationCaptionNoSd);
    for(int i=AnimationCaptionError;i<=AnimationCaptionMail;++i) {
        int before=c.calls;
        int y=i==AnimationCaptionError?16:(i==AnimationCaptionMail?13:17);
        animation_caption_draw(&c,(AnimationCaption)i,y);
        assert(c.calls>before);
    }
    animation_caption_draw_levelup(&c);
    return 0;
}
"""
        )

    def test_all_recovery_caption_ideographs_are_in_boot_font(self):
        directory = ROOT / "applications/services/gui"
        header = (directory / "native_zh_boot_font.h").read_text(encoding="utf-8")
        body = header.split("native_zh_boot_font[] = {", 1)[1].split("};", 1)[0]
        font = parse_font(
            bytes(int(x, 16) for x in re.findall(r"0x([0-9a-f]{2})", body))
        )
        source = (
            ROOT / "applications/services/desktop/animations/views/animation_caption.c"
        ).read_text(encoding="utf-8")
        for char in set(source):
            if "\u4e00" <= char <= "\u9fff":
                self.assertIsNotNone(font.payload(ord(char)), char)

    def test_flipper_format_keeps_utf8_on_a_non_utf8_host(self):
        # Emulate a machine whose implicit text encoding cannot handle Chinese.
        import builtins

        original = builtins.open

        def non_utf8_default(*args, **kwargs):
            if "b" not in (args[1] if len(args) > 1 else kwargs.get("mode", "r")):
                kwargs.setdefault("encoding", "ascii")
            return original(*args, **kwargs)

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "meta.txt"
            value = FlipperFormatFile()
            value.setHeader("Flipper Animation", 1)
            value.writeKey("Text", "请检查电池\\n状态异常")
            with patch("builtins.open", non_utf8_default):
                value.save(path)
                result = FlipperFormatFile()
                result.load(path)
            self.assertEqual(result.getHeader(), ("Flipper Animation", 1))
            self.assertEqual(result.readKey("Text"), "请检查电池\\n状态异常")
            self.assertIn("请检查电池".encode(), path.read_bytes())
