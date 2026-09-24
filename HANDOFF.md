# 换电脑接续：Momentum 个人定制与 iPhone 中文工作台

交接日期：2026-09-24。当前工作分支：`codex/iphone-zh-architecture`，基于 `b06c940ec326fef33954b49cffbc085f16607aaf`，**只在本地、尚未推送**，没有对应的 PR。原开发分支为 `codex/momentum-unleashed`。

这是用户授权、由 AI 辅助的个人定制。上游 `AGENTS.md`、`CONTRIBUTING.md` 的禁止 AI 贡献规则和原文件保留；本交接不代表上游认可，也不包含向上游提交贡献的请求。

## 先读这些

1. [mobile/README.md](mobile/README.md)：iPhone App 源码结构、构建与测试入口（与 Xcode 工程、CI 一起编写中）。
2. [REQUIREMENTS.md](documentation/custom/REQUIREMENTS.md)：需求、各模块源码状态和验收清单。
3. [VALIDATION.md](documentation/custom/VALIDATION.md)：实际运行过的构建与测试，以及尚未运行的项目。
4. [FEATURE_CATALOG.zh-CN.json](documentation/custom/FEATURE_CATALOG.zh-CN.json)：中文功能说明；App 内置副本 `mobile/FlipperLab/Sources/FlipperCore/Resources/FeatureCatalog.json` 必须与它逐字节一致。
5. [IPHONE_ZH_PLAN.md](documentation/custom/IPHONE_ZH_PLAN.md)：设计依据和方案阶段的记录，不代表当前进度。

## 当前任务

用户选择 Momentum 作为固件基础，保留 Xtreme/Momentum 的界面、主题和定制体验，并逐项适配 Unleashed 的功能。本轮用户明确要求实现仓库中的全部需求，不停留在方案：

- 新做 iPhone App，连接 Flipper，利用手机算力增强功能。目标设备为 iPhone 17 Pro Max，运行已安装的最新 iOS（确切版本未记录）。
- Flipper 本机功能部分重写：新增中文入口应用 Flipper Lab，保留已验证的硬件驱动；现有原生应用保持原有语言。
- 手机与设备提供中文界面和功能介绍。

Mac、Flipper 硬件版本和扩展板的确切型号仍未知。

分工：主控负责决策与验收，编写蓝牙连接和设备控制代码，并审查全部改动。五个本机 Claude CLI 工作进程分别负责记录解析与存储、iOS 界面、设备端中文工作台与字库、工程与 CI、UTF-8 修复；实际观察到的返回模型为 `claude-opus-5-5`（`--effort max`）。这些委派仍在进行，主控复核前不算完成。本机 Claude 只是开发工具，App 不调用任何云端 AI 服务。

## 当前状态

| 内容 | 状态 |
| --- | --- |
| 固定子模块 | 已按主仓库记录的提交递归初始化，未升级任何 gitlink |
| 核心固件构建（`SKIP_EXTERNAL=1`） | Windows 上 2026-09-24 15:37 成功，退出码 0，生成核心更新包与 SDK；只覆盖当时的工作区 |
| 完整更新包（含外部应用） | 构建正在运行，结果待记录 |
| 旧桌面回归 | 本轮 Windows 为 1 项通过、2 项因缺少 `cc` 跳过；3 项全过是上一台 macOS 的历史结果 |
| iPhone App（`mobile/FlipperLab`） | 蓝牙连接、RPC、文件传输和红外发送源码已编写；解析与存储、界面、工程与 CI 编写中；从未编译 |
| Flipper Lab（`applications/main/lab`） | 中文入口、分页说明、字库和启动现有应用正在编写 |
| UTF-8 文字换行修复 | 编写中 |
| iOS 编译、模拟器、蓝牙真机测试 | 未运行；分支推送后先由 GitHub macOS CI 做编译检查 |
| 刷写、部署、App Store 发布 | 未进行，不在本轮范围；App 也不含固件升级功能 |
| ESP32、“WiFi 终结者” | 型号和固件未确认，没有相关实现 |

构建命令、产物路径和未完成的证据见 [VALIDATION.md](documentation/custom/VALIDATION.md)。

## 新电脑取得源码

