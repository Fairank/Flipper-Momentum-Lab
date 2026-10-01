# Flipper Lab iPhone 界面重设计规范

日期：2026-09-24。分支：`codex/iphone-zh-architecture`。本文是**实现规范**，不是效果图集：它规定令牌、构图、状态、文案、组件和验收项，供下一阶段直接写 SwiftUI 代码。本文没有改动任何应用代码、测试、目录 JSON 或传输层。

适用范围：`mobile/FlipperLab/App/` 下的界面层。目标 iOS 17 及以上；主要目标机 iPhone 17 Pro Max；CI 模拟器为 iPhone 16 Pro。本 App 是个人项目，不是 Flipper Devices 官方 App，界面中不得暗示官方身份。

## 0. 依据与硬性约束

### 0.1 依据的源码

| 文件 | 本文用到的内容 |
| --- | --- |
| `App/Views/RootView.swift` | 五个 Tab、设备页、设备文件页、任务页、指南列表与详情的现有结构和文案 |
| `App/Views/ToolsView.swift` | 工具页、比较记录页 |
| `App/Views/LibraryView.swift` | 资料库、记录详情、分析分区、编辑记录 |
| `App/AppModel.swift` | 可观察属性 `records`、`guides`、`tasks`、`busy`、`libraryReady`、`error`；方法 `load`、`cancelTask`、`directory`、`importDeviceFile`、`importFile`、`saveRecord`、`deleteRecord`、`upload`、`sendInfrared` |
| `App/FlipperDevice.swift` | 可观察属性 `state`、`nearby`、`info`、`deviceName`、`lastError`、`transferredBytes`、`protocolVersion`、`ready`；方法 `scan`、`connect`、`disconnect`、`cancelOperation`、`clearError`；常量：搜索 15 秒自动停止，配对与单条命令 45 秒超时，总耗时 600 秒 |
| `Sources/FlipperCore/Models.swift` | `RecordKind` 六类标题、扩展名、设备目录；`CaptureRecord`；`AnalysisReport` 的 facts、notes、buttons、pulseDurations |
| `Sources/FlipperCore/FeatureGuide.swift` | 指南字段：id、title、summary、deviceHelp、requires、steps、phoneRole、flipperRole、result、limits。**`status` 与 `phase` 目前不解码**，界面不能显示状态徽章（见第 12 节） |
| `Sources/FlipperCore/Resources/FeatureCatalog.json` | 8 篇指南的实际文案 |
| `UITests/FlipperLabUITests.swift` | 锁定的标签与结构（见 0.2） |
| `App/PreviewRecords.swift` | 仅 `-ui-testing-fixtures` 启动参数下载入两条“示例：”记录；正常启动没有任何样例数据 |

### 0.2 现有 UI 测试锁定的标签与结构（必须原样保留）

| 位置 | 锁定项 | 说明 |
| --- | --- | --- |
| Tab 栏 | 五个 Tab 标题 `设备`、`工具`、`资料库`、`任务`、`指南`，顺序不变，第一个为 `设备` | 测试用 `app.tabBars.buttons["…"]`，因此必须是原生 `TabView`，不能自绘 Tab 栏 |
| 设备页 | 导航栏标题 `设备`；启动时存在按钮 `搜索附近的 Flipper`（模拟器处于“蓝牙不可用”状态时也要存在，可禁用） | `app.navigationBars["设备"]`、`app.buttons["搜索附近的 Flipper"].exists` |
| 资料库 | 导航栏标题 `中文资料库`；工具栏按钮无障碍标签 `导入文件`；记录行是按钮且标签包含记录名 | 空状态里的导入按钮改用别的文字（`从 iPhone 文件导入`），避免同名按钮重复 |
| 工具页 | 有一个无障碍标签**精确等于** `比较两次记录` 的按钮 | 卡片含副标题时必须显式 `accessibilityLabel("比较两次记录")` |
| 比较记录 | 导航栏标题 `比较记录` | |
| 任务页 | 导航栏标题 `任务` | |
| 指南 | 指南行是按钮且标签包含指南标题；详情导航栏标题等于 `guide.title`；详情中存在静态文本 `操作步骤` | |
| 记录详情 | 存在静态文本 `分析结果` 与 `包络时序`（作为分区标题，精确匹配） | |
| 启动参数 | `-ui-testing-fixtures` 行为不变 | |

### 0.3 可显示数据白名单

界面上出现的每一个数值或状态都必须来自下表；表外的内容（电量、存储、固件版本、经验值、同步进度百分比、信号格数、在线时长等）一律不显示。

| 数据 | 来源 | 备注 |
| --- | --- | --- |
| 连接状态文字 | `device.state.rawValue` | 七个中文值已在枚举中，直接使用，不另抄一份 |
| 设备名称 | `device.deviceName` | 未连接时为默认值 `Flipper Zero`，只在就绪态显示 |
| 协议版本 | `device.protocolVersion` | 未检查时为 `未检查`，只在就绪态显示 |
| 附近设备名与 RSSI | `device.nearby` | RSSI 以 `-62 dBm` 原样显示，不换算成信号格 |
| 设备报告的信息 | `device.info` | 键名按设备返回原样显示，不翻译、不猜测含义 |
| 连接错误 | `device.lastError` | |
| 本次命令已写入字节数 | `device.transferredBytes` | 可选显示；只是当前命令的出站字节计数，不是百分比 |
| 记录、标签、备注、来源路径、创建时间 | `model.records` | |
| 分析结果 | `RecordAnalyzer.analyze` 返回的 `AnalysisReport` | 事实标题与说明句由分析器给出，界面不改写 |
| 任务标题、详情、状态、开始时间 | `model.tasks` | 仅本次运行、最多 100 条 |
| 指南内容与篇数 | `model.guides` | |
| 忙碌 | `model.busy` | |
| 资料库是否加载成功 | `model.libraryReady` | |

## 1. 设计立场

### 1.1 概念

**「放在工作台上的伙伴设备」**。设备页第一眼看到的是一台抽象化的设备正面：橙色背光的点阵屏里住着一只原创像素海豚，旁边是方向键。它用屏幕上的表情和 ASCII 令牌“说话”，中文说明用系统字体写在屏幕外面。其余四页是同一张工作台上的不同工位：工具抽屉、资料架、任务单、说明书。

### 1.2 原则

1. **伙伴而非说明书**。设备页由设备本体、状态和一个主动作构成；“首次连接”步骤退到下方，就绪后隐藏。
2. **橙色是光，不是油漆**。橙色只用于 LCD 背光、主按钮、像素标记和 Tab 选中态；正文、链接、说明文字从不使用橙色（橙色在米白底上对比度不足 3:1）。
3. **像素只出现在“设备的声音”里**。像素画、ASCII 令牌、等宽小字只用于 LCD、装饰标记、路径、十六进制和原文；中文段落一律系统字体，不做像素化。
4. **面板由内容驱动**。没有内容的面板不出现；没有的数据不编造；示例记录只在测试启动参数下出现。
5. **诚实的禁用**。每个禁用控件旁有一句具体原因，来源于当前状态（未连接、任务进行中、来源不在设备、串口日志不能上传、文件超过 2 MiB）。
6. **每屏一个主动作，每屏一种结构签名**。设备页是英雄区加主按钮；工具页是三张工具卡；资料库是筛选芯片加记录卡；任务页是时间线；指南是编号索引卡。

### 1.3 与现有实现的差异

| 项目 | 现在 | 重设计 |
| --- | --- | --- |
| 容器 | 五页全部是系统 `List`/`Form` 灰白分组 | `ScrollView` + 自定义面板；只有系统弹窗、搜索栏、文件选择器保持系统样式 |
| 设备页开头 | 一行状态文字 + 按钮 + 四步说明 | 设备英雄区（LCD + 像素海豚 + 方向键）→ 状态 → 单个主按钮 → 内容面板 |
| Tab 栏 | 系统浅色 | 墨色底栏，选中项橙色，未选中暖灰 |
| 主按钮 | 系统蓝/橙文字链接 | 橙底墨字 52pt 实体按钮 |
| 红外按钮 | 列表里的文字行 | 两列“实体按键”样式，带按下位移 |
| 类型筛选 | `Picker` 菜单 | 横向滚动的 44pt 芯片 |
| 禁用控件 | 灰掉无说明 | 灰掉并在旁边说明原因 |
| 空状态 | 系统 `ContentUnavailableView` | 像素托盘插图 + 标题 + 说明 + 可选动作 |

## 2. 设计令牌

实现建议：新建 `App/Theme/LabPalette.swift`，用 `Color(uiColor: UIColor { traits in … })` 提供动态色，不新增 Asset Catalog；十六进制转换写一个私有 `UIColor(hex:)`。

