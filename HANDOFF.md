# 换电脑接续：Flipper 中文固件与 iPhone 工作台

更新：2026-09-29。工作分支 `codex/iphone-zh-architecture`，草稿 PR [#1](https://github.com/Fairank/Flipper-Momentum-Lab/pull/1)，目标分支 `codex/momentum-unleashed`。尚未合并，也没有上架或已签名 IPA。

最新实现详见 [第三轮：手机能力共享与中文资源](documentation/custom/COMPANION_AND_CHINESE_20260929.md)，历史实现见 [第二轮](documentation/custom/UNION_CHINESE_CONTINUATION.md) 和 [协议适配](documentation/custom/UPSTREAM_FUSION.md)。API 为 89.0，protobuf 为 0.29 并保留 ASCII 输入扩展；iPhone GPS/网络处理端现已实现。常规中文改用 SD 字库及有界缓存，覆盖 7,097 个字形；无卡保留 223 字形子集，升级器独立保留 135 字形。最新测试与产物证据见 [VALIDATION.md](documentation/custom/VALIDATION.md)。旧编译包与 API 89.0 的应用不能混用。

## 当前实现

| 内容 | 状态与入口 |
| --- | --- |
| iPhone 中文 App | 设备、功能、资料库、任务、指南五页；蓝牙 RPC、应用启动、文件传输、离线分析、红外单次发送代码已实现。实际蓝牙流程未真机验收 |
| MIFARE Classic | “功能 → NFC 离线工作台”：两组认证样本恢复密钥、字典验证、合并去重和导出。公开答案、生成样本、取消和模拟器界面已自动验证；普通 .nfc 转储不能代替认证样本 |
| AIO 数据链路 | “功能 → 扩展板实时数据”：Lab Bridge 把 UART 输出经 BLE 转到手机，显示真实字节、丢失/截断并导出。代码和构建通过，实物链路未测；未实现未知板卡固件的专用无线驱动 |
| 原生中文界面 | 在已有中文场景与排版修复上补动态信息、68 条动画对白、九类默认动画文字层；SD 字库随升级包安装。第三方、动态及其他位图文字仍有遗漏，没有重写全部驱动 |
| 本机新功能 | 快捷设置、床头时钟、菜单过渡；累计二十个导入工具/应用及手机端中文说明。本轮新增手机 GPS、棋钟、计时器、分形、骰子等，并把手机联网测试加入正式工具 |
| 手机定位与网络共享 | “设备 → 手机能力共享”中分别开启，要求 BLE 就绪和 App 前台。GPS、HTTP(S)、TCP、UDP、WebSocket 请求处理已实现；系统 TLS/ATS 保持默认。实际 BLE 链路与权限流程尚未真机验收 |
| 固件功能说明 | Flipper Lab 中文帮助及启动入口保留；有 66 张帮助页和 6 个原生菜单的源码预览，均不是真机截图 |
| Wi-Fi | 已保存扫描日志的离线多网络分析可用；没有新增定向断链控制。通用串口接收不能等同于 Wi-Fi 控制或实物板卡已适配 |

用户的手机为 iPhone 17 Pro Max，普通 Apple ID，可借用或使用 Mac。当前 Windows 工作环境没有 Xcode，用户暂时不连接 Flipper/AIO，要求先完成代码与自动测试。AIO Board 1.4 的厂商、芯片丝印、现装固件、端口和供电仍未知。

## 在 Mac 上接续

1. 获取上方工作分支，并阅读 [手机安装说明](mobile/FlipperLab/README.zh-CN.md)。
2. 安装完整 Xcode 与 XcodeGen，在仓库根目录运行 `sh mobile/FlipperLab/prepare-mac.sh`，用自己的 Apple ID 选择团队后安装。源码通过模拟器构建不等于已有签名安装包。
3. `swift test --package-path mobile/FlipperLab` 运行核心测试；App 和 UI 测试按手机说明运行。Classic C 目标由本地 Swift 包一起构建，没有远程 Swift 包依赖。
4. 按 [手机能力共享说明](documentation/custom/PHONE_COMPANION_GUIDE.zh-CN.md) 核对定位与网络。确认 AIO 实物后再验收 BLE 配对、文件字节一致性、UART 接收/停止/断连。不要把模拟器截图或公开样例结果记作用户设备结果。

## 固件与开发检查

- 使用固定子模块：`git submodule update --init --recursive`，不要升级 gitlink。
- 使用仓库工具链 39。完整打包先执行 `./fbt updater_package`，成功后**另一次**执行 `./fbt fap_dist`；同一 SCons 图同时请求两者可能因分发目录清理失败。Windows 用 `fbt.cmd`，必要时将工作区映射为 ASCII 路径再构建。
- 运行 `python scripts/generate_lab_font.py --check`、`python scripts/generate_native_zh_font.py --check`、`python scripts/generate_native_zh_font.py --updater --check` 和 `python scripts/generate_zh_resource.py --check`；修改中文文案后重新生成对应字库。
- 桌面检查：`python -m unittest discover -s scripts/tests -p "test*.py" -v`。必须有 C 编译器，跳过 C 测试不能算通过。Linux 的恢复与原生 GUI 回归启用 ASan/UBSan。
- CI 检查恢复升级器不超过 131,072 字节；本轮另外核验升级包内 24 项指定应用和 SD 字库。常规包包含 291 个正式 FAP、121 个 FAL，完整开发分发含 343 / 124。本地主固件到当前无线栈前还余 9,112 字节；云端准确值见验证记录。新增内容仍必须通过打包边界检查，不能按链接器全部 `.free_flash` 估算；还需检查新字库缓存的运行时 RAM 和线程栈。
- UI 预览脚本为 `scripts/render_lab_preview.py`、`scripts/render_native_zh_preview.py` 和 `scripts/render_animation_zh_preview.py`。后两者需 `--output-dir`，动画预览还需 Pillow 与主机 C 编译器。从源码绘制的图片不能替代刷机验收。

## 记录与分工

[需求与未完成项](documentation/custom/REQUIREMENTS.md)、[实际验证](documentation/custom/VALIDATION.md)、[中文覆盖范围](documentation/custom/NATIVE_ZH_PROGRESS.md)、[Classic 格式与限制](mobile/FlipperLab/CLASSIC_OFFLINE.zh-CN.md)、[串口桥条件](mobile/FlipperLab/SERIAL_BRIDGE.zh-CN.md)是接续依据。两份 FeatureCatalog JSON 必须逐字节相同。

用户已明确授权 AI 修改本个人仓库、测试并推送现有草稿 PR，覆盖继承的上游反 AI 贡献限制；未授权向上游投稿。最新默认仅通过 CLI 使用 `claude-fable-5-1 --effort max` 处理边界清楚的基础工作；前段按当时指定执行的 Opus 任务和本轮 Fable 任务分别记录实际返回模型、退出状态。主助手负责关键逻辑、审核和真实验收，不静默切换。App 不调用 Claude 或其他云端 AI。
