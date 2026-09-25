# 手机功能中心与 Flipper 蓝牙启动

iPhone 的“功能”页是独立的中文界面：手机展示 Flipper 功能、简短介绍和使用条件，点选后用蓝牙 RPC 的 `App.StartRequest` 要求 Flipper 打开对应应用。不会把 Flipper 的 128 × 64 屏幕镜像到手机。射频、NFC、红外、GPIO 等实际工作仍由 Flipper 的硬件及当前应用完成。

内置条目的启动名称逐一对照本仓库 `applications/**/application.fam`，涵盖红外、Sub-GHz、NFC、125 kHz RFID、iButton、GPIO、Bad USB、U2F、归档、Flipper Lab、Momentum 与部分系统设置；“设备应用列表”使用固件加载器的 `Apps` 入口。对于 SD 卡上的其他外部应用，用户可主动刷新 `/ext/apps`，手机只展示设备实际列出的 `.fap` 文件，并以设备路径启动。文件名衍生的标题不伪装成已翻译的功能说明。

固件的 `applications/services/rpc/rpc_app.c` 把 `App.StartRequest` 交给加载器；加载器找不到应用时返回错误，已有应用占用加载器时也会拒绝新启动。手机会明确显示这些情况。对于不支持 RPC 退出的普通应用，切换到下一应用前可能需要先在 Flipper 上退出当前应用。当前实现没有强制终止正在运行的应用，也不会自动输入按键来绕过应用本身的退出流程。

连接、命令状态及应用列表都需要 iPhone 17 Pro Max 与本仓库固件的 Flipper 真机验收。macOS CI 的编译和模拟器测试只能证明代码可编译、离线界面可运行；模拟器没有真实蓝牙。扩展板的驱动与供电仍取决于精确型号，手机页面不能替代硬件兼容性验证。