### 2.1 色彩（浅色为基准）

| 令牌 | 浅色 | 深色 | 用途 |
| --- | --- | --- | --- |
| `bg` | `#F4EFE6` | `#131110` | 页面底色（暖米白 / 暖黑） |
| `surface` | `#FFFCF7` | `#1E1B18` | 面板、卡片、输入框底 |
| `surfaceAlt` | `#EFE8DC` | `#26221E` | 机身面板、原文块、静音面板、未选中芯片按下态 |
| `ink` | `#1C1917` | `#F2ECE3` | 正文、标题、描边、LCD 像素（LCD 像素在深色模式仍用 `#1C1917`） |
| `inkSecondary` | `#57534E` | `#BDB4A8` | 次要文字、事实标题、面板正文说明 |
| `inkTertiary` | `#6B6560` | `#9A9188` | 时间、路径、脚注；在 `surfaceAlt` 上只用于 13pt 及以上 |
| `line` | `#D6CEC2` | `#3A342E` | 1pt 分隔线、普通卡片描边 |
| `orange` | `#FF8200` | `#FF8C1A` | LCD 背光、主按钮底、像素标记、Tab 选中、选中芯片 |
| `orangeDeep` | `#D96A00` | `#E07400` | 主按钮按下态与描边、图表负值柱 |
| `orangeSoft` | `#FFE3C2` | `#4A2C0F` | 类型方块底、进行中徽章底、搜索中进度条底 |
| `ok` | `#2E7D32` | `#6FCF7A` | 就绪点、成功文字 |
| `okBg` / `okText` | `#DCEFD9` / `#1F5E24` | `#1F3B22` / `#9BD9A3` | 已完成徽章 |
| `danger` | `#B42318` | `#F0716A` | 错误文字、危险按钮描边与文字 |
| `dangerBg` / `dangerText` | `#F9DCD9` / `#8E1B12` | `#4A1F1B` / `#F5A199` | 失败徽章、错误面板标题 |
| `warnText` | `#8A4B00` | `#FFB566` | “适用范围”、限制类说明的标题 |
| `tabBar` | `#1C1917` | `#131110` | Tab 栏底；深色模式加 1pt `line` 顶边 |
| `tabInactive` | `#BDB4A8` | `#BDB4A8` | Tab 未选中项 |

对比度（估算值，实现时请用工具复核，目标：正文 ≥ 4.5:1，图形与边界 ≥ 3:1）：

| 组合 | 估算 | 结论 |
| --- | --- | --- |
| `ink` on `surface` / `bg` / `surfaceAlt`（浅色） | 17 / 15 / 14 | 通过 |
| `inkSecondary` on `surface` / `bg` / `surfaceAlt`（浅色） | 7.4 / 6.7 / 6.3 | 通过 |
| `inkTertiary` on `surface` / `bg` / `surfaceAlt`（浅色） | 5.6 / 5.0 / 4.7 | 通过；`surfaceAlt` 上只用于 ≥13pt |
| `#1C1917` on `orange`（浅 / 深） | 7.0 / 7.5 | 主按钮、LCD 像素通过 |
| `orange` on `surface`（浅色，作为文字） | 2.4 | **不通过**，因此橙色不用于文字 |
| `orangeDeep` on `surface`（浅色，作为图形边界） | 3.4 | 通过（图形） |
| `ok` / `danger` / `warnText` on `surface`（浅色） | 5.0 / 6.4 / 6.7 | 通过 |
| `okText` on `okBg`；`dangerText` on `dangerBg`（浅色） | 6.5 / 6.9 | 通过 |
| `orange` / `tabInactive` on `tabBar`（浅色） | 7.0 / 8.5 | 通过 |
| 深色：`ink` / `inkSecondary` / `inkTertiary` on `surface` | 14.6 / 8.4 / 5.5 | 通过 |
| 深色：`ok` / `danger` / `warnText` on `surface` | 8.9 / 5.4 / 9.8 | 通过 |
| 深色：`okText` on `okBg`；`dangerText` on `dangerBg`；`ink` on `orangeSoft` | 7.5 / 6.7 / 10.8 | 通过 |

色彩规则：

- 文字只用 `ink`、`inkSecondary`、`inkTertiary`、`ok`、`danger`、`warnText`、`okText`、`dangerText`。
- 橙色填充上的文字永远是 `#1C1917`（浅深色相同），不是白色。
- 主按钮加 1pt `orangeDeep` 描边，保证按钮边界与底色 ≥ 3:1。
- 全局 `tint` 保持现有的 `.orange`（供系统进度指示器、Tab 选中项使用）；内容区所有文字型按钮改用第 9 节的自定义 `ButtonStyle`，不使用裸的 tint 文字链接。系统弹窗按钮沿用系统样式，属已知限制。

### 2.2 字体

全部使用系统字体与 Dynamic Type 文本样式；中文段落不使用等宽或圆体。

| 角色 | 定义 | 用途 |
| --- | --- | --- |
| `screenTitle` | 导航栏 inline 标题（系统） | 各页标题 |
| `heroStatus` | `.title2` `.semibold` | 设备页状态标题 |
| `panelTitle` | `.headline` | 卡片标题、记录名、任务标题、指南标题 |
| `body` | `.body` | 正文、事实值、步骤 |
| `bodySecondary` | `.subheadline`，色 `inkSecondary` | 说明句、摘要 |
| `label` | `.caption` `.semibold`，色 `ink` | 像素标签文字 |
| `factTitle` | `.caption`，色 `inkSecondary` | 事实标题 |
| `foot` | `.footnote`，色 `inkTertiary` | 脚注、限制说明 |
| `mono` | `.system(.footnote, design: .monospaced)` | 路径、RSSI、字节数、时间、十六进制、差异行 |
| `monoCaption` | `.system(.caption, design: .monospaced)` | 卡片右上的元信息、指南编号 |
| `raw` | `.system(.caption, design: .monospaced)`，`textSelection(.enabled)` | 原始内容预览 |
| `lcd` | `.system(size: max(10, px * 4), weight: .bold, design: .monospaced)` | 仅 LCD 内的 ASCII 令牌，不参与 Dynamic Type，`accessibilityHidden(true)` |

Dynamic Type：所有布局在 `.accessibility3` 及以上必须仍可读，规则见各屏“适配”。`ViewThatFits` 用于横排转竖排。

### 2.3 间距、圆角、描边

| 项目 | 值 |
| --- | --- |
| 基础网格 | 4pt；常用 4 / 8 / 12 / 16 / 24 / 32 |
| 页面左右内边距 | 16pt |
| 面板内边距 | 16pt；静音面板 12pt |
| 像素标签到面板 | 8pt；面板之间 12pt；分组之间 24pt |
| 圆角 | 面板 14；按钮 12；行内按钮与按键 8；芯片、徽章、LCD 内屏、路径条 4；机身卡 28；LCD 边框 6 |
| 描边 | 普通面板 1pt `line`；强调面板与机身 1.5pt `ink`（深色用 `inkSecondary`）；错误面板 1.5pt `danger`；LCD 边框 6pt 实心 `ink` |
| 控件最小高度 | 44pt（行内按钮、芯片）；次按钮 48pt；主按钮 52pt；红外按键 56pt |
| 像素单位 `px` | LCD 内一个“大像素”的边长，取 2、3 或 4pt（见 4.2） |
| 阴影 | 不用阴影；层次靠描边与底色 |

### 2.4 动效

`@Environment(\.accessibilityReduceMotion)` 为真时，下表“减少动态”列生效。

| 动效 | 默认 | 减少动态 |
| --- | --- | --- |
| 搜索中信号弧 | 4 帧循环：无 → 1 弧 → 2 弧 → 3 弧，每帧 350ms，用 `TimelineView(.periodic)` | 静态显示 3 弧 |
| 空闲眨眼（idle、ready） | 每 5 秒闭眼 120ms | 不眨眼 |
| 状态文字切换 | 0.2s 淡入淡出 | 无动画 |
| 红外按键按下 | 下移 2pt、底边由 3pt 变 1pt | 只改底色 |
| 其他 | 无 | 无 |

不做启动动画、视差、弹跳、闪烁。

### 2.5 图标

功能图标用 SF Symbols（可缩放、可读屏）；身份装饰用像素精灵（第 4.5 节）。

