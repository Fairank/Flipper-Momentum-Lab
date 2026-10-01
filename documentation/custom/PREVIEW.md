# 屏幕布局预览（Flipper Lab）

记录日期：2026-09-24。本文说明 `scripts/render_lab_preview.py` 的用途、计算依据和证明范围。

**源码布局预览，非真机截图。** 脚本只根据源码计算像素，没有运行固件、模拟器或真机。
主控已运行全部画面的生成，退出码 0、65 个画面、无警告，并打开菜单、蓝牙与红外 PNG 检查。手机界面另由 GitHub macOS CI 导出真实模拟器截图，二者证据类型不同。

## 用途

`scripts/render_lab_preview.py` 把 Flipper Lab（`applications/main/lab/`）的每个画面在
128×64 位图上重放一遍，输出：

| 文件 | 内容 |
| --- | --- |
| `<name>.svg` | 一个画面；`viewBox` 为 128×64，每个像素一个单位，`shape-rendering="crispEdges"`。含 `<title>` 与 `<desc>`（后者写明"非真机截图"）。 |
| `<name>.png` | 同一位图按 `--scale` 整数放大的索引色 PNG（背景橙色、字形黑色），由标准库 `zlib`/`struct` 写出。 |
| `index.html` | 图库：按主题分组的 2× 缩略图、说明、布局常量表、警告列表。无脚本、无外部资源，可直接用 `file://` 打开。 |

默认画面：主题列表（选中第一个主题，文件 `menu-<首个主题 id>`，当前为 `menu-about`）、
`bluetooth` 全部页（`bluetooth-01` … `bluetooth-07`）、`infrared` 全部页。
`--all` 追加所有主题的所有页，以及选中每个主题时的列表画面（`menu-<id>`），用于检查滚动与滚动条位置。

## 运行

```text
python scripts/render_lab_preview.py                          # 写入 documentation/custom/previews/
python scripts/render_lab_preview.py --all                    # 全部主题、全部页、全部列表状态
python scripts/render_lab_preview.py --output-dir D:\tmp\lab  # 目录可在仓库之外，不存在则创建
python scripts/render_lab_preview.py --topic nfc --topic gpio --scale 3 --no-png
```

| 参数 | 说明 |
| --- | --- |
| `--output-dir` | 输出目录，默认 `documentation/custom/previews`。不限制在仓库内。 |
| `--scale` | PNG 像素放大倍数，也是 SVG 的固有宽高（默认 4）。缩略图固定 2×。 |
| `--topic ID` | 要渲染的主题 id，可重复；默认 `bluetooth`、`infrared`。未知 id 记为警告。 |
| `--all` | 渲染全部主题、全部页和全部列表状态；忽略 `--topic`。 |
| `--no-png` | 只写 SVG 与 `index.html`。 |
| `--source` / `--symbol` / `--content` | 与生成器相同的输入，默认取 `generate_lab_font.py` 的 `DEFAULT_SOURCE`（`lib/u8g2/u8g2_fonts.c`）、`DEFAULT_SYMBOL`（`u8g2_font_wqy12_t_gb2312`）、`DEFAULT_CONTENT`（`lab_content.json`）。 |

退出码：`0` 完成；`1` 完成但有警告（stderr 与 `index.html` 都列出）；`2` 无法渲染（输入不可读、
JSON 结构无效、字体提取失败、无法导入生成器）。

警告的情形：生成器会拒绝的内容（`check_layout` 失败，此时仍按固件的截断路径画出）、
源字体缺字（u8g2 的行为是不画、不进位，预览照此处理）、`lab_draw_text()` 实际发生截断、
未知的主题 id。这些都表示当前内容不会原样通过 `generate_lab_font.py`。

脚本只依赖 Python 3.9 标准库，并在运行时导入同目录的 `generate_lab_font.py`。

## 计算依据

### 输入全部来自生成器

