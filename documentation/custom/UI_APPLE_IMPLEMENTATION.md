# Flipper Lab iPhone UI — Apple-native refinement: implementation handoff

Implemented by Claude Opus 5.5 (`claude-opus-5-5`, effort max, as requested by the caller) from
`UI_APPLE_DESIGN.md` plus the root overrides. Tools used: Read/Write/Edit/Glob/Grep only.
**Not built, not run:** no Xcode build, simulator or UI-test run was possible here. Root owns
build, tests and acceptance on Mac CI.

## Changed files (all under `mobile/FlipperLab/`)
- `App/FlipperLabApp.swift` — global `.tint(LabColor.accent)`; DEBUG test overrides untouched.
- `App/Views/RootView.swift` — four tabs 设备 · 资料库 · 任务 · 指南 via `tabItem`; forced-dark iOS 17 tab chrome removed.
- `App/Views/Theme/LabTheme.swift` — `LabColor` = `brandOrange`, `accent`, `orangeSoft`, `lcdInk`; `LabFont` = `mono`, `monoCaption`, `lcd`; `LabFormat`. Removed `labNavigation` (toolbar background/ink tint), `labTabChrome`, `labFootnote`.
- `App/Views/Theme/LabButtonStyles.swift` — every custom `ButtonStyle` deleted. Now holds two label helpers only: `PrimaryButtonLabel` (lcdInk text when enabled, system look when disabled) and `WideButtonLabel`. Call sites apply `.borderedProminent`/`.bordered` + `.controlSize(.large)`.
- `App/Views/Components/LabContainers.swift` — `ReasonNote` (info.circle, footnote secondary), `BusyRow`, `ErrorRow`, `SectionHeader` (count under the title at AX sizes, `textCase(nil)`); kept `AdaptiveStack`, `FlowLayout`. Removed LabPage/LabPanel/PixelLabel/LabDivider/LabChevron/LabProgressStrip/ErrorPanel/EmptyPanel.
- `App/Views/Components/LabBadges.swift` — `SymbolTile` (30 pt, scales with Dynamic Type up to 2×), `KindTile`, `FactRow`, `FactList`, `StepRow` (plain secondary number), `TagCapsule`, `KindFilterBar` (44 pt+ capsule pills). Removed NumberBox, StatusBadge, BulletRow, PathStrip, TagChip, KindChipBar.
- `App/Views/Pixel/DeviceHeroView.swift` — `LCDScreen` kept; the new `DeviceStatusHeader` (LCD px 2 beside the status title, then the explanation; stacks at AX sizes; motion task and Reduce Motion unchanged) replaces the D-pad/back-key hero. The file keeps its old name.
- `App/Views/Pixel/PixelArt.swift` — removed the unused `pointer` sprite.
- `App/Views/{Device,Library,RecordDetail,AnalysisSections,CompareRecords,Tasks,Guides,GuideDetail,EditRecord,DeviceFiles}View(s).swift` — rebuilt as inset-grouped `List`/`Form` pages. Large titles on the four roots, inline titles on pushed pages.
- `App/Views/ToolsView.swift` — **now comment-only (the tools here cannot delete files). Please `git rm` it.**
- `UITests/FlipperLabUITests.swift` — updated (see below).

## New IA and entry points
- 比较: 资料库 toolbar `更多` (`library.more`) → `library.compare`. Also record toolbar `更多` (`record.more`) → `record.compare`, which opens `CompareRecordsView(model:initialFirst:)` with the record pre-filled as A.
- 从 Flipper 导入: 设备 ready state `device.browseFiles`, and 资料库 `更多` → `library.importDevice`. The item is disabled with a subtitle reason (需要先在“设备”页连接 Flipper。 / 有任务正在进行。).
- 编辑 is a toolbar button (`record.edit`). 导出原始文件 (`record.export`), 与其他记录比较 and 删除记录 (`record.delete`, still opens the existing confirmation dialog) are in the record `更多` menu.
- 扩展板: its own section at the end of 指南, strings verbatim; hidden only while a guide search is active.