| 用途 | 符号 |
| --- | --- |
| Tab | 保持现有：`antenna.radiowaves.left.and.right`、`waveform.path`、`square.stack.3d.up`、`checklist`、`book.closed` |
| 类型方块：红外遥控 | `av.remote` |
| Sub-GHz 记录 | `antenna.radiowaves.left.and.right` |
| NFC 标签 | `creditcard` |
| 低频 RFID | `sensor.tag.radiowaves.forward` |
| iButton | `key` |
| 串口日志 | `terminal` |
| 目录 / 文件 | `folder` / `doc.plaintext` |
| 导入 / 导出 / 上传 | `square.and.arrow.down` / `square.and.arrow.up` / `arrow.up.doc` |
| 刷新、编辑、删除 | `arrow.clockwise`、`pencil`、`trash` |
| 手机负责 / Flipper 负责 | `iphone` / `dot.radiowaves.left.and.right` |

实现时逐个确认符号在 iOS 17 SDK 存在；缺失时退回 `doc`。

## 3. 外壳：Tab 栏、导航栏、背景

```
┌──────────────────────────────────────────┐
│ 导航栏（bg 底，ink 标题，inline）           │
│                                          │
│   页面内容：ScrollView + VStack(spacing 12)│
│   左右 16pt，底部留 24pt                   │
│                                          │
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫  ← tabBar 墨色底
┃  设备    工具    资料库    任务    指南    ┃  ← 选中：orange 图标+文字；未选中：tabInactive
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

- `RootView` 保持 `TabView` + 五个 `NavigationStack`，顺序与标题不变；保留 `.environment(\.locale, zh_CN)` 与 `操作提示` 弹窗。
- Tab 栏：`.toolbarBackground(Color.tabBar, for: .tabBar)`、`.toolbarBackground(.visible, for: .tabBar)`、`.toolbarColorScheme(.dark, for: .tabBar)`；选中色来自全局 tint。若系统未按预期渲染未选中色，用 `UITabBarAppearance` 明确设置 `tabInactive`。
- 导航栏：所有根页面 `.navigationBarTitleDisplayMode(.inline)`；`.toolbarBackground(Color.bg, for: .navigationBar)` 且 `.visible`。标题文字沿用锁定值。
- 背景：每页最外层 `Color.bg.ignoresSafeArea()`。
- 不使用 `List`、`Form`、`Section`；分区标题用第 9 节的 `PixelLabel`。
- 系统组件保持系统样式：`searchable`、`fileImporter`、`fileExporter`、`confirmationDialog`、`alert`、`Picker(.menu)`。

## 4. 设备英雄区与像素伙伴

### 4.1 构图

```
╭────────────────────────────────────────────────╮  机身卡：surfaceAlt 底，圆角 28，描边 1.5 ink
│  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━┓                  │
│  ┃                 READY      ┃      ╭─────╮     │  LCD：6pt ink 边框，内屏 orange
│  ┃                            ┃   ╭──┤  ▲  ├──╮  │
│  ┃      ▄▄                    ┃   │◀ │  ●  │ ▶│  │  方向键：ink 圆环 88pt，中心 orange
│  ┃  ▄  ▄██▄▄▄▄▄▄▄▄▄▄   ) ) )  ┃   ╰──┤  ▼  ├──╯  │
│  ┃  ▀▀▀████████████▀▀▘        ┃      ╰─────╯     │
│  ┃      ▀▀   ▀                ┃              [↩] │  返回键 28×28
│  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━┛                  │
│▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂│  底部 6pt orange 色带（背壳露出）
╰────────────────────────────────────────────────╯
```

这是抽象化的设备正面示意，不是官方渲染图，也不声称还原真机配色。不引用任何远程图片或资源文件；全部用 `Canvas`、`Path`、`RoundedRectangle`、`Circle` 绘制。

### 4.2 尺寸

- 卡片宽 = 屏宽 − 32；内边距 16；内部 `HStack(spacing: 16)`：LCD 面板、`Spacer`、方向键列（宽 88）。
- `px = clamp(floor((卡片内宽 − 16 − 88) / 64), 2, 4)`。iPhone 16 Pro 得 3（LCD 内屏 192×96），iPhone 17 Pro Max 得 4（256×128），4.7 英寸机型得 2（128×64）。
- LCD 外框 = 内屏 + 12pt（6pt 边框）；圆角外 6、内 3。
- 方向键：外环直径 88，描边 2pt `ink`；四个方向标记为 8×8 `ink` 方块（像素感，不用三角形）；中心圆 24pt，`orange` 填充、1.5pt `ink` 描边。返回键 28×28，圆角 6，`ink` 描边 1.5，中心 6×6 `orange` 方块。
- 底部色带 6pt，跟随卡片圆角裁切。
- 横屏或 iPad：卡片最大宽 520pt，居中。
- Dynamic Type ≥ `.accessibility1`：改为 `VStack`，隐藏方向键与返回键，LCD 以 `px = clamp(floor(卡片内宽 / 64), 2, 4)` 计算。

### 4.3 LCD 内容网格

内屏是 64×32 个大像素的网格。坐标以左上为 (0,0)。

| 元素 | 位置 | 说明 |
| --- | --- | --- |
| 海豚精灵 32×16 | 左下，(1, 12) | 所有状态都显示 |
| 信号弧 7×7 | (35, 16) | 搜索中动画；连接三态静态显示三弧 |
| 睡眠符号 3×3 | (30, 8) | 仅“蓝牙不可用” |
| 文本块 | 右上，右边距 2 格，顶边距 2 格，右对齐 | `lcd` 字体；1 行令牌或 2 行（就绪态）；只绘制 ASCII，遇到非 ASCII 字符整行不画 |

就绪态文本：第一行设备名（超过 13 字符截断加 `…`，`…` 由代码替换为 `~` 以保持 ASCII），第二行 `RPC ` + `protocolVersion`。其他状态文本为单行令牌，见 4.6。

### 4.4 渲染实现要点

```swift
struct PixelBitmap { let rows: [String] }          // '#' 为墨点，'.' 为空；每行等长
struct PixelBitmapView: View {
    let bitmap: PixelBitmap; let unit: CGFloat; let color: Color
    var body: some View {
        Canvas { context, _ in
            for (y, row) in bitmap.rows.enumerated() {
                for (x, ch) in row.enumerated() where ch == "#" {
                    context.fill(Path(CGRect(x: CGFloat(x) * unit, y: CGFloat(y) * unit,
                                             width: unit, height: unit)), with: .color(color))
                }
            }
        }
        .frame(width: CGFloat(bitmap.rows.first?.count ?? 0) * unit,
               height: CGFloat(bitmap.rows.count) * unit)
        .accessibilityHidden(true)
    }
}
```

- 位图数据放在 `PixelSprites.swift`，Debug 下 `assert` 每行长度一致。
- LCD 面板本身是一个 `ZStack`：橙色内屏 → 多个 `PixelBitmapView` 用 `offset(x: gx*px, y: gy*px)` 定位 → 文本块。整个 LCD `accessibilityHidden(true)`。
- 不做像素栅格纹理、不做扫描线、不做发光。

### 4.5 精灵位图（原创，随本文交付）

海豚（睁眼）32×16：

```swift
static let dolphinOpen = PixelBitmap(rows: [
"................................",
".............##.................",
".............####...............",
"..............######............",
"##............#######...........",
".##.......###############.......",
"..##...#################..##....",
"...#####################..###...",
"....############################",
"...############################.",
"..##...#####################....",
".##.......###############.......",
"##............#######...........",
"...............###..............",
"..............##................",
"................................",
])
```

海豚（闭眼，用于眨眼与“蓝牙不可用”）：只有第 7 行（索引 6）不同，换成 `"..##...#####################...."`，其余行相同。眼睛由第 7、8 行 x=24–25 的空点构成，闭眼时只剩第 8 行的一条横线。

信号弧，三张 7×7 叠加（第 n 帧绘制 arc1…arcN）：

```swift
static let arc1 = PixelBitmap(rows: [
".......", ".......", "#......", ".#.....", "#......", ".......", ".......",
])
static let arc2 = PixelBitmap(rows: [
".......", "..#....", "...#...", "...#...", "...#...", "..#....", ".......",
])
static let arc3 = PixelBitmap(rows: [
"....#..", ".....#.", "......#", "......#", "......#", ".....#.", "....#..",
])
```

睡眠符号 3×3：

```swift
static let sleep = PixelBitmap(rows: ["###", ".#.", "###"])
```

空状态托盘 16×7（用于所有空状态插图，颜色 `inkSecondary`，`px = 4`）：

```swift
static let tray = PixelBitmap(rows: [
"#..............#",
"#..............#",
"#..............#",
"#..............#",
"#....######....#",
"#...#......#...#",
"################",
])
```

### 4.6 状态映射

| `device.state` | 海豚帧 | 叠加 | LCD 令牌 | 屏幕外状态标题 | 解释句（`bodySecondary`） | 主控件 | 次控件 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `idle` 尚未连接 | 睁眼，空闲眨眼 | 无 | `NO LINK` | `state.rawValue` | 搜索附近已开启蓝牙的 Flipper，每次搜索最长 15 秒。 | 主按钮 `搜索附近的 Flipper`（`busy` 时禁用） | 无 |
| `scanning` 正在搜索 | 睁眼 | 信号弧动画 | `SCAN` | 同上 | 请把 Flipper 放在手机旁边，15 秒后会自动停止。 | 进度条形（不可点）：`ProgressView` + `正在搜索…` | 次按钮 `停止搜索` → `disconnect()` |
| `connecting` 正在配对与连接 | 睁眼 | 三弧静态 | `PAIR` | 同上 | 首次配对时，在 iPhone 弹出的窗口中输入 Flipper 屏幕上的 6 位配对码；超过 45 秒未完成会自动断开。 | 进度条形 `正在连接…` | 危险按钮 `取消连接` → `disconnect()` |
| `discovering` 正在准备通信 | 睁眼 | 三弧静态 | `SETUP` | 同上 | 正在订阅 Flipper 的串口服务。 | 进度条形 `正在连接…` | 同上 |
| `negotiating` 正在检查设备 | 睁眼 | 三弧静态 | `CHECK` | 同上 | 正在检查协议版本并读取设备信息。 | 进度条形 `正在连接…` | 同上 |
| `ready` 设备已就绪 | 睁眼，空闲眨眼 | 无 | 两行：设备名 / `RPC x.y` | 同上；下方 `mono` 一行 `设备名 · 协议 x.y` | 可以浏览设备文件并导入记录；资料库中的记录可以上传到 Flipper。 | 主按钮 `浏览设备文件 ›`（`NavigationLink`，`busy` 时禁用） | 危险按钮 `断开连接` |
| `unavailable` 蓝牙不可用 | 闭眼 | 睡眠符号 | `NO BT` | 同上 | `device.lastError`；为空时显示 `请开启 iPhone 蓝牙。` | 主按钮 `搜索附近的 Flipper`，禁用 | 可选：次按钮 `打开 iPhone 设置`（`UIApplication.openSettingsURLString`） |

错误面板：`lastError != nil` 且 `state == .idle` 时，在主控件下方显示错误面板（1.5pt `danger` 描边，标题 `连接出错`，正文 `lastError`，行内按钮 `知道了` → `device.clearError()`）。`unavailable` 时错误文本已作为解释句显示，不再重复面板。

### 4.7 无障碍

- 机身卡 `accessibilityElement(children: .ignore)`，标签：`Flipper 设备示意图，状态：\(state.rawValue)`；就绪时追加 `，\(deviceName)，协议版本 \(protocolVersion)`。
- LCD、精灵、方向键、返回键全部 `accessibilityHidden(true)`；它们不承载屏幕外没有的信息。
- 状态标题和解释句是普通文本，VoiceOver 按顺序朗读。
- 就绪态 `ok` 色小圆点只是装饰，文字已表达状态。

## 5. 各屏规格

通用：每页 = `ScrollView { VStack(alignment: .leading, spacing: 12) }`，左右 16pt，顶部 8pt，底部 24pt。像素标签在面板外部上方。

### 5.1 设备（`DeviceView`）

结构签名：英雄区 + 状态 + 单个主动作。

```
┌ 导航栏：设备 ─────────────────────────────┐
│ ╭ 机身卡（第 4 节）╮                        │
│ ╰──────────────────╯                        │
│ 设备已就绪                                   │  heroStatus
│ Flipper Kaeru · 协议 0.25                    │  mono（仅就绪）
│ 可以浏览设备文件并导入记录；…                  │  bodySecondary
│ ┌────────────────────────────────────────┐  │
│ │           浏览设备文件  ›              │  │  主按钮 52pt
│ └────────────────────────────────────────┘  │
│ [ 断开连接 ]                                 │  危险按钮 48pt
│                                              │
│ ■ 设备报告的信息                              │  像素标签（仅 info 非空）
│ ┌────────────────────────────────────────┐  │
│ │ <键名 monoCaption>                      │  │
│ │ <值 body，可选中>                        │  │
│ │ ──────────────────────────────────────  │  │
│ │ …                                      │  │
│ └────────────────────────────────────────┘  │
│ 个人项目，不是 Flipper Devices 的官方 App。    │  foot
└──────────────────────────────────────────────┘
```

未就绪时（`idle`、`scanning`、连接三态、`unavailable`）：

```
│ [主控件 / 进度条形]                           │
│ [次控件]                                     │
│ ┌ 错误面板（仅 idle 且 lastError 非空）┐      │
│ │ 连接出错                              │      │
│ │ <lastError>                 [知道了]  │      │
│ └───────────────────────────────────────┘      │
│ ■ 附近设备           <N 台 monoCaption>        │  仅 idle / scanning
│ ┌────────────────────────────────────────┐  │
│ │ Flipper Kaeru                 -62 dBm  ›│  │  行按钮 ≥44pt，RSSI mono
│ │ ──────────────────────────────────────  │  │
│ │ 正在搜索，请将设备放在手机旁。（空态）     │  │
│ └────────────────────────────────────────┘  │
│ ■ 首次连接                                   │  仅未就绪
│ ┌────────────────────────────────────────┐  │
│ │ 01 在 Flipper 设置中开启蓝牙。            │  │  编号 monoCaption + body
│ │ 02 允许本应用使用 iPhone 蓝牙。           │  │
│ │ 03 选择设备，在 iPhone 输入 Flipper 屏幕上的配对码。│
│ │ 04 等待“设备已就绪”后操作。               │  │
│ │ 传输和分析时请保持应用在前台。模拟器无法验证真实蓝牙连接。│ foot
│ └────────────────────────────────────────┘  │
```

规则：

- 附近设备行：`Button` → `device.connect`；禁用条件与现有一致（`busy` 或状态不是 `scanning`/`idle`）。空态文案：`scanning` 时 `正在搜索，请将设备放在手机旁。`，否则 `搜索后在这里选择设备。`。`unavailable` 时不显示此面板。
- “设备报告的信息”只在 `info` 非空时出现；键按 `keys.sorted()`；值 `textSelection(.enabled)`。
- 主按钮 `搜索附近的 Flipper` 在 `idle`、`unavailable` 显示（`unavailable` 禁用），保证启动即存在。
- 可选忙碌条：`busy` 时在状态标题上方显示静音面板 `正在处理，详情见“任务”页。`。

适配：≥ `.accessibility1` 时英雄区竖排（4.2）；按钮文字允许两行。

验收 A1–A8：

- A1 启动即存在按钮 `搜索附近的 Flipper`，导航栏标题 `设备`。
- A2 七个状态各有对应的 LCD 令牌、海豚帧、标题、解释句和控件，按 4.6 表逐项核对。
- A3 模拟器上显示“蓝牙不可用”、闭眼海豚、睡眠符号，解释句为 `lastError` 原文。
- A4 `lastError` 在 `idle` 时显示错误面板，`知道了` 清除。
- A5 就绪态显示设备名与协议版本，均来自模型；不显示任何表外数据。
- A6 减少动态开启时无眨眼、无弧动画。
- A7 VoiceOver 朗读机身卡为一句状态描述，LCD 不单独朗读。
- A8 `.accessibility5` 下所有文字完整、按钮可点。

### 5.2 设备文件（`DeviceFilesView`）

```
┌ ‹ 设备    设备文件 / <目录名>         [刷新] ┐
│ ┌ /ext/infrared ┐                            │  PathStrip：mono，surfaceAlt 底，可选中
│ 选择文件导入手机；支持红外、Sub-GHz、NFC、RFID、iButton 和文本日志，单个文件最多 2 MiB。 │ foot
│ ┌────────────────────────────────────────┐   │
│ │ ▢ subghz                              › │   │  目录行：folder 方块 + 名称
│ │ ──────────────────────────────────────  │   │
│ │ tv_remote.ir                            │   │  文件行：名称 ≤3 行
│ │ 1.2 KB                       [ 导入 ]   │   │  大小 mono；行内按钮 44pt
│ │ ──────────────────────────────────────  │   │
│ │ big_capture.sub                         │   │
│ │ 3.1 MB   ▸ 超过 2 MiB，不能导入  [ 导入 ] │   │  禁用原因 + 禁用按钮
│ └────────────────────────────────────────┘   │
```

- 状态：`loading` → 面板内 `ProgressView("读取目录…")`；`failure` → 错误面板；空 → 面板内一行 `此目录为空。`（不用大插图，避免层层目录都出现插图）。
- 目录行 `NavigationLink`，`busy` 时禁用；文件行 `导入` 按钮禁用条件与现有一致，原因文案：超过 2 MiB → `超过 2 MiB，不能导入`；`busy` → `有任务正在进行`。
- 标题规则保持：根目录 `设备文件`，子目录为最后路径分量。

验收 B1–B4：B1 路径条可选中；B2 三种加载状态各自正确；B3 超限文件按钮禁用且有原因；B4 刷新按钮在 `busy` 或未就绪时禁用。

### 5.3 工具（`ToolsView`）

结构签名：三张大工具卡。

```
┌ 导航栏：工具 ─────────────────────────────┐
│ ┌────────────────────────────────────────┐  │  静音面板
│ │ 让手机处理记录，让 Flipper 连接硬件       │  │  panelTitle
│ │ 导入真实采集文件后，在手机本地完成统计、图表、搜索和比较。分析过程不上传云端。│ bodySecondary
│ └────────────────────────────────────────┘  │
│ ■ 记录工具                                   │
│ ┌────────────────────────────────────────┐  │  工具卡：强调面板，≥88pt，整卡可点
│ │ ▣  分析与整理记录                      › │  │  28pt 符号在 orangeSoft 方块内
│ │    统计、图表、搜索，全部在手机本地完成。   │  │
│ └────────────────────────────────────────┘  │
│ ┌────────────────────────────────────────┐  │
│ │ ▣  比较两次记录                        › │  │  accessibilityLabel 精确为“比较两次记录”
│ │    同类型的两条记录按行对比。              │  │
│ └────────────────────────────────────────┘  │
│ ┌────────────────────────────────────────┐  │
│ │ ▣  从 Flipper 导入                     › │  │  未就绪或 busy 时禁用
│ │    浏览设备存储，把文件导入资料库。         │  │
│ │    ▸ 需要先在“设备”页连接 Flipper。       │  │  禁用原因（仅禁用时）
│ └────────────────────────────────────────┘  │
│ ■ 功能介绍                                   │
│ ┌────────────────────────────────────────┐  │
│ │ 01 设备连接                            › │  │  前 6 篇指南，行 ≥44pt
│ │ 02 中文资料库                          › │  │
│ │ …                                      │  │
│ └────────────────────────────────────────┘  │
│ ■ 扩展板                                     │
│ ┌────────────────────────────────────────┐  │  静音面板
│ │ [待确认硬件]  等待确认板卡型号            │  │  芯片：surfaceAlt + inkSecondary
│ │ ESP32 和“WiFi 终结者”需要精确型号、接线与固件版本后才能适配。当前可以导入已保存的文本日志，尚未实现实时串口采集。│
│ └────────────────────────────────────────┘  │
```

- 三张卡的目的地保持：`LibraryView`、`CompareRecordsView`、`DeviceFilesView(path: "/ext")`。
- 禁用原因：`!device.ready` → `需要先在“设备”页连接 Flipper。`；`busy` → `有任务正在进行。`。
- 扩展板面板没有按钮。

验收 C1–C4：C1 `比较两次记录` 可被精确标签命中并推入 `比较记录`；C2 三卡目的地正确；C3 禁用卡有原因；C4 指南行数 ≤ 6 且点击进入详情。

### 5.4 资料库（`LibraryView`）

结构签名：筛选芯片 + 记录卡。

```
┌ 导航栏：中文资料库                 [导入文件] ┐
│ 🔍 名称、标签、备注                           │  系统 searchable
│ [全部][红外遥控][Sub-GHz 记录][NFC 标签][低频 RFID][iButton][串口日志]  横向滚动，44pt 芯片
│ ■ 记录               共 12 条 · 显示 12 条     │  像素标签 + monoCaption 元信息（真实计数）
│ ┌────────────────────────────────────────┐  │
│ │ ▣  客厅电视遥控                        › │  │  KindTile 44 + panelTitle
│ │    红外遥控 · 客厅 / 电视                 │  │  bodySecondary（类型 · 标签）
│ │    2026-09-24   /ext/infrared/tv.ir      │  │  mono：日期 + 来源路径或“来自 iPhone 文件”
│ └────────────────────────────────────────┘  │
│ ┌ 空状态面板 ┐                               │
│ │   [托盘精灵]                            │  │
│ │   这里还没有记录                          │  │  panelTitle
│ │   从 iPhone 文件或 Flipper 设备导入，随后可离线分析。│ bodySecondary
│ │   [ 从 iPhone 文件导入 ]                  │  │  主按钮；触发同一个 fileImporter
│ └─────────────────────────────────────────┘  │
```

- 未加载（`!libraryReady`）：顶部错误面板 `资料库尚未加载。加载失败时会保留原文件，请先重试。` + 行内按钮 `重试加载`（`busy` 禁用）；此时不显示芯片与空状态插图。
- 芯片：`全部` + `RecordKind.allCases` 的 `title`；选中态 `orange` 底 + `#1C1917` 字 + 1pt `orangeDeep` 描边；未选中 `surface` + 1pt `line`；`accessibilityAddTraits(.isButton)`，选中加 `.isSelected`。
- 搜索与过滤逻辑与现有 `visible` 相同。
- 记录卡是 `NavigationLink`，无障碍标签由名称、类型、标签自然拼接（包含名称即可）。
- 工具栏 `导入文件` 按钮保持 `Label("导入文件", systemImage:)`，`busy` 或未加载时禁用。
- 有筛选或搜索但无结果时，空状态标题改为 `没有匹配的记录`，说明 `换一个类型或关键词试试。`，不显示导入按钮。

