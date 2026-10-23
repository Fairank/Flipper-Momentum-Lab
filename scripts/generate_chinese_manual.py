"""Generate the Chinese manual HTML and PDF from reviewed public JSON.

Requires reportlab and a Chinese TrueType font. No hardware access or data upload.
"""

import argparse
import html
import json
from pathlib import Path
from urllib.parse import quote

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    PageTemplate,
    Paragraph,
    Spacer,
    PageBreak,
    LongTable,
    TableStyle,
)
from reportlab.platypus.tableofcontents import TableOfContents

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--root", type=Path, required=True)
parser.add_argument("--font", type=Path, default=Path("C:/Windows/Fonts/msyh.ttc"))
parser.add_argument(
    "--bold-font", type=Path, default=Path("C:/Windows/Fonts/msyhbd.ttc")
)
args = parser.parse_args()
root = args.root.resolve()
data_dir = root / "documentation/custom/manual"
content = json.loads((data_dir / "content.zh-CN.json").read_text(encoding="utf-8"))
catalog = json.loads((data_dir / "apps.zh-CN.json").read_text(encoding="utf-8"))
apps = catalog["apps"]
assert len(apps) == 295 and len({a["path"] for a in apps}) == 295
assert len(catalog["libraries"]) == 121
assert all(a["purpose"] and a["dependency"] and a["source_manifest"] for a in apps)
for path in (
    [a["source_manifest"] for a in apps]
    + [a["source_readme"] for a in apps if a["source_readme"]]
    + [p for c in content["chapters"] for p in c["sources"]]
):
    if not (root / path).is_file():
        raise ValueError(f"Missing source: {path}")

external_sha = "55a446b1b01bf2a2f98161d704e62cc47075ad30"


def source_url(path):
    if path.startswith("applications/external/"):
        return (
            "https://github.com/Next-Flip/Momentum-Apps/blob/"
            + external_sha
            + "/"
            + quote(path[len("applications/external/") :], safe="/")
        )
    return (
        "https://github.com/Fairank/Flipper-Momentum-Lab/blob/"
        + catalog["source_commit"]
        + "/"
        + quote(path, safe="/")
    )


e = html.escape


def html_section(section):
    blocks = ["<section><h3>" + e(section["title"]) + "</h3>"]
    blocks += ["<p>" + e(p) + "</p>" for p in section.get("paragraphs", [])]
    if "steps" in section:
        blocks += [
            "<ol>"
            + "".join("<li>" + e(p) + "</li>" for p in section["steps"])
            + "</ol>"
        ]
    if "table" in section:
        table = section["table"]
        blocks += [
            '<div class="table-scroll"><table><thead><tr>'
            + "".join('<th scope="col">' + e(x) + "</th>" for x in table["headers"])
            + "</tr></thead><tbody>"
            + "".join(
                "<tr>" + "".join("<td>" + e(x) + "</td>" for x in row) + "</tr>"
                for row in table["rows"]
            )
            + "</tbody></table></div>"
        ]
    blocks.append("</section>")
    return "".join(blocks)


nav = "".join(
    '<a href="#' + e(c["id"]) + '">' + e(c["title"]) + "</a>"
    for c in content["chapters"]
)
chapters = []
for c in content["chapters"]:
    sources = " · ".join(
        '<a href="'
        + e(source_url(p))
        + '" target="_blank" rel="noopener">'
        + e(Path(p).name)
        + "</a>"
        for p in c["sources"]
    )
    chapters.append(
        '<article class="chapter" id="'
        + e(c["id"])
        + '"><h2>'
        + e(c["title"])
        + '</h2><p class="intro">'
        + e(c["intro"])
        + "</p>"
        + "".join(html_section(s) for s in c["sections"])
        + '<details class="sources"><summary>本章依据</summary><p>'
        + sources
        + "</p></details></article>"
    )