脚本没有第二个字体解析器。它调用 `generate_lab_font.py` 的
`load_content`、`extract_font`、`parse_font`、`required_codes`、`build_subset`、`verify_subset`、
`Metrics.glyph`（内部是 `decode_glyph`）、`check_layout`、`render_content_header`、`describe`，
并使用其 `SCREEN_W/SCREEN_H`、`DEFAULT_*` 常量和 `Glyph` 字段（`width/height/x/y/advance/pixels`）。

- 字形像素：先按生成器的方式构造字体子集并用 `verify_subset` 校验，再用同一解码器取像素。
  子集里的字形字节与将来写入 `lab_font.h` 的字节相同（都是从 `u8g2_fonts.c` 原样复制）。
  子集构造失败时退回完整源字体并记警告。
- 布局常量：直接解析 `render_content_header()` 输出中的 `#define LAB_* 值`，
  因此与生成器写入 `lab_content.h` 的数值同源；缺任何一个都报错退出。
  `index.html` 的"布局常量"折叠表列出这些值，可与生成后的 `lab_content.h` 逐项核对。

如果另一位委派修改了生成器的上述函数名或返回结构，本脚本会以 `AttributeError`/`TypeError`
回溯失败，不会静默给出错误图像。

### 绘制调用逐一对应

| 固件源码 | 预览实现 | 说明 |
| --- | --- | --- |
| `lab_app.c:121-136` `lab_draw_callback` | `Renderer.menu` / `Renderer.detail` 开头 | 清屏、黑色、自定义字体。每个画面一个全新的 `Frame`。 |
| `lab_app.c:42-58` `lab_draw_text` | `Renderer.text` | 先量宽，放得下就整串画；否则按 UTF-8 边界逐字节试探到 `LAB_TEXT_MAX_BYTES`，取最后一个放得下的前缀。 |
| `lab_app.c:60-77` `lab_draw_chrome` | `Renderer.chrome` | 页码右对齐到 `LAB_INDICATOR_RIGHT`，标题可用宽度 = `INDICATOR_RIGHT - GAP - TEXT_X - 页码宽`；两条横线 x 从 0 到 127；页脚。 |
| `lab_app.c:80-83` `lab_first_row` | `Renderer.menu` 内 `first` | 选中项尽量居中：`0` 或 `min(topic-1, count-rows)`。 |
| `lab_app.c:85-107` `lab_draw_menu` | `Renderer.menu` | 每行 `top = ROWS_TOP + row*ROW_H`，基线 `top + ROW_BASELINE`；选中行先画 `LIST_W×ROW_H` 黑框，再以白色画字（反白）；最后画滚动条。 |
| `lab_app.c:109-119` `lab_draw_detail` | `Renderer.detail` | 空行跳过；基线同列表行。 |
| `applications/services/gui/elements.c:71-95` `elements_scrollbar_pos` | `Renderer.scrollbar` | `x = canvas_width = 128`：先白色清 3 像素宽轨道，`x-2` 列每隔一行一个点，再画 3 像素宽滑块。 |
| `gui/canvas.c:220-226` `canvas_draw_str` → `u8g2_DrawUTF8` | `Renderer.draw_str` | 见下"像素规则"。 |
| `gui/canvas.c:271-275` `canvas_string_width` → `u8g2_GetUTF8Width` | `Renderer.width` | 各字形 `advance` 之和，最后一个找到的字形改用 `width + x`；与生成器 `Metrics.width` 同一公式，另外模拟了缺字时 u8g2 的状态。 |
| `gui/canvas.c:504-509` / `544-551` / `481-486` | `Frame.box` / `Frame.hline` / `Frame.dot` | `u8g2_DrawBox`、`u8g2_DrawLine`（水平，两端含）、`u8g2_DrawPixel`；超出 128×64 的像素丢弃。 |

### 像素规则