适配：芯片在大字号下自动增高；记录卡元信息行在 ≥ `.accessibility1` 时换行显示。

验收 D1–D6：D1 标题 `中文资料库`，工具栏按钮标签 `导入文件`；D2 芯片 ≥44pt、选中态可读；D3 记录卡标签含名称，测试样本 `示例：客厅遥控` 可点；D4 空状态无样例数据；D5 未加载态有重试；D6 计数为真实数量。

### 5.5 记录详情（`RecordDetailView`）

结构签名：记录牌 + 分析面板 + 按键区。

```
┌ ‹ 返回     <记录名，inline>                    ┐
│ ┌ 记录牌（强调面板）───────────────────────┐   │
│ │ ▣ 红外遥控                   2026-09-24  │   │  KindTile + kind.title + 日期 mono
│ │ /ext/infrared/tv.ir                       │   │  PathStrip，无路径显示“来自 iPhone 文件”
│ │ [客厅] [电视]                              │   │  静态标签芯片（surfaceAlt，caption）
│ │ 备注段落…                                  │   │  body（有备注才显示）
│ │ [编辑名称、标签与备注]   [导出原始文件]      │   │  次按钮 48pt；ViewThatFits 竖排
│ └───────────────────────────────────────────┘   │
│ ■ 分析结果                                       │  静态文本精确“分析结果”
│ ┌───────────────────────────────────────────┐   │
│ │ 文件类型                                   │   │  FactRow：factTitle + body 可选中
│ │ IR signals file（遥控器）                   │   │
│ │ 按钮数量                                   │   │
│ │ 3                                          │   │
│ │ …                                          │   │
│ │ ▸ 原始信号记录的是解调后的包络…             │   │  notes：foot，前缀 ▸（像素小三角，橙）
│ └───────────────────────────────────────────┘   │
│ ■ 包络时序                                       │  静态文本精确“包络时序”
│ ┌───────────────────────────────────────────┐   │
│ │  ▌▌ ▌  ▌▌▌ ▌ ▌  ▌▌   BarMark：正值 ink，负值 orangeDeep │
│ │ 横轴为记录顺序，纵轴为持续时间（微秒）。…     │   │  现有说明句，caption
│ └───────────────────────────────────────────┘   │
│ ■ 红外按钮 · 单次执行                             │  仅红外且 buttons 非空
│ ┌──────────────────┐ ┌──────────────────┐        │
│ │ 01  Power        │ │ 02  Vol_up       │        │  按键样式 56pt，两列网格
│ └──────────────────┘ └──────────────────┘        │
│ ▸ 此记录来自 iPhone 文件，需先上传到 Flipper 才能执行。│  禁用原因（仅禁用时，按优先级取一句）
│ 先连接 Flipper 并上传此记录。执行前会核对设备文件；执行后请观察家电响应。│ foot
│ ■ 上传                                           │  kind.deviceDirectory != nil
│ [ 上传到 Flipper ]  ▸ 需要先在“设备”页连接 Flipper。│  次按钮 + 原因
│ 每次生成独立文件并读回核对。中文名称和备注保存在手机。│ foot
│ （串口日志）串口日志只保存在手机，不能作为设备应用文件上传。│ 静音面板，替代上传区
│ ■ 原始内容                                       │
│ ┌───────────────────────────────────────────┐   │  surfaceAlt 底，raw 字体，可选中
│ │ Filetype: IR signals file                  │   │
│ │ …（前 16,384 字符）                         │   │
│ └───────────────────────────────────────────┘   │
│ 预览仅显示前 16,384 个字符；导出包含完整内容。      │  foot（仅超长时）
│ [ 删除手机中的记录 ]                              │  危险按钮
```

