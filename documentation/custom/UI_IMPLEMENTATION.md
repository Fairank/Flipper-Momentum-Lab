# Flipper Lab iPhone 界面重设计：实现交接

日期：2026-09-24。分支：`codex/iphone-zh-architecture`。依据：[UI_REDESIGN.md](UI_REDESIGN.md) 及主助手的六条修订。

**本文是 Opus 委派完成时的源码交接记录。** 当时尚未编译或测试；以下未验证说明保留为历史记录。之后主控已完成编译、运行、截图检查及导航栏对比度修正，最终证据见 [UI_REVIEW.md](UI_REVIEW.md) 的“最终验收”。

## 1. 文件

全部位于 `mobile/FlipperLab/App/Views/`（修订 1：Theme/Pixel/Components 都放在 Views 之下）。

| 文件 | 内容 |
| --- | --- |
| `Theme/LabTheme.swift` | `LabColor`（§2.1 全部色值，`UIColor` 动态色，不用 Asset Catalog）、`LabFont`、`LabFormat`、`labNavigation(_:)`（inline 标题 + 暖色导航栏）、`labTabChrome()`（墨色 Tab 栏）、`Text.labFootnote()` |
| `Theme/LabButtonStyles.swift` | Primary 52pt、Secondary/Destructive 48pt、Compact 44pt、红外 Key 56pt（3pt 底边，按下 1pt；减少动态时只换底色）、Card、Row、Chip；均读取 `isEnabled` 画真实禁用态 |
| `Pixel/PixelArt.swift` | `PixelBitmap`、`PixelShape`（`Path` 绘制）、`PixelBitmapView`、原创精灵：海豚（睁眼/闭眼）、三段信号弧、睡眠 Z、托盘、原因指针 |
| `Pixel/DeviceHeroView.swift` | LCD（64×32 格，`px` 取 4/3/2，`ViewThatFits` 选择）、方向键、返回键、机身卡、状态映射、眨眼与信号弧动画 |
| `Components/LabContainers.swift` | `LabPage`、`LabPanel`、`PixelLabel`、`ReasonNote`、`LabProgressStrip`、`ErrorPanel`、`EmptyPanel`、`AdaptiveStack`、`FlowLayout` 等 |
| `Components/LabBadges.swift` | `SymbolTile`/`KindTile`、`NumberBox`、`StatusBadge`、`FactRow`/`FactList`、`StepRow`、`BulletRow`、`PathStrip`、`TagChip`、`KindChipBar` |
| `RootView.swift` | 只剩外壳：原生 `TabView` 五页各自 `NavigationStack`、`zh_CN`、`操作提示` 弹窗（仍显示 `model.error`） |
| `DeviceView.swift`、`DeviceFilesView.swift`、`ToolsView.swift`、`CompareRecordsView.swift`、`LibraryView.swift`、`RecordDetailView.swift`、`AnalysisSections.swift`、`EditRecordView.swift`、`TasksView.swift`、`GuidesView.swift`、`GuideDetailView.swift` | 各屏，一屏一文件 |

另改：`App/FlipperLabApp.swift`（全局 tint 改为 `LabColor.orange`；`#if DEBUG` 下的 `UITestPresentation`），`UITests/FlipperLabUITests.swift`，本文件。未改 `AppModel.swift`、`FlipperDevice.swift`、`PreviewRecords.swift`、`FlipperCore`、包测试、`project.yml`、工作流与设计文档。新建子目录由 XcodeGen 的 `App` 递归收录，需要重新生成工程（CI 已执行 `xcodegen generate`）。

## 2. 保留的行为

- 连接：`scan`/`disconnect`（停止搜索、取消连接、断开）/`connect`/`clearError` 调用与原来相同；附近设备行的禁用条件原样保留；名称与 RSSI 原样显示（`-62 dBm`）；`lastError` 实时显示。BLE、超时和命令流程未改。
- 设备信息按 `keys.sorted()` 原样显示，值可选中；设备文件浏览、刷新、导入的调用与 `.task(id:)` 逻辑不变，导入按钮禁用条件不变（忙碌、未就绪、超过 2 MiB）。
- 资料库：`fileImporter`、搜索与类型过滤的 `visible` 算法、加载失败重试不变；工具栏按钮仍是 `导入文件`。
- 记录详情：分析仍在 `Task.detached` 中执行；编辑 sheet、`fileExporter`、删除确认文案与 `onChange` 自动返回不变；上传按钮条件不变；原文预览仍为前 16,384 个字符（改用 `prefix` 判断截断，不再每次计数全文）。
- 红外：仍由用户逐次点击调用 `model.sendInfrared(record, index:)`；禁用条件与原来完全一致（未就绪、忙碌、来源不在 `/ext/infrared/`），另按优先级显示原因。
- 比较：`RecordComparison.make` 原样迁入 `CompareRecordsView.swift`（5,000 行、200 处差异、每行 240 字符上限不变），仍在后台任务中执行；界面只把已有的“第 N 行 / A: / B:”字符串拆开显示，格式不符时整段原样显示。
- 任务：进行中卡、`cancelTask()`、徽章文字直接用 `task.state.rawValue`；时间格式不变。
- 指南：搜索规则（标题 + 摘要）不变；详情七项内容全部显示。
- 示例数据：只来自 `AppModel` 在 `-ui-testing-fixtures` 下载入的 `PreviewRecords`，名称与标签带“示例”；正常启动为空。