options = '<option value="">全部分类（295）</option>' + "".join(
    '<option value="'
    + e(c["name"])
    + '">'
    + e(c["zh"])
    + " · "
    + str(c["count"])
    + "</option>"
    for c in catalog["categories"]
)
cards = []
for i, a in enumerate(apps, 1):
    links = (
        '<a href="'
        + e(source_url(a["source_manifest"]))
        + '" target="_blank" rel="noopener">应用声明</a>'
    )
    if a["source_readme"]:
        links += (
            ' · <a href="'
            + e(source_url(a["source_readme"]))
            + '" target="_blank" rel="noopener">来源 README</a>'
        )
    cards.append(
        '<article class="app-card" data-category="'
        + e(a["category"])
        + '" id="app-'
        + str(i)
        + '"><div class="app-top"><span class="number">'
        + str(i).zfill(3)
        + '</span><span class="badge">'
        + e(a["category_zh"])
        + "</span></div><h3>"
        + e(a["name"])
        + '</h3><p class="purpose">'
        + e(a["purpose"])
        + '</p><p class="path">'
        + e(a["path"])
        + "</p><dl><dt>使用条件</dt><dd>"
        + e(a["dependency"])
        + "</dd><dt>验收状态</dt><dd>"
        + e(a["status"])
        + "</dd></dl><details><summary>来源与原始说明</summary><p>"
        + links
        + "</p><p>"
        + e(
            a["description_source"]
            or "声明未提供完整用途说明；中文说明已标明需核对的范围。"
        )
        + "</p><p>"
        + e(a["source_origin"])
        + "</p></details></article>"
    )