- 分析状态：`report == nil && failure == nil` → 分析面板位置显示 `ProgressView("正在分析…")`；`failure` → 错误面板（标题 `无法分析`，正文 `failure`）。
- 红外按键禁用原因优先级：`!device.ready` → `先在“设备”页连接 Flipper。`；`sourcePath` 不以 `/ext/infrared/` 开头 → `此记录来自 iPhone 文件，需先上传到 Flipper 才能执行。`；`busy` → `有任务正在进行。`。按键标签 `\(index + 1). \(name)`，编号以 `monoCaption` 两位显示但无障碍标签保持 `1. Power` 形式。
- 上传按钮禁用原因：`!device.ready` → `需要先在“设备”页连接 Flipper。`；`busy` → `有任务正在进行。`。
- 记录被删除后：`ContentUnavailableView("记录已删除", systemImage: "doc")` 并自动返回，行为不变。
- 编辑 sheet、导出、删除确认沿用现有逻辑与文案。
- 图表：`Chart` 高度 `@ScaledMetric` 180，最大 260；保留现有 `accessibilityLabel`。

验收 E1–E8：E1 `分析结果`、`包络时序` 静态文本存在且精确；E2 样本 `示例：客厅遥控` 打开后可上滑看到图表；E3 按键网格 ≥56pt、两列、禁用时有原因；E4 串口日志显示不能上传的说明而非禁用按钮；E5 原文块可选中、超长提示正确；E6 删除流程不变；E7 深色模式下图表两种柱可区分；E8 `.accessibility3` 下按键改单列。

