# Flipper 固件初步评估

项目选择已更新为 **Momentum 本地定制版**，保留 Momentum 的风格并逐项移植 Unleashed 的改进。开发目录为 [项目首页](../../ReadMe.md)，首批改动与验证记录见 [LOCAL_CHANGES.md](../../LOCAL_CHANGES.md)。以下维护状态为初次检查时的记录。

检查日期：2026-09-10。维护记录通过 GitHub 页面和 API 核对；代码观察基于本地 Xtreme 源码。本文是功能盘点和升级建议，未进行编译或真机测试。

## 选择建议

如果目标是保留 Xtreme 的功能风格并继续开发，优先考虑 **Momentum**。它的项目说明明确称其为 Xtreme 的直接延续，主题包、菜单定制、扩展应用、BadKB 等功能与原项目接近。

| 固件 | 当前核实结果 | 适合的用途 |
| --- | --- | --- |
| Xtreme | 已于 2024-11-19 归档；最终提交为停止开发通知；最近正式版是 XFW-0053_02022024 | 学习源码、研究旧功能、对照实现 |
| Momentum | 最近代码提交为 2026-08-18；最近正式版为 mntm-012，发布于 2025-12-31 UTC | 延续 Xtreme 使用体验，进行功能定制 |
| Unleashed | 最近代码提交为 2026-09-10；最近正式版为 unlshd-092，发布于 2026-08-21 UTC | 更关注协议功能、官方应用兼容性和持续维护 |

代码提交日期与正式版发布日期是两件事：Momentum 的正式版较久未发，但开发分支仍有更新。最近提交包括文件浏览器内存优化和大目录光标修复。正式版是否适合某个现有设备，还需要结合设备当前固件、应用和配件确认。