style = """
:root{--orange:#c34800;--ink:#182022;--muted:#596365;--paper:#f7f7f3;--line:#dfE3dd;--soft:#fff0e6;--white:#fff}*{box-sizing:border-box}html{scroll-behavior:smooth;scroll-padding-top:24px}body{margin:0;background:var(--paper);color:var(--ink);font:16px/1.8 -apple-system,BlinkMacSystemFont,"Segoe UI","Microsoft YaHei",sans-serif}a{color:var(--orange);text-decoration-thickness:1px;text-underline-offset:3px}a:hover{text-decoration:underline}button,input,select{font:inherit}a:focus-visible,button:focus-visible,input:focus-visible,select:focus-visible,summary:focus-visible{outline:3px solid var(--orange);outline-offset:4px}header{max-width:1320px;margin:auto;padding:60px 32px 32px}.eyebrow{font-size:12px;letter-spacing:.15em;font-weight:700;color:var(--orange)}h1{font-size:clamp(30px,4vw,48px);line-height:1.25;letter-spacing:-.02em;margin:16px 0}h2{font-size:27px;line-height:1.4;margin:0 0 12px}h3{font-size:19px;line-height:1.4;margin:24px 0 10px}p{margin:10px 0 16px}.lead{color:var(--muted);max-width:800px;font-size:18px}.scope{max-width:900px;border-left:3px solid var(--orange);padding:12px 18px;background:var(--soft);border-radius:0 12px 12px 0;font-size:14px}.stats{display:flex;gap:14px;flex-wrap:wrap;margin:24px 0}.stat{border:1px solid var(--line);padding:12px 22px;border-radius:14px;background:var(--white)}.stat strong{font-size:25px;display:block;line-height:1.4}.stat span{font-size:13px;color:var(--muted)}.layout{max-width:1320px;padding:0 32px 60px;margin:auto;display:grid;grid-template-columns:240px minmax(0,1fr);gap:32px}nav{position:sticky;top:24px;align-self:start;background:var(--white);border:1px solid var(--line);border-radius:16px;padding:18px;font-size:13px;max-height:calc(100vh - 48px);overflow:auto}nav a{display:block;padding:8px 6px;color:var(--ink);text-decoration:none;border-radius:8px}nav a:hover{background:var(--soft);color:var(--orange)}.chapter,.index{background:var(--white);padding:32px;border:1px solid var(--line);border-radius:18px;margin-bottom:24px}.intro{color:var(--muted);font-size:17px}.table-scroll{overflow-x:auto;margin:16px 0}table{border-collapse:collapse;width:100%;font-size:14px;line-height:1.65}th{text-align:left;background:#f1f3ef;color:#354142}th,td{padding:11px 12px;vertical-align:top;border-bottom:1px solid var(--line);min-width:115px}td:first-child{font-weight:600}ol{padding-left:24px}li{padding:5px 0}.sources{font-size:12px;color:var(--muted);margin-top:28px;border-top:1px solid var(--line);padding-top:12px}summary{cursor:pointer}.filters{display:grid;grid-template-columns:1fr 220px;gap:12px;margin:24px 0 12px}input,select{width:100%;min-height:48px;border:1px solid #899593;background:#fff;border-radius:10px;padding:9px 13px;color:var(--ink);font-size:14px}.label{display:block;font-size:13px;color:var(--muted);margin-bottom:6px}.result-count{font-size:13px;color:var(--muted)}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px;margin-top:18px}.app-card{border:1px solid var(--line);border-radius:14px;padding:20px;background:#fcfcf9}.app-card h3{margin:14px 0 10px;font-size:18px}.app-top{display:flex;justify-content:space-between;gap:12px}.badge{font-size:11px;background:var(--soft);color:var(--orange);border-radius:6px;padding:2px 8px}.number{font-size:11px;color:var(--muted);font-variant-numeric:tabular-nums}.purpose{font-size:14px}.path{font:11px/1.7 ui-monospace,Consolas,monospace;word-break:break-all;color:var(--muted);padding:9px;background:#eef1ed;border-radius:6px}dl{font-size:12px;margin:14px 0}dt{font-weight:600;margin-top:10px}dd{margin:1px 0;color:var(--muted)}.app-card details{font-size:12px;overflow-wrap:anywhere}.empty{padding:30px;background:#f1f3ef;border-radius:10px}footer{font-size:12px;color:var(--muted);padding:24px 0}.skip{position:absolute;left:-9999px}.skip:focus{left:16px;top:16px;background:#fff;padding:10px;z-index:5}[hidden]{display:none!important}
@media(max-width:900px){.layout{grid-template-columns:1fr;padding:0 20px 30px;gap:20px}header{padding:36px 20px 20px}nav{position:static;max-height:none;display:grid;grid-template-columns:repeat(2,minmax(0,1fr))}.chapter,.index{padding:24px}}@media(max-width:540px){body{font-size:15px}.grid,.filters{grid-template-columns:1fr}.chapter,.index{padding:20px;border-radius:14px}h2{font-size:23px}h3{font-size:18px}.stats{gap:8px}.stat{padding:10px 12px;flex:1;min-width:95px}.stat strong{font-size:21px}.stat span{font-size:11px}nav{padding:10px;font-size:12px}.app-card{padding:17px}th,td{padding:9px}.lead{font-size:16px}}@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}}@media print{body{background:#fff}header{padding:0}nav,.filters,.result-count{display:none}.layout{display:block;padding:0}.chapter,.index,.app-card{border:0;padding:0}.grid{display:block}.app-card{break-inside:avoid;margin:14px 0}.chapter{break-before:page}.sources{display:none}}
"""
script = """
const search=document.querySelector('#app-search'), category=document.querySelector('#app-category'), cards=[...document.querySelectorAll('.app-card')], count=document.querySelector('#result-count'), empty=document.querySelector('#empty');
const corpus=cards.map(card=>card.textContent.toLocaleLowerCase());
function filterApps(){const terms=search.value.trim().toLocaleLowerCase().split(/\\s+/).filter(Boolean);let visible=0;cards.forEach((card,index)=>{const show=(!category.value||card.dataset.category===category.value)&&terms.every(term=>corpus[index].includes(term));card.hidden=!show;if(show)visible++;});count.textContent=`显示 ${visible} / ${cards.length} 个应用`;empty.hidden=visible>0;}
search.addEventListener('input',filterApps);category.addEventListener('change',filterApps);filterApps();
"""
document = (
    '<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="description" content="对应已安装融合版的中文菜单说明、操作步骤与全部295个应用索引。"><title>'
    + e(content["title"])
    + "</title><style>"
    + style
    + '</style></head><body><a class="skip" href="#main">跳转到正文</a><header><div class="eyebrow">FLIPPER MOMENTUM LAB / 中文说明</div><h1>'
    + e(content["title"])
    + '</h1><p class="lead">'
    + e(content["subtitle"])
    + '</p><p class="lead">'
    + e(content["edition"])
    + '</p><div class="stats"><div class="stat"><strong>12</strong><span>使用与设置章节</span></div><div class="stat"><strong>295</strong><span>完整应用索引</span></div><div class="stat"><strong>121</strong><span>后台插件 · 非应用按钮</span></div></div><div class="scope">'
    + e(content["scope"])
    + '</div><p><a href="../../../output/pdf/flipper-fusion-manual.zh-CN.pdf">下载离线 PDF</a> · <a href="#app-index">直接查应用</a></p></header><div class="layout"><nav aria-label="手册目录">'
    + nav
    + '<a href="#app-index">附录 · 全部应用索引</a></nav><main id="main">'
    + "".join(chapters)
    + '<article class="index" id="app-index"><h2>附录 · 全部应用中文索引</h2><p class="intro">全部文件已在安装时核验；只有 Clock、Flipper Lab、SD Info 做过 USB 启动与退出验收。系统组件通常从 Settings 等菜单进入。</p><div class="filters"><label><span class="label">英文名、中文用途或路径</span><input id="app-search" type="search" placeholder="例如：红外、时钟、ESP32、clock" autocomplete="off"></label><label><span class="label">分类</span><select id="app-category">'
    + options
    + '</select></label></div><p id="result-count" class="result-count" role="status" aria-live="polite">全部 295 个应用</p><p id="empty" class="empty" hidden>没有匹配的应用。请换个关键词，或选择全部分类。</p><div class="grid">'
    + "".join(cards)
    + "</div></article><footer>依据已安装更新包、源码声明与 USB 验收。源码固定为 52f236fd，外部应用固定为 55a446b1。网页可离线搜索，不需要账号或网络；来源链接需要联网。</footer></main></div><script>"
    + script
    + "</script></body></html>"
)
(data_dir / "index.html").write_text(document, encoding="utf-8")

