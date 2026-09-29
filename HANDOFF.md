# 换电脑接续：Flipper 中文固件与 iPhone 工作台

更新：2026-09-29。工作分支 `codex/iphone-zh-architecture`，草稿 PR [#1](https://github.com/Fairank/Flipper-Momentum-Lab/pull/1)，目标分支 `codex/momentum-unleashed`。尚未合并，也没有上架或已签名 IPA。

本轮固件融合详见 [UPSTREAM_FUSION.md](documentation/custom/UPSTREAM_FUSION.md)。API 已更新为 89.0，protobuf 更新为 0.29 并保留 ASCII 输入扩展；原生字库现为 690 字形。以下手机功能保持原有范围；新增 GPS/网络代理只有固件端接口，iPhone 处理端未实现。旧编译包与 API 89.0 的应用不能混用。

## 当前实现

| 内容 | 状态与入口 |
| --- | --- |
| iPhone 中文 App | 设备、功能、资料库、任务、指南五页；蓝牙 RPC、应用启动、文件传输、离线分析、红外单次发送代码已实现。实际蓝牙流程未真机验收 |
| MIFARE Classic | “功能 → NFC 离线工作台”：两组认证样本恢复密钥、字典验证、合并去重和导出。公开答案、生成样本、取消和模拟器界面已自动验证；普通 .nfc 转储不能代替认证样本 |
| AIO 数据链路 | “功能 → 扩展板实时数据”：Lab Bridge 把 UART 输出经 BLE 转到手机，显示真实字节、丢失/截断并导出。代码和构建通过，实物链路未测；未实现未知板卡固件的专用无线驱动 |
| 原生中文界面 | 前轮完成 227 个应用/设置 C 文件、1,039 处文案，本轮补充新菜单、协议场景和红外保存流程；另有菜单中文显示名、字体回退、UTF-8 滚动/换行/对齐。当前 690 字形、17,336 字节。不是全部原生/第三方界面均完成翻译，更没有重写全部驱动 |
| 固件功能说明 | Flipper Lab 中文帮助及启动入口保留；有 66 张帮助页源码预览，另新增 4 张原生菜单代表预览，均不是真机截图 |
| Wi-Fi | 已保存扫描日志的离线多网络分析可用；没有新增定向断链控制。通用串口接收不能等同于 Wi-Fi 控制或实物板卡已适配 |

用户的手机为 iPhone 17 Pro Max，普通 Apple ID，可借用或使用 Mac。当前 Windows 工作环境没有 Xcode，用户暂时不连接 Flipper/AIO，要求先完成代码与自动测试。AIO Board 1.4 的厂商、芯片丝印、现装固件、端口和供电仍未知。

## 在 Mac 上接续

1. 获取上方工作分支，并阅读 [手机安装说明](mobile/FlipperLab/README.zh-CN.md)。
2. 安装完整 Xcode 与 XcodeGen，在仓库根目录运行 `sh mobile/FlipperLab/prepare-mac.sh`，用自己的 Apple ID 选择团队后安装。源码通过模拟器构建不等于已有签名安装包。
3. `swift test --package-path mobile/FlipperLab` 运行核心测试；App 和 UI 测试按手机说明运行。Classic C 目标由本地 Swift 包一起构建，没有远程 Swift 包依赖。
4. 核对实物后再运行 BLE 配对、文件字节一致性、UART 接收/停止/断连验收。不要把模拟器截图或公开样例结果记作用户设备结果。

## 固件与开发检查

- 使用固定子模块：`git submodule update --init --recursive`，不要升级 gitlink。
- 使用仓库工具链 39。完整打包先执行 `./fbt updater_package`，成功后**另一次**执行 `./fbt fap_dist`；同一 SCons 图同时请求两者可能因分发目录清理失败。Windows 用 `fbt.cmd`，必要时将工作区映射为 ASCII 路径再构建。
- 运行 `python scripts/generate_lab_font.py --check` 和 `python scripts/generate_native_zh_font.py --check`；修改中文文案后重新生成字库。
- 桌面检查：`python -m unittest discover -s scripts/tests -p "test*.py" -v`。必须有 C 编译器，跳过 C 测试不能算通过。Linux 的恢复与原生 GUI 回归启用 ASan/UBSan。
- CI 检查恢复升级器不超过 131,072 字节，且资源包含 `lab.fap`、`lab_bridge.fap`。中文字体仅进入正常固件，恢复升级器维持原有英文。
- UI 预览脚本分别为 `scripts/render_lab_preview.py` 和 `scripts/render_native_zh_preview.py`；后者需 `--output-dir`。从源码绘制的图片不能替代刷机验收。

## 记录与分工

[需求与未完成项](documentation/custom/REQUIREMENTS.md)、[实际验证](documentation/custom/VALIDATION.md)、[中文覆盖范围](documentation/custom/NATIVE_ZH_PROGRESS.md)、[Classic 格式与限制](mobile/FlipperLab/CLASSIC_OFFLINE.zh-CN.md)、[串口桥条件](mobile/FlipperLab/SERIAL_BRIDGE.zh-CN.md)是接续依据。两份 FeatureCatalog JSON 必须逐字节相同。

用户已明确授权 AI 修改本个人仓库、测试并推送现有草稿 PR，覆盖继承的上游反 AI 贡献限制；未授权向上游投稿。最新模型偏好是仅通过 CLI 使用 `claude-fable-5-1 --effort max` 处理边界清楚的基础工作，主助手负责关键逻辑、审核和真实验收，记录实际模型及退出状态，不静默切换。App 不调用 Claude 或其他云端 AI。
