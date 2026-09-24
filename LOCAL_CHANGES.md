# Momentum 本地定制版

以 Momentum 的界面、主题包和应用体系为基础，逐项适配 Unleashed 中有价值的改进。

## 来源

- Momentum 基线：`d3f89dfe2ef6b01839201598e9be1590cba80322`，2026-08-18。
- 本地开发分支：`codex/momentum-unleashed`。
- 上游来源为 Momentum；`unleashed` 指向 Unleashed，供后续比较。新电脑的 `origin` 应指向个人仓库，`upstream` 指向 Momentum。
- 本次为 AI 辅助的个人本地定制。Momentum 上游的 `AGENTS.md` 和 `CONTRIBUTING.md` 禁止 AI 贡献；这些文件保持原样，本定制并非上游发布或认可的版本。
- 原有许可证、作者信息及第三方来源保留。

## 第一批改进

### 应用资源加载进度

带有内置资源的应用首次启动或更新后，把资源释放到 SD 卡时，在原有加载动画下显示进度条。进度按文件数量计算；不同文件大小不同，因此它不表示剩余时间。

适配时保留 Momentum 先读取应用清单、按应用标记卸载主题包、再加载完整应用的流程。资源处理返回后，无论成功还是失败，都会复位进度条。

来源：[Unleashed 69c0368](https://github.com/DarkFlippers/unleashed-firmware/commit/69c036819ef2b8415ac3c579104b039e43f91ec6)。

### 插件加载容错

扫描插件目录时，损坏或不兼容的插件不会中断后续扫描。属于其他应用的插件被跳过；真实加载错误和目录读取错误会返回给调用者。无线驱动按 `radio_device_*.fal` 文件名筛选，避免加载同目录的无关插件。

原有的“目录无法打开时视为没有插件”行为保留。自行改名的无线驱动需保留 `radio_device_` 前缀；本仓库自带的 CC1101 驱动符合此约定。无线设备插件接口版本继续使用 Momentum 的版本 1。

同时调整两个插件示例：遇到部分失败仍使用已加载插件，并正常释放管理器。

来源：[Unleashed 944219d](https://github.com/DarkFlippers/unleashed-firmware/commit/944219d0bac00ba2ece04dd3670f2f22ccd7a0bf)。仅移植插件扫描及驱动筛选部分，未引入该提交中其他应用布局变更。

### 构建源文件顺序固定

收集源文件时按原顺序去重，避免 Python 随机哈希种子改变源文件模式的处理顺序。这个修复改善构建一致性，不等于保证整个安装包逐字节相同。

来源：[Unleashed 83fbee3](https://github.com/DarkFlippers/unleashed-firmware/commit/83fbee38f1399e65833835a256f0c5b0501f54e7)，仅移植 `GatherSources` 的去重改进。

## 兼容性与范围

- 主题包、桌面、菜单样式和 Momentum 设置界面沿用基线。
- 本地固件 API 从 87.1 更新为 87.2，新增四个函数，没有删除或修改既有导出函数的签名。仍需通过完整构建和实际应用启动验证兼容性。
- Momentum 已集成许多 Unleashed 功能。本次没有把 Unleashed 整个开发分支直接合并；协议列表与外接硬件的新特性需要逐项确认差异后再移植。
- 尚未连接或刷写 Flipper。后续需要在真机上验证首次/再次启动、SD 卡错误、主题包显示，以及坏插件夹在两个正常插件之间的表现。

## 验证

本地回归入口：

```sh
python3 scripts/tests/test_unleashed_integration.py -v
```

三个测试覆盖：

1. 五种 `PYTHONHASHSEED` 下的源文件模式顺序、去重与排除项。
2. 实际 C 插件扫描函数的错误后继续加载、前缀过滤、外来插件跳过、首个错误保留、目录读取失败和句柄释放。
3. 实际 C 加载视图函数的进度限幅、复位、重复值免重绘、动画保留和进度条布局边界。

C 测试使用桌面端存储及绘图替身；不能替代整机编译、真实 SD 卡、GUI 线程和硬件验证。

截至 2026-09-24，三个测试通过，修改过的 13 个 C/header 文件通过工具链的格式检查，`git diff --check` 通过。既有 4,675 个 API 条目的签名和状态保持不变。

已安装并验证官方工具链 39（GCC 12.3.1，当前机器为 macOS arm64）。首次构建 `FBT_NO_SYNC=1 ./fbt SKIP_EXTERNAL=1 updater_package` 因缺少外部应用头文件 `subghz_playlist/playlist_file.h` 失败。随后已按原固定版本取得 `subghz_playlist`、`subghz_remote`、`ir_remote` 三个外部应用目录；补齐后尚未重新编译。没有成功生成可刷写安装包，也没有进行真机验证。

完整交接见 [HANDOFF.md](HANDOFF.md)，需求见 [REQUIREMENTS.md](documentation/custom/REQUIREMENTS.md)，验证及依赖细节见 [VALIDATION.md](documentation/custom/VALIDATION.md)。
