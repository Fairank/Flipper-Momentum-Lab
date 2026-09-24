# 验证记录

记录日期：2026-09-24。本文只记录实际运行过的检查。源码已编写不等于编译、模拟器或真机通过；本轮没有刷写设备、部署或发布 App。

## 当前环境

- 本地分支 `codex/iphone-zh-architecture`，基于 `b06c940ec326fef33954b49cffbc085f16607aaf`；尚未推送，没有 PR。
- Windows 11 原生环境，官方工具链 39 可用。
- 全部固定子模块已递归初始化，未升级任何 gitlink；版本见 [SOURCE_LOCK.json](SOURCE_LOCK.json)。
- 本机为 Windows，没有 Xcode；Mac 型号未知。iPhone、Flipper 和扩展板均未接入测试。

## 当前结果

| 检查 | 结果 | 能证明的范围 |
| --- | --- | --- |
| 核心固件构建：`FBT_NO_SYNC=1 fbt.cmd SKIP_EXTERNAL=1 updater_package` | 2026-09-24 15:37（本地时间）结束，退出码 0 | 构建当时的工作区能编译核心固件并打包 |
| 完整更新包：不带 `SKIP_EXTERNAL` 的 `updater_package`，包含外部应用 `fap_dist` | 运行中，退出码与产物待记录 | 暂无 |
| 旧桌面回归：`python -X utf8 scripts/tests/test_unleashed_integration.py -v` | 1 passed / 2 skipped（缺少桌面 C 编译器 `cc`）；本轮较早时运行，之后未重跑 | 只执行了源文件顺序测试 |
| FlipperCore 单元测试、App 编译、模拟器 | 未运行 | 无 |
| 蓝牙连接、iPhone 与 Flipper 真机 | 未运行 | 无 |

核心构建产物：

- `dist/f7-C/flipper-z-f7-update-mntm-codex-iphone-zh-architecture-b06c940e.tgz`
- 同目录下的 SDK 压缩包
- SHA-256：尚未记录。

包名中的 `b06c940e` 来自当前基线提交，不代表构建时工作区没有未提交改动。该结果不覆盖 15:37 之后加入的 Flipper Lab、字库和 UTF-8 修复，这些改动完成后须重新构建。产物未刷写到任何设备。

### Windows 中文路径

原工作区路径含中文，旧版 protoc 无法处理，构建因此失败。用 `subst` 把仓库临时映射到一个 ASCII 盘符，并设置 `PYTHONUTF8=1` 后，核心构建通过。操作步骤见 [HANDOFF.md](../../HANDOFF.md) 的“Windows 构建”；`subst P: /D` 只删除盘符映射，不删除源码。

`FBT_NO_SYNC=1` 会跳过 fbt 的子模块同步，只能在子模块已按固定提交初始化后使用。

## 本轮源码状态

各模块的“已编写 / 编写中”见 [REQUIREMENTS.md](REQUIREMENTS.md)。所有 iPhone 与 Flipper Lab 源码均未经过编译或运行，功能说明中的状态以 [FEATURE_CATALOG.zh-CN.json](FEATURE_CATALOG.zh-CN.json) 为准。

## 委派记录

- 方式：用户授权的本机 Claude CLI 工作进程。实际观察到的返回模型为 `claude-opus-5-5`，参数 `--effort max`，不是 `claude-fable-5-1` 默认设置。
- 五项工作：记录解析与存储、iOS 界面、设备端中文工作台与字库、工程与 CI、UTF-8 修复。状态：进行中，尚未经主控复核，不计为完成。
- 主控负责决策、验收、蓝牙与设备控制代码，并审查全部改动。
- [IPHONE_ZH_PLAN.md](IPHONE_ZH_PLAN.md) 中“未找到 CLI、未调用委派”是当时的状态，已由本节更新。

## 待补证据

1. 完整更新包构建的退出码、关键错误或产物路径。
2. 核心包与完整包的 SHA-256。
3. 加入 Flipper Lab、字库和 UTF-8 修复后的重新构建结果和固件大小。
4. 分支推送后 GitHub macOS CI 的 Swift 包测试与 App 编译结果。
5. 模拟器检查，以及 iPhone 17 Pro Max 与 Flipper 真机的完整蓝牙流程。
6. 在有 `cc` 的环境运行旧回归的 3 项结果。
7. 扩展板型号及测试记录。

GitHub 上继承的固件工作流仍带上游发布假设和官方 API 版本一致性检查。个人定制 API 87.2 可能与该检查冲突；工作流尚未适配，其状态不能等同于本定制的验证结论。

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

本轮在完整初始化的子模块上，Windows 核心构建已经通过；macOS 上没有重新构建。