## Preserved behaviour
- All model calls, guards and reason strings for import, edit, export, upload, IR, delete, scan, connect and disconnect are unchanged. The 设备 page folds its two old busy messages into a single note: 有任务正在进行，详情见“任务”页。
- Analysis, compare and directory `.task(id:)` blocks are byte-identical, including `Task.detached`, cancellation checks and the loading/error/empty states. No work was moved into `body`.
- Chart: same data, linear scale, signed bars and identifiers. Negative bars/legend now use `accent` instead of `orangeDeep`. The caption keeps the units and the 512-point reduction caveat; the redundant “这是包络时序。” was dropped.
- Offline 设备 states 蓝牙不可用 once (status title). The explanation is still `lastError`, and the old 蓝牙不可用，暂时不能搜索。 note is gone. Unavailable: 打开 iPhone 设置 is prominent and 搜索 is `.bordered` + disabled.
- LCD: fixed size, `accessibilityHidden`. `device.hero` now sits on the real header group (`children: .contain`); `device.status` is on its title.
- No custom glass, `toolbarBackground`/`toolbarColorScheme` or forced scheme/font outside DEBUG. No AccentColor asset. Normal launch stays empty.

## Deliberate deviations from the design text
1. Device-state spinner sits beside the status title instead of in a separate row (it would repeat 正在搜索/正在连接).
2. The selected filter pill is `brandOrange` + `lcdInk`, not an accent fill: system white text on the dark-mode accent #FFB566 fails contrast.
3. Facts render as one row with hairlines, so `record.facts` is a real container and all facts are built together.
4. The compare truncation caveat leads its section rather than sitting in the footer, which could be 200 rows below.
5. 适用范围 is a normal section row. Guide summaries are 2 lines, unlimited at AX sizes.
6. New short menu subtitles: export 原始采集内容，不含中文名称、标签和备注; delete 只删除手机中的记录，Flipper 上的文件会保留 (有任务正在进行。 while busy).

## UI tests (three tests kept; screenshots 01–17 kept, 03 = 03-资料库菜单)
- Kept: fixture isolation, chart fully inside the viewport, disabled `record.irKey.0` with the exact reason, dark luminance < 0.3, AX3 scan ≥ 60 pt, light-glass tab contrast (now on the unselected 资料库 tab), the RGBA loop.
- Updated: `navigationBars["资料库"]`; compare reached via 资料库 → 更多 (light) and via the record menu (dark AX3).
- Added:
  - 4 tab buttons.
  - While unavailable: exactly one static text containing 蓝牙不可用, `device.openSettings` present and scan disabled.
  - `library.emptyImport` on an empty library.
  - `library.importDevice` disabled offline.
  - Record menu has export/compare/delete, and delete shows the confirmation title.
  - Compare slot A is pre-filled from the record menu (checks `value` or `label`).
- List laziness: new bounded `reveal()` (1 s wait + fixed drags, max 14) and a shared `dragUp`. `scrollUntilHittable`/`scrollFullyIntoView` behaviour is unchanged.

## Checks actually performed (static only)
- Grep of `mobile/FlipperLab` for every removed type, style, token and modifier: zero matches. `preferredColorScheme`/`dynamicTypeSize(` appear only inside `#if DEBUG`.
- Grep that every `LabColor`/`LabFont`/`LabFormat`/`PixelSprites` member used is defined, and every token/component defined is used.
- Grep of accessibility identifiers against the design §2 flow map: all present.
- Manual read-through for iOS 17 API availability (`ContentUnavailableView`, `.topBarTrailing`, two-parameter `onChange`, `navigationDestination(isPresented:)`) and for SwiftUI builder rules.

## Risks for root to verify on CI
- Menus: how UIKit exposes menu-item identifiers, subtitles and `isEnabled`. The tests match `identifier OR label BEGINSWITH title`; the subtitle itself is only verified by screenshot 03.
- `app.tabBars.buttons.count == 4` on iOS 26, and whether the delete confirmation title is exposed as an element on iOS 26.
- Enabled prominent labels rely on the inner `.foregroundStyle(lcdInk)` overriding `.borderedProminent`'s white; check 01/02 visually.
- `.controlSize(.large)` bordered buttons are assumed to be ≥ 44 pt on iOS 17 and 26. `Color.primary` bars in Charts need a visual check in 10.
- AX3 tests depend on `reveal()` for rows below the fold; tune `maxDrags` if CI devices differ.
- Out of my write scope and now stale: `mobile/FlipperLab/README.zh-CN.md` lines 12, 28, 107 and 244 still describe five pages / 工具.