pdfmetrics.registerFont(TTFont("CN", str(args.font), subfontIndex=0))
pdfmetrics.registerFont(TTFont("CNB", str(args.bold_font), subfontIndex=0))
pdfmetrics.registerFontFamily(
    "CN", normal="CN", bold="CNB", italic="CN", boldItalic="CNB"
)
orange = colors.HexColor("#c34800")
ink = colors.HexColor("#182022")
muted = colors.HexColor("#596365")
line = colors.HexColor("#dfe3dd")
styles = {
    "body": ParagraphStyle(
        "BodyCN",
        fontName="CN",
        fontSize=10,
        leading=17,
        textColor=ink,
        wordWrap="CJK",
        spaceAfter=8,
    ),
    "intro": ParagraphStyle(
        "IntroCN",
        fontName="CN",
        fontSize=10.5,
        leading=17.5,
        textColor=muted,
        wordWrap="CJK",
        spaceAfter=14,
    ),
    "title": ParagraphStyle(
        "TitleCN",
        fontName="CNB",
        fontSize=29,
        leading=42,
        textColor=ink,
        wordWrap="CJK",
        spaceAfter=22,
    ),
    "h1": ParagraphStyle(
        "H1CN",
        fontName="CNB",
        fontSize=20,
        leading=30,
        textColor=ink,
        wordWrap="CJK",
        spaceAfter=12,
        keepWithNext=True,
    ),
    "h2": ParagraphStyle(
        "H2CN",
        fontName="CNB",
        fontSize=12,
        leading=20,
        textColor=orange,
        wordWrap="CJK",
        spaceBefore=10,
        spaceAfter=7,
        keepWithNext=True,
    ),
    "cell": ParagraphStyle(
        "CellCN", fontName="CN", fontSize=9, leading=14, textColor=ink, wordWrap="CJK"
    ),
    "head": ParagraphStyle(
        "HeadCN", fontName="CNB", fontSize=9, leading=14, textColor=ink, wordWrap="CJK"
    ),
    "small": ParagraphStyle(
        "SmallCN",
        fontName="CN",
        fontSize=7.5,
        leading=11.5,
        textColor=muted,
        wordWrap="CJK",
        spaceAfter=4,
    ),
    "app": ParagraphStyle(
        "AppCN",
        fontName="CN",
        fontSize=8.2,
        leading=12.5,
        textColor=ink,
        wordWrap="CJK",
    ),
}
width, height = A4
margin = 19 * mm
usable = width - 2 * margin


def P(text, style="body"):
    return Paragraph(e(text), styles[style])


