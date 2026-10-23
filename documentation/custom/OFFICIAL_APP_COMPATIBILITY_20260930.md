# 融合固件与官方 Flipper 手机 App 的兼容范围

更新日期：2026-09-30。当前优先适配官方 Flipper App；此前的自建中文 iPhone App 和界面改动已保存，暂停继续设计。本机保留英文界面及功能升级。本文区分源码兼容路径、官方手机界面的限制和尚未完成的设备验收，不将接口存在写成真机可用。

官方 iOS 参考固定为 dev 源码快照 [`46074e4c92895ab566a3ef5c599f066b1d507063`](https://github.com/flipperdevices/Flipper-iOS-App/tree/46074e4c92895ab566a3ef5c599f066b1d507063)，MIT 许可；该快照不等于当前 App Store 安装版本，后者需在实物验收时记录。

## 标准连接与控制路径

融合固件保留标准 BLE 串口服务、protobuf RPC 0.29、设备信息属性、文件管理、`App.Start`、屏幕流和虚拟按键。当前硬件目标为 f7，固件 API 为 89.0；API 版本与 RPC 协议版本是两项不同的兼容条件。

固定官方源码接受 protobuf 0.6 起、1.0 以下的版本；应用目录读取 API 的门槛为 0.17，应用打开入口的门槛为 0.18。当前 0.29 满足这些源码门槛。官方读取 `devinfo.hardware.target` 及 `devinfo.firmware.api`，用实际目标和 API 请求应用构建，不能伪报官方固件身份或更低 API 来取得不匹配的文件。官方服务是否提供 f7／89.0 的对应构建尚未完成实际验证。

参考：[连接与版本检查](https://github.com/flipperdevices/Flipper-iOS-App/blob/46074e4c92895ab566a3ef5c599f066b1d507063/Flipper/Packages/Core/Sources/Model/Device.swift)、[应用版本门槛、设备属性及构建请求](https://github.com/flipperdevices/Flipper-iOS-App/blob/46074e4c92895ab566a3ef5c599f066b1d507063/Flipper/Packages/Core/Sources/Applications/Applications.swift)、[蓝牙实现](https://github.com/flipperdevices/Flipper-iOS-App/blob/46074e4c92895ab566a3ef5c599f066b1d507063/Flipper/Packages/Peripheral/Sources/Bluetooth/Platform/FlipperPeripheral.swift)。

普通 GUI FAP 使用 `App.Start` 的文件路径及空参数启动，在设备屏幕绘制界面，并通过 GUI 虚拟按键接受操作。官方 App 在目录应用启动成功后打开屏幕遥控（Remote Control）。这条路径无需每个普通 GUI FAP 实现专用的应用 RPC 按钮接口；`args="RPC"` 的专用模式则仍取决于各应用自身实现，不能把两者当成同一个接口。

参考：[官方启动及进入屏幕遥控的行为](https://github.com/flipperdevices/Flipper-iOS-App/blob/46074e4c92895ab566a3ef5c599f066b1d507063/Flipper/iOS/UI/Apps/Components/AppRow.swift)。手机是否切换到屏幕遥控由官方 App 决定，固件不能使其保留此前自建 App 的独立中文功能页。

## “已安装”列表并非全部本地 FAP

官方 App 不递归扫描 `/ext/apps` 以建立已安装列表。固定实现读取 `/ext/apps_manifests` 中非隐藏的 `.fim` 安装清单，解析后确认清单所指文件存在，并筛选清单的 `DevCatalog` 是否与手机目录设置一致。

还有两项限制：

- 清单路径必须拆成四段，例如 `/ext/apps/Tools/clock.fap`；`/ext/apps/GPIO/Sensors/example.fap` 这类多层路径会被该解析器过滤。打开动作又按类别名称和应用 alias 重建路径，因此清单、类别及真实文件位置必须一致。
- 联网时会按应用 UID 查询官方目录。查询不到的应用被标为 `building`，对应打开／更新按钮不可用；离线状态检查则只比较清单与固件的 API 主版本。给私有应用任意填写 UID 或生成 `.fim`，不能保证它在联网后的官方目录里可打开或更新。已加载条目的删除路径另由清单决定，这仍不是任意 FAP 文件浏览器。

本地已核验的 `85e08bc3` 英文恢复更新包含 295 个 FAP，其中 232 个位于单层类别、63 个位于多层目录；该包没有 `.fim` 或 `apps_manifests` 目录项。这些计数仅说明该固定包的资源与官方发现机制，不是官方 App 已验收的应用数量。

参考：[安装清单发现、校验及路径](https://github.com/flipperdevices/Flipper-iOS-App/blob/46074e4c92895ab566a3ef5c599f066b1d507063/Flipper/Packages/Core/Sources/Applications/FlipperApps.swift)、[清单格式与四段路径解析](https://github.com/flipperdevices/Flipper-iOS-App/blob/46074e4c92895ab566a3ef5c599f066b1d507063/Flipper/Packages/Core/Sources/Applications/Applications%2BManifest.swift)、[线上 UID 检查与打开路径](https://github.com/flipperdevices/Flipper-iOS-App/blob/46074e4c92895ab566a3ef5c599f066b1d507063/Flipper/Packages/Core/Sources/Applications/Applications.swift)。

全部融合功能不会自动成为官方手机目录里的独立按钮。真实官方目录应用的清单与路径可以逐项核对；私有及多层 FAP 的通用操作入口是 **官方 Remote Control → 设备上的 Apps 或 Archive → 找到应用文件并打开**。这是屏幕遥控设备现有 GUI 的路径，需要 SD 文件、资源、API、应用及硬件均满足要求；并不等于官方手机目录已支持这些应用。

## 使用入口

1. 将本融合固件及同一次构建的 SD 资源安装到 Flipper；打开设备蓝牙，在官方 App 中配对。不要混用不同 API 的 FAP。
2. 官方 App 打开 Remote Control／屏幕遥控，用手机箭头、OK 和 Back 操作设备菜单。
3. 在设备菜单打开 Flipper Lab，选 Phone Remote；详情页按 OK 进入 Apps 浏览器，再选择 SD 分类及应用。也可从设备菜单直接进入 Apps，或使用 Archive 找到文件。
4. 普通 GUI 应用继续接受相同的屏幕与按键操作。没有专用 RPC 退出接口的应用，用屏幕里的 Back 退出；专用 RPC 模式仍需该应用实现相应接口。

官方 App 的界面语言依其版本和语言支持；遥控画面显示设备的英文界面。本项目保存的中文独立详情不会自动出现在官方 App 中。官方固件更新入口可能安装另一套固件；更新本融合版请使用本仓库对应构建的更新包。

## 功能和硬件条件

| 情况 | 兼容边界 |
| --- | --- |
| 普通 GUI 应用 | 可按上述标准启动／屏幕遥控路径适配；依赖资源、加载器和应用输入行为，仍需逐项实测。 |
| GPIO 与外接板 | 手机不提供电气接口或扩展板驱动。板卡型号、芯片、固件、接线及供电需要确认；AIO Board 1.4 的未知卖家版本不能按名称宣布兼容。 |
| USB 应用 | Flipper 与目标主机的 USB 连接、USB 模式及应用条件仍需满足。手机蓝牙连接不能替代这条 USB 连接。 |
| 切换蓝牙 profile 的应用 | 使用或更换 HID 等 profile 的应用可能影响当前 BLE 串口连接及遥控；不能保证所有蓝牙应用与官方手机连接同时工作。 |
| 手机 GPS／网络共享、NFC 离线工作台 | 这些处理端属于已保存的自建手机 App。仅修改固件不能让官方 App 自动提供手机定位、网络代理、离线分析或新增页面；官方 App 未实现的自定义协议没有对应处理端。 |
| Lab Bridge 串口数据 | 固件已有通用串口桥及自建手机接收端代码；官方 App 不会因此自动出现专用的实时数据页面，也没有未知 AIO 无线固件的适配证明。 |

## 本轮固件改动与本地验证

最终本地工作树的 **152项主机／实际C回归全部通过**（92.131秒、无跳过），`updater_package`、独立 `fap_dist` 和 `lint_all` 通过。下面的改动已构建验证；蓝牙与屏幕行为仍待实物验收。

- `App.Start` 改用内部 `loader_start_from_rpc` 路径，要求 FAP API 匹配。API 不兼容时在进入阻塞弹窗前返回失败，避免 RPC 启动正在等待、屏幕遥控按键也需同一 RPC 调度而无法完成弹窗交互。这个内部入口不作为新公共 FAP API 导出；普通本机加载路径保留原有 `Cancel／Continue` 提示与行为。
- GUI 遥控在索引按键状态数组前拒绝负数及越界的按键／事件枚举；输入序列计数限制在 30 位有效范围，回绕时跳过代表未按下的零值。合法按键操作保持既有语义。
- Flipper Lab 增加英文 Phone Remote 主题（11主题／62页），确认后打开设备 Apps 浏览器。浏览器不占用普通应用线程槽，因此延迟启动成功后立即推进队列／发布结束通知，避免从 Apps 打开指南再返回 Apps 时原浏览器一直等待；仅真正运行的应用保存启动路径。

新增23项测试包括7项真实遥控处理函数、6项真实外部加载函数、3项真实启动入口与消息结构、6项真实延迟队列／浏览器通知，以及1项指南启动名称校验。负枚举测试覆盖合法／非法组合；序号回绕用例在修复前失败。队列测试使用同一测试编译旧 `c755bfa5` 函数后复现缺少通知、浏览器未唤醒的失败；修复后验证清理完成才通知，以及真实应用退出前不提前通知。入口测试通过实际消息和结果指针验证普通入口 `false`、RPC入口 `true` 和参数／状态保留。

这些测试编译生产函数并替代平台依赖，未覆盖整条 RPC 解码、实际 loader 服务线程和 GUI／蓝牙端到端链路；不能把主机通过写成每个设备功能都已可用。SDK公开头文件和 `api_symbols.csv` 未改变，内部入口不改变 API89。

本地包 `flipper-z-f7-update-mntm-codex-iphone-zh-architecture-c755bfa5.tgz` 为13,008,016字节，SHA-256 `d08e87d50782e81520d251e8d134ba3d0057d496ddd124a3eab9d1e488f81caf`；它是 **c755基础上的本轮未提交工作树构建**，不是该旧提交的干净包。DFU地址／CRC、295 FAP／121 FAL、28项指定应用、API89及资源核验通过。主固件869,000字节，距无线栈 `0x080D7000` 前余11,640字节；升级器120,245字节，低于131,072字节上限。73张帮助布局渲染无警告，仅为源码预览。

代码 **`52f236fda19990e4587c4c82ea28cd2a63d40e46`** 已上传现有草稿PR。云端 [Lab validation](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/36712917909) 全部通过：152项主机回归（16.926秒、无跳过）、字库与布局检查、自建iPhone的196项Swift核心（13.428秒）、10项UI（468.180秒、零失败）、Mac准备模式及无签名模拟器构建；[完整固件](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/36712917791) 与 [Lint](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/36712917869) 通过。手机环境为Xcode26.6／Swift6.3.3／iPhone17ProMax／iOS26.5模拟器，这些并非官方App或真实BLE测试。后续验收文档提交不改变该代码。

[干净CI固件附件11095483234](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/36712917791/artifacts/11095483234) 已下载核验：ZIP13,021,894字节，SHA-256 `79d17087855e04ca81cfefc40b351f239153d53fdd3c7c021ac628d057ffcdfd`；内部 `flipper-z-f7-update-mntm-HEAD-ee43b2c2.tgz` 为13,006,148字节，SHA-256 `7cab7ff698a184528c67df0ae92607248ff12eb09a9e22c03a7c2c6274d43d24`，PR合并检出 `ee43b2c229ee33ba5d76f44aef32736c495c627b`。主固件868,976字节、保留区前余11,664字节、升级器120,217字节；DFU地址／CRC、295FAP／121FAL、28项指定应用、API89、SD资源及两份独立伴侣FAP与包内一致性通过。附件保留至2026-10-14；源码和构建入口长期保留。

该修改不会解除不匹配应用的 ABI 或缺失符号问题，也不会把未兼容的 FAP 宣布为可用。JSON证据见 [本轮核验摘要](OFFICIAL_APP_COMPATIBILITY_20260930.json)。

## 验收状态与后续检查

标准 BLE／RPC 兼容结论来自固定源码核对。官方 App 与本固件之间的配对、文件传输、应用启动、屏幕遥控及断连恢复尚未完成真机验收；iPhone 签名安装、AIO 联调和逐应用硬件验收也未完成。Momentum／Unleashed 全部功能的完整并集仍未完成。

本轮需记录官方 App 的实际版本与语言、Flipper 固件提交及 API，然后检查标准握手／属性、SD 文件管理、正常 GUI 应用的目录启动与虚拟按键、私有或多层应用的设备端导航，以及不兼容 FAP 的失败返回。GPIO、USB 和切换蓝牙 profile 的应用应单独验收，不能用一个普通应用通过代替全部功能通过。

已有自动检查及历史包证据见 [VALIDATION.md](VALIDATION.md)；此前自建手机 App 的界面记录保留在 [OFFICIAL_APP_REFINEMENT_20260930.md](OFFICIAL_APP_REFINEMENT_20260930.md)，不作为本轮官方 App 真机兼容证明。
