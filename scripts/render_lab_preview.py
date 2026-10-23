#!/usr/bin/env python3
"""Render Flipper Lab screens from source as SVG and PNG layout previews.

Replays the draw calls of applications/main/lab/lab_app.c on a 128x64 bitmap.
Text, layout constants and glyph pixels come from scripts/generate_lab_font.py,
which reads applications/main/lab/lab_content.json and the u8g2 source font, so
no second font parser exists here. Nothing runs firmware or a simulator: the
pictures are computed from the sources and are not screenshots.

    python scripts/render_lab_preview.py                  # menu, bluetooth, infrared
    python scripts/render_lab_preview.py --all            # every topic, page and menu state
    python scripts/render_lab_preview.py --output-dir DIR # anywhere, also outside the repo

Per screen: <name>.svg and <name>.png; plus index.html. Exit code 0: done;
1: done with warnings (stderr and index.html list them); 2: nothing rendered.
Standard library only, Python 3.9+.
"""
from __future__ import annotations

import argparse
import html
import json
import re
import struct
import sys
import zlib
from pathlib import Path
from typing import Dict, List, NamedTuple, Optional, Set, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    import generate_lab_font as gen

    IMPORT_ERROR = ""
except Exception as error:  # missing, renamed or half-written generator
    gen = None
    IMPORT_ERROR = str(error)

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "documentation" / "custom" / "previews"
DEFAULT_TOPICS = ("bluetooth", "infrared")
CAPTION = "源码布局预览，非真机截图"
PAGE_TITLE = "Flipper Lab 屏幕布局预览"
BACKLIGHT = (255, 130, 0)  # approximate colour of the lit display, not measured
INK = (0, 0, 0)
THUMB_SCALE = 2  # gallery thumbnails: an integer scale keeps the 12 px font readable
CONSTANTS = (
    "LAB_TEXT_X", "LAB_TEXT_MAX_W", "LAB_LIST_W", "LAB_INDICATOR_RIGHT", "LAB_INDICATOR_GAP",
    "LAB_TITLE_Y", "LAB_RULE_TOP", "LAB_ROWS_TOP", "LAB_ROW_H", "LAB_ROW_BASELINE", "LAB_ROWS",
    "LAB_RULE_BOTTOM", "LAB_FOOTER_Y", "LAB_TEXT_MAX_BYTES", "LAB_TOPIC_COUNT",
)  # fmt: skip


def esc(text: str) -> str:
    """Escape for HTML text, HTML attributes and XML (SVG) alike."""
    return html.escape(text, quote=True)


def css(rgb: Tuple[int, int, int]) -> str:
    return "#%02x%02x%02x" % rgb


def f32(value: float) -> float:
    """Round to IEEE single precision, like the firmware's float arithmetic."""
    return struct.unpack("f", struct.pack("f", value))[0]


def shown(path: Path) -> str:
    """Repository-relative path, or just the name for files outside the repository."""
    try:
        return path.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return path.name


# ---------------------------------------------------------------------------
# Frame buffer and the canvas/u8g2 calls lab_app.c uses


class Frame:
    """1-bit frame buffer: bits[y * width + x] is 1 where the display pixel is dark."""

    def __init__(self, width: int, height: int):
        self.width, self.height = width, height
        self.bits = bytearray(width * height)  # canvas_clear(): every pixel clear
        self.color = 1  # u8g2 draw colour: 1 = ColorBlack sets, 0 = ColorWhite clears

    def dot(self, x: int, y: int) -> None:
        """u8g2_DrawPixel(): pixels outside the buffer are dropped."""
        if 0 <= x < self.width and 0 <= y < self.height:
            self.bits[y * self.width + x] = self.color

    def box(self, x: int, y: int, width: int, height: int) -> None:
        """u8g2_DrawBox()"""
        for py in range(y, y + height):
            for px in range(x, x + width):
                self.dot(px, py)

    def hline(self, x1: int, x2: int, y: int) -> None:
        """u8g2_DrawLine() for the horizontal lines the app draws: both ends inclusive."""
        for px in range(min(x1, x2), max(x1, x2) + 1):
            self.dot(px, y)

    def row(self, y: int) -> bytearray:
        return self.bits[y * self.width : (y + 1) * self.width]