def linked(label, url, style="small"):
    return Paragraph(
        '<link href="'
        + e(url, quote=True)
        + '" color="#c34800">'
        + e(label)
        + "</link>",
        styles[style],
    )


def table(headers, rows, widths=None, app=False):
    data = [[P(x, "head") for x in headers]] + [
        [P(x, "app" if app else "cell") for x in row] for row in rows
    ]
    t = LongTable(
        data,
        colWidths=widths or [usable / len(headers)] * len(headers),
        repeatRows=1,
        hAlign="LEFT",
    )
    t.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#f1f3ef")),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 9),
                ("RIGHTPADDING", (0, 0), (-1, -1), 9),
                ("TOPPADDING", (0, 0), (-1, -1), 7),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
                ("LINEBELOW", (0, 0), (-1, 0), 0.6, line),
                ("LINEBELOW", (0, 1), (-1, -1), 0.35, line),
                (
                    "ROWBACKGROUNDS",
                    (0, 1),
                    (-1, -1),
                    [colors.white, colors.HexColor("#fcfcf9")],
                ),
            ]
        )
    )
    return t


class ManualDoc(BaseDocTemplate):
    def afterFlowable(self, flowable):
        if isinstance(flowable, Paragraph) and hasattr(flowable, "bookmark"):
            text = flowable.getPlainText()
            self.canv.bookmarkPage(flowable.bookmark)
            self.canv.addOutlineEntry(text, flowable.bookmark, 0)
            self.notify("TOCEntry", (0, text, self.page, flowable.bookmark))


def decoration(canvas, doc):
    canvas.saveState()
    if doc.page > 1:
        canvas.setStrokeColor(line)
        canvas.line(margin, height - 14 * mm, width - margin, height - 14 * mm)
        canvas.setFillColor(muted)
        canvas.setFont("CN", 7.5)
        canvas.drawString(margin, height - 11 * mm, "Flipper 融合版 / 中文使用手册")
        canvas.drawRightString(
            width - margin, height - 11 * mm, "ee43b2c2 · 2026-10-01"
        )
    canvas.setFillColor(muted)
    canvas.setFont("CN", 7.5)
    canvas.drawString(margin, 11 * mm, "英文菜单名对应中文用途 · API 89.0")
    canvas.drawRightString(width - margin, 11 * mm, str(doc.page))
    canvas.restoreState()


out_dir = root / "output/pdf"
out_dir.mkdir(parents=True, exist_ok=True)
out = out_dir / "flipper-fusion-manual.zh-CN.pdf"
doc = ManualDoc(
    str(out),
    pagesize=A4,
    leftMargin=margin,
    rightMargin=margin,
    topMargin=22 * mm,
    bottomMargin=20 * mm,
    title=content["title"],
    author="Flipper Momentum Lab",
    subject=content["subtitle"],
    pageCompression=1,
)
doc.addPageTemplates(
    PageTemplate(
        id="Manual",
        frames=[
            Frame(
                margin,
                20 * mm,
                usable,
                height - 42 * mm,
                leftPadding=0,
                rightPadding=0,
                topPadding=0,
                bottomPadding=0,
            )
        ],
        onPage=decoration,
    )
)
story = [
    Spacer(1, 22 * mm),
    P("FLIPPER MOMENTUM LAB", "h2"),
    P(content["title"], "title"),
    P(content["subtitle"], "intro"),
    Spacer(1, 9 * mm),
    P(content["edition"]),
    Spacer(1, 9 * mm),
    table(
        ["使用章节", "应用索引", "后台插件"], [["12 章", "295 个 FAP", "121 个 FAL"]]
    ),
    Spacer(1, 10 * mm),
    P(content["scope"]),
    Spacer(1, 8 * mm),
    P("适合拿着设备对照阅读。先找英文菜单，再看中文用途和使用条件。", "intro"),
    Spacer(1, 12 * mm),
    P(
        "这是中文说明书，不是已经实现全局中文切换。真实蓝牙与 AIO 验收仍待完成。",
        "small",
    ),
    PageBreak(),
    P("目录", "h1"),
]
toc = TableOfContents()
toc.levelStyles = [
    ParagraphStyle(
        "TOCCN",
        fontName="CN",
        fontSize=10,
        leading=22,
        textColor=ink,
        wordWrap="CJK",
        leftIndent=0,
        firstLineIndent=0,
        spaceBefore=3,
    )
]
story += [
    toc,
    Spacer(1, 20),
    P(
        "网页版带分类筛选、关键词搜索和逐项来源链接；PDF 带目录书签，可以检索英文名或中文用途。",
        "intro",
    ),
]
for chapter in content["chapters"]:
    heading = P(chapter["title"], "h1")
    heading.bookmark = chapter["id"]
    story += [PageBreak(), heading, P(chapter["intro"], "intro")]
    for s in chapter["sections"]:
        story.append(P(s["title"], "h2"))
        story += [P(p) for p in s.get("paragraphs", [])]
        story += [P(str(i) + ". " + p) for i, p in enumerate(s.get("steps", []), 1)]
        if "table" in s:
            tb = s["table"]
            cols = len(tb["headers"])
            cw = [usable * 0.34, usable * 0.66] if cols == 2 else [usable / cols] * cols
            story += [table(tb["headers"], tb["rows"], cw), Spacer(1, 8)]
    references = " · ".join(
        '<link href="'
        + e(source_url(path), quote=True)
        + '" color="#c34800">'
        + e(Path(path).name)
        + "</link>"
        for path in chapter["sources"]
    )
    story += [Spacer(1, 6), Paragraph("本章依据：" + references, styles["small"])]