- 基线：`lib/u8g2/u8g2_font.c:515-521`，字形顶行 = 基线 − (字形高 + y 偏移)；
  `u8g2_DrawGlyph`（`:718-737`）加的 `font_calc_vref` 在默认基线模式下为 0（`:936-941`）。
  例如某个字形若高 12、y 偏移 −2，则在基线 24 时占第 14 到 25 行，正好是一整行 `ROW_H = 12`
  （具体字形的高和偏移由解码器逐字给出，未在本文核对）。
- 透明字体模式：`canvas.c:214-218` 设 `u8g2_SetFontMode(1)`，只画墨点，不画字形背景（`u8g2_font.c:437`）。
- 颜色：`ColorBlack` 置位、`ColorWhite` 清零；选中行因此反白。
- 滚动条浮点：`block_h = (float)height / total`，滑块 `y + block_h*pos` 传入 `int32_t` 截断，
  `MAX(block_h, 1)` 传入 `size_t` 截断。脚本用 `struct.pack("f")` 把每一步舍入到单精度。
  对当前内容（10 个主题、轨道 36 像素）逐一验算，滑块顶部为 14、17、21、24、28、32、35、39、42、46，
  高 3 像素；这些值不依赖乘加是否被编译器合并为 FMA。

## 能证明什么，不能证明什么

| 项目 | 结论 |
| --- | --- |
| 字形像素与 `lab_font.h` 将包含的字节一致 | 由构造保证：同一源字节、同一解码器。未与设备上 u8g2 的解码结果比对。 |
| 坐标、基线、反白、分隔线、页码、页脚、滚动条与 `lab_app.c`/`elements.c` 一致 | 逐行人工对照编写（上表）。已运行生成脚本并查看代表性 PNG；未与设备逐像素比对。 |
| 布局常量与 `lab_content.h` 一致 | 解析生成器自身的输出；`lab_content.h` 已生成且生成器 `--check` 通过。 |
| u8g2 运行时行为（基线、透明模式、剪裁） | 来自阅读 `lib/u8g2/u8g2_font.c` 与 `gui/canvas.c` 的推断，未在设备上验证。 |
| 脚本能运行、输出可打开 | 已证明：全部输出成功，PNG 已由图像查看器解码。 |
| 固件可编译、应用可运行、真机显示效果 | 未证明，也不是本脚本的目标。 |

## 已知近似与假设

- 背景色 `#ff8200` 是屏幕背光的近似色，不是实测；真机像素有间隙和亮度差异。
- 只模拟亮色模式。Momentum 的 `dark_mode`（`canvas.c:148-167`）会整体反色，未模拟。
- 假定应用在 `GuiLayerFullscreen` 全屏层，画布 128×64、偏移 0，没有状态栏叠加。
- 资源包（asset pack）字体替换只影响 `canvas_set_font`，本应用每帧调用
  `canvas_set_custom_u8g2_font`（`lab_app.c:130`），因此不受影响。
- 字体字形的许可问题见 `applications/main/lab/README.md`，预览输出会包含这些字形的位图。

## 实际运行与产物

```text
python scripts/render_lab_preview.py --all --output-dir ../flipper-tools/flipper-previews
```

2026-09-24 运行成功：65 张 SVG、65 张 PNG 和 `index.html`；10 个菜单状态、55 页说明，无警告。已打开代表性的菜单、蓝牙说明、红外说明 PNG。字库已生成，`generate_lab_font.py --check` 与 30 项字库测试通过。

工作流 `lab-validation.yml` 新增同样的全部页面渲染，上传 `flipper-source-previews-<attempt>`，保留 14 天；此工作流修改待下一次 CI 验证。

手机旧版截图来自 run 35975959905 的 `iphone-screenshots-1`，真实运行设备是 iPhone 16 Pro / iOS 18.5 模拟器，示例记录明确标记为示例。用户要求重做手机 UI，旧图不作为新版交付；新版按 iPhone 17 Pro Max / iOS 26.5 配置重新截图，运行结果见 VALIDATION.md。

Flipper 真机按键响应、中文显示和设备上 u8g2 解码仍需真机核对。