class Renderer:
    """Replays lab_app.c on a Frame. Each method names the C function it mirrors."""

    def __init__(
        self, content: gen.Content, metrics: gen.Metrics, constants: Dict[str, int]
    ):
        self.content, self.metrics, self.k = content, metrics, constants
        self.missing: Set[str] = set()  # characters without a glyph; u8g2 draws nothing
        self.cut: List[str] = []  # lines lab_draw_text() had to shorten
        self.frame = Frame(gen.SCREEN_W, gen.SCREEN_H)

    def glyph(self, char: str) -> Optional[gen.Glyph]:
        try:
            return self.metrics.glyph(
                ord(char)
            )  # generator decoder == u8g2_font_decode_glyph()
        except gen.FontError:
            self.missing.add(char)
            return None

    def width(self, text: str) -> int:
        """canvas_string_width() -> u8g2_string_width(): sum of advances, then the
        last found glyph's advance is replaced by its real extent (width + x offset)."""
        total = dx = 0
        last = None
        for char in text:
            glyph = self.glyph(char)
            dx = glyph.advance if glyph is not None else 0  # u8g2_GetGlyphWidth() -> 0
            total += dx
            last = glyph if glyph is not None else last
        if last is not None and last.width:
            total += last.width + last.x - dx
        return total

    def draw_str(self, x: int, y: int, text: str) -> None:
        """canvas_draw_str() -> u8g2_DrawUTF8(), transparent font mode, baseline reference:
        a glyph's top row sits at y - (height + y offset), u8g2_font_decode_glyph()."""
        for char in text:
            glyph = self.glyph(char)
            if glyph is None:
                continue
            if glyph.width:
                left, top = x + glyph.x, y - (glyph.height + glyph.y)
                for col, row in glyph.pixels:
                    self.frame.dot(left + col, top + row)
            x += glyph.advance

    # lab_app.c ---------------------------------------------------------

    def text(self, x: int, y: int, max_w: int, text: str) -> None:
        """lab_draw_text(): the whole string if it fits, else cut at a UTF-8 boundary."""
        if self.width(text) <= max_w:
            self.draw_str(x, y, text)
            return
        raw, fit = text.encode("utf-8"), 0
        for end in range(1, min(self.k["LAB_TEXT_MAX_BYTES"], len(raw)) + 1):
            if end < len(raw) and (raw[end] & 0xC0) == 0x80:
                continue  # inside a UTF-8 character
            if self.width(raw[:end].decode("utf-8")) > max_w:
                break
            fit = end
        kept = raw[:fit].decode("utf-8")
        self.cut.append(f"{text!r} -> {kept!r} (limit {max_w} px)")
        self.draw_str(x, y, kept)

    def chrome(self, title: str, indicator: str, footer: str) -> None:
        """lab_draw_chrome()"""
        k = self.k
        indicator_w = self.width(indicator)
        title_w = k["LAB_INDICATOR_RIGHT"] - k["LAB_INDICATOR_GAP"] - k["LAB_TEXT_X"]
        if indicator_w < title_w:
            self.draw_str(
                k["LAB_INDICATOR_RIGHT"] - indicator_w, k["LAB_TITLE_Y"], indicator
            )
            title_w -= indicator_w
        self.text(k["LAB_TEXT_X"], k["LAB_TITLE_Y"], title_w, title)
        right = self.frame.width - 1
        self.frame.hline(0, right, k["LAB_RULE_TOP"])
        self.frame.hline(0, right, k["LAB_RULE_BOTTOM"])
        self.text(k["LAB_TEXT_X"], k["LAB_FOOTER_Y"], k["LAB_TEXT_MAX_W"], footer)

    def scrollbar(self, x: int, y: int, height: int, pos: int, total: int) -> None:
        """elements_scrollbar_pos() from gui/elements.c; its float maths is single precision."""
        frame = self.frame
        frame.color = 0
        frame.box(x - 3, y, 3, height)
        frame.color = 1
        for i in range(y, height + y, 2):
            frame.dot(x - 2, i)
        if total:
            block_h = f32(f32(height) / f32(total))
            top = int(
                f32(f32(y) + f32(block_h * f32(pos)))
            )  # int32_t parameter truncates
            frame.box(
                x - 3, top, 3, int(max(block_h, 1.0))
            )  # MAX(block_h, 1) -> size_t

    def menu(self, topic: int) -> Frame:
        """lab_draw_callback() + lab_draw_menu() with `topic` selected."""
        k, topics = self.k, self.content.topics
        self.frame = Frame(gen.SCREEN_W, gen.SCREEN_H)
        self.chrome(
            self.content.menu_title, topics[topic].indicator, self.content.menu_footer
        )
        count, rows = len(topics), k["LAB_ROWS"]
        # lab_first_row(): keep the selection in the middle when possible
        first = 0 if count <= rows or topic == 0 else min(topic - 1, count - rows)
        for row in range(rows):
            index = first + row
            if index >= count:
                break
            top = k["LAB_ROWS_TOP"] + row * k["LAB_ROW_H"]
            if index == topic:
                self.frame.box(0, top, k["LAB_LIST_W"], k["LAB_ROW_H"])
                self.frame.color = 0
            baseline = top + k["LAB_ROW_BASELINE"]
            self.text(
                k["LAB_TEXT_X"], baseline, k["LAB_TEXT_MAX_W"], topics[index].label
            )
            self.frame.color = 1
        self.scrollbar(
            self.frame.width, k["LAB_ROWS_TOP"], rows * k["LAB_ROW_H"], topic, count
        )
        return self.frame

    def detail(self, topic: int, page: int) -> Frame:
        """lab_draw_callback() + lab_draw_detail() for one page."""
        k = self.k
        item = self.content.topics[topic]
        lines = item.pages[page].lines
        self.frame = Frame(gen.SCREEN_W, gen.SCREEN_H)
        self.chrome(item.title, item.pages[page].indicator, item.footer)
        for row in range(k["LAB_ROWS"]):
            if not lines[row]:
                continue
            y = k["LAB_ROWS_TOP"] + row * k["LAB_ROW_H"] + k["LAB_ROW_BASELINE"]
            self.text(k["LAB_TEXT_X"], y, k["LAB_TEXT_MAX_W"], lines[row])
        return self.frame


