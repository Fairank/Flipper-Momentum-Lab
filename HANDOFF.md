# 换电脑接续：Momentum 个人定制

交接日期：2026-09-24。当前开发分支：`codex/momentum-unleashed`。

## 先了解当前任务

用户选择 Momentum 作为 Flipper Zero 固件基础，保留 Xtreme/Momentum 的界面、主题和定制体验，逐项适配 Unleashed 的有用功能。后续希望研究 ESP32 和“WiFi 终结者”扩展，但现在要求先保存已经完成的内容和全部需求，在另一台电脑继续，暂不一次做完升级。

这是用户授权、由 AI 辅助的个人定制。上游 `AGENTS.md`、`CONTRIBUTING.md` 的禁止 AI 贡献规则和原文件保留；本交接不代表上游认可，也不包含向上游提交贡献的请求。

| 内容 | 当前状态 |
| --- | --- |
| Momentum 源码及固定依赖版本 | 已记录，见 [SOURCE_LOCK.json](documentation/custom/SOURCE_LOCK.json) |
| 应用资源释放进度条 | 已实现，本地回归通过 |
| 插件扫描容错、无线驱动前缀过滤 | 已实现，本地回归通过 |
| 构建源文件模式稳定去重 | 已实现，本地回归通过 |
| 完整固件编译、安装包 | 尚未通过，最近错误及后续准备见下文 |
| Flipper 真机刷写与验证 | 未进行 |
| ESP32、“WiFi 终结者”升级 | 仅记录需求，尚未确认具体硬件和固件 |

## 新电脑取得源码

仓库计划使用 `Fairank/Flipper-Momentum-Lab`。若仓库尚未建立或上传完成，不要把本段视为已经上传成功的证明。私有仓库需要使用有访问权限的 GitHub 账号登录 Git 客户端。

```sh
git clone --branch codex/momentum-unleashed https://github.com/Fairank/Flipper-Momentum-Lab.git
cd Flipper-Momentum-Lab
git remote add upstream https://github.com/Next-Flip/Momentum-Firmware.git
git remote add unleashed https://github.com/DarkFlippers/unleashed-firmware.git
git submodule update --init --recursive --depth 1 --jobs 4
```

远程名称已存在时直接复用。子模块必须按主仓库记录的提交检出，不要使用 `git submodule update --remote` 升级到最新版本。断网后可重试上面的子模块命令；如果某个仓库不支持浅获取，针对它去掉 `--depth 1` 重试。

外部应用源码由 `applications/external` 子模块管理，并非丢失的文件。工具链、构建缓存和日志没有纳入版本控制；新电脑通过 `fbt` 下载适合自身系统的工具链。

## 优先继续哪一步

先看 [需求与待办](documentation/custom/REQUIREMENTS.md) 和 [验证记录](documentation/custom/VALIDATION.md)。当前第一步是恢复依赖并完成构建验证；不要马上合并 Unleashed 全分支或批量添加无线功能。

在 macOS / Linux 上运行现有回归（需要 Python 3 和桌面 C 编译器 `cc`）：

```sh
python3 scripts/tests/test_unleashed_integration.py -v
git diff --check
```

应当是 3 个测试全部通过。如果显示 `skipped`，说明 C 编译器缺失，不能记为全部测试通过。Windows 可在 WSL 中运行这组桌面 C 回归；Windows 原生固件构建用仓库自带 `fbt.cmd`。

macOS / Linux 的核心构建检查：

```sh
FBT_GIT_SUBMODULE_SHALLOW=1 ./fbt SKIP_EXTERNAL=1 updater_package
```

核心构建通过后，再构建含外部应用的完整包：

```sh
FBT_GIT_SUBMODULE_SHALLOW=1 ./fbt updater_package
```

Windows PowerShell 的完整包入口：

```powershell
$env:FBT_GIT_SUBMODULE_SHALLOW = "1"
.\fbt.cmd updater_package
```

`SKIP_EXTERNAL=1` 不代表不需要外部源码：Momentum 的文件管理器仍引用三个外部应用的头文件。上一台电脑第一次构建在这里失败，随后补齐了这些头文件，但未重新构建。新电脑正常初始化全部子模块后再验证，遇到后续错误需如实记录。

只有构建正常结束并检查 `dist/` 下实际输出后，才能标为已生成安装包。完整包和核心构建检查的结果要分别记录。设备当前固件、SD 卡内容和板卡型号尚未确认，尚无刷写或硬件测试结果。

## 开发时保留的决定

- Momentum 基线为 `d3f89dfe2ef6b01839201598e9be1590cba80322`，不能把它描述为永远最新。
- 无线设备插件 API 保持 Momentum 的版本 1；不要直接照搬 Unleashed 的版本 2。
- 本定制的固件 SDK API 为 87.2，新增四个导出函数，保留既有签名；这不是上游官方版本声明。
- 主题包、动画、菜单和设置体验沿用 Momentum；移植前先核对是否已经有等价功能。
- 仓库继承的 GitHub Actions 是上游发布流程，含与官方 API 版本比较、上传配置等。尚未适配个人仓库，不能将其直接当作本定制版的验证结论。
- 上游作者、许可证和来源均保留。不要向 `Next-Flip`、`DarkFlippers` 或 `Flipper-XFW` 推送本地改动。

## 可直接交给下一台电脑的助手

> 请先阅读 HANDOFF.md、LOCAL_CHANGES.md 和 documentation/custom/REQUIREMENTS.md。继续我授权的个人 Momentum 定制，保留 Momentum/Xtreme 风格，按需要适配 Unleashed。现在先恢复固定依赖、运行已有三个回归并完成完整固件构建，记录真实结果；不要把计划当作已实现，也不要一次实现全部待办。ESP32 和“WiFi 终结者”的具体型号及现有固件尚未确认，先厘清兼容性和需求再扩展。上游贡献政策文件保留，不向上游投稿。

## 文档导航

- [LOCAL_CHANGES.md](LOCAL_CHANGES.md)：三个已实现改动、来源和兼容性。
- [REQUIREMENTS.md](documentation/custom/REQUIREMENTS.md)：用户需求、候选项、优先级和验收标准。
- [VALIDATION.md](documentation/custom/VALIDATION.md)：测试结果、编译失败位置、依赖状态。
- [INITIAL_ASSESSMENT.md](documentation/custom/INITIAL_ASSESSMENT.md)：2026-09-10 的固件选型与 Xtreme 源码评估，保留历史检查日期。
- [SOURCE_LOCK.json](documentation/custom/SOURCE_LOCK.json)：主源码、Unleashed 来源提交及子模块固定版本。