heading = P("附录 · 295 个应用中文索引", "h1")
heading.bookmark = "app-index"
story += [
    PageBreak(),
    heading,
    P(catalog["scope"], "intro"),
    P(
        "每项均按实际安装文件列出。文件已验不代表功能已全部实测。完整来源与 README 链接见网页版；系统组件通常由原生设置入口调用。"
    ),
]
index = {a["path"]: i for i, a in enumerate(apps, 1)}
for c in catalog["categories"]:
    group = [a for a in apps if a["category"] == c["name"]]
    category_heading = P(
        c["zh"] + " / " + c["name"] + " · " + str(len(group)) + " 个", "h2"
    )
    rows = []
    for a in group:
        left = Paragraph(
            "<b>"
            + str(index[a["path"]]).zfill(3)
            + " "
            + e(a["name"])
            + '</b><br/><font size="7" color="#596365">'
            + e(a["path"])
            + "</font>",
            styles["app"],
        )
        right = Paragraph(
            e(a["purpose"])
            + '<br/><font size="7.2" color="#596365">条件：'
            + e(a["dependency"])
            + "<br/>"
            + e(a["status"])
            + "</font>",
            styles["app"],
        )
        rows.append([left, right])
    t = LongTable(
        [
            [category_heading, ""],
            [P("英文名 / SD 路径", "head"), P("中文用途 / 条件 / 验收", "head")],
        ]
        + rows,
        colWidths=[usable * 0.41, usable * 0.59],
        repeatRows=2,
        hAlign="LEFT",
    )
    t.setStyle(
        TableStyle(
            [
                ("SPAN", (0, 0), (-1, 0)),
                ("BACKGROUND", (0, 1), (-1, 1), colors.HexColor("#f1f3ef")),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 8),
                ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                ("TOPPADDING", (0, 0), (-1, -1), 7),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
                ("LINEBELOW", (0, 1), (-1, -1), 0.35, line),
                (
                    "ROWBACKGROUNDS",
                    (0, 2),
                    (-1, -1),
                    [colors.white, colors.HexColor("#fcfcf9")],
                ),
            ]
        )
    )
    story += [t, Spacer(1, 12)]
story += [
    Spacer(1, 10),
    P(
        "121 个后台插件分布于 cli、js_app、metroflip、nfc、subghz、subghz_gps、totp 和 unit_tests 等应用资源目录。完整插件路径保存在配套 apps.zh-CN.json 中。",
        "small",
    ),
]
doc.multiBuild(story)
print(
    json.dumps(
        {
            "html": str(data_dir / "index.html"),
            "pdf": str(out),
            "apps": len(apps),
            "chapters": len(content["chapters"]),
            "pdf_pages": doc.page,
        },
        ensure_ascii=False,
    )
)