### 5.6 编辑记录（`EditRecordView`）

```
┌ 取消        编辑记录          保存 ┐
│ ■ 中文名称                          │
│ ┌────────────────────────────────┐ │  文本框：surface，1pt line，圆角 8，≥48pt
│ │ 客厅电视遥控                     │ │
│ └────────────────────────────────┘ │
│ ■ 标签                              │
│ ┌────────────────────────────────┐ │
│ │ 客厅, 电视                       │ │  占位：标签，用逗号分隔
│ └────────────────────────────────┘ │
│ ■ 备注                              │
│ ┌────────────────────────────────┐ │  TextEditor，最小高 160
│ └────────────────────────────────┘ │
│ 只修改手机资料库里的名称与说明，保留原始采集数据。 │ foot
```

- 保存、取消、名称为空时禁用、保存中禁止下滑关闭：全部沿用现有逻辑。
- 聚焦时描边改 1.5pt `ink`。

验收 F1–F3：F1 三个字段可编辑并保存；F2 名称为空时 `保存` 禁用；F3 大字号下字段自动增高。

### 5.7 比较记录（`CompareRecordsView`）

```
┌ ‹ 工具        比较记录                        ┐
│ ┌ 记录 A ────────────────┐ ┌ 记录 B ────────┐ │  两个“槽位”面板，ViewThatFits 竖排
│ │ [请选择            ▾]  │ │ [请选择     ▾] │ │  Picker(.menu)，≥44pt
│ └────────────────────────┘ └────────────────┘ │
│ 同类型记录更容易比较。文本按相同行号对比；插入一行会影响后续行的对应关系。│ foot
│ 正在比较…（comparing）                          │
│ ■ 记录 A 的统计                                 │  FactRow 列表
│ ■ 记录 B 的统计                                 │
│ ■ 按行对比            <N 处差异 monoCaption>     │
│ ┌────────────────────────────────────────────┐ │  每处差异一个 surfaceAlt 块
│ │ 第 12 行                                    │ │  label
│ │ A  9000 4500 560 …                          │ │  mono；A 标记 ink 方块
│ │ B  9000 4500 580 …                          │ │  mono；B 标记 orangeDeep 方块
│ └────────────────────────────────────────────┘ │
│ 内容较多，结果已截短。最多比较前 5,000 行…         │  foot（limited 时）
```

- 差异字符串来自 `RecordComparison`，界面只做展示拆分：按换行拆成 3 段时分别渲染，否则整段以 `mono` 显示。比较逻辑不改。
- 无差异：`两份文本内容相同。` 或 `已比较范围内没有差异。`（沿用）。

验收 G1–G3：G1 标题 `比较记录`；G2 选择两条记录后出现三个分区；G3 截短提示正确。

### 5.8 任务（`TasksView`）

结构签名：进行中卡 + 时间线。

```
┌ 导航栏：任务 ───────────────────────────────┐
│ ┌ 进行中（强调面板，仅 busy）────────────────┐ │
│ │ ◌ 正在处理…                               │ │  ProgressView + panelTitle
│ │ 上传 客厅电视遥控                           │ │  当前 running 任务标题（tasks 中 state == .running 的第一条）
│ │ 本次命令已写入 12,288 字节                   │ │  可选，mono，transferredBytes > 0 时
│ │ [ 取消当前任务 ]                            │ │  危险按钮
│ │ 取消设备操作会断开连接；已写入设备的部分文件可能保留。│ foot
│ └───────────────────────────────────────────┘ │
│ ■ 本次运行                 <N 项 monoCaption>   │
│ ┌───────────────────────────────────────────┐ │
│ │ [已完成]  上传 客厅电视遥控                  │ │  徽章 + panelTitle
│ │ 已上传并读回核对：/ext/infrared/Lab_….ir     │ │  bodySecondary，可选中
│ │ 14:02:11                                   │ │  mono
│ ├───────────────────────────────────────────┤ │
│ │ [失败]    执行红外按钮                       │ │
│ │ 请先将此红外记录上传至当前设备。               │ │
│ │ 13:58:40                                   │ │
│ └───────────────────────────────────────────┘ │
│ ┌ 空状态 ┐ [托盘精灵] 还没有任务 / 导入、保存或执行后的结果会显示在这里。 │
│ 显示本次打开应用期间最近 100 项任务。设备确认执行后，仍需观察实际家电或硬件的响应。│ foot
```

- 徽章映射：`进行中` → `orangeSoft` 底 + `ink`；`已完成` → `okBg`/`okText`；`失败` → `dangerBg`/`dangerText`；`已取消` → `surfaceAlt` + `inkSecondary`。徽章文字直接用 `task.state.rawValue`。
- 时间格式沿用 `hour().minute().second()`。

验收 H1–H4：H1 标题 `任务`；H2 空状态无样例；H3 四种徽章在深浅色均可读；H4 `busy` 时出现进行中卡并可取消。

### 5.9 指南（`GuidesView`）

结构签名：编号索引卡。

```
┌ 导航栏：功能指南 ───────────────────────────┐
│ 🔍 搜索功能                                    │
│ ■ 离线说明                 共 8 篇 monoCaption   │
│ ┌───────────────────────────────────────────┐ │
│ │ 01  设备连接                             › │ │  编号：32×32 surfaceAlt 方块内 monoCaption
│ │     通过蓝牙连接 Flipper，检查通信协议版本并显示设备信息。│ bodySecondary，≤2 行
│ ├───────────────────────────────────────────┤ │
│ │ 02  中文资料库                           › │ │
│ └───────────────────────────────────────────┘ │
│ ┌ 空状态 ┐ [托盘精灵] 指南尚未加载 [ 重新加载 ] │
```

- 过滤逻辑沿用（标题 + 摘要包含关键词）。编号按 `guides` 原顺序。
- 行是 `NavigationLink`，无障碍标签含标题。

验收 I1–I3：I1 含 `设备连接` 的行可点并推入同名详情；I2 搜索仍可用；I3 空状态有重新加载按钮。

### 5.10 指南详情（`GuideDetail`）