## 3. 视觉与交互变化

- 五页和详情页都改为 `ScrollView` + 主题面板；背景延伸到导航栏和 Tab 栏之下。只有编辑记录使用原生 `Form`（按主助手约束，数据录入用 Form），但隐藏系统底色并换用暖色行底与像素标签。
- 设备页：机身卡（LCD 海豚 + 方向键 + 返回键 + 底部橙色色带）→ 状态标题（`state.rawValue`）→ 解释句 → 单个主动作 → 面板。LCD 只画 ASCII 令牌（`NO LINK`/`SCAN`/`PAIR`/`SETUP`/`CHECK`/`NO BT`，就绪时为真实设备名与 `RPC` 版本），整块对 VoiceOver 隐藏，机身卡作为一个元素朗读状态。无电量、信号格、经验值或进度百分比。
- 修订 3：未显示 `transferredBytes`。修订 4：`discovering` 的解释句为 `正在准备连接…`。
- 每个禁用控件旁都有具体原因（未连接、任务进行中、超过 2 MiB、来源不在设备红外目录等）。限制说明紧贴对应动作：导出不含中文名称与备注、删除只影响手机、上传生成独立文件、比较截短说明位于差异列表上方。
- 大字号（accessibility 档）下：机身卡隐藏方向键、只保留 LCD；横排改竖排（`AdaptiveStack`）；红外按键改单列；中文不缩字。
- 动效：搜索时信号弧 350ms 一帧，空闲/就绪每 5 秒眨眼 120ms，状态文字 0.2s 淡入淡出；“减少动态”开启时全部静止。

与规范的有意差异：`lastError` 在除“蓝牙不可用”外的任何状态都显示错误面板（规范只写 idle，这样不丢失原先的实时错误显示）；`unavailable` 时搜索按钮按规范禁用并提供可选的 `打开 iPhone 设置`；精灵用 `Shape`/`Path` 而不是 `Canvas` 绘制；位图不用 Debug 断言，海豚每行写成 4 个 8 格块以便核对，初始化器按最宽行对齐，因此不会在测试中崩溃（规范 G9 的断言未实现）。

## 4. UI 测试

`UITests/FlipperLabUITests.swift` 现有 3 项（原为 2 项）。控件用稳定的 accessibility identifier 定位，锁定的中文文案再对 `label` 断言；Tab、导航栏标题、`分析结果`、`包络时序`、`操作步骤` 仍按文字查找。

| 测试 | 覆盖 | 截图附件（`.keepAlways`） |
| --- | --- | --- |
| `testOfflineNavigationAndChineseGuide` | 五个 Tab、`搜索附近的 Flipper`、离线状态只能是“蓝牙不可用”或“尚未连接”、正常启动无“示例：”记录、`比较两次记录` → `比较记录`、`设备连接` 指南与 `操作步骤` | `01-设备` … `07-中文连接指南` |
| `testExampleRecordAnalysis` | 两条示例记录存在、事实 `文件类型`/`按钮数量` 出现（证明分析完成）、滚动到 `包络时序` 与图表容器都可点中、`1. Power` 按键在离线时禁用且旁边显示原因 | `08-示例资料库`、`09-示例记录分析`、`10-示例脉冲图`、`11-示例红外按键` |
| `testDarkAppearanceAndAccessibilityTextNavigation` | `-ui-testing-dark` 与 `-ui-testing-large-text`（accessibility3）：主按钮高度 ≥ 60pt，截图左侧页边像素亮度 < 0.3，依次进入资料库记录、比较、任务、指南详情 | `12-深色大字-设备` … `17-深色大字-指南` |

滚动使用固定距离、无惯性的拖动（最多 14 次），测试有上限且不依赖动画。两个 DEBUG 启动参数只在 `FlipperLabApp.swift` 的 `#if DEBUG` 中读取；没有参数时不覆盖系统外观和字号，Release 构建中不存在这段代码。

## 5. 未验证事项与 CI 需要确认的内容

1. **编译**：Swift 5 模式、iOS 17 部署目标，Xcode 26.6 下的类型检查与并发警告（`Shape`/`Layout` 的隔离警告在 Swift 5 模式下至多为警告）。
2. **CI 运行**：`xcodegen generate` → 模拟器构建 → iPhone 17 Pro Max / iOS 26.5 上 3 项 UI 测试；包测试应仍为 52 项（本次未改包代码）。
3. **截图人工检查**：导出 01–17 号附件，确认机身卡与 LCD 像素清晰（17 Pro Max 上应选 `px = 4`）、示例资料库、脉冲图两色柱、真实指南页、深色与大字号页面无截断。
4. **iOS 26 外观**：Liquid Glass 下 `toolbarBackground(..., for: .tabBar)` 可能不生效，Tab 栏可能呈现系统玻璃样式而非墨色底；需看截图决定是否处理。
5. **测试 API 假设**：容器元素（`record.pulseChart`）的 `isHittable`、`press(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)`、截图取样位置都基于常规 XCUITest 行为，未实际运行。
6. **已知限制（与原版相同）**：返回按钮、工具栏按钮、搜索栏“取消”和系统弹窗使用全局橙色 tint，在米白底上作为文字对比度低于 4.5:1；规范 §2.1 已列为系统组件限制。
7. **真机**：蓝牙搜索、配对、就绪、传输、红外执行和对应界面状态都只能在 iPhone 与 Flipper 真机上验证；模拟器截图只证明离线界面。
