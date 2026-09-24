# 验证记录

记录日期：2026-09-24。本文只记录实际运行过的检查。源码已编写不等于编译、模拟器或真机通过；CI 通过不等于真机可用。本轮没有刷写设备、部署或发布 App。

## 当前环境

- 分支 `codex/iphone-zh-architecture`，基于 `b06c940ec326fef33954b49cffbc085f16607aaf`，已推送。草稿 PR：[Fairank/Flipper-Momentum-Lab#1](https://github.com/Fairank/Flipper-Momentum-Lab/pull/1)，目标分支 `codex/momentum-unleashed`，尚未合并。首个提交 `8c4695de2763fa6457d3b0b5c76e803129ea9379`；之后的提交仍在推送和检查中，本文不记录最新提交号。
- GitHub 访问：GitHub App 安装 164333683 已限制为只授权 `Fairank/Flipper-Momentum-Lab`，浏览器授权由主控在用户明确许可后完成；连接器可写入该仓库。本机 `gh` 未登录。
- Windows 11 原生环境，官方工具链 39 可用；工作区内有 Zig 0.16.0，可作为桌面回归的 C 编译器。
- 全部固定子模块已递归初始化，未升级任何 gitlink；版本见 [SOURCE_LOCK.json](SOURCE_LOCK.json)。
- 本机没有 Xcode，也没有可用的 Mac；iPhone、Flipper 和扩展板均未接入测试。

## 新测试环境基线（提交 43bd0358）

2026-09-24，[Lab validation 35977973407](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35977973407) 在 Xcode 26.6、iPhone 17 Pro Max / iOS 26.5 上完成：52 项核心测试、2 项 UI 测试、36 项桌面回归通过，65 个 Flipper 源码画面成功生成。Lint 与 Lab firmware 同样通过。此提交仍为旧手机界面，视觉重做的结果必须另行记录。

## 后续核验（提交 `8a1347be`）

- [Lab validation 35975959905](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35975959905)：51 项 Swift 包测试、模拟器构建、2 项 UI 测试、36 项 Python/C 回归全部通过。截图附件 10 张已导出，并查看设备、示例资料库和脉冲图。模拟器为 **iPhone 16 Pro / iOS 18.5**，工具为 Xcode 16.4；不是用户的 17 Pro Max 真机。
- [Lint 35975959943](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35975959943)：通过。
- [Lab firmware 35975959893](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35975959893)：通过。PR 检出合并提交 `4c49beb70a2f4486a934b51c077fa4df97bb0d8d`，对应分支头 `8a1347beb085431eb4d9164a066387db5f32916a`。
- CI 更新包 `flipper-z-f7-update-mntm-HEAD-4c49beb7.tgz`：12,649,645 字节；SHA-256 `f098a60ebfc0c5cc5b8bc08dc468ee676fa617a1b45014339a4e7ef4b6277693`。下载后已核对清单；包内 `resources.tar.gz` 的 `apps/Tools/lab.fap` 与单独产物逐字节一致，22,360 字节。它取代下方较早的本地未提交包作为当前构建证据，尚未刷写。
- `render_lab_preview.py --all`：实际运行成功，65 个画面（10 个菜单状态、55 页说明），无警告；PNG 已打开检查。布局预览由实际字库与源码计算，**不是固件运行或真机截图**。
- 用户否定旧手机界面，要求 Claude 5.1 Max 设计、Opus 5.5 实现，正在重做。旧截图仅作历史验证，不能代表新版完成。
- 本次同时新增资料库编码前总量检查及一项回归，以及文件读取的 2 MiB + 1 硬上限，等待新的 macOS CI（预期 52 项包测试）。CI 已改为 Xcode 26.6、iPhone 17 Pro Max / iOS 26.5，结果待跑；不把该设置写成已通过。

## 较早结果

### 固件

| 检查 | 结果 | 能证明的范围 |
| --- | --- | --- |
| 核心固件构建：`FBT_NO_SYNC=1 fbt.cmd SKIP_EXTERNAL=1 updater_package` | 2026-09-24 15:37（本地时间）结束，退出码 0 | 当时的工作区能编译核心固件并打包；不含 Flipper Lab 与 UTF-8 修复 |
| 完整更新包：`FBT_NO_SYNC=1 fbt.cmd -j1 updater_package fap_dist`（含外部应用、Flipper Lab、字库、UTF-8 修复） | 成功；日志在仓库外 `../flipper-tools/full-build-zh-retry.log` | 当时的工作树（基于 `b06c940e`，含未提交改动，早于最后的格式化和文档改动）能完整编译并生成更新包和 `.fap` 分发目录 |
| 同时请求 `updater_package fap_dist` | Windows 再次重建时失败，`-j1` 也会复现 | `sconsdist.py` 会清理整个输出目录，导致同一构建图中已检查的安装目录失效；应分两次调用，先 `updater_package`，成功后再 `fap_dist` |

完整包产物：

- `dist/f7-C/flipper-z-f7-update-mntm-codex-iphone-zh-architecture-b06c940e.tgz`
- 大小：12,649,553 字节
- SHA-256：`dbae720f9b2207694994c8d6a35d58a40872a06fe468fb7a75bcc088862096e9`
- `dist/f7-C/apps/Tools/lab.fap`：22,360 字节

包名中的 `b06c940e` 只是基线提交，不证明该包对应远程的任何提交；用最终源码（CI 的 `lab-firmware.yml` 或本地重建）生成的包可以取代它。构建输出提示两个上游无效 appid（`.cli_gui`、`.f0_mtp`）被排除，这是继承自上游应用清单的警告，未处理，也不是本定制引入的。产物未刷写到任何设备。

大小记录（只作参考，不能据此推算剩余 Flash/RAM；堆、运行时和各存储区域需要另行测量）：

| 对象 | 数值 |
| --- | --- |
| 固件 `arm-none-eabi-size` | text 838,296 / data 960 / bss 9,956 |
| `lab.fap` 文件 | 22,360 字节 |
| `lab.fap` 加载后的代码段 | 15,913 字节，另加应用栈 3,072 字节和运行时动态堆 |
| 字库子集 | 423 字形，9,896 字节 |

### 桌面回归与生成器

| 检查 | 结果 | 能证明的范围 |
| --- | --- | --- |
| Windows：`scripts/tests/test_unleashed_integration.py` 与 `scripts/tests/test_gui_utf8.py`，`cc` 解析到工作区 Zig 0.16.0 的 `zig cc` | 3 项旧回归 + 3 项 UTF-8 测试通过，无跳过（真实编译） | 源文件顺序、插件扫描、进度视图，以及 UTF-8 换行的桌面替身行为 |
| Windows：`scripts/tests/test_lab_font.py` | 30 项通过；生成器改为 clang-format 兼容输出后复跑仍通过 | 字库子集、文本尺寸检查、启动目标核对 |
| GitHub Ubuntu 任务（run 35974984160，首个提交）：`unittest discover` 与 `generate_lab_font.py --check` | 任务通过，36 项测试全部通过 | 同上，在自带 `cc` 的 Linux 上 |

### iPhone App（GitHub macOS CI，首个提交）

运行：<https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35974984160>，工作流 `lab-validation.yml`。

| 检查 | 结果 | 能证明的范围 |
| --- | --- | --- |
| `swift test --package-path mobile/FlipperLab` | 51 项通过 | RPC 分帧、protoc 生成的互操作向量、六类记录解析、存储上限与损坏处理、内置指南完整性；在 macOS 上以 macOS 为目标编译 |
| XcodeGen 生成工程 + 不签名 iOS 模拟器构建 | 通过 | `App/` 与 UI 测试目标能为模拟器编译 |
| 模拟器 UI 测试 `testOfflineNavigationAndChineseGuide` | 1 项通过：依次进入设备、资料库、工具（含比较记录）、任务、指南五个页面，并打开“设备连接”指南 | 离线模拟器界面能启动和导航；**不证明蓝牙、文件传输或红外** |
| 所用模拟器机型与 iOS 版本 | 未记录（首个运行的日志不可用） | — |
| 截图导出产物（`iphone-screenshots-<attempt>`、`simulator-test-evidence-<attempt>`）与示例记录固定样本测试 `testExampleRecordAnalysis` | 首个运行之后加入，结果待记录 | 暂无 |

### 尚未运行

| 检查 | 状态 |
| --- | --- |
| `lab-firmware.yml` | 后续运行已通过，见上方“后续核验” |
| iPhone 17 Pro Max 真机、蓝牙流程、红外实际响应 | 未运行；没有可用的 Mac 和真机 |
| Flipper 真机屏幕检查（Flipper Lab、UTF-8 换行） | 未运行；源码渲染预览已运行成功，其输出不是真机截图 |
| 剩余 Flash/RAM 测量 | 未做 |
| 新增 API 导出与已有应用的兼容性核对 | 未做 |

### Windows 中文路径

原工作区路径含中文，旧版 protoc 无法处理，构建因此失败。用 `subst` 把仓库临时映射到一个 ASCII 盘符，并设置 `PYTHONUTF8=1` 后，核心构建与完整包构建通过。操作步骤见 [HANDOFF.md](../../HANDOFF.md) 的“Windows 固件”；`subst P: /D` 只删除盘符映射，不删除源码。

`FBT_NO_SYNC=1` 会跳过 fbt 的子模块同步，只能在子模块已按固定提交初始化后使用。

## 本轮源码状态

各模块的源码状态与已有验证见 [REQUIREMENTS.md](REQUIREMENTS.md)。功能说明中的状态以 [FEATURE_CATALOG.zh-CN.json](FEATURE_CATALOG.zh-CN.json) 为准（`catalog_status: implementation_in_progress`；条目状态为 `implemented_unverified`、`in_progress` 或 `hardware_required`）。

## 委派记录

- 方式：用户授权的本机 Claude CLI 工作进程。主控负责决策、验收、蓝牙与设备控制代码，并审查全部改动。
- 较早的委派请求并返回 `claude-opus-5-5`（`--effort max`）：记录解析与存储、设备端中文说明、工程与 CI、UTF-8 修复、文档五项退出码 0；iOS 界面一项因服务端安全策略退出码 1，没有产出任何界面文件，界面由主控直接实现。
- 主控已复核解析与存储、设备端说明、字库生成器和 UTF-8 修复的代码，并运行了上述测试。
- 当前的委派要求为 `claude-fable-5-1 --effort max`：连通性探测返回该模型，退出码 0；预览与文档任务均实际返回该模型、退出码 0，主控已复核。用户随后明确指定界面重做由 5.1 Max 设计、Opus 5.5 实现，该任务按新指令执行并单独记录；其他任务默认保持 5.1 Max。
- [IPHONE_ZH_PLAN.md](IPHONE_ZH_PLAN.md) 中“未找到 CLI、未调用委派”是当时的状态，已由本节更新。

## 待补证据

1. 新界面与内存上限检查已有新版 CI 证据，见下方手机界面各轮验收记录；后续代码变更须补相应证据。
2. 固件若继续变更，重新生成对应提交的更新包及 SHA-256。
3. 剩余 Flash/RAM 的测量。
4. 模拟器主要页面截图已检查；其他设备尺寸、VoiceOver 与真实操作状态仍待验收。
5. iPhone 17 Pro Max 与 Flipper 真机的完整蓝牙流程。
6. Flipper 真机屏幕检查；65 个源码渲染预览已输出并通过 CI，不能替代真机检查。
7. 扩展板型号及测试记录。

仓库继承的上游固件工作流仍带上游发布假设和官方 API 版本一致性检查；它们的状态不能等同于本定制的验证结论，本定制以 `lab-validation.yml` 与 `lab-firmware.yml` 为准。

## 历史记录：上一台 macOS

以下结果来自上一台 macOS arm64 机器（官方工具链 39，GCC 12.3.1），本轮未在 macOS 复跑。

| 检查 | 结果 | 能证明的范围 |
| --- | --- | --- |
| `python3 scripts/tests/test_unleashed_integration.py -v` | 3 个测试通过 | 源文件模式顺序、插件扫描及进度视图的桌面回归 |
| 修改过的 13 个 C/header 文件使用工具链 `clang-format --dry-run --Werror` | 通过 | 本批 C/header 格式 |
| Python 文件 Black 检查 | 通过 | 本批 Python 格式 |
| `git diff --check` | 通过 | 改动没有空白错误 |
| API CSV 与基线比较 | 4,675 个既有条目签名和状态不变，新增 4 个，无重复名称 | 导出表文本兼容性，不能代替应用运行 |

这些测试从生产实现抽取函数，以桌面存储/绘图替身执行，没有验证真实 SD 卡、GUI 线程调度、板上内存和硬件行为。

当时 `applications/external` 只稀疏检出三个目录，嵌套依赖也未完整初始化。`FBT_NO_SYNC=1 ./fbt SKIP_EXTERNAL=1 updater_package` 以退出码 2 失败：

```text
applications/main/archive/helpers/archive_files.c:4:10: fatal error:
applications/external/subghz_playlist/playlist_file.h: No such file or directory
```

本轮在完整初始化的子模块上，Windows 核心构建与完整包构建均已通过；macOS 上没有重新构建。

## 手机首轮界面验收（2026-09-24）

代码版本 `bfc43b4a949a6d4b4e4fa791e26f053c7abcf3d1` 在 [35985874280](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35985874280) 通过 52 项核心测试、3 项 UI 测试、36 项桌面回归与模拟器构建；完整固件构建 [35985874510](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35985874510) 和 Lint 亦通过。运行环境为 Xcode 26.6 / iPhone 17 Pro Max / iOS 26.5；17 张原始截图，含修正后的浅色栏、完整波形和深色大字页面。模型分工、实际返回值、主控修正和截图 SHA256 见 [UI_REVIEW.md](UI_REVIEW.md)。

设计由本机 `claude-fable-5-1 --effort max` 完成，实现由用户本轮指定的 `claude-opus-5-5 --effort max` 完成；实际模型一致，均退出码 0。主控审阅后采纳，并修复截图检查发现的问题。

## 手机苹果原生界面优化（2026-09-24）

根据用户的新反馈，手机重新整理为设备、资料库、任务、指南四页，使用原生导航、分组列表、表单、菜单和系统颜色，保留 Flipper 橙色及小像素屏。Fable 5.1 Max 负责设计，Opus 5.5 Max 负责实现，均由本地 CLI 实际调用并正常退出；主助手审核决定并修复截图发现的问题。实际模型、代码核对和各轮运行证据见 [UI_APPLE_REVIEW.md](UI_APPLE_REVIEW.md)。

最终验证提交 `9611f7403c5f41df964048c01ee0c622b3c6842d` 已通过 [35998623945](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35998623945) 的 52 项核心测试、3 项 UI 测试、36 项桌面回归与模拟器构建。[完整固件构建](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35998623890) 与 [Lint](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35998623705) 通过。运行环境为 Xcode 26.6 / iPhone 17 Pro Max / iOS 26.5。

应用源码在 `4e80b06e` 后保持不变，后续修正截图测试，使资料库和记录详情的图标检查直接针对保存的整屏原图。最新 17 张截图中一张受到模拟器系统通知遮挡，因此展示选取同一应用代码两次运行中的 17 张无遮挡原图；每张注明出处且未编辑像素。完整来源、ZIP SHA-256、人工核对范围及测试局限见 [UI_APPLE_REVIEW.md](UI_APPLE_REVIEW.md)。之后只更新文档的提交不另作一次代码验证。