```
┌ ‹ 指南        设备连接（inline）              ┐
│ ┌ 用途（静音面板）──────────────────────────┐ │
│ │ 通过蓝牙连接 Flipper，检查通信协议版本并显示设备信息。│ body
│ └───────────────────────────────────────────┘ │
│ ■ 准备事项                                     │
│ ┌───────────────────────────────────────────┐ │
│ │ ▪ iPhone 已开启蓝牙，并允许 Flipper Lab 使用蓝牙 │ 6×6 ink 方块作项目符号
│ │ ▪ …                                        │ │
│ └───────────────────────────────────────────┘ │
│ ■ 操作步骤                                     │  静态文本精确“操作步骤”
│ ┌───────────────────────────────────────────┐ │
│ │ 01  在 Flipper 上进入 Settings → Bluetooth…  │ │  编号 monoCaption 在 orangeSoft 方块 28×28
│ │ 02  …                                       │ │
│ └───────────────────────────────────────────┘ │
│ ■ 分工                                         │
│ ┌────────────────────┬──────────────────────┐ │  ViewThatFits：两列或竖排
│ │ 📱 手机负责          │ ▣ Flipper 负责        │ │  panelTitle + 符号
│ │ 搜索 Flipper 的蓝牙…  │ 显示配对码…            │ │  body
│ │                      │ ▸ 打开蓝牙并回到主界面… │ │  deviceHelp，foot
│ └────────────────────┴──────────────────────┘ │
│ ■ 怎样理解结果                                 │  普通面板，body
│ ■ 适用范围                                     │  标签文字色 warnText；普通面板，body
```

- 七个分区标题：用途、准备事项、操作步骤、手机负责 / Flipper 负责（合并为“分工”面板，但两个小标题原文保留）、怎样理解结果、适用范围。
- 步骤编号从 1 起，格式两位。

验收 J1–J3：J1 标题为 `guide.title`，存在静态文本 `操作步骤`；J2 分工面板在 `.accessibility1` 以上竖排；J3 `适用范围` 完整显示。

## 6. 状态图

### 6.1 设备连接（`FlipperDevice.state`）

```
                 scan()                  connect(d)               服务与流控就绪        握手成功
 [idle] ───────────────► [scanning] ───────────────► [connecting] ──────────► [discovering] ─► [negotiating] ─► [ready]
   ▲        15 秒自动停止 ◄───┘  │                        │                      │                 │              │
   │                            │ disconnect()           │ 45 秒超时 / 失败 → fail()：lastError 置值，回到 idle  │
   │◄───────────────────────────┴────────────────────────┴──────────────────────┴─────────────────┴──────────────┘
   │                                    disconnect() / cancelOperation() / 任何 fail()
   │
 [unavailable] ◄──── 蓝牙关闭或未授权（任何时刻）；恢复后回到 idle，lastError 清空
```

界面映射见 4.6。`unavailable` 下调用 `scan()` 只会刷新 `lastError`，不会进入 `scanning`。

### 6.2 任务（`AppModel.perform`）

```
 [无任务] ── 触发操作 ──► [running, busy = true] ──┬─► [completed]  busy = false
                                                    ├─► [failed]     busy = false，弹出“操作提示”
                                                    └─► [cancelled]  busy = false（取消不弹窗）
 忙碌时再次触发 → 不新建任务，直接弹出“正在处理其他操作”类错误
```

界面：`busy` 决定进行中卡与所有设备/写入按钮的禁用；任务卡徽章跟随状态。

### 6.3 资料库加载

```
 [未加载 libraryReady = false] ── load() ──► [已加载]  或  [加载失败：records 为空，error 弹窗，页面顶部错误面板 + 重试]
```

### 6.4 记录详情分析

```
 [分析中 report = nil, failure = nil] ──► [有结果 report] 或 [失败 failure]；record 被删除 → “记录已删除”并返回
```

### 6.5 比较

```
 [未选满] ──选满──► [comparing] ──► [result] 或 [failure]；改变选择 → 回到 comparing
```

## 7. 空状态与错误状态汇总

| 位置 | 触发 | 插图 | 标题 | 说明 | 动作 |
| --- | --- | --- | --- | --- | --- |
| 资料库 | 无记录 | 托盘 | 这里还没有记录 | 从 iPhone 文件或 Flipper 设备导入，随后可离线分析。 | 从 iPhone 文件导入 |
| 资料库 | 有记录但筛选无结果 | 无 | 没有匹配的记录 | 换一个类型或关键词试试。 | 无 |
| 资料库 | 未加载 | 无 | 资料库尚未加载 | 加载失败时会保留原文件，请先重试。 | 重试加载 |
| 任务 | 无任务 | 托盘 | 还没有任务 | 导入、保存或执行后的结果会显示在这里。 | 无 |
| 指南 | 未加载 | 托盘 | 指南尚未加载 | 无 | 重新加载 |
| 设备文件 | 目录为空 | 无 | 此目录为空。 | 无 | 无 |
| 设备文件 | 读取失败 | 无 | 无法读取目录 | `failure` 原文 | 刷新 |
| 附近设备 | 空 | 无 | 正在搜索，请将设备放在手机旁。 / 搜索后在这里选择设备。 | 无 | 无 |
| 设备页 | `lastError` 且 idle | 无 | 连接出错 | `lastError` 原文 | 知道了 |
| 记录详情 | 分析失败 | 无 | 无法分析 | `failure` 原文 | 无 |
| 记录详情 | 记录已删除 | 系统 | 记录已删除 | 无 | 自动返回 |
| 比较 | 失败 | 无 | 无法比较 | `failure` 原文 | 无 |

错误面板样式统一：1.5pt `danger` 描边、标题 `dangerText`、正文 `ink`、可选中。

## 8. 微文案总表

“锁定”列为 Y 的文案受现有 UI 测试约束，不能改动。

| 屏幕 | 文案 | 锁定 |
| --- | --- | --- |
| Tab | 设备 / 工具 / 资料库 / 任务 / 指南 | Y |
| 设备 | 导航栏 `设备` | Y |
| 设备 | `搜索附近的 Flipper` | Y |
| 设备 | `停止搜索`、`取消连接`、`断开连接`、`浏览设备文件`、`知道了`、`连接出错`、`打开 iPhone 设置`（可选） | |
| 设备 | 状态标题：`device.state.rawValue` | |
| 设备 | 解释句：见 4.6 表 | |
| 设备 | `附近设备`、`首次连接`、`设备报告的信息` | |
| 设备 | `正在搜索，请将设备放在手机旁。` / `搜索后在这里选择设备。` | |
| 设备 | 首次连接四步与脚注：沿用现有文本 | |
| 设备 | `个人项目，不是 Flipper Devices 的官方 App。` | |
| 设备 | `正在处理，详情见“任务”页。`（可选忙碌条） | |
| 设备文件 | `设备文件`、`刷新`、`导入`、`读取目录…`、`此目录为空。`、`无法读取目录`、`超过 2 MiB，不能导入`、`有任务正在进行` | |
| 工具 | 导航栏 `工具` | |
| 工具 | `比较两次记录`（无障碍标签精确） | Y |
| 工具 | `分析与整理记录`、`从 Flipper 导入`、`记录工具`、`功能介绍`、`扩展板`、`待确认硬件`、`需要先在“设备”页连接 Flipper。`、`有任务正在进行。` | |
| 工具 | 工具卡副标题：`统计、图表、搜索，全部在手机本地完成。` / `同类型的两条记录按行对比。` / `浏览设备存储，把文件导入资料库。` | |
| 资料库 | 导航栏 `中文资料库` | Y |
| 资料库 | 工具栏 `导入文件` | Y |
| 资料库 | `从 iPhone 文件导入`、`记录`、`全部`、`共 N 条 · 显示 M 条`、`这里还没有记录`、`没有匹配的记录`、`重试加载`、`来自 iPhone 文件` | |
| 记录详情 | `分析结果`、`包络时序` | Y |
| 记录详情 | `编辑名称、标签与备注`、`导出原始文件`、`红外按钮 · 单次执行`、`上传`、`上传到 Flipper`、`原始内容`、`删除手机中的记录`、`正在分析…`、`无法分析` | |
| 记录详情 | 禁用原因：`先在“设备”页连接 Flipper。` / `此记录来自 iPhone 文件，需先上传到 Flipper 才能执行。` / `有任务正在进行。` / `需要先在“设备”页连接 Flipper。` | |
| 记录详情 | `串口日志只保存在手机，不能作为设备应用文件上传。` | |
| 编辑记录 | `编辑记录`、`取消`、`保存`、`中文名称`、`标签，用逗号分隔`、`备注` | |
| 比较 | 导航栏 `比较记录` | Y |
| 比较 | `记录 A`、`记录 B`、`请选择`、`正在比较…`、`记录 A 的统计`、`记录 B 的统计`、`按行对比`、`无法比较`、`N 处差异` | |
| 任务 | 导航栏 `任务` | Y |
| 任务 | `正在处理…`、`取消当前任务`、`本次运行`、`还没有任务`、`本次命令已写入 N 字节`（可选） | |
| 指南 | 导航栏 `功能指南`、`搜索功能`、`离线说明`、`共 N 篇`、`指南尚未加载`、`重新加载` | |
| 指南详情 | 标题 `guide.title`；静态文本 `操作步骤` | Y |
| 指南详情 | `用途`、`准备事项`、`分工`、`手机负责`、`Flipper 负责`、`怎样理解结果`、`适用范围` | |
| LCD 令牌 | `NO LINK` / `SCAN` / `PAIR` / `SETUP` / `CHECK` / `READY`（就绪态改为两行真实值）/ `NO BT` | |