# ---------------------------------------------------------------------------
# Inputs, taken from the generator


def layout_constants(content: gen.Content) -> Dict[str, int]:
    """The LAB_* values exactly as the generator writes them into lab_content.h."""
    header = gen.render_content_header(content)
    found = re.findall(r"^#define (LAB_\w+)\s+(\d+)$", header, re.MULTILINE)
    constants = {name: int(value) for name, value in found}
    missing = [name for name in CONSTANTS if name not in constants]
    if missing:
        raise gen.GeneratorError(
            f"generator header does not define {', '.join(missing)}"
        )
    return constants


def load(
    source: Path, symbol: str, content_path: Path, warnings: List[str]
) -> Tuple[gen.Content, gen.Metrics, str]:
    """Content, font subset and metrics built the way generate_lab_font.generate() does."""
    content = gen.load_content(json.loads(content_path.read_text(encoding="utf-8")))
    source_data, _comment = gen.extract_font(
        source.read_text(encoding="latin-1"), symbol
    )
    font = gen.parse_font(source_data)
    codes = gen.required_codes(content)
    try:
        subset = gen.build_subset(font, codes)
        font = gen.verify_subset(font, subset, codes)
        note = f"{symbol} 子集：{len(codes)} 个字形，{len(subset)} 字节（与 lab_font.h 相同的构造）"
    except gen.FontError as error:  # e.g. a character the source font lacks
        warnings.append(f"the generator would fail: {error}")
        note = f"{symbol} 完整字体（{len(source_data)} 字节），子集构造失败"
    metrics = gen.Metrics(font)
    try:
        gen.check_layout(content, metrics)
    except gen.ContentError as error:
        warnings.append(f"the generator would reject this content: {error}")
    return content, metrics, note