仓库为 [Fairank/Flipper-Momentum-Lab](https://github.com/Fairank/Flipper-Momentum-Lab)。本轮分支尚未推送；在推送前，远程仓库只有 `codex/momentum-unleashed`，不含 iPhone 与中文代码。推送后把下面的分支名换成 `codex/iphone-zh-architecture`。推送需要有写入权限的 GitHub 账号。

```sh
git clone --depth 1 --branch codex/momentum-unleashed https://github.com/Fairank/Flipper-Momentum-Lab.git
cd Flipper-Momentum-Lab
git remote add upstream https://github.com/Next-Flip/Momentum-Firmware.git
git remote add unleashed https://github.com/DarkFlippers/unleashed-firmware.git
git submodule update --init --recursive --depth 1 --jobs 4
```

子模块必须按主仓库记录的提交检出，不要使用 `git submodule update --remote`。某个仓库不支持浅获取时，针对它去掉 `--depth 1` 重试。外部应用源码由 `applications/external` 子模块管理；工具链、构建缓存和日志不纳入版本控制，新电脑由 `fbt` 下载适合自身系统的工具链。

## 构建与测试

只有构建正常结束并检查 `dist/` 下的实际输出后，才能标为已生成安装包。核心构建和完整包分别记录。

### macOS / Linux

```sh
python3 scripts/tests/test_unleashed_integration.py -v   # 需要 cc，应为 3 项通过
git diff --check
FBT_GIT_SUBMODULE_SHALLOW=1 ./fbt SKIP_EXTERNAL=1 updater_package   # 核心构建
FBT_GIT_SUBMODULE_SHALLOW=1 ./fbt updater_package                   # 完整包（含外部应用）
```

回归显示 `skipped` 表示缺少 C 编译器，不能记为全部通过。

### Windows 构建

仓库路径含中文时，旧版 protoc 会失败。先把仓库临时映射到一个未占用的 ASCII 盘符（下例用 `P:`，按实际情况更换），在该盘符下构建：

```powershell
# 在仓库根目录执行
subst P: "$PWD"
Push-Location P:\
$env:PYTHONUTF8 = "1"
$env:FBT_NO_SYNC = "1"                      # 仅在子模块已按固定提交初始化后使用
.\fbt.cmd SKIP_EXTERNAL=1 updater_package   # 核心构建
.\fbt.cmd updater_package                   # 完整包（含外部应用）
Pop-Location                                # 先离开 P:
subst P: /D                                 # 只删除盘符映射，不删除源码
```

Windows 原生环境缺少 `cc` 时，桌面 C 回归会跳过；需在 WSL、macOS 或 Linux 中运行才能得到 3 项结果。

### iPhone App

构建与测试步骤见 [mobile/README.md](mobile/README.md)，需要 macOS 和 Xcode。本轮所用的 Windows 电脑没有 Xcode，App 从未编译；推送后由 GitHub macOS CI 先做编译检查，模拟器与真机测试仍需单独进行。

## 开发时保留的决定

- Momentum 基线为 `d3f89dfe2ef6b01839201598e9be1590cba80322`，不能描述为永远最新。
- 无线设备插件 API 保持 Momentum 的版本 1；不要直接照搬 Unleashed 的版本 2。
- 本定制的固件 SDK API 为 87.2，新增四个导出函数，保留既有签名；这不是上游官方版本声明。
- 主题包、动画、菜单和设置体验沿用 Momentum。Flipper Lab 是新增的中文入口，现有原生应用不强行翻译，已验证的硬件驱动不重写。
- 手机与设备使用仓库锁定的 protobuf（Next-Flip `ea4f185f5eaa265955c520eae2832887ee6aa5e4`），不替换为官方最新版本；App 要求 RPC 0.25 起的 0.x 版本。
- App 只在手机本地分析记录，不接云端 AI，不含固件升级；不新增密钥恢复、滚动码复现、实时射频数据流或未确认扩展板的驱动。
- 两份功能目录 JSON 必须逐字节一致。
- 仓库继承的 GitHub Actions 是上游发布流程，含与官方 API 版本比较、上传配置等，尚未适配个人仓库，不能当作本定制的验证结论。
- 上游作者、许可证和来源均保留。不要向 `Next-Flip`、`DarkFlippers` 或 `Flipper-XFW` 推送本地改动。

## 可直接交给下一台电脑的助手

> 请先阅读 HANDOFF.md、mobile/README.md、documentation/custom/REQUIREMENTS.md 和 VALIDATION.md。继续我授权的个人 Momentum 定制：按 REQUIREMENTS.md 实现全部需求，iPhone 优先（iPhone 17 Pro Max）。保留 Momentum/Xtreme 风格和已验证的硬件驱动，现有原生应用不强行翻译。验收只按实际运行结果勾选，源码、编译、模拟器和真机分别记录，不把计划或未运行的测试写成完成。ESP32 与“WiFi 终结者”型号确认前不实现相关驱动。保留上游贡献政策文件，不向上游投稿；推送、刷写或发布前先征得我的确认。

## 历史记录

- 上一轮（`codex/momentum-unleashed`）的要求是“先保存已完成内容和全部需求，暂不一次做完”。该范围已被本轮“实现全部需求”取代，见 REQUIREMENTS.md 的 R6 与 R11。
- 上一台 macOS 的核心构建在 archive 引用外部应用头文件处失败（退出码 2），当时依赖不完整；本轮在完整子模块上的 Windows 核心构建已通过，macOS 未复跑。详见 VALIDATION.md 的历史记录。
- IPHONE_ZH_PLAN.md 保存方案阶段的检查结果和当时状态（App 未实现、未找到可用的 Claude CLI），不代表当前进度。

## 其他文档

- [LOCAL_CHANGES.md](LOCAL_CHANGES.md)：首批三个固件改动、来源和兼容性。
- [SOURCE_LOCK.json](documentation/custom/SOURCE_LOCK.json)：主源码、Unleashed 来源提交及子模块固定版本。
- [INITIAL_ASSESSMENT.md](documentation/custom/INITIAL_ASSESSMENT.md)：2026-09-10 的固件选型与 Xtreme 源码评估，保留历史检查日期。
