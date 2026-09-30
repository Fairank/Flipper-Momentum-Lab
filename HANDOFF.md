# 换电脑接续：Flipper 英文固件与中文 iPhone 工作台

更新：2026-09-30。工作分支 `codex/iphone-zh-architecture`，草稿 PR [#1](https://github.com/Fairank/Flipper-Momentum-Lab/pull/1)，目标分支 `codex/momentum-unleashed`。尚未合并，也没有上架或已签名 IPA。

**当前目标：暂停自建手机 UI，优先适配官方 Flipper 手机 App；本机英文和功能升级保留。** 先读 [官方 App 兼容范围](documentation/custom/OFFICIAL_APP_COMPATIBILITY_20260930.md)：标准屏幕遥控、应用启动和文件管理有源码兼容路径，官方目录及未实现的手机能力仍有客户端限制。当前英文帮助扩至11主题／62页，新增“Phone Remote”链接 Apps 浏览器；固件修复 RPC 启动 API 不匹配的阻塞弹窗、遥控输入边界和非线程 Apps 的队列收尾。逐提交实际结果见 [验证记录](documentation/custom/VALIDATION.md)。真实 BLE／AIO、逐应用控制和完整功能并集仍未完成。

此前已恢复2,252处C文案、27个名称、23份介绍、22份动画元数据；固定子模块APDU中文保留，SD字库及125字形无卡子集支持中文用户文件，265字形扫描参考子集不链接主固件。自建手机保留31项中文映射、嵌套发现、结构化NFC比较、中文错误、来源／分类／多词筛选、独立详情和有限前台恢复。已验证的旧手机源码及原图见 [手机优化](documentation/custom/OFFICIAL_APP_REFINEMENT_20260930.md)；未完成的下一轮风格稿备份在本机 `work/flipper-tools/paused-flipper-phone-style-20260930/`，未编译或发布。

本轮对照官方固定源码实现应用浏览和连接恢复；点选直接在设备打开，手机不自动切到屏幕镜像。恢复会清理旧会话、重新握手和读取目录，具体操作不会重发；旧任务异常不能关闭新连接。目录预览明确标记样例，不改变真实连接或启动白名单。真实BLE／AIO、逐应用控制和完整功能并集仍未验收完成；未提供签名IPA。

历史第四轮代码 `12b8c35f3` 增加四个中文应用、记事本数据保护和真实 WebSocket 回环测试，`6f94bdc9d` 补存储回归与手机比较入口导航修订，见 [第四轮实现与预览](documentation/custom/UNION_CHINESE_20260930.md)。该轮累计导入二十四个应用，手机中文映射当时为28项（现为31项）；正式包295个FAP／121个FAL，本地129项Python／C回归无跳过。下文第三轮的测试／包数量为历史记录，最新实际验收以 [VALIDATION.md](documentation/custom/VALIDATION.md) 首节为准。

手机能力共享详见 [第三轮](documentation/custom/COMPANION_AND_CHINESE_20260929.md)，历史实现见 [第二轮](documentation/custom/UNION_CHINESE_CONTINUATION.md) 和 [协议适配](documentation/custom/UPSTREAM_FUSION.md)。API为89.0，protobuf为0.29并保留ASCII输入扩展；iPhone GPS／网络处理端已实现。中文用户文件兼容保留7,097字形SD资源及有界缓存，实际无卡子集125字形／3,450字节；升级器已恢复英文，CJK子集为空。最新测试与产物证据见 [VALIDATION.md](documentation/custom/VALIDATION.md)。旧编译包与API89.0的应用不能混用。

## 当前实现

| 内容 | 状态与入口 |
| --- | --- |
| iPhone 中文 App | 设备、功能、资料库、任务、指南五页；蓝牙 RPC、应用启动、文件传输、离线分析、红外单次发送代码已实现。实际蓝牙流程未真机验收 |
| MIFARE Classic | “功能 → NFC 离线工作台”：两组认证样本恢复密钥、字典验证、合并去重和导出。公开答案、生成样本、取消和模拟器界面已自动验证；普通 .nfc 转储不能代替认证样本 |
| AIO 数据链路 | “功能 → 扩展板实时数据”：Lab Bridge 把 UART 输出经 BLE 转到手机，显示真实字节、丢失/截断并导出。代码和构建通过，实物链路未测；未实现未知板卡固件的专用无线驱动 |
| 原生英文界面 | 用户要求恢复英文，已按原文／审核提案恢复文案及显示名称；保留功能修复与中文用户文件兼容，没有重写全部驱动 |
| 本机新功能 | 快捷设置、床头时钟、菜单过渡；累计二十四个导入工具／应用及手机端中文说明。最近增加弹跳球、方块搬运、数独、昵称生成器，保留掷骰、记事本与时钟的输入、存档和文件保护修复，设备显示恢复英文 |
| 手机定位与网络共享 | “设备 → 手机能力共享”中分别开启，要求 BLE 就绪和 App 前台。GPS、HTTP(S)、TCP、UDP、WebSocket 请求处理已实现；系统 TLS/ATS 保持默认。实际 BLE 链路与权限流程尚未真机验收 |
| 固件功能说明 | Flipper Lab 为英文帮助，11个主题／62页；新增 Phone Remote 可打开 Apps。73张菜单及帮助源码布局预览，均不是真机截图 |
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
- CI检查恢复升级器不超过131,072字节；另核验升级包内28项指定应用和SD字库。常规包包含295个正式FAP、121个FAL，完整开发分发另含开发示例。恢复英文后本地主固件到当前无线栈前余11,816字节，已核验的云端包余11,840字节；准确提交和附件见验证记录。新增内容仍必须通过打包边界检查，不能按链接器全部`.free_flash`估算；还需检查字库缓存的运行时RAM和线程栈。
- UI 预览脚本为 `scripts/render_lab_preview.py`、`scripts/render_native_zh_preview.py`、`scripts/render_animation_zh_preview.py` 和 `scripts/render_union_zh_preview.py`。后三者需 `--output-dir`，动画和应用预览还需 Pillow 与主机 C 编译器。从源码绘制的图片不能替代刷机验收。

## 记录与分工

[需求与未完成项](documentation/custom/REQUIREMENTS.md)、[实际验证](documentation/custom/VALIDATION.md)、[中文覆盖范围](documentation/custom/NATIVE_ZH_PROGRESS.md)、[Classic 格式与限制](mobile/FlipperLab/CLASSIC_OFFLINE.zh-CN.md)、[串口桥条件](mobile/FlipperLab/SERIAL_BRIDGE.zh-CN.md)是接续依据。两份 FeatureCatalog JSON 必须逐字节相同。

用户已明确授权 AI 修改本个人仓库、测试并推送现有草稿 PR，覆盖继承的上游反 AI 贡献限制；未授权向上游投稿。最新默认仅通过 CLI 使用 `claude-fable-5-1 --effort max` 处理边界清楚的基础工作；前段按当时指定执行的 Opus 任务和本轮 Fable 任务分别记录实际返回模型、退出状态。主助手负责关键逻辑、审核和真实验收，不静默切换。App 不调用 Claude 或其他云端 AI。