# ---------------------------------------------------------------------------
# Output


class Screen(NamedTuple):
    group: str
    name: str  # file stem, ASCII
    title: str
    frame: Frame


def svg_document(frame: Frame, scale: int, title: str, desc: str) -> str:
    """Standalone SVG: one subpath per horizontal run of dark pixels."""
    runs = []
    for y in range(frame.height):
        row, x = frame.row(y), 0
        while x < frame.width:
            if not row[x]:
                x += 1
                continue
            start = x
            while x < frame.width and row[x]:
                x += 1
            runs.append(f"M{start} {y}h{x - start}v1h{start - x}z")
    path = "".join(runs)
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{frame.width * scale}" '
        f'height="{frame.height * scale}" viewBox="0 0 {frame.width} {frame.height}" '
        'shape-rendering="crispEdges">\n'
        f"  <title>{esc(title)}</title>\n"
        f"  <desc>{esc(desc)}</desc>\n"
        f'  <rect width="{frame.width}" height="{frame.height}" fill="{css(BACKLIGHT)}"/>\n'
        f'  <path fill="{css(INK)}" d="{path}"/>\n'
        "</svg>\n"
    )


def png_document(frame: Frame, scale: int) -> bytes:
    """Indexed-colour PNG of the frame at an integer scale: index 0 backlight, 1 ink."""

    def chunk(kind: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(kind + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", crc)

    raw = bytearray()
    for y in range(frame.height):
        line = bytes(bit for bit in frame.row(y) for _ in range(scale))
        raw += (b"\0" + line) * scale  # filter type 0 in front of every scanline
    ihdr = struct.pack(
        ">IIBBBBB", frame.width * scale, frame.height * scale, 8, 3, 0, 0, 0
    )
    return b"".join(
        (
            b"\x89PNG\r\n\x1a\n",
            chunk(b"IHDR", ihdr),
            chunk(b"PLTE", bytes(BACKLIGHT + INK)),
            chunk(b"IDAT", zlib.compress(bytes(raw), 9)),
            chunk(b"IEND", b""),
        )
    )


STYLE = """
body{margin:0;padding:16px;background:#e6e6e6;color:#222;line-height:1.5;
font-family:system-ui,"Segoe UI","PingFang SC","Microsoft YaHei","Noto Sans CJK SC",sans-serif}
h1{font-size:22px;margin:0 0 8px}h2{font-size:17px;margin:24px 0 8px}
.notice{display:inline-block;background:#fff3c4;border:1px solid #c9a227;padding:6px 12px;
font-weight:700}
.warn{background:#fde2e1;border:1px solid #c0392b;padding:0 12px 8px;margin-top:16px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(272px,1fr));gap:12px}
figure{margin:0;background:#fff;padding:8px;border-radius:4px}
img{display:block;border:1px solid #888;image-rendering:crisp-edges;image-rendering:pixelated}
figcaption{font-size:14px;margin-top:6px;word-break:break-all}
table{border-collapse:collapse;background:#fff}
td,th{border:1px solid #bbb;padding:2px 8px;text-align:left}
dl{display:grid;grid-template-columns:max-content 1fr;gap:2px 12px;margin:8px 0}
dt{font-weight:700}dd{margin:0}
footer{margin-top:24px;font-size:13px;color:#555}
"""


def gallery_html(
    screens: List[Screen],
    constants: Dict[str, int],
    notes: List[Tuple[str, str]],
    warnings: List[str],
    png: bool,
) -> str:
    """Self-contained gallery: no scripts, no remote resources, all text escaped."""
    groups: Dict[str, List[Screen]] = {}
    for screen in screens:
        groups.setdefault(screen.group, []).append(screen)
    width, height = gen.SCREEN_W * THUMB_SCALE, gen.SCREEN_H * THUMB_SCALE
    parts = [
        "<!DOCTYPE html>",
        '<html lang="zh-CN">',
        "<head>",
        '<meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width, initial-scale=1">',
        f"<title>{esc(PAGE_TITLE)}</title>",
        f"<style>{STYLE}</style>",
        "</head>",
        "<body>",
        f"<h1>{esc(PAGE_TITLE)}</h1>",
        f'<p class="notice">{esc(CAPTION)}</p>',
        "<p>每张图由 scripts/render_lab_preview.py 计算得出：读取 lab_content.json 的文字与布局，"
        "取 u8g2 源字体的字形像素，按 lab_app.c 的绘制调用顺序在 128×64 位图上重放。"
        "它只说明源码中的坐标与字形如何组合，不证明固件已编译、能运行或与真机显示一致。"
        "说明与证明范围见 documentation/custom/PREVIEW.md。</p>",
        "<dl>"
        + "".join(f"<dt>{esc(k)}</dt><dd>{esc(v)}</dd>" for k, v in notes)
        + "</dl>",
        "<details><summary>布局常量（解析自生成器写入 lab_content.h 的 #define）</summary><table>"
        + "".join(
            f"<tr><th>{esc(k)}</th><td>{v}</td></tr>" for k, v in constants.items()
        )
        + "</table></details>",
    ]
    if warnings:
        items = "".join(f"<li>{esc(w)}</li>" for w in warnings)
        parts.append(f'<section class="warn"><h2>警告</h2><ul>{items}</ul></section>')
    for group, items_in_group in groups.items():
        parts += [f"<h2>{esc(group)}</h2>", '<div class="grid">']
        for screen in items_in_group:
            name = esc(screen.name)
            links = f'<a href="{name}.svg">SVG</a>'
            if png:
                links += f' · <a href="{name}.png">PNG</a>'
            parts.append(
                f'<figure><a href="{name}.svg"><img src="{name}.svg" width="{width}" '
                f'height="{height}" alt="{esc(screen.title)}（{esc(CAPTION)}）"></a>'
                f"<figcaption>{esc(screen.title)}<br><small>{esc(CAPTION)} · {links}</small>"
                "</figcaption></figure>"
            )
        parts.append("</div>")
    parts += [
        f"<footer>缩略图为 {THUMB_SCALE}× 整数缩放；点击可打开单独的 SVG。"
        "背景色为近似的屏幕背光色，非实测。</footer>",
        "</body>",
        "</html>",
        "",
    ]
    return "\n".join(parts)


# ---------------------------------------------------------------------------


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT,
        help="where to write; may be outside the repository (default: %(default)s)",
    )
    parser.add_argument(
        "--scale",
        type=int,
        default=4,
        help="PNG pixel size and SVG intrinsic size (default 4)",
    )
    parser.add_argument(
        "--topic",
        action="append",
        metavar="ID",
        help="topic id to render, repeatable (default: %s)" % ", ".join(DEFAULT_TOPICS),
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="every topic and page, and the menu with each topic selected",
    )
    parser.add_argument(
        "--no-png", action="store_true", help="write only SVG files and index.html"
    )
    parser.add_argument(
        "--source", type=Path, help="C file with the u8g2 font (generator default)"
    )
    parser.add_argument("--symbol", help="u8g2 font symbol (generator default)")
    parser.add_argument(
        "--content", type=Path, help="lab_content.json (generator default)"
    )
    args = parser.parse_args(argv)
    for stream in (
        sys.stdout,
        sys.stderr,
    ):  # Windows consoles may not encode the content
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(errors="backslashreplace")
    if gen is None:
        print(f"error: cannot import generate_lab_font.py next to this script: {IMPORT_ERROR}",
              file=sys.stderr)  # fmt: skip
        return 2
    if args.scale < 1:
        parser.error("--scale must be at least 1")

    source = args.source or gen.DEFAULT_SOURCE
    symbol = args.symbol or gen.DEFAULT_SYMBOL
    content_path = args.content or gen.DEFAULT_CONTENT
    warnings: List[str] = []
    try:
        content, metrics, font_note = load(source, symbol, content_path, warnings)
        constants = layout_constants(content)
    except (gen.GeneratorError, OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    topics = content.topics
    ids = [topic.id for topic in topics]
    if args.all:
        selected = menu_states = list(range(len(topics)))
    else:
        selected, menu_states = [], [0]
        for wanted in dict.fromkeys(args.topic or DEFAULT_TOPICS):
            if wanted in ids:
                selected.append(ids.index(wanted))
            else:
                warnings.append(
                    f"no topic with id {wanted!r} (known: {', '.join(ids)})"
                )

    renderer = Renderer(content, metrics, constants)
    screens: List[Screen] = []
    for index in menu_states:
        topic = topics[index]
        title = f"{content.menu_title} · 选中「{topic.label}」 {topic.indicator}"
        screens.append(
            Screen("主题列表", f"menu-{topic.id}", title, renderer.menu(index))
        )
    for index in selected:
        topic = topics[index]
        for number, page in enumerate(topic.pages, 1):
            name, title = f"{topic.id}-{number:02d}", f"{topic.title} {page.indicator}"
            group = f"{topic.title}（{topic.id}）"
            screens.append(
                Screen(group, name, title, renderer.detail(index, number - 1))
            )
    if renderer.missing:
        listed = ", ".join(gen.describe(ord(char)) for char in sorted(renderer.missing))
        warnings.append(f"no glyph for {listed}; drawn as nothing, as u8g2 does")
    warnings += [f"lab_draw_text() cut {entry}" for entry in renderer.cut]

    out = args.output_dir
    out.mkdir(parents=True, exist_ok=True)
    desc = (
        f"{CAPTION}。scripts/render_lab_preview.py 根据 lab_content.json 与 {symbol} "
        "重放 lab_app.c 的绘制调用；未运行固件或模拟器。"
    )
    for screen in screens:
        svg = svg_document(
            screen.frame, args.scale, f"Flipper Lab · {screen.title}", desc
        )
        (out / f"{screen.name}.svg").write_bytes(svg.encode("utf-8"))
        if not args.no_png:
            (out / f"{screen.name}.png").write_bytes(
                png_document(screen.frame, args.scale)
            )
    notes = [
        ("内容", shown(content_path)),
        ("字体", font_note),
        ("字体来源", shown(source)),
        (
            "绘制依据",
            "lab_app.c、gui/elements.c 的 elements_scrollbar_pos()、gui/canvas.c、"
            "lib/u8g2/u8g2_font.c",
        ),
        ("尺寸", f"PNG 与 SVG 固有尺寸 {args.scale}×，缩略图 {THUMB_SCALE}×"),
        ("画面数", str(len(screens))),
    ]
    page = gallery_html(screens, constants, notes, warnings, not args.no_png)
    (out / "index.html").write_bytes(page.encode("utf-8"))
    print(f"wrote {len(screens)} screens and index.html to {out}")
    for warning in warnings:
        print(f"warning: {warning}", file=sys.stderr)
    return 1 if warnings else 0


if __name__ == "__main__":
    sys.exit(main())
