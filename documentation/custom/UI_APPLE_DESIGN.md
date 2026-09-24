# Flipper Lab iPhone UI — Apple HIG refinement spec

Scope: visual/interaction refinement of the existing Chinese companion app on top of baseline
bfc43b4a (Xcode 26.6, iPhone 17 Pro Max, iOS 26.5). No new product, services or algorithms.
Where this document conflicts with `UI_REDESIGN.md`, this document wins. Root decides.

Evidence actually viewed (real simulator captures, not mockups), all six with the Read tool:
`documentation/custom/previews/apple-baseline/01.png` (设备), `03.png` (工具), `08.png` (资料库),
`10.png` (full waveform), `12.png` (dark + accessibility text, 设备), `07.png` (设备连接 guide).
The other 11 baseline screenshots were **not** viewed. Code read: every file under
`App/Views/`, `App/FlipperLabApp.swift`, `UITests/FlipperLabUITests.swift`.

Legend: **[HIG]** = Apple's published guidance (Layout, Typography, Tab bars, Buttons,
Liquid Glass adoption, WWDC25 session 359). **[rec]** = my recommendation, not an Apple rule.
Apple publishes no mandatory corner radius or spacing grid; every pt value below is [rec].

## 1. Screenshot critique

- **01.png 设备 (light).** The decorative device (LCD + D-pad + back key, 1.5 pt ink outline,
  orange strip) fills roughly the top 30 % before any content. The same fact is stated four
  times: LCD `NO BT`, heading 蓝牙不可用, explanation 请开启蓝牙…, and the note 蓝牙不可用，暂时不能搜索。
  The disabled primary (grey slab) is visually weaker than the secondary 打开 iPhone 设置
  (heavy black outline), so the hierarchy is inverted [HIG buttons: clear primary/secondary].
  The inline title wastes the large-title affordance of a tab root. Every section carries an
  orange pixel square; the border weight of 首次连接 equals that of the action area.
- **03.png 工具.** Three of four entries duplicate other tabs: 分析与整理记录 pushes a second
  copy of LibraryView (its own search state), 功能介绍 repeats the first six guides, 从 Flipper 导入
  repeats 设备 → 浏览设备文件 [WWDC25 359: remove redundant hierarchy; HIG tab bars: distinct
  destinations]. The marketing intro panel is the first thing on screen; the two emphasised
  cards and the disabled card have the same 56 pt tile and near-identical weight, so nothing reads
  as the action to take. 扩展板 is pushed below the fold as a fourth uniform card.
- **08.png 资料库.** Tab label 资料库 vs. title 中文资料库 [HIG tab bars: consistent labels].
  Square-cornered hardware-style chips with a solid orange 全部 dominate the list they filter.
  Header meta 共 2 条 · 显示 2 条 is redundant when the counts are equal. The mono caption on a
  Chinese date (2026年9月24日) mixes two type systems in one line; row cards use a stroke instead
  of the system inset-grouped surface. Otherwise the search field and toolbar item are native.
- **10.png 波形.** The facts list is close to native. The two analyser notes sit inside the
  facts panel with a fixed-size pointer sprite; the chart caption repeats the section title
  (…这是包络时序。). The 40 000 µs gap flattens the 560 µs pulses into a hairline, so the "full
  waveform" is technically complete but visually unreadable. Every panel has the same 1 pt
  frame, so facts, chart and IR keys all carry equal weight; the IR key section starts under
  the tab bar with a pseudo-3D key face.
- **12.png dark + AX3.** The hero's light-grey outline becomes the heaviest frame on screen;
  the disabled primary is a large dark-grey slab with low-contrast text; the outlined secondary
  is again the most prominent control. The 6 pt orange square and the 2 pt-unit pointer sprite
  do not scale with text, so they shrink to specks beside AX-size Chinese [HIG typography:
  scale meaningful icons with text]. Wrapping and Dynamic Type otherwise behave correctly.
- **07.png 指南详情.** Content is good and unabridged. Presentation is six equally-weighted
  boxes (muted, bordered, bordered…); 分工 splits Chinese prose into two narrow columns on
  6.1-inch phones; bullets are hand-drawn 6 pt squares that also do not scale. A reading page
  should be a grouped list, not a stack of cards.

## 2. Information architecture (proposal: four tabs)