来源：[Xtreme](https://github.com/Flipper-XFW/Xtreme-Firmware)、[Momentum 项目说明](https://github.com/Next-Flip/Momentum-Firmware)、[Momentum 提交记录](https://github.com/Next-Flip/Momentum-Firmware/commits/dev/)、[Momentum mntm-012](https://github.com/Next-Flip/Momentum-Firmware/releases/tag/mntm-012)、[Unleashed 项目说明](https://github.com/DarkFlippers/unleashed-firmware)、[Unleashed 提交记录](https://github.com/DarkFlippers/unleashed-firmware/commits/dev/)、[Unleashed unlshd-092](https://github.com/DarkFlippers/unleashed-firmware/releases/tag/unlshd-092)。

## 本地源码

- 原参考检出目录：`Xtreme-Firmware`（未随本项目重复复制；源码入口见下文固定版本链接）
- 分支：`dev`
- 提交：`54619d013a120897eeade491decf4d1e95217c06`
- 下载方式：浅克隆最新源码，递归获取依赖；未下载主仓库完整历史。
- 主仓库包含 4,410 个跟踪文件；`applications` 中有 85 个应用清单文件，不含外部应用子模块。一个清单可能声明多个插件或服务，因此清单数不等于可启动应用数。
- 用户随后选择 Momentum 作为开发基础，因此停止 Xtreme 的剩余依赖下载。Xtreme 主源码已落地，但外部应用及部分子模块尚未完成下载或切换到固定版本，不能视为完整可构建检出。

## 里面有什么

它是基于 FreeRTOS/Furi 的嵌入式固件，主要代码为 C/C++，使用 fbt/SCons 构建。

| 模块 | 已看到的内容 | 固定版本入口 |
| --- | --- | --- |
| 无线与卡片 | Sub-GHz、NFC、低频 RFID、iButton、1-Wire | [主应用目录](https://github.com/Flipper-XFW/Xtreme-Firmware/tree/54619d013a120897eeade491decf4d1e95217c06/applications/main) |
| 红外与硬件接口 | 红外遥控、GPIO、外设扩展服务 | [红外应用](https://github.com/Flipper-XFW/Xtreme-Firmware/tree/54619d013a120897eeade491decf4d1e95217c06/applications/main/infrared)、[扩展服务](https://github.com/Flipper-XFW/Xtreme-Firmware/tree/54619d013a120897eeade491decf4d1e95217c06/applications/services/expansion) |
| USB 与蓝牙 | BadKB、HID、U2F、大容量存储、蓝牙服务 | [系统应用](https://github.com/Flipper-XFW/Xtreme-Firmware/tree/54619d013a120897eeade491decf4d1e95217c06/applications/system) |
| 界面与主题 | Xtreme 设置、主题包、动画、锁屏、菜单、按键及状态栏设置 | [Xtreme 设置应用](https://github.com/Flipper-XFW/Xtreme-Firmware/tree/54619d013a120897eeade491decf4d1e95217c06/applications/main/xtreme_app)、[主题与设置库](https://github.com/Flipper-XFW/Xtreme-Firmware/tree/54619d013a120897eeade491decf4d1e95217c06/lib/xtreme) |
| 文件工具 | 文件浏览、搜索、收藏、复制移动、文本和十六进制查看器 | [文件管理](https://github.com/Flipper-XFW/Xtreme-Firmware/tree/54619d013a120897eeade491decf4d1e95217c06/applications/main/archive) |
| 扩展开发 | JavaScript 运行环境及 GPIO、串口、存储、界面模块；用户应用入口 | [JavaScript 应用](https://github.com/Flipper-XFW/Xtreme-Firmware/tree/54619d013a120897eeade491decf4d1e95217c06/applications/system/js_app)、[用户应用](https://github.com/Flipper-XFW/Xtreme-Firmware/tree/54619d013a120897eeade491decf4d1e95217c06/applications_user) |
| 底层与验证 | 存储、电源、RPC、应用加载器、硬件抽象，以及协议、存储等单元测试 | [系统服务](https://github.com/Flipper-XFW/Xtreme-Firmware/tree/54619d013a120897eeade491decf4d1e95217c06/applications/services)、[测试目录](https://github.com/Flipper-XFW/Xtreme-Firmware/tree/54619d013a120897eeade491decf4d1e95217c06/applications/debug/unit_tests) |

Wi-Fi、GPS 等外设相关功能需要对应硬件支持，不能仅靠更换固件获得这些硬件能力。

## 值得升级的方向

以下是基于抽样阅读的开发候选，尚未实施。

1. **以仍在维护的固件建立开发基线。** 在 Momentum 上验证构建，再逐项对照 Xtreme 的目标功能；文件格式、设置和应用 API 需要单独核对兼容性。已有上游修复应优先复用。
2. **改进文件搜索体验。** [当前实现](https://github.com/Flipper-XFW/Xtreme-Firmware/blob/54619d013a120897eeade491decf4d1e95217c06/applications/main/archive/scenes/archive_scene_search.c#L37)每次遍历 SD 卡目录并匹配文件名，已采用后台线程并支持取消。可以增加搜索范围、文件类型过滤、结果数量限制和分页；索引是否值得做，先测大量文件时的耗时与内存。
3. **让设置保存失败可见、可恢复。** [保存函数](https://github.com/Flipper-XFW/Xtreme-Firmware/blob/54619d013a120897eeade491decf4d1e95217c06/lib/xtreme/settings.c#L166)直接写配置，逐项写入结果未向调用者反馈。可以增加错误返回、界面提示、临时文件校验与备份恢复，验证存储空间不足及写入中断的行为。
4. **增加中文界面和简洁的学习说明。** 当前菜单场景可见硬编码英文；[locale 服务](https://github.com/Flipper-XFW/Xtreme-Firmware/blob/54619d013a120897eeade491decf4d1e95217c06/applications/services/locale/locale.c)主要处理日期、时间、计量单位。完整中文化需要文本资源、字库和排版一起设计，建议先做一个独立应用验证显示和内存成本。
5. **开发一个实用的小应用。** 可从个人红外遥控整理、串口日志记录、GPIO 状态查看等切入，优先使用 `applications_user` 或现有 JavaScript 接口，缩小首次改动范围。
6. **补充基础行为回归。** 一个可直接从源码推导的问题是：[12 小时时间格式](https://github.com/Flipper-XFW/Xtreme-Firmware/blob/54619d013a120897eeade491decf4d1e95217c06/applications/services/locale/locale.c#L45)仅在小时大于 12 时设置 PM，因此正午 12:xx 会显示 AM。可以作为小修复练习，并检查 00、11、12、13、23 点边界；尚未进行真机复现。

建议开发顺序：选定基线 → 原样编译 → 一个小功能或明确缺陷 → 真机验证 → 扩大改动。本初步评估仅记录当时源码与维护状态；后续实际进展见 [LOCAL_CHANGES.md](../../LOCAL_CHANGES.md) 和 [HANDOFF.md](../../HANDOFF.md)。
