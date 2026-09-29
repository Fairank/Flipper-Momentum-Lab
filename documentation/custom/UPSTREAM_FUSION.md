# Momentum / Unleashed 融合记录（2026-09-29）

本文保存上一轮 `22904e309` 的范围和结果。之后补入快捷设置、时钟、菜单动画、十个普通工具及更多中文支持，见 [第二轮实现](UNION_CHINESE_CONTINUATION.md)。以下“尚未完成”描述的是上一轮状态；最新残留项以第二轮记录和应用差异清单为准。

本轮以 Momentum 的主题包、桌面和应用体系为基础，按共同祖先比较并适配 Unleashed 更新。**这不是两个固件的完整功能并集，也不代表全部第三方应用、手机代理或外接硬件已验收。** 文件变更与模型执行记录见 [UPSTREAM_FUSION.json](UPSTREAM_FUSION.json)。

## 固定来源

| 来源 | 本轮核对的提交 |
| --- | --- |
| [Momentum dev](https://github.com/Next-Flip/Momentum-Firmware/commit/d3f89dfe2ef6b01839201598e9be1590cba80322) | `d3f89dfe2ef6b01839201598e9be1590cba80322` |
| [Unleashed dev](https://github.com/DarkFlippers/unleashed-firmware/commit/15bca58e644c8e75fcac42a1929b3d37cbea208f) | `15bca58e644c8e75fcac42a1929b3d37cbea208f` |
| 共同祖先 | `78cbcab365895e9efc5304253d7feb7e472500ec` |
| [手机通信协议](https://github.com/DarkFlippers/flipperzero-protobuf/commit/05d4dc1e11dc3d22c453e13edebf82ff5ead5bd2) | `05d4dc1e11dc3d22c453e13edebf82ff5ead5bd2`，0.29 |

这些是核对日期的固定提交；后续上游更新不会自动进入本仓库。保留原作者、许可证和源码注释。本项目由仓库所有者授权 AI 辅助修改，没有向禁止 AI 贡献的上游投稿。

## 已合入的主要内容

| 模块 | 本轮变化 | 保留与验证边界 |
| --- | --- | --- |
| NFC | 更新协议库和原生场景，合入 MIFARE Plus、Ultralight AES、共享字典及卡片解析修复；补回新场景中文 | 保留本项目手机离线分析。库或菜单存在不表示任意卡均可恢复密钥 |
| 低频 RFID / iButton | 更新协议、读写目标和原生操作场景；合入数据正确性修复 | 实卡读写尚未验收；保留 Momentum 的独有协议 |
| Sub-GHz | 协议及底层公共实现更新、新增协议菜单项、历史去重/接收时长处理、外接 CC1101 断开恢复、发送清理 | 保留 Momentum 的 32 位哈希、GPS、转发设置和外置应用结构；未新增 Wi-Fi 断链 |
| 红外 | 通用遥控器暂停后可保存有效信号为新遥控器或追加到已有遥控器 | 保留蓝光、显示器、电子标牌和自定义数据库入口；新页面中文化；红外实机未测 |
| 主菜单 | 增加网格、Macintosh、立体三种样式 | 原有九种样式编号及 DSi 默认值不变；Macintosh 开窗和立体旋转过渡动画尚未移植 |
| 加载与文件管理 | 加载视图支持文字和进度；应用启动等待视图或超时；归档首次加载有等待界面 | 保留 Momentum 的独立设置菜单、主题包卸载/恢复、ASCII 输入和中文排版 |
| 输入与数据 | 数字输入空值/范围/最小整数保护、数组比较长度修复、文本布局边界、脚本非正计时间隔拒绝 | 主机测试编译实际 C 实现；不以界面占位或重写算法模型代替实现测试 |
| 系统 / 构建 | HID 按键范围、存储/串口/红外等修复；共享库排除选项及分组源文件收集；发布日志不执行被关闭日志的参数 | 保留 Momentum USB CCID；API 版本提升为 89.0，配套应用须重建 |
| 查找设备 | 合入 Google 标签格式及广播间隔配置；修正切换类型和旧配置的间隔边界 | 没有验证 Google 服务配网和真机定位 |
| 手机协议底座 | 新增 GPS、网络代理服务和 RPC 消息；旧会话不能清理新会话，过期响应不交给新会话 | **iPhone App 尚未实现这些 GPS/互联网代理消息的处理端**；服务编译通过不等于手机代理可用 |

## 兼容处理

- `assets/protobuf` 保持干净的公开子模块；两个父仓库协议覆盖文件保留 Momentum 的 ASCII 输入扩展。73 个旧 content 字段（含 Empty / StopSession）的名称、类型和编号保持不变，新增 15 个字段使用上游 76–90 编号。
- API 89.0 是本分支的兼容边界。既有公共结构体布局发生变化，不能声称与 Momentum 87.x 或 Unleashed 88.x 的旧 FAP 二进制兼容。使用同次构建的完整升级包和应用。
- 不把两套同名的菜单插件接口或 Sub-GHz 应用装载方式同时塞入固件。相应源码按路径迁移后合并，保留 Momentum 的装载方式。
- `applications/external` 继续固定原提交，未自动更新整个第三方应用集合。原有 `.cli_gui`、`.f0_mtp` 清单因非法 appid 被构建器跳过，不能记为本轮已构建的应用。
- GPS/网络回调在递归互斥量内执行，注销会等待正在执行的回调；回调可以发送请求或注销自身，但不得等待另一个响应或阻塞等待应用线程。

## 尚未完成的功能并集

1. Unleashed 的独立快捷设置页面、菜单过渡动画及所有桌面设置差异没有逐项移植；Momentum 已有亮度、音量、蓝牙等控制，但不是布局和交互完全相同。
2. 两边外部应用子模块、时钟应用和额外资源尚未完成全部版本对照。独立 Nice O-Code、Security+ PIN 应用未纳入本轮。
3. iPhone 对新增 GPS / 网络代理的处理端未实现。AIO 1.4 的实际厂商、芯片、引脚和固件未识别；现有 UART → Flipper → BLE 接收代码不能据此称作板卡完整适配。
4. 原生和第三方界面仍有英文；新菜单和红外流程已补中文，不等于全面中文化或全面重写。
5. 没有进行刷机、实卡、射频、蓝牙配对、断连恢复或长期运行验收。没有新增针对单个/多个 Wi-Fi 的强制断链控制。

## 验证入口

```sh
python3 -m unittest discover -s scripts/tests -p 'test*.py' -v
python3 scripts/generate_lab_font.py --check
python3 scripts/generate_native_zh_font.py --check
./fbt updater_package
./fbt fap_dist
```

升级包与 `fap_dist` 必须分两次执行。固件构建使用工具链 39 / GCC 12.3.1；主机 C 测试需有编译器。设备端新增协议样本测试尚未在 Flipper 上执行。

本轮本机和 CI 的最终结果记录在 [VALIDATION.md](VALIDATION.md)，不沿用旧提交的绿色检查作为本轮结论。

## Claude 协作

早先明确指定的两个任务实际返回 `claude-opus-5-5`：数字输入实现经审核并补边界修复后采用；加载视图初稿的接口及布局不符合上游，未按原稿采用。之后按最新偏好调用 `claude-fable-5-1 --effort max`，完成差异清单、加载视图兼容修正、三个菜单样式和加载器生命周期回归。主助手审核、修复兼容问题、执行测试和构建。

一项中文文案任务被 Claude 服务拒绝，未产生采用的结果。它不计入已完成编码。实际返回模型和退出状态记录于 JSON；原始 CLI 日志、凭据和本机配置不上传。