Proposed tabs: **设备 · 资料库 · 任务 · 指南**. The 工具 tab is removed because it is a hub of
duplicates plus one real tool (比较) and one note (扩展板); a tab whose contents live elsewhere
violates "distinct top-level destinations" [HIG tab bars] and adds a redundant navigation layer
[WWDC25 359]. 比较 becomes a contextual action where its inputs live (资料库 toolbar menu and
each record's menu), 从 Flipper 导入 joins the other import entry in 资料库 and stays the ready-state
primary action on 设备, and 扩展板 becomes the informational footer of 指南. 任务 stays a tab: it is a
genuine destination (session history), its cancel action must be one tap from anywhere while busy,
and the existing UI tests already target it. Every task state, detail and the cancel button are
retained unchanged. Root may instead keep five tabs; then 工具 must shrink to 比较 + 扩展板 only.

Reachable-flow map (identifier → new location; identifiers are kept unless marked new):

| Flow | Entry after refinement |
|---|---|
| Search / stop / connect / cancel / disconnect | 设备 root: `device.scan`, `device.stopScan`, `device.nearby.N`, `device.cancelConnect`, `device.disconnect` |
| Open Settings, clear error | 设备 unavailable state: `device.openSettings`; error section: `device.clearError` |
| Device info, file browser, download | 设备 ready: `device.browseFiles` → DeviceFilesView (`files.refresh`, `files.folder.*`, `files.import.*`) |
| Local import | 资料库 toolbar `library.import`; empty state `library.emptyImport` |
| Import from Flipper | 资料库 toolbar menu item `library.importDevice` (new; disabled with subtitle reason) |
| Search / filter | `.searchable` on 资料库; capsule pills `library.filter.*` |
| Edit / export / delete / upload | Detail toolbar 编辑 `record.edit`; menu: 导出 `record.export`, 删除 `record.delete`; in-content 上传 `record.upload` |
| Analysis, full waveform, IR single-shot | Detail sections `record.facts`, `record.pulseChart`, `record.irKey.N` + visible reason |
| Compare | 资料库 menu `library.compare` (new) and detail menu 与其他记录比较 (pre-fills A) → `compare.pickerA/B` |
| Task history / cancel | 任务 tab; running section `tasks.cancel` |
| Eight guides, full content | 指南 list `guides.row.*` → GuideDetailView; `guides.reload` |
| Retry library load | `library.retry` |

## 3. Tokens

**Typography** [HIG typography: semantic styles, Dynamic Type, minimise truncation].
Tab roots: `.navigationTitle` + `.large`; pushed pages inline. Device status: `.title2.semibold`.
Row title `.headline`; row subtitle `.subheadline` secondary; section footers/caveats
`.footnote` secondary; counts `.footnote.monospacedDigit()`. Monospaced design only for paths,
RSSI, hex and diff lines; never for Chinese or dates (use `Text(date, format:)` in the default
face). Icons beside text are SF Symbols inheriting the text style so they scale [HIG].
LCD tokens keep their fixed pixel font and stay hidden from VoiceOver (unchanged).

**Colour / surface** [HIG + Liquid Glass: system semantic colours; bars own their material].
Page `Color(.systemGroupedBackground)`; content rows `.secondarySystemGroupedBackground`
(via `List`/`Form` inset grouped, no strokes); text `.primary/.secondary/.tertiary`;
separators system. Keep only these brand tokens: `brandOrange` (#FF8200 / #FF8C1A, used for
the LCD, the primary button fill and the running-task marker), `accent` (current controlTint
#994500 / #FFB566, the app `.tint`; on light glass it must stay this dark so tab labels contrast
[HIG tab bars]), `lcdInk` #1C1917 (text on any orange fill; white on #FF8200 is ≈2.5:1 and must
never be used), `orangeSoft` for icon tiles. Remove `toolbarBackground` on navigation bars,
remove the iOS 17 forced-dark tab scheme; system bars adapt on every OS. No `.glassEffect` on
content; glass is only what the system draws for bars/toolbar items [Liquid Glass].

**Spacing** [rec; HIG layout only asks for alignment, grouping and safe areas].
Use `List`/`Form` defaults wherever possible. Custom stacks: 16 pt horizontal (system margin),
20 pt between sections, 8 pt header→content, 12 pt between stacked buttons, content max width
680 pt on iPad. Custom cards, if unavoidable: continuous 12 pt radius, no stroke.

**Buttons** [HIG buttons: ≥ 44 × 44 pt hit area on iPhone; one clearly prominent action].
- Primary (one per state/screen): `.borderedProminent` + `.controlSize(.large)` + `.tint(brandOrange)`
  + explicit `.foregroundStyle(lcdInk)`, full width. Disabled = system dimming plus a visible reason.
- Secondary: `.bordered` + `.large`, full width. Destructive: `.bordered` + `role: .destructive`.
- Inline row action (导入, 知道了, 重试): `.bordered` capsule, `.frame(minHeight: 44)` hit area.
- IR keys: `.bordered` `.large`, leading-aligned "01  Power", 2-column grid (1 column at AX sizes);
  drop the 3 pt edge and press offset (hardware imitation).
