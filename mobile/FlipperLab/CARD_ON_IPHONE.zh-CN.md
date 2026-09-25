# 门禁卡记录与 iPhone NFC

Flipper 从持有人获准使用的卡读取并保存记录后，本 App 可以经蓝牙导入相关 `.nfc` 或 `.rfid` 文件，在手机资料库查看、分析、备份与导出。**保存文件不等于把 iPhone 变成这张门禁卡。** 本 App 不提供“复制到 iPhone 后刷门”的按钮，也不把原始卡数据写进 Apple Wallet。

- **125 kHz 低频 RFID**：Flipper 可以处理此类卡，但 iPhone 的 NFC 不是这套低频硬件，无法直接用该记录刷相应读卡器。
- **13.56 MHz NFC**：能读到或解析 `.nfc` 文件，也不代表 iPhone 能模拟该卡的身份、UID、通信协议和认证。苹果的普通 Core NFC 接口用于读写兼容标签；卡模拟属于另外的受授权能力，有地区、用途和发行方条件。
- **官方手机门禁凭证**：如果门禁运营方提供 Apple Wallet 员工证、住宅钥匙，或其他受支持的正式数字凭证，应由发行方按其流程开通。Flipper 的记录不能代替该开通过程。

App 的记录详情会按 NFC／低频 RFID 显示相应说明。当前没有门禁发行方合作、Apple 卡模拟授权或实物读卡器验收；因此不会声称某张导入卡已可在 iPhone 上使用。

参考：[Apple Core NFC](https://developer.apple.com/documentation/corenfc)、[Apple NFC & SE Platform](https://developer.apple.com/support/nfc-se-platform)、[Apple Wallet 员工证](https://support.apple.com/en-ca/119901)、[Flipper Zero 硬件规格](https://docs.flipper.net/zero/development/hardware/tech-specs)。