所有中文标点用全角；数字与单位之间留半角空格；引号用“ ”。

## 9. 组件清单与文件划分

每个文件控制在 150 行以内；`App/` 下的子目录会被 XcodeGen 递归收录，新增文件后需重新生成工程（CI 已执行）。

| 文件 | 内容 | 输入 |
| --- | --- | --- |
| `Theme/LabPalette.swift` | 2.1 全部色彩令牌，`Color` 静态属性 | 无 |
| `Theme/LabTypography.swift` | 2.2 字体角色的 `Font`/修饰符 | 无 |
| `Theme/LabMetrics.swift` | 间距、圆角、描边、最小高度常量 | 无 |
| `Theme/LabButtonStyles.swift` | `LabPrimaryButtonStyle`、`LabSecondaryButtonStyle`、`LabDestructiveButtonStyle`、`LabCompactButtonStyle`、`LabKeyButtonStyle` | `isEnabled`、`reduceMotion` |
| `Pixel/PixelBitmap.swift` | `PixelBitmap`、`PixelBitmapView`（4.4） | rows、unit、color |
| `Pixel/PixelSprites.swift` | 4.5 全部位图 | 无 |
| `Pixel/LCDPanel.swift` | 橙色内屏 + 边框；接收 `frame: DolphinFrame`、`overlay: LCDOverlay`（none / arcs(n) / sleep）、`lines: [String]`、`px` | 见 4.3 |
| `Pixel/DPadView.swift` | 方向键与返回键 | 无 |
| `Pixel/DeviceHeroView.swift` | 机身卡；根据 `device.state` 与动效环境计算帧与叠加；无障碍标签 | `FlipperDevice` |
| `Components/LabPanel.swift` | 面板容器，`style: .neutral / .emphasis / .danger / .muted` | 内容闭包 |
| `Components/PixelLabel.swift` | 6×6 橙方块 + 标签文字 + 右侧可选 `meta` | title、meta |
| `Components/ReasonNote.swift` | `▸` 像素三角 + `foot` 原因句 | text |
| `Components/StatusBadge.swift` | 任务状态徽章 | `TaskEntry.State` |
| `Components/FactRow.swift` | 事实标题 + 值 | `AnalysisFact` |
| `Components/KindTile.swift` | 44×44 类型方块 | `RecordKind` |
| `Components/ChipBar.swift` | 横向芯片，`selection: Binding<RecordKind?>` | `RecordKind.allCases` |
| `Components/EmptyPanel.swift` | 托盘精灵 + 标题 + 说明 + 可选按钮 | title、message、action |
| `Components/PathStrip.swift` | 等宽路径条 | path |
| `Components/StepRow.swift` | 两位编号 + 文本 | index、text |
| `Views/RootView.swift` | 仅外壳（Tab、locale、弹窗） | `AppModel` |
| `Views/DeviceView.swift` | 5.1 | |
| `Views/DeviceFilesView.swift` | 5.2 | |
| `Views/ToolsView.swift` | 5.3 | |
| `Views/CompareRecordsView.swift` | 5.7，`RecordComparison` 原样迁入 | |
| `Views/LibraryView.swift` | 5.4，`RawRecordDocument` 原样迁入 | |
| `Views/RecordDetailView.swift` | 5.5 | |
| `Views/AnalysisSections.swift` | 分析结果、包络时序、红外按键 | `AnalysisReport` |
| `Views/EditRecordView.swift` | 5.6 | |
| `Views/TasksView.swift` | 5.8 | |
| `Views/GuidesView.swift` | 5.9 | |
| `Views/GuideDetailView.swift` | 5.10 | |

按钮样式细则：

| 样式 | 高度 | 底 | 描边 | 文字 | 按下 | 禁用 |
| --- | --- | --- | --- | --- | --- | --- |
| Primary | 52，圆角 12，撑满 | `orange` | 1pt `orangeDeep` | `.headline`，`#1C1917` | 底 `orangeDeep` | 底 `surfaceAlt`，描边 `line`，字 `inkTertiary` |
| Secondary | 48，圆角 12 | `surface` | 1.5pt `ink` | `.headline`，`ink` | 底 `surfaceAlt` | 描边 `line`，字 `inkTertiary` |
| Destructive | 48，圆角 12 | `surface` | 1.5pt `danger` | `.headline`，`danger` | 底 `dangerBg` | 同 Secondary 禁用 |
| Compact | 44，圆角 8，横向内边距 14 | `surface` | 1pt `ink` | `.subheadline.semibold`，`ink` | 底 `surfaceAlt` | 描边 `line`，字 `inkTertiary` |
| Key（红外） | ≥56，圆角 8 | `surface` | 1.5pt `ink` + 3pt 底边 `ink` | `.headline`，`ink` | 下移 2pt，底边 1pt | 描边 `line`，无底边，字 `inkTertiary` |

所有按钮 `.contentShape(Rectangle())`，最小高度不因 Dynamic Type 缩小。

## 10. 非目标

- 不新增功能、不改 `FlipperDevice`、`AppModel` 的方法语义、不改 `FlipperCore`、不改目录 JSON 与测试。
- 不显示电量、存储空间、固件版本（`info` 中设备原样返回的键值除外）、经验值、成就、同步百分比、信号格数、连接时长。
- 不自绘 Tab 栏，不做手势导航，不做启动页动画，不做主题切换设置（跟随系统深浅色）。
- 不引入字体文件、图片资源、第三方包；不新增 Asset Catalog（App 图标另议）。
- LCD 内不渲染中文；中文永远在屏幕外以系统字体显示。
- 不做 iPad 专属布局，只要求不崩坏。
- 不为“扩展板”提供任何操作入口或状态显示。
- 不在正常启动时注入任何示例记录或示例任务。
- 不做后台运行、通知、触觉以外的系统集成；触觉为可选项。

## 11. 实现顺序与验收总表

建议顺序：令牌与组件 → 外壳 → 英雄区与精灵 → 设备页 → 资料库与记录详情 → 其余页面 → 无障碍与深色模式检查 → 跑 CI UI 测试并查看导出的截图。

| 编号 | 检查项 | 方法 |
| --- | --- | --- |
| G1 | 0.2 表中全部锁定项不变，两条 UI 测试不改动即通过 | CI `FlipperLabUITests` |
| G2 | 界面上没有 0.3 白名单以外的数据 | 全文检索“电量”“存储”“XP”“进度”“%” |
| G3 | 浅色、深色各截一遍五页 + 详情，文字对比度符合 2.1 | 截图 + 对比度工具 |
| G4 | `.accessibility5` 下五页可用，无截断 | 模拟器辅助功能设置 |
| G5 | 减少动态开启时无任何循环动画 | 模拟器设置 |
| G6 | 所有可点控件 ≥ 44pt | Xcode 视图调试 |
| G7 | VoiceOver 顺序：标题 → 状态 → 主动作 → 面板 | 真机或模拟器辅助功能检查器 |
| G8 | 正常启动资料库与任务为空且无样例 | 不带参数启动 |
| G9 | 精灵位图各行等长，Debug 断言通过 | 单元或启动检查 |
| G10 | 各屏验收 A–J 全部核对 | 逐项 |

CI 通过只证明离线界面；蓝牙相关状态（搜索、配对、就绪、错误）在没有真机前只能在代码层面按 4.6 表核对。

## 12. 可选项与需要模型改动的事项

以下不属于本次界面实现的必做范围；若采纳，需要在实现阶段单独评估并改动模型代码。

| 事项 | 说明 |
| --- | --- |
| 指南状态徽章（已编写未验证 / 编写中 / 需先确认硬件） | `FeatureGuide` 未解码 `status`、`phase`；增加可选字段后才能显示。显示时用 `surfaceAlt` 芯片，文字为中文说明，不用颜色暗示“可用” |
| 跨 Tab 跳转（如就绪态“去资料库”） | `RootView` 需要 `@State` 选中项绑定；本文未依赖此能力 |
| `打开 iPhone 设置` | 用 `UIApplication.openSettingsURLString`；只在 `unavailable` 显示 |
| 进行中卡显示 `transferredBytes` | 文案必须写明是“本次命令已写入”，不是百分比 |
| 就绪时触觉 | `.sensoryFeedback(.success, trigger: device.ready)` |
| Tab 选中指示条 | `UITabBarAppearance.selectionIndicatorImage` 画一条 6×3 橙色像素条；需在真机核对是否显示 |
| 忙碌条 | 设备页与资料库顶部的静音面板 |