- Toolbar: system bar items and `Menu`; menu items use the two-`Text` title + subtitle form so a
  disabled item still states its reason (e.g. 从 Flipper 导入 / 需要先在“设备”页连接 Flipper).

## 4. Before → after per screen

- **设备.** Hero → compact status header: LCD at px 2 (128 × 64 pt, dolphin + arcs/sleep,
  no D-pad/back key) beside status title, name·协议 line and one explanation; VStack at AX sizes.
  State-specific single primary: idle 搜索附近的 Flipper; unavailable 打开 iPhone 设置 prominent with
  搜索 disabled `.bordered` and **no** extra note (heading already says it); scanning spinner row +
  停止搜索; connecting spinner row + 取消连接 (destructive); ready 浏览设备文件 prominent + 断开连接.
  Busy note under the primary only when `model.busy`. Then grouped sections: 附近设备 (rows,
  RSSI mono, honest empty text), 连接出错 (red icon, message, 知道了), 首次连接 (steps 01–04 as rows
  with footer 传输和分析时请保持应用在前台。), 设备报告的信息 (key mono secondary / value selectable).
  Page footer once: 个人项目，不是 Flipper Devices 的官方 App。 Large title 设备.
- **资料库.** Large title 资料库 (tab label matches). Toolbar: 导入文件 (`square.and.arrow.down`)
  + `Menu` 更多 (`ellipsis.circle`): 从 iPhone 文件导入, 从 Flipper 导入 (disabled + subtitle when not
  ready/busy), 比较两次记录. Search in the bar; capsule pills (`.bordered`, selected
  `.borderedProminent` accent) 44 pt tall. `List` inset grouped: 30 pt kind tile, name, kind · tags,
  footnote date + source (default face, middle truncation). Header shows one count
  (显示 N 条 only when a filter/search hides items). Empty: `ContentUnavailableView` with the
  pixel tray as icon, description 从 iPhone 文件或 Flipper 导入采集文件；统计、图表和比较都在手机本地完成，不上传云端。
  and the prominent import button. Not-loaded and busy/loading rows kept.
- **记录详情.** Inline title = name. Header section: tile, name `.title2`, kind · date, path
  mono row, tag capsules, notes. Toolbar: 编辑 (text button, sheet) + `Menu`: 导出原始文件
  (subtitle 不含中文名称、标签和备注), 与其他记录比较, 删除记录 (destructive → existing dialog).
  Sections: 分析结果 (facts rows; analyser notes as the section footer, verbatim), 包络时序
  (chart, legend, footer 横轴为记录顺序，纵轴为持续时间（µs）；超过 512 个点时按区间取代表值。),
  红外按钮 · 单次执行 (grid + visible reason + footer caveat), 上传 (secondary button + reason +
  footer; serial-log note stays), 原始内容 (mono, selectable, truncation footer).
  [rec, optional] `.chartYScale(type: .symmetricLog)` with labelled axis so pulses stay visible
  next to the gap; if adopted, say so in the footer. Loading/failed analysis rows kept.
- **比较.** `Form`: section 选择记录 with two menu pickers 记录 A / 记录 B (44 pt rows) and the
  line-alignment caveat as footer; empty-library reason row; 正在比较 spinner row; 无法比较 error;
  results as sections 记录 A 的统计 / 记录 B 的统计 / 按行对比 (N 处差异, truncation note as footer,
  diff blocks mono with A/B markers). Optional `init(model:initialFirst:)` for pre-fill.
- **任务.** Large title 任务. While busy: section 正在进行 (spinner + title, 取消当前任务 destructive,
  footer 取消设备操作会断开连接…). Section 本次运行: rows with SF status symbols in semantic colours
  (running `brandOrange` progress, completed `.green` checkmark.circle, failed `.red`
  xmark.circle, cancelled `.secondary` minus.circle), title, detail selectable, time footnote.
  Footer 显示本次打开应用期间最近 100 项任务…. Empty: `ContentUnavailableView` 还没有任务.
- **指南 / 指南详情.** List rows: number `.footnote` secondary, title, summary (2 lines), search in
  bar, 8 rows. Last section footer: 扩展板 note verbatim (待确认硬件 …). Detail: grouped sections
  用途 / 准备事项 (rows, no square bullets) / 操作步骤 (numbered rows) / 分工 (two stacked rows
  手机负责, Flipper 负责 with `deviceHelp` as footer) / 怎样理解结果 / 适用范围 (footer style, full text).
  Text selectable; nothing abridged.
- **编辑记录 / 设备文件.** Plain `Form` with system section headers, footer caveat, 取消/保存 bar
  items (rules unchanged). Files: path as header, limits sentence as footer, rows with folder or
  file icon, size mono, inline 导入 capsule; reasons stay beside disabled rows; refresh in bar.

## 5. SwiftUI component / file change plan

