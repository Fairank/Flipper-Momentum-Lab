# Flipper Lab（iPhone）

本目录是个人 Flipper 固件分支（基于 Momentum 的定制，经用户授权）中的原生 iPhone App：SwiftUI 界面，Core Bluetooth 连接，经 Flipper 现有的 BLE 串口服务与 RPC 协议通信，界面为简体中文。它不是 Flipper Devices 的官方 App，也不代表上游项目认可。总体方案见 [iPhone 与中文协作方案](../../documentation/custom/IPHONE_ZH_PLAN.md)。

## 当前状态

手机使用设备、资料库、任务、指南四个主页面，采用原生大标题、分组列表、表单和菜单，保留橙色及像素小屏。比较入口在资料库和记录详情的“更多”菜单中。设计决定、实际模型和运行证据见 [苹果界面优化验收](../../documentation/custom/UI_APPLE_REVIEW.md)。

| 项目 | 状态 |
| --- | --- |
| 工程配置与本说明 | 在 Windows 电脑上编写，本地没有 Xcode 或可用的 Mac。下文的本地命令只在 GitHub macOS CI 中以等效步骤运行过 |
| Swift 包测试（`swift test`） | 提交 `9611f740` 的 [CI 35998623945](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35998623945)：52 项通过 |
| 模拟器构建（不签名） | 同一运行通过 |
| 模拟器 UI 测试 | 同一运行的 3 项测试通过：四页导航、中文指南、示例分析、菜单、深色大字；iPhone 17 Pro Max / iOS 26.5，Xcode 26.6。只证明离线界面，不证明蓝牙 |
| 模拟器截图导出、示例记录固定样本测试 | 已导出 17 张。展示的 17 张逐页复核原图选自应用代码完全相同的两次运行，以避开系统通知和过渡帧；出处与校验值见验收记录 |
| GitHub Actions（[`lab-validation.yml`](../../.github/workflows/lab-validation.yml)） | 已运行；后续提交的结果以 PR [#1](https://github.com/Fairank/Flipper-Momentum-Lab/pull/1) 的检查为准 |
| 真机：蓝牙配对、设备文件导入、上传读回、红外执行 | 均未验证；没有可用的 Mac 和 Flipper |
| App Store / TestFlight | 未准备：没有 App 图标，未做上架或审核相关准备 |

下文的本地步骤尚未在 Mac 上手动执行过。第一次在 Mac 上执行时请记录实际输出和错误。

## 目录结构

| 路径 | 内容 |
| --- | --- |
| `Package.swift` | Swift 包 `FlipperLab`（swift-tools-version 5.9），唯一产品为库 `FlipperCore`，没有第三方依赖 |
| `Sources/FlipperCore/` | 与界面无关的核心代码：RPC/protobuf 编解码与分包重组、六类记录解析与分析、资料库存储、记录模型，以及离线指南资源 `Resources/FeatureCatalog.json` |
| `Tests/FlipperCoreTests/` | `FlipperCore` 的 XCTest 单元测试；其中 `ProtocolVectorTests.swift` 由 `scripts/generate_rpc_vectors.py` 用固件锁定的 `.proto` 生成 |
| `App/` | iPhone App 源码（SwiftUI 界面、蓝牙连接、资料库与任务逻辑），只由 Xcode 工程编译 |
| `UITests/` | XCUITest 界面测试目标 `FlipperLabUITests`：四页导航、指南、示例记录分析、菜单以及深色大字号，每步保存截图附件 |
| `App/Info.plist` | App 的 Info 模板，构建时 Xcode 会替换其中的 `$(…)` 变量 |
| `project.yml` | XcodeGen 工程描述 |
| `FlipperLab.xcodeproj` | 由 XcodeGen 生成在本目录，不是手写文件，不要提交 |

## 工程语义：包与工程在同一目录

- `project.yml` 和 `Package.swift` 都在 `mobile/FlipperLab/`。XcodeGen 以规格文件所在目录为工程根目录解析相对路径，所以 `packages.FlipperLab.path: "."` 指的就是 `mobile/FlipperLab/` 自身，与执行命令时的当前目录无关。
- XcodeGen 默认把 `FlipperLab.xcodeproj` 生成到规格文件所在目录。在本目录执行 `xcodegen generate --spec project.yml`，与在仓库根目录执行 `xcodegen generate --spec mobile/FlipperLab/project.yml`，得到的是同一位置的同一个工程。
- 生成的工程包含三部分：
  - 应用目标 `FlipperLab`：只编译 `App/` 中的文件（排除 `Info.plist`），产品为 `FlipperLab.app`；
  - 界面测试目标 `FlipperLabUITests`：编译 `UITests/`，依赖应用目标，在模拟器或真机上启动 App 做黑盒测试；
  - 本地 Swift 包 `FlipperLab`：应用链接其库产品 `FlipperCore`。包里只有 `Package.swift` 声明的 `FlipperCore` 和 `FlipperCoreTests` 两个目标；`App/` 和 `UITests/` 虽在包目录内，但不属于包。
- 工程定义了一个共享 scheme：`FlipperLab`，用于构建和运行 App（运行用 Debug，归档用 Release）。它的测试动作只运行 `FlipperLabUITests`；包的单元测试不在 scheme 里，用 `swift test` 运行。
- 请打开 `FlipperLab.xcodeproj`。如果在 Xcode 中直接打开 `Package.swift` 或整个目录，只会得到 Swift 包（`FlipperCore` 及其测试），没有 iPhone App 目标。
- 同一目录里同时有 `Package.swift` 和 `.xcodeproj`，命令行调用 `xcodebuild` 时请始终写明 `-project FlipperLab.xcodeproj`。
- `swift test` 只编译并测试 Swift 包（在 Mac 上以 macOS 为目标平台），不编译 `App/`，不能代替 iOS 构建；模拟器构建也不会运行单元测试。
- 修改 `project.yml`，或在 `App/` 中新增、删除、移动文件后，要重新运行 `xcodegen generate`。重新生成会覆盖在 Xcode 界面中对工程做的修改，包括签名团队和 Bundle ID。
- `swift test` 会在本目录生成 `.build/`，仓库已忽略该目录。

## 环境要求

- 一台 Mac 和 Xcode。需要带 iOS 17 SDK、支持 Swift 5.9 的 Xcode（即 Xcode 15 或更新），建议用最新正式版；最低可用的 Xcode 版本尚未实测。
- 安装到 iPhone 时，Xcode 还必须支持手机上的 iOS 版本（通常需要不低于该 iOS 主版本的 Xcode），而较新的 Xcode 对 macOS 版本也有要求。
- 命令行工具指向完整的 Xcode：`xcode-select -p` 应输出 `…/Xcode.app/Contents/Developer`，否则执行 `sudo xcode-select -s /Applications/Xcode.app`。
- [Homebrew](https://brew.sh) 与 XcodeGen：`brew install xcodegen`。
- 工程和 Swift 包都没有第三方依赖，构建时不会下载 Swift 包；需要联网的只有安装 Xcode、XcodeGen 以及签名。
- Windows 不能生成工程，也不能编译、运行或签名本 App。

## 1. 生成 Xcode 工程

```sh
cd mobile/FlipperLab
xcodegen generate --spec project.yml
open FlipperLab.xcodeproj
```

## 2. 运行 Swift 包测试

```sh
# 在仓库根目录执行
swift test --package-path mobile/FlipperLab
```

测试位于 `Tests/FlipperCoreTests/`，共 52 项，覆盖 RPC 帧编码、BLE 分包在任意位置切开后的重组、超长/截断/溢出输入的拒绝、设备文件名不能改变路径、protoc 生成的协议向量、六类记录的解析与拒绝（空文件、非法文本、超过 2 MiB、头部与扩展名矛盾）、资料库存储的上限与损坏处理，以及内置指南的完整性。最新基线增加资料库编码前总量检查，52 项通过；本地是否通过以实际输出为准。

## 3. 模拟器构建与运行

与 CI 相同的命令行构建（不签名）：

```sh
cd mobile/FlipperLab
xcodebuild build \
  -project FlipperLab.xcodeproj \
  -scheme FlipperLab \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

在 Xcode 中运行：顶部选择 scheme `FlipperLab` 和任一 iPhone 模拟器，按 ⌘R。iOS 模拟器不能使用蓝牙，只能检查界面、离线指南和本地资料库；连接 Flipper 必须用真机。

### 模拟器 UI 测试与截图

与 CI 相同的步骤：在模拟器上运行 `FlipperLabUITests`，再从结果包导出每一步保存的截图。把 `<模拟器名称>` 换成 `xcrun simctl list devices available` 里的一台 iPhone。

```sh
cd mobile/FlipperLab
xcodebuild test \
  -project FlipperLab.xcodeproj \
  -scheme FlipperLab \
  -destination 'platform=iOS Simulator,name=<模拟器名称>' \
  -resultBundlePath "$TMPDIR/FlipperLab.xcresult" \
  CODE_SIGNING_ALLOWED=NO
xcrun xcresulttool export attachments \
  --path "$TMPDIR/FlipperLab.xcresult" \
  --output-path "$TMPDIR/screenshots"
```

三项测试都以简体中文启动 App：`testOfflineNavigationAndChineseGuide` 进入设备、资料库、任务、指南四个页面，并检查资料库菜单、比较记录和“设备连接”指南；`testExampleRecordAnalysis` 用 `-ui-testing-fixtures` 载入两条示例记录，检查分析、完整脉冲图、离线红外按钮和删除确认；`testDarkAppearanceAndAccessibilityTextNavigation` 检查深色大字页面，以及从记录进入比较时预选记录 A。截图编号为 01–17，其中 03 是资料库菜单、12–17 是深色大字。这些测试只验证离线界面，不证明蓝牙、上传或红外。

## 4. 用自己的团队签名，安装到 iPhone 17 Pro Max

目标手机为 iPhone 17 Pro Max，运行用户已安装的较新 iOS，具体版本号尚未记录。签名和安装必须在 Mac 上的 Xcode 中完成；CI 只做不签名的模拟器构建，产物不能装到 iPhone，本仓库也不提供 IPA。

1. 在 iPhone 的 **设置 → 通用 → 关于本机** 查看 iOS 版本，确认 Mac 上的 Xcode 支持它。
2. Xcode → **Settings… → Accounts**，登录自己的 Apple ID。免费 Apple ID 显示为 “Personal Team”；加入付费 Apple Developer Program 的账号显示团队名称。
3. 用数据线连接 iPhone，解锁后在弹窗中选择“信任”这台电脑。
4. 在 iPhone 的 **设置 → 隐私与安全性 → 开发者模式** 中开启开发者模式，按提示重启并确认。此选项通常在 iPhone 连接过 Xcode 之后才出现。
5. 在 Xcode 左侧选中工程 `FlipperLab`，TARGETS 选 `FlipperLab` → **Signing & Capabilities**：保持 **Automatically manage signing** 勾选，在 **Team** 中选择自己的团队。工程没有预设任何团队。
6. 如果提示 Bundle Identifier `org.fairank.FlipperLab` 无法注册（已被其他团队占用），在同一页面改成自己唯一的标识，例如 `org.fairank.FlipperLab.<你的后缀>`。
7. 顶部运行目标选择你的 iPhone，按 ⌘R。如果 iPhone 提示“不受信任的开发者”，到 **设置 → 通用 → VPN与设备管理** 信任自己的开发者证书，再打开 App。
8. 按当前代码，App 一启动就创建蓝牙管理器，所以首次启动会立即请求蓝牙权限。拒绝后仍可使用指南和资料库；之后可在 **设置 → 隐私与安全性 → 蓝牙** 中允许 Flipper Lab。

注意：

- 重新运行 `xcodegen generate` 会清除第 5、6 步在 Xcode 中的设置，需要重新选择。若要长期使用自己的 Bundle ID，可修改 `project.yml` 中的 `PRODUCT_BUNDLE_IDENTIFIER` 后重新生成；这会改动受版本控制的文件，提交前请自行确认。
- 免费个人团队签名的 App 约 7 天后失效，需要从 Xcode 重新安装；免费团队对可安装的 App 数量等也有限制。付费开发者账号的开发签名有效期更长。
- 可选的命令行真机构建。需要先在 Xcode 的 Accounts 中登录同一账号；它只编译和签名，安装与调试仍建议在 Xcode 中进行：

```sh
cd mobile/FlipperLab
xcodebuild build \
  -project FlipperLab.xcodeproj \
  -scheme FlipperLab \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=<你的 10 位团队 ID>
```

## 功能（依据当前代码）

以下内容根据 `App/` 与 `Sources/FlipperCore/` 的现有源码整理。离线界面在 CI 模拟器上走过一遍；所有涉及蓝牙和设备的功能均未经真机验证。

**设备连接**

- 搜索广播 Flipper 服务标识 `0x3080` 的设备，15 秒后自动停止，列表最多 100 台。
- 连接所选设备并按提示配对（Flipper 串口服务的读写要求认证）；45 秒内未就绪则断开并提示超时。
- 连接后订阅串口服务，检查 RPC 协议主版本（目前只接受 0），读取设备报告的系统信息（键值列表）。
- 状态依次为：尚未连接、正在搜索、正在配对与连接、正在准备通信、正在检查设备、设备已就绪；蓝牙关闭或无权限时显示“蓝牙不可用”。

**设备文件**

- 只能浏览 `/ext`（SD 卡）下的目录；路径中的 `..`、反斜杠等会被拒绝；单个目录超过 4096 项会报错。
- 从 Flipper 导入单个文件：不超过 2 MiB、UTF-8 文本，识别出类型并通过格式检查后才保存到手机资料库，同时记录设备上的来源路径。

**手机资料库**

- 记录类型：红外遥控（`.ir`）、Sub-GHz（`.sub`）、NFC（`.nfc`）、低频 RFID（`.rfid`）、iButton（`.ibtn`）、串口日志（`.txt`）。
- 也可通过系统文件选择器从 iPhone 文件导入，限制相同，原文件不会被修改。
- 可编辑中文名称、标签和备注，原始采集内容保持不变；可通过系统导出面板导出原始文件。
- 可查看分析结果，并对两条记录按行比较（比较行数和显示的差异数量有上限）。
- 删除只影响手机资料库，不删除 Flipper 上的文件。
- 数据保存在 App 沙盒的 `Documents/Library`。没有开启“文件”App 或访达（Finder）文件共享；删除 App 会同时删除资料库。

**上传到 Flipper**

- 上传到对应目录：`/ext/infrared`、`/ext/subghz`、`/ext/nfc`、`/ext/lfrfid`、`/ext/ibutton`。文件名为 `Lab_<UUID>.<扩展名>`，每次上传都生成新文件；中文名称只保存在手机。
- 上传后读回比对，一致才算成功。
- 串口日志只保存在手机，不能上传。

**红外按钮执行**

- 只适用于来源路径位于 `/ext/infrared/` 的红外记录（从该目录导入，或已上传到该目录）；执行前读回连接中的 Flipper 上的该文件，与手机记录不一致则拒绝执行。
- 通过 RPC 启动 Flipper 的红外应用（RPC 模式），加载文件，对所选按钮执行一次“按下并松开”，然后退出该应用。
- 显示“设备已确认执行”只表示 Flipper 回复了命令，不代表家电一定有响应。
- 出错时 App 会断开连接。代码注释认为固件在连接关闭时会停止红外输出，此点尚未经真机验证。

**任务与取消**

- 每项操作在“任务”页显示为进行中、已完成、失败或已取消；只保留本次运行期间最近 100 条，不会持久保存。
- 同一时间只执行一项设备操作，忙时新操作会被拒绝。
- 取消设备操作会断开蓝牙连接，之后需要重新连接；已写入设备的部分文件可能保留。
- 单次请求 45 秒无响应即视为超时并断开连接；App 不会自动重试或重放操作。

**离线中文指南**

- 内容来自内置的 `FeatureCatalog.json`，无需连接设备即可阅读；它必须与 `documentation/custom/FEATURE_CATALOG.zh-CN.json` 逐字节一致。
- 共 8 篇：设备连接、中文资料库、红外工作台、中文入口与功能说明、Sub-GHz 记录分析、NFC/RFID/iButton 记录、串口日志查看、扩展板状态与诊断。
- 截至本文更新时，该文件标注为实现中（`catalog_status: implementation_in_progress`），条目状态为 `implemented_unverified`、`in_progress` 或 `hardware_required`；指南中的描述不等于功能已经在真机上验证。

## 未提供的功能与限制

- 不支持任何扩展板（ESP32、“WiFi 终结者”等）：代码中没有相关实现，也不按名称推断兼容性。
- 不做原始射频或红外信号的实时蓝牙流式传输，也不通过蓝牙逐脉冲控制 Flipper；手机只处理已保存的记录文件。
- 除红外按钮执行外，App 不会让 Flipper 发射或模拟 Sub-GHz、NFC、RFID、iButton 信号；这些记录只能导入、分析、整理、导出和上传。
- 没有手机触发的采集、实时串口采集或 iCloud 同步。
- 手机算力不会扩大 Flipper 的硬件能力（频段、采样率、支持的标签类型等）。
- 界面只有简体中文。设备族包含 iPad，可以安装，但没有做过任何 iPad 测试。

## 前台运行限制

- Info.plist 没有声明蓝牙后台模式（`UIBackgroundModes` 中的 `bluetooth-central`），代码也没有实现 Core Bluetooth 状态恢复。
- 切换到其他 App、回到主屏幕或锁屏后，iOS 很快会挂起本 App：搜索停止，正在进行的读取、导入、上传或红外执行会暂停，回到前台后可能超时失败，需要重新连接再试。
- 操作期间请让本 App 保持在前台并保持屏幕点亮；当前代码不会阻止自动锁屏。
- 这是有意的取舍：App 没有后台续传、断点续传或断线后自动恢复任务的逻辑，所以不声明后台模式，避免暗示能在后台持续工作。
- 开发者注意：若以后给 `CBCentralManager` 加入状态恢复标识，必须同时在 Info.plist 加入 `UIBackgroundModes` → `bluetooth-central`，否则运行时会出错；加入后仍需在真机上验证实际的后台行为。

## 首次配对与故障排查

- 在 Flipper 的 **Settings → Bluetooth** 中打开蓝牙。首次连接时按 Flipper 屏幕和 iPhone 弹窗的提示完成配对（通常需要在 iPhone 上输入 Flipper 显示的配对码）。
- 配对失败或连接后很快断开：在 iPhone **设置 → 蓝牙** 中对该 Flipper 选择“忽略此设备”，并在 Flipper **Settings → Bluetooth → Unpair All Devices** 清除配对，然后重试。
- 使用本 App 前，请断开官方 Flipper App 等其他正在连接这台 Flipper 的 App；多个 App 同时使用同一个 RPC 会话可能互相干扰。
- 提示“Flipper 正忙”：先退出 Flipper 上正在运行的应用。
- Xcode 提示 `No such module 'FlipperCore'`：确认打开的是 `FlipperLab.xcodeproj`；可尝试 **File → Packages → Reset Package Caches**，或重新运行 `xcodegen generate`。
- 签名提示需要开发团队（“requires a development team”）：按第 4 步选择团队。

## 版本与工程配置

- 版本 0.1.0，构建号 1；开发用 Bundle ID `org.fairank.FlipperLab`；主屏幕名称 “Flipper Lab”；最低 iOS 17.0；设备族 iPhone 与 iPad。
- 界面测试目标 `FlipperLabUITests` 的 Bundle ID 为 `org.fairank.FlipperLab.UITests`，Info.plist 由 Xcode 自动生成。
- Swift：`Package.swift` 为 swift-tools-version 5.9；App 目标 `SWIFT_VERSION = 5.0`，即 Swift 5 语言模式，包目标同样按 Swift 5 语言模式编译。
- 签名：自动签名，未设置 `DEVELOPMENT_TEAM`。
- Info.plist：开发地区为简体中文（`zh-Hans`）、中文蓝牙用途说明、系统默认启动屏（空的 `UILaunchScreen`）、单窗口。没有后台模式、文件共享、加密出口合规声明或其他权限；导入和导出都经系统文件面板，不需要额外声明。
- 没有 App 图标资源，主屏幕显示系统默认的占位图标。以后在 `Assets.xcassets` 中加入 AppIcon 时，需要同时在 `project.yml` 设置 `ASSETCATALOG_COMPILER_APPICON_NAME`。

## CI（GitHub Actions）

工作流为 [`.github/workflows/lab-validation.yml`](../../.github/workflows/lab-validation.yml)：

- 触发：推送到 `codex/**` 分支、Pull Request 或手动运行。推送和 PR 只在 `mobile/`、`scripts/tests/`、`applications/main/lab/`、`applications/services/gui/`、`scripts/generate_lab_font.py` 或工作流本身有改动时触发；同一分支或 PR 的新运行会取消旧运行。
- macOS 26 / Xcode 26.6：安装 XcodeGen，执行 `swift test`，生成工程，做不签名的模拟器通用构建（`CODE_SIGNING_ALLOWED=NO`，警告不视为错误），然后在指定的 iPhone 17 Pro Max / iOS 26.5 模拟器上运行 `FlipperLabUITests`，并从结果包导出截图。
- Ubuntu 24.04：执行 `python3 -m unittest discover -s scripts/tests`（旧回归、UTF-8 回归、字库生成器测试）和 `scripts/generate_lab_font.py --check`。其中的 C 回归需要主机 C 编译器，缺少时任务直接失败，不会带着跳过的测试通过。
- 只有读取仓库内容的权限，不使用任何密钥；不签名、不发布，不向上游或更新服务器上传，也不生成可安装的 IPA。

产物（在运行页面的 Artifacts 下载，`<attempt>` 为该次运行的重试序号）：

| 产物 | 内容 | 保留 |
| --- | --- | --- |
| `iphone-screenshots-<attempt>` | UI 测试各步骤的模拟器截图 | 14 天 |
| `simulator-test-evidence-<attempt>` | `FlipperLab.xcresult` 结果包 | 7 天 |
| `xcodebuild-log-<attempt>` | 只在模拟器构建失败时上传的 xcodebuild 日志 | 7 天 |

设备端固件由另一个工作流 [`lab-firmware.yml`](../../.github/workflows/lab-firmware.yml) 构建，产物 `flipper-lab-firmware-<提交>` 含更新包、`SHA256SUMS.txt` 和 `dist/f7-C/apps/Tools/lab.fap`，保留 14 天；运行 [35977973532](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35977973532) 已通过。

当前界面和最新运行结果见 [UI_APPLE_DESIGN.md](../../documentation/custom/UI_APPLE_DESIGN.md) 与 [UI_APPLE_REVIEW.md](../../documentation/custom/UI_APPLE_REVIEW.md)。此前五页像素机身方案的历史验证保留在 [UI_REVIEW.md](../../documentation/custom/UI_REVIEW.md)。CI 通过不代表蓝牙、上传或红外功能在真机上可用。

## 真机验证清单（尚未执行，没有可用的 Mac 和 Flipper）

- [ ] 记录 iPhone 型号、iOS 版本、Xcode 版本和 Flipper 固件版本
- [ ] 首次配对、拒绝蓝牙权限、蓝牙关闭、断开重连、设备忙碌时的提示
- [ ] 浏览 `/ext` 并导入各类型记录，包括空文件、损坏文件和超过 2 MiB 的文件
- [ ] 上传后读回核对，以及设备目录已存在时的行为
- [ ] 红外按钮执行与实际家电响应；执行中取消或断开连接
- [ ] 切到后台和锁屏后的行为
- [ ] 重启 App 后资料库记录仍在、任务列表已清空
