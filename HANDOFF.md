# 换电脑接续：Momentum 个人定制与 iPhone 中文工作台

交接日期：2026-09-24。当前工作分支：`codex/iphone-zh-architecture`，基于 `b06c940ec326fef33954b49cffbc085f16607aaf`，已推送到个人仓库；草稿 PR [Fairank/Flipper-Momentum-Lab#1](https://github.com/Fairank/Flipper-Momentum-Lab/pull/1) 指向 `codex/momentum-unleashed`，尚未合并。分支的首个提交为 `8c4695de2763fa6457d3b0b5c76e803129ea9379`；之后的提交仍在推送和 CI 检查中，最新提交号以 PR 页面为准，本文不记录。

这是用户授权、由 AI 辅助的个人定制。上游 `AGENTS.md`、`CONTRIBUTING.md` 的禁止 AI 贡献规则和原文件保留；本交接不代表上游认可，也不包含向上游提交贡献的请求。

## 先读这些

1. [mobile/FlipperLab/README.zh-CN.md](mobile/FlipperLab/README.zh-CN.md)：iPhone App 源码结构、构建、测试步骤与 CI 产物。
2. [REQUIREMENTS.md](documentation/custom/REQUIREMENTS.md)：需求、各模块源码状态和验收清单。
3. [VALIDATION.md](documentation/custom/VALIDATION.md)：实际运行过的构建与测试，以及尚未运行的项目。
4. [FEATURE_CATALOG.zh-CN.json](documentation/custom/FEATURE_CATALOG.zh-CN.json)：中文功能说明；App 内置副本 `mobile/FlipperLab/Sources/FlipperCore/Resources/FeatureCatalog.json` 必须与它逐字节一致。
5. [applications/main/lab/README.md](applications/main/lab/README.md) 与 [FONT_LICENSE.md](applications/main/lab/FONT_LICENSE.md)：设备端 Flipper Lab 的文件、文字编辑流程和字库来源。
6. [IPHONE_ZH_PLAN.md](documentation/custom/IPHONE_ZH_PLAN.md)：设计依据和方案阶段的记录，不代表当前进度。

## 当前任务

用户选择 Momentum 作为固件基础，保留 Xtreme/Momentum 的界面、主题和定制体验，并逐项适配 Unleashed 的功能。本轮用户明确要求实现仓库中的全部需求，不停留在方案：

- 新做 iPhone App，连接 Flipper，利用手机算力增强功能。目标设备为 iPhone 17 Pro Max，运行已安装的最新 iOS（确切版本未记录）。
- Flipper 本机功能重写：已新增中文入口应用 Flipper Lab，保留已验证的硬件驱动。现有原生应用目前仍是英文，**全面中文化仍是用户需求中未完成的部分**，不是已被放弃或缩减的范围。
- 手机与设备提供中文界面和功能介绍。
- 用户当前还要求提供手机页面和 Flipper 页面的预览。旧手机界面已导出 10 张模拟器截图，用户否定其设计并要求重做：Claude 5.1 Max 设计、Opus 5.5 实现，由主控复核。Flipper 预览脚本已输出 65 个画面，它不是真机截图。

Mac、Flipper 硬件版本和扩展板的确切型号仍未知。本轮没有可用的 Mac，也没有 Flipper 真机可测。

分工：主控负责决策与验收，编写蓝牙连接和设备控制代码，并审查全部改动。委派给本机 Claude CLI 的工作及其返回模型见 VALIDATION.md 的“委派记录”：记录解析与存储、设备端中文说明、字库生成器和 UTF-8 修复已经主控复核并跑过测试，iOS 界面由主控直接实现。本机 Claude 只是开发工具，App 不调用任何云端 AI 服务。

## 当前状态

| 内容 | 状态 |
| --- | --- |
| 固定子模块 | 已按主仓库记录的提交递归初始化，未升级任何 gitlink |
| 核心固件构建（`SKIP_EXTERNAL=1`） | Windows 上 2026-09-24 15:37 成功，退出码 0；不含 Flipper Lab 与 UTF-8 修复 |
| 完整更新包（含外部应用、Flipper Lab、字库、UTF-8 修复） | Windows 工具链 39 用 `fbt.cmd -j1 updater_package fap_dist` 构建成功；产物、大小与 SHA-256 见 VALIDATION.md。该包来自基于 `b06c940e` 的未提交工作树，早于最后的格式化和文档改动，包名不是远程提交的证明 |
| 桌面 C 回归 | Windows 上以工作区 Zig 0.16.0 充当 `cc` 真实编译：3 项旧回归 + 3 项 UTF-8 全部通过，无跳过；GitHub Ubuntu 任务 36 项通过（含 30 项字库生成器测试） |
| iPhone App（`mobile/FlipperLab`） | 五个中文页面、蓝牙 RPC、文件列目录与下载、唯一文件名上传读回、六类记录离线分析与脉冲统计和比较、资料库编辑/导出/删除、任务记录、一次性红外发送、8 篇指南已编写。首个提交的 GitHub macOS CI：51 项 Swift 包测试通过，不签名模拟器构建通过，1 项离线 UI 测试走完五个页面并打开中文连接指南 |
| iPhone 截图导出、两条示例记录的固定样本 UI 测试 | 提交 `8a1347be`：2 项 UI 测试通过，10 张截图；iPhone 16 Pro / iOS 18.5。正在重做界面，新版须重新验收 |
| Flipper Lab（`applications/main/lab`） | 10 个中文主题与快捷启动、423 字形字库子集已编写并编译进完整包（`lab.fap` 22,360 字节）；真机未验证，源码渲染预览 65 个画面已生成 |
| UTF-8 文字换行修复（`text_box.c`、`utf8_internal.h`） | 已编写，3 项桌面回归通过；真机未验证 |
| 现有原生应用与系统设置的全面中文化 | 未开始；仍是用户需求（REQUIREMENTS.md R9/R10） |
| 蓝牙真机、Flipper 真机屏幕 | 未运行；没有可用的 Mac 和真机 |
| 实时串口采集、更多手机端离线分析、固件升级功能 | 未实现 |
| 刷写、部署、App Store 发布 | 未进行，不在本轮范围 |
| ESP32、“WiFi 终结者” | 型号和固件未确认，没有驱动或相关实现 |

构建命令、产物路径和未完成的证据见 [VALIDATION.md](documentation/custom/VALIDATION.md)。

## GitHub 访问

- 个人仓库为 [Fairank/Flipper-Momentum-Lab](https://github.com/Fairank/Flipper-Momentum-Lab)。GitHub App 安装（安装号 164333683）已收窄为只授权这一个仓库；浏览器授权由主控在用户明确许可后完成。
- 通过该连接器可以读写此仓库（推送分支、开 PR）；本机 `gh` 命令行仍未登录，不要依赖它。
- 不要向 `Next-Flip`、`DarkFlippers` 或 `Flipper-XFW` 推送本地改动。

## 新电脑取得源码

```sh
git clone --depth 1 --branch codex/iphone-zh-architecture https://github.com/Fairank/Flipper-Momentum-Lab.git
cd Flipper-Momentum-Lab
git remote add upstream https://github.com/Next-Flip/Momentum-Firmware.git
git remote add unleashed https://github.com/DarkFlippers/unleashed-firmware.git
git submodule update --init --recursive --depth 1 --jobs 4
```

`codex/momentum-unleashed` 是上一轮的分支，也是 PR #1 的目标分支，不含 iPhone 与中文代码。子模块必须按主仓库记录的提交检出，不要使用 `git submodule update --remote`。某个仓库不支持浅获取时，针对它去掉 `--depth 1` 重试。外部应用源码由 `applications/external` 子模块管理；工具链、构建缓存和日志不纳入版本控制，新电脑由 `fbt` 下载适合自身系统的工具链。

## 构建与测试

只有构建正常结束并检查 `dist/` 下的实际输出后，才能标为已生成安装包。核心构建和完整包分别记录。

### 桌面回归与生成器检查（任何系统）

```sh
python3 -m unittest discover -s scripts/tests -p "test*.py" -v   # 3 项旧回归 + 3 项 UTF-8 + 30 项字库生成器
python3 scripts/generate_lab_font.py --check                        # 字库头文件是否过期
git diff --check
```

C 回归通过 `shutil.which("cc")` 查找主机 C 编译器；找不到时显示 `skipped`，不能记为通过。Windows 原生环境没有 `cc`，本轮让 `cc` 解析到工作区内 Zig 0.16.0 的 `zig cc` 后真实编译并通过；WSL、macOS、Linux 自带 `cc` 即可。

### macOS / Linux 固件

```sh
FBT_GIT_SUBMODULE_SHALLOW=1 ./fbt SKIP_EXTERNAL=1 updater_package   # 核心构建
FBT_GIT_SUBMODULE_SHALLOW=1 ./fbt updater_package                   # 完整包（含外部应用）
FBT_GIT_SUBMODULE_SHALLOW=1 ./fbt fap_dist                          # 成功后另一次调用，复制 .fap
```

### Windows 固件

仓库路径含中文时，旧版 protoc 会失败。先把仓库临时映射到一个未占用的 ASCII 盘符（下例用 `P:`，按实际情况更换），在该盘符下构建：

```powershell
# 在仓库根目录执行
subst P: "$PWD"
Push-Location P:\
$env:PYTHONUTF8 = "1"
$env:FBT_NO_SYNC = "1"                          # 仅在子模块已按固定提交初始化后使用
.\fbt.cmd SKIP_EXTERNAL=1 updater_package       # 核心构建
.\fbt.cmd -j1 updater_package                   # 完整包
if ($LASTEXITCODE -ne 0) { throw "更新包构建失败" }
.\fbt.cmd -j1 fap_dist                          # 必须另一次调用，原因见下
Pop-Location                                    # 先离开 P:
subst P: /D                                     # 只删除盘符映射，不删除源码
```

不要在同一次调用中同时请求 `updater_package fap_dist`：打包脚本会删除 `dist`，导致构建图中已检查的目录失效；即使 `-j1` 也曾复现。先生成更新包，再单独调用 `fap_dist`。构建输出会提示两个上游无效 appid（`.cli_gui`、`.f0_mtp`）被排除，这是继承自上游应用清单的警告，保留即可。产物在 `dist/f7-C/`：更新包 `flipper-z-f7-update-mntm-<分支>-<提交>.tgz`、SDK 压缩包，以及 `apps/Tools/lab.fap`。

### iPhone App

构建与测试步骤见 [mobile/FlipperLab/README.zh-CN.md](mobile/FlipperLab/README.zh-CN.md)，本地需要 macOS 和 Xcode。本轮的 Windows 电脑没有 Xcode，也没有可用的 Mac；编译、Swift 包测试和模拟器 UI 测试都由 GitHub macOS CI（`.github/workflows/lab-validation.yml`）完成，真机蓝牙测试仍需单独进行。

## 开发时保留的决定

- Momentum 基线为 `d3f89dfe2ef6b01839201598e9be1590cba80322`，不能描述为永远最新。
- 无线设备插件 API 保持 Momentum 的版本 1；不要直接照搬 Unleashed 的版本 2。
- 本定制的固件 SDK API 为 87.2，新增四个导出函数，保留既有签名；这不是上游官方版本声明。
- 主题包、动画、菜单和设置体验沿用 Momentum。Flipper Lab 是新增的中文入口，已验证的硬件驱动不重写。现有原生应用的全面中文化是仍待完成的需求，在做完之前它们保持英文。
- 手机与设备使用仓库锁定的 protobuf（Next-Flip `ea4f185f5eaa265955c520eae2832887ee6aa5e4`），不替换为官方最新版本；App 要求 RPC 0.25 起的 0.x 版本。
- App 只在手机本地分析记录，不接云端 AI，不含固件升级；不新增密钥恢复、滚动码复现、实时射频数据流或未确认扩展板的驱动。
- 两份功能目录 JSON 必须逐字节一致。
- 仓库继承的上游 GitHub Actions（build、release、webhook 等）带有上游发布假设和官方 API 版本比较；本定制的验证以 `lab-validation.yml`（iPhone 与桌面回归）和 `lab-firmware.yml`（固件与 `lab.fap` 产物）为准，继承工作流的状态不能当作本定制的验证结论。
- 上游作者、许可证和来源均保留。不要向 `Next-Flip`、`DarkFlippers` 或 `Flipper-XFW` 推送本地改动。

## 可直接交给下一台电脑的助手

> 请先阅读 HANDOFF.md、mobile/FlipperLab/README.zh-CN.md、documentation/custom/REQUIREMENTS.md 和 VALIDATION.md。继续我授权的个人 Momentum 定制：按 REQUIREMENTS.md 实现全部需求，iPhone 优先（iPhone 17 Pro Max）。分支 codex/iphone-zh-architecture 已推送，草稿 PR #1 指向 codex/momentum-unleashed。保留 Momentum/Xtreme 风格和已验证的硬件驱动；现有原生应用的全面中文化仍是需求，未做完前不要写成已完成或已取消。验收只按实际运行结果勾选，源码、编译、CI、模拟器和真机分别记录，不把计划或未运行的测试写成完成。ESP32 与“WiFi 终结者”型号确认前不实现相关驱动。保留上游贡献政策文件，不向上游投稿；合并、刷写或发布前先征得我的确认。

## 历史记录

- 上一轮（`codex/momentum-unleashed`）的要求是“先保存已完成内容和全部需求，暂不一次做完”。该范围已被本轮“实现全部需求”取代，见 REQUIREMENTS.md 的 R6 与 R11。
- 上一台 macOS 的核心构建在 archive 引用外部应用头文件处失败（退出码 2），当时依赖不完整；本轮在完整子模块上的 Windows 核心构建与完整包构建均已通过，macOS 未复跑。详见 VALIDATION.md 的历史记录。
- IPHONE_ZH_PLAN.md 保存方案阶段的检查结果和当时状态（App 未实现、未找到可用的 Claude CLI），不代表当前进度。
- 本轮较早的委派任务返回模型为 `claude-opus-5-5`；其中 iOS 界面任务因服务端安全策略退出码 1、未产出文件，界面改由主控直接实现。一般任务默认 `claude-fable-5-1 --effort max`；用户最新明确指定本次 UI 重做为 5.1 Max 设计、Opus 5.5 实现。记录实际返回模型，不静默替换，见 VALIDATION.md。

## 其他文档

- [LOCAL_CHANGES.md](LOCAL_CHANGES.md)：首批三个固件改动、来源和兼容性。
- [SOURCE_LOCK.json](documentation/custom/SOURCE_LOCK.json)：主源码、Unleashed 来源提交及子模块固定版本。
- [INITIAL_ASSESSMENT.md](documentation/custom/INITIAL_ASSESSMENT.md)：2026-09-10 的固件选型与 Xtreme 源码评估，保留历史检查日期。