- `Theme/LabTheme.swift`: reduce `LabColor` to `brandOrange`, `accent`, `lcdInk`, `orangeSoft`;
  delete bg/surface/ink/line/tabBar tokens, `labNavigation` (toolbar background + ink tint) and
  `labTabChrome`. Keep `LabFont.lcd`, `LabFormat`. Add `AccentColor` asset (light/dark).
- `Theme/LabButtonStyles.swift`: keep one `labPrimary` (prominent + orange + ink); delete outline,
  key, card, row and chip styles in favour of `.bordered`, `List` rows and capsule pills.
- `Components/LabContainers.swift`: delete `LabPage`, `LabPanel`, `PixelLabel`, `LabDivider`,
  `LabChevron`. `ReasonNote` → `Label(text, systemImage: "info.circle")` footnote secondary.
  `LabProgressStrip` → `BusyRow` (spinner + text). `ErrorPanel` → `ErrorSection` (red symbol,
  selectable message, actions). `EmptyPanel` → `ContentUnavailableView` wrapper with the pixel tray.
  Keep `AdaptiveStack`, `FlowLayout`.
- `Components/LabBadges.swift`: `SymbolTile` 30 pt; `NumberBox` → plain secondary text;
  `StatusBadge` → symbol + text; `FactRow` two-line row; `KindChipBar` → capsule pills.
- `Pixel/DeviceHeroView.swift` → `DeviceStatusHeader` (LCD px 2 + text); delete `DPadView`,
  `BackKeyView`; keep motion task and Reduce Motion behaviour; keep `device.hero` identifier.
- `RootView.swift`: four `NavigationStack` tabs via `tabItem` (iOS 17 compatible); alert kept.
- `ToolsView.swift`: delete. `LibraryView.swift`: List, toolbar menu, pills, empty state, new
  `library.importDevice` / `library.compare` items. `DeviceView.swift`, `RecordDetailView.swift`,
  `AnalysisSections.swift`, `CompareRecordsView.swift`, `TasksView.swift`, `GuidesView.swift`,
  `GuideDetailView.swift`, `EditRecordView.swift`, `DeviceFilesView.swift`: restructure per §4;
  model calls, guards and reason strings unchanged.
- `FlipperLabApp.swift`: `.tint(LabColor.accent)`; DEBUG test overrides unchanged.
- `UITests/FlipperLabUITests.swift`: expect 4 tab buttons; `navigationBars["资料库"]`; reach
  比较记录 via 资料库 → 更多 → 比较两次记录; rename capture 03 to the open menu; add checks in §6.
  Existing luminance and tab-icon regressions stay as they are.

## 6. Acceptance checks

Visual (compare recaptured 01/03/08/10/12/07 and the remaining 11 in the same three tests):
1. No solid custom bar colour anywhere: `toolbarBackground(`, `toolbarColorScheme(` and
   `LabColor.bg` have zero matches under `App/`. Large titles on the four tab roots.
2. Page background is the system grouped colour in light and dark (dark luminance < 0.3 test
   passes); no stroked cards remain except the LCD bezel.
3. Text on any orange fill is `lcdInk`, never white; selected tab and toolbar items use `accent`;
   unselected tab icon dark-pixel fraction > 0.02 test passes on light glass.
4. Offline 设备 page states 蓝牙不可用 exactly once in visible text (LCD token excluded); one
   prominent button per state; 打开 iPhone 设置 is the prominent one when unavailable.
5. 资料库 shows no marketing intro; the privacy sentence appears only in the empty state.
6. Dynamic Type AX3 (dark): all buttons ≥ 44 pt tall, primary ≥ 60 pt (existing test), no
   truncated labels, no horizontal clipping, status header stacked vertically, every icon beside
   text visibly scaled with it (no fixed sprites except LCD and empty-state tray).
7. Reduce Motion on: LCD static, no state-change animations.
Interaction:
8. Every identifier in §2 exists and is hittable in its listed location; `record.irKey.0` is
   disabled offline with 先在“设备”页连接 Flipper。 visible next to the grid.
9. 更多 menu items 从 Flipper 导入 and detail 上传到 Flipper are disabled offline and show their
   reason (menu subtitle / inline note); no reason text is repeated elsewhere on the same page.
10. Normal launch shows no 示例 records; fixtures argument still shows exactly the two examples.
11. Cancel: while a fixture task runs, `tasks.cancel` is reachable within one tap of the 任务 tab.
12. All eight guides open and render every field of the catalogue entry, selectable.

## 7. Out of scope and open points for root

Not covered: CoreBluetooth, RPC, AppModel, parser/store, fixtures, firmware, CI. Decisions left
to root: four vs. five tabs (§2), the optional symmetric-log chart scale, and whether 删除 stays
in the detail menu or returns as a red bottom row (both keep the confirmation dialog).
