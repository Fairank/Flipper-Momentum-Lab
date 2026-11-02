# 手机能力共享使用指南：定位与网络

> **状态：实现已提交，待真机验收。** 本文按当前源码整理并由主助手核对，写于 2026-09-29。自动测试、构建和升级包的实际结果见 [验证记录](VALIDATION.md)；文中的设备行为仍需真机确认。没有连接 iPhone、Flipper 或扩展板进行验收，也未达到完整并集或中文全覆盖。

## 1. 这是什么

Flipper Lab（iPhone App）与 Flipper 保持蓝牙连接期间，可以按设备应用的请求提供两项手机能力：**定位**和**网络访问**。两项各有一个开关，互相独立，默认关闭。

- 工作方式：设备应用调用固件的 GPS / Network 服务 → 请求经蓝牙 RPC 发到手机 → 手机定位或联网 → 结果经蓝牙发回设备。
- **这是应用级的请求转发，不是系统级网络共享（个人热点），也不是透明 VPN。** Flipper 不会获得网络接口；没有调用这些服务的设备应用不会因此联网。
- 打开开关本身不会定位或联网，只有设备应用发出请求后手机才执行。
- 联网使用 iPhone 当前的 Wi-Fi 或蜂窝网络，可能消耗流量。

本文涉及两个设备应用：“手机 GPS”（`gps_rpc`）和“手机联网测试”（`example_network`）。

## 2. 准备条件

| 项目 | 要求 |
| --- | --- |
| Mac | 完整的 Xcode、XcodeGen，以及自己的 Apple ID |
| iPhone | iOS 17.0 或更新（工程的最低版本）。模拟器没有蓝牙，必须用真机 |
| Flipper 固件 | 使用本项目本轮固件（API 89.0 / RPC 0.29）。App 的基础握手只检查 RPC 0.25 起的兼容版本；握手成功不表示旧固件含新增 GPS/网络服务 |
| 设备应用 | SD 卡上存在 `/ext/apps/Tools/gps_rpc.fap` 和/或 `/ext/apps/Tools/example_network.fap` |

**App 不会安装这两个 `.fap`。** 本轮固件升级包已检查包含这两个文件及中文资源，安装入口与附件见 [验证记录](VALIDATION.md)。这不表示它们已写入你的 SD 卡；只更新固件而未安装对应资源时，仍需检查卡上的实际文件。文件不存在时，手机列表里不会出现对应条目。

## 3. 在 Mac 上用普通 Apple ID 安装 App

仓库只有源码，没有 IPA、TestFlight 或 App Store 版本。完整步骤与排错见 [Flipper Lab 说明](../../mobile/FlipperLab/README.zh-CN.md)，摘要如下：

1. 在 Mac 上安装完整的 Xcode 并打开一次；安装 Homebrew 后执行 `brew install xcodegen`。
2. 取得分支 `codex/iphone-zh-architecture` 的源码，在仓库根目录执行 `sh mobile/FlipperLab/prepare-mac.sh`，生成并打开 `FlipperLab.xcodeproj`。
3. Xcode → **Settings… → Accounts**，登录自己的 Apple ID。普通免费账号显示为 “Personal Team”。
4. 用数据线连接 iPhone 并信任这台电脑；在 iPhone **设置 → 隐私与安全性 → 开发者模式** 中开启，按提示重启。
5. 选中工程 `FlipperLab` → TARGETS `FlipperLab` → **Signing & Capabilities**：保持 **Automatically manage signing** 勾选，在 **Team** 中选择自己的团队。Bundle Identifier 无法注册时，改成自己的唯一标识。
6. 运行目标选择自己的 iPhone，按 ⌘R。提示“不受信任的开发者”时，到 **设置 → 通用 → VPN与设备管理** 信任自己的证书。

普通 Apple ID 的 Personal Team 描述文件在签发 7 天后过期，需要从 Xcode 重新构建安装；见 [Apple 的 Personal Team 说明](https://developer.apple.com/help/account/basics/about-your-developer-account)。`prepare-mac.sh --prepare-only` 已在 macOS CI 运行，个人账号签名安装仍未在用户实机执行，第一次请记录实际输出和错误。

## 4. 配对并连接 Flipper

1. 在 Flipper 的 **设置 → 蓝牙** 中打开蓝牙（旧固件显示 Settings → Bluetooth）。先断开其他正在连接这台 Flipper 的 App。
2. 打开 Flipper Lab。首次启动会请求蓝牙权限；拒绝后“设备”页显示“蓝牙不可用”，可点“打开 iPhone 设置”修改。
3. 在“设备”页点“搜索附近的 Flipper”（每次最长 15 秒），在“附近设备”中点选自己的 Flipper。
4. 首次配对时，在 iPhone 弹窗中输入 Flipper 屏幕上的 6 位配对码；45 秒内未完成会自动断开。
5. 等待状态经过“正在配对与连接”“正在准备通信”“正在检查设备”，变为“**设备已就绪**”。

## 5. 打开“手机能力共享”并开启开关

1. 在“设备”页向下找到“**手机能力共享**”一行并点开。该行下方的说明是“连接后，可分别开启手机定位与网络共享。”
2. 页面标题为“手机能力共享”，分为“定位”“网络”“文件与兼容性”三组。
3. 按需要打开“**共享手机定位**”或“**共享手机网络**”。每个开关下方有一行状态文字。

开关规则：

- **默认关闭**：每次连接到达“设备已就绪”时，两个开关都被重置为关闭。
- **需要蓝牙就绪**：未连接时开关不可操作，页面提示“先在“设备”页连接 Flipper，再开启需要的能力。”
- **仅限前台**：App 进入后台（例如回到主屏幕或切到其他 App）时，两项共享立即关闭。
- **断开即停**：蓝牙断开、连接出错或手动点“断开连接”时，两项共享关闭。
- **不会自动恢复**：回到前台或重新连接后，需要手动再次打开。
- 关闭开关会取消进行中的请求和连接，尚未开始发送的相应回复被丢弃。

## 6. 系统权限

| 权限 | 何时出现 | 拒绝后的预期表现 |
| --- | --- | --- |
| 蓝牙 | App 首次启动 | “设备”页显示“蓝牙不可用” |
| 定位（使用 App 期间） | 第一次打开“共享手机定位”且尚未选择过权限时，状态行显示“请允许在使用 App 时访问位置” | 状态行显示“定位权限未开放，可在 iPhone 设置中修改”。开关可以保持打开，但设备请求只会得到“无权限” |
| 本地网络 | 设备应用请求访问局域网地址时，可能由系统询问 | 待真机验收 |

App 只申请“使用 App 期间”的定位权限，不申请“始终”；Info.plist 没有声明任何后台模式。iPhone 系统定位服务关闭时，状态行显示“iPhone 系统定位服务已关闭”。

## 7. 启动设备应用

建议先打开需要的共享开关，再启动应用。

| 手机条目与设备应用名称 | 设备路径 |
| --- | --- |
| 手机 GPS | `/ext/apps/Tools/gps_rpc.fap` |
| 手机联网测试 | `/ext/apps/Tools/example_network.fap` |

**从手机启动**

1. 进入“功能”页，在“设备已安装应用”中点“刷新设备应用”。列表读取自设备 SD 卡的 `/ext/apps`。
2. 在“设备应用 · 工具”分组中找到上表的条目。只有 SD 卡上确实存在该文件时，条目才会出现。
3. 点选条目。成功时任务结果为“Flipper 已接受启动请求。后续交互在设备上继续。”

| 提示 | 处理 |
| --- | --- |
| 设备 SD 卡上尚未找到其他已安装应用。 | SD 卡上没有读到 `.fap`，检查 SD 卡和文件 |
| 请先刷新设备应用列表，再选择设备上确实安装的应用。 | 重新点“刷新设备应用” |
| 设备未安装这个应用，或当前固件不支持直接打开。 | 确认文件存在、固件为本项目固件 |
| Flipper 无法启动该应用，请检查 SD 卡、应用版本和设备提示。 | 确认 `.fap` 与固件匹配 |
| Flipper 正忙，请先退出设备上的当前应用。 | 在 Flipper 上退出当前应用后重试 |

**在 Flipper 上启动**

在 Flipper 的应用列表（Apps）中进入 Tools 分类，打开“手机 GPS”或“手机联网测试”。名称取自两个应用的 `application.fam`；设备上的实际显示待真机验收。

## 8. 手机 GPS（`gps_rpc`）

- 应用每秒检查一次，向手机请求每秒 4 次的定位流。手机按 iPhone 定位服务的实际速度发送，且不超过请求的频率；设备可请求的范围是每秒 1–10 次。
- 屏幕显示纬度、经度、航向、速度（m/s）、海拔（m）、卫星、精度（m）。
- **iPhone 不提供卫星数量。** 手机固定发送 0 表示“未知”，应用在“卫星”一栏显示 `--`。请不要把 0 或 `--` 当作真实的卫星数。速度或航向不可用时同样以 0 发送，设备无法区分“真实为 0”与“没有数据”。
- 确定键切换屏幕背光，返回键退出。每收到一次有效定位闪绿灯；定位流请求发不出去时闪红灯。

| 设备屏幕 | 含义（按源码） |
| --- | --- |
| 未连接 USB/BLE | 尚未收到手机的任何回复：没有 RPC 连接、刚启动，或超过 5 秒没有收到数据 |
| 定位服务已关闭 | 手机未打开“共享手机定位”，或 iPhone 系统定位服务关闭 |
| 定位权限被拒绝 | 手机尚未授权或已拒绝定位权限 |
| 定位出错 | 手机定位失败，或结果无法使用 |
| GPS 不可用 | 手机回复“不支持” |
| 等待数据... | 状态正常但还没有定位数据 |

**新鲜度与速率**

- 手机只发送时间戳在最近 15 秒内、且不早于本次请求前 5 秒的定位；坐标无效或精度为负的结果被丢弃。
- 蓝牙较慢时只保留最新一条定位，不补发旧位置。
- 手机暂时拿不到有效定位时不会发送任何数据。应用超过 5 秒没有收到数据，会停止当前定位流、回到“未连接 USB/BLE”，并在下一次检查时重新请求。**因此看到“未连接 USB/BLE”不一定表示蓝牙已断开。**
- 其他设备应用可以使用单次定位请求：30 秒内没有有效定位时，手机回复“未知错误”，状态行显示“暂时无法取得有效位置”。`gps_rpc` 只使用定位流。

## 9. 手机联网测试（`example_network`）

- 启动后显示“手机联网测试”、`https://example.com/` 和“按确定键开始”。**启动本身不会联网。**
- **短按确定键**后，应用才向手机发出一次 HTTPS GET `https://example.com/`（超时 30 秒），并要求把响应正文保存到该应用自己的数据目录。源码写的是 `APP_DATA_PATH("networktest_response.txt")`，按固件的路径解析规则对应 `/ext/apps_data/example_network/networktest_response.txt`。
- 手机完成请求后，经蓝牙把文件写入 SD 卡并读回校验，再向设备回复结果。
- 请求进行中按返回键退出，应用会向手机发送关闭请求，手机取消该请求。

| 设备屏幕 | 含义（按源码） |
| --- | --- |
| 按确定键开始 | 等待操作 |
| 正在请求并写入 SD 卡 | 请求已发给手机 |
| 手机联网请求已完成，并显示 HTTP 状态码和“N 字节 已存卡” | 手机回复成功 |
| 失败，按确定重试，并显示“错误码: N” | 手机回复失败，或 180 秒没有收到回复（此时错误码为 2） |
| 请连接手机并开启共享 | 请求发不出去：当前没有 RPC 连接 |

蓝牙已连接但没有打开“共享手机网络”时，手机回复错误码 7，设备显示的是“失败，按确定重试”，而不是“请连接手机并开启共享”。

同一目录中还有 ping、WebSocket 等示例（分类为 Examples，界面为英文），不在本文范围内，手机端也没有为它们提供中文条目。其中 WebSocket 示例在启动时就会发起连接，与“手机联网测试”按键后才请求的行为不同。

## 10. 网络共享的范围与限制

| 方式 | 说明 |
| --- | --- |
| HTTPS / HTTP | GET、POST、PUT、PATCH、DELETE、HEAD；GET 和 HEAD 不能带正文 |
| WebSocket（`wss` / `ws`） | 文本或二进制消息 |
| TCP | 不带 TLS 的原始连接 |
| UDP | 不带 DTLS 的数据报 |

**大小与并发**

- 同时最多 4 个连接（TCP、UDP、WebSocket 合计）和 2 个网页请求。
- 每次发送或接收的数据块最多 512 字节。超过 512 字节的 UDP 数据报被丢弃；超过的 WebSocket 消息会使该连接以错误关闭。
- 单个网页请求的正文、响应或文件最多 2 MB（源码为 2 × 1024 × 1024 字节），超过即中止。
- 网址最长 2048 字节，主机名最长 255 字节，请求头合计最多 8192 字节。
- 重定向最多 5 次，每一跳都重新检查网址；跳到其他站点后不再携带 `Authorization`。
- 超时默认 30 秒，设备指定的值被限制在 1–120 秒。
- 不保存 Cookie、缓存和凭据。`Host`、`Cookie`、`Content-Length` 等请求头不允许设备指定；网址不能带用户名、密码或 `#` 片段。
- 蓝牙较慢时，手机会暂停读取网络数据，等待蓝牙发送；等待超过 45 秒则关闭该连接，状态行显示“蓝牙数据传输未完成，连接已关闭”。
- 手机端不会自动重试网络连接。

**TLS 与 iOS 连接保护（ATS）**

- HTTPS 和 `wss` 使用 iOS 系统的证书校验。App 没有自定义信任，也不提供客户端证书或其他凭据；服务器提出的其他身份验证要求一律拒绝。证书不受信任时请求失败，错误码 13。
- **App 的 Info.plist 没有任何 ATS 例外，也没有全局放开。** iOS 默认的连接保护生效，`http://` 和 `ws://` 请求可能被系统拒绝，此时同样归为错误码 13。是否放行以系统为准，尚未经真机验证。
- TCP 和 UDP 是原始连接，本身不加密。

打开网络共享后，页面显示“活动连接”“收到数据”“发出数据”和“最近服务器”。

## 11. 文件路径限制

设备应用请求保存响应或上传文件时，手机只读写 SD 卡 `apps_data` 下的应用目录：

- 路径必须是 `/ext/apps_data/<应用目录>/<文件名>` 或其下更深的层级。
- 总长不超过 240 字节；不允许 `.`、`..`、空路径段、反斜杠和控制字符。
- 不满足时手机不做任何读写，向设备回复错误码 15。
- 写入时自动创建缺少的目录，写完后读回比对，不一致视为失败。
- 取消或断开时可能留下没写完的文件，需要重新下载。
- 文件传输与 App 的其他设备操作共用同一条蓝牙通道；其他操作 45 秒内没有结束时，文件传输失败。

## 12. 状态与错误处理

**手机状态行**

| 分组 | 状态文字 | 含义 |
| --- | --- | --- |
| 定位 | 定位共享已关闭 | 开关关闭 |
| 定位 | 等待定位权限选择 | 系统权限询问尚未回答 |
| 定位 | 定位共享已就绪，等待设备请求 | 已授权，设备还没有请求 |
| 定位 | 正在共享定位，更新速度取决于手机定位服务 | 定位流已开始 |
| 定位 | 正在共享定位 · 精度约 N 米 | 刚发送了一次定位 |
| 定位 | 正在等待有效定位 | 系统暂时没有定位结果 |
| 定位 | 定位服务暂不可用 | 定位失败，当前请求已停止 |
| 网络 | 网络共享已关闭 | 开关关闭 |
| 网络 | 网络共享已就绪，等待设备请求 | 开关打开，设备还没有请求 |
| 网络 | 共享中 · 连接已建立 | TCP、UDP 或 WebSocket 已打开 |
| 网络 | 共享中 · 请求已完成 | 一次请求已回复设备 |

**设备端错误码**

| 错误码 | 含义（手机端说明文字） |
| --- | --- |
| 1 | 无法解析服务器地址 |
| 2 | 网络请求超时 |
| 3 | 服务器拒绝连接 |
| 4、5 | 无法连接网络或服务器 |
| 6、7 | 连接不可用或标识重复；未打开“共享手机网络”时回复 7 |
| 8 | 网络发送失败 |
| 9 | 网络接收失败 |
| 10 | 连接数或数据大小超过限制 |
| 11 | 暂不支持此网络协议，也包括不允许的请求头、GET 或 HEAD 带正文 |
| 12 | 请求未完成，请重试 |
| 13 | 服务器安全连接验证失败：证书问题，或被 iOS 连接保护拒绝 |
| 14 | 服务器地址无效 |
| 15 | SD 卡文件传输失败：路径不允许、读写失败或校验失败 |

- 请求执行中出现的失败，会同时回复设备并更新手机的网络状态行。共享未打开（7）、标识重复（6）和文件错误（15）只回复设备，状态行不变。
- 设备请求不符合协议，或未完成的请求堆积过多（网络操作已有 16 个、定位请求已有 4 个时再来新请求），App 会断开蓝牙连接，“设备”页显示“连接出错”。重新连接后两个开关回到关闭。

## 13. 尚未验证与证据不足

**尚未验证**

- **真实蓝牙链路**：配对、握手、共享请求与回复的往返，以及蓝牙较慢时的排队与超时。
- **iPhone 定位流程**：权限弹窗、各种授权状态、室内外取得定位的时间、关闭“精确位置”时的表现，以及静止时定位更新间隔是否会超过设备端的 5 秒超时。
- **Flipper 真机与扩展板**：两个应用在真实 Flipper 上的启动、中文显示和 SD 卡写入均未验证。本功能不涉及扩展板，也没有在任何板卡上验证。
- **真实网络**：对真实服务器的 TLS 握手、ATS 对 `http://` 和 `ws://` 的处理、本地网络权限。源码中的 HTTP 测试使用进程内桩，TCP 和 UDP 测试只连接本机回环。
- **WebSocket 握手与收发**：源码中的测试只覆盖请求解析、网址与请求头检查、连接数上限，没有与任何服务器完成握手的测试。
- **后台与断开**：进入后台、锁屏、断开蓝牙时开关是否按预期关闭。

**已检查与仍需确认**

- 已直接核验本轮升级包包含两个 `.fap`；用户设备是否安装仍需查看 SD 卡。
- Flipper 应用列表中中文名称的实际显示仍待真机确认。
- 已运行协议编解码、网络规则、路径校验、发送队列和应用条目测试，并构建 iPhone App。具体提交、测试数量及模拟器 UI 结果以 [验证记录](VALIDATION.md) 为准；它们不替代实物验收。

## 14. 真机验收清单（待真机验收）

以下每一项都必须在真机上执行，模拟器和源码检查不能代替。全部项目当前状态均为**待真机验收**。

| 序号 | 验收项 | 所需设备 | 状态 |
| --- | --- | --- | --- |
| 1 | 记录 iPhone 型号、iOS 版本、Xcode 版本、Flipper 固件版本 | Mac、iPhone、Flipper | 待真机验收 |
| 2 | 用普通 Apple ID 签名安装并启动 App | Mac、iPhone | 待真机验收 |
| 3 | 配对并到达“设备已就绪” | iPhone、Flipper | 待真机验收 |
| 4 | 未连接时两个开关不可操作；连接后两个开关默认关闭 | iPhone、Flipper | 待真机验收 |
| 5 | 首次打开“共享手机定位”出现权限询问；允许与拒绝两种情况下的状态文字 | iPhone、Flipper | 待真机验收 |
| 6 | 从手机“功能”页刷新并启动“手机 GPS”；在 Flipper 上直接启动 | iPhone、Flipper（SD 卡含 `gps_rpc.fap`） | 待真机验收 |
| 7 | 室外取得定位：经纬度和精度合理，“卫星”显示 `--` | iPhone、Flipper | 待真机验收 |
| 8 | 关闭定位开关、关闭系统定位、静止 5 秒以上时设备屏幕的变化 | iPhone、Flipper | 待真机验收 |
| 9 | 启动“手机联网测试”后不按键：手机不出现“最近服务器”，收发数据为 0 | iPhone、Flipper（SD 卡含 `example_network.fap`） | 待真机验收 |
| 10 | 打开“共享手机网络”后短按确定：设备显示完成、HTTP 状态码和字节数 | iPhone、Flipper | 待真机验收 |
| 11 | SD 卡上 `/ext/apps_data/example_network/networktest_response.txt` 存在，大小与屏幕字节数一致 | iPhone、Flipper | 待真机验收 |
| 12 | 未打开网络共享时短按确定：设备显示失败和错误码 | iPhone、Flipper | 待真机验收 |
| 13 | 请求进行中切到后台或断开蓝牙：开关关闭，回到前台或重连后不自动恢复 | iPhone、Flipper | 待真机验收 |
| 14 | 锁屏、下拉通知中心、出现系统弹窗时的行为（源码只在后台状态关闭共享） | iPhone、Flipper | 待真机验收 |

验收时请记录实际屏幕文字、错误码和时间，不要用源码推断代替观察结果。

## 15. 依据的源码

- iPhone App：[`PhoneSharingView.swift`](../../mobile/FlipperLab/App/Views/PhoneSharingView.swift)、[`DeviceView.swift`](../../mobile/FlipperLab/App/Views/DeviceView.swift)、[`FunctionsView.swift`](../../mobile/FlipperLab/App/Views/FunctionsView.swift)、[`PhoneCompanion.swift`](../../mobile/FlipperLab/App/PhoneCompanion.swift)、[`PhoneLocationProvider.swift`](../../mobile/FlipperLab/App/PhoneLocationProvider.swift)、[`FlipperDevice.swift`](../../mobile/FlipperLab/App/FlipperDevice.swift)、[`FlipperLabApp.swift`](../../mobile/FlipperLab/App/FlipperLabApp.swift)、[`Info.plist`](../../mobile/FlipperLab/App/Info.plist)
- 核心库：[`CompanionProtocol.swift`](../../mobile/FlipperLab/Sources/FlipperCore/CompanionProtocol.swift)、[`CompanionNetworking.swift`](../../mobile/FlipperLab/Sources/FlipperCore/CompanionNetworking.swift)、[`CompanionStorage.swift`](../../mobile/FlipperLab/Sources/FlipperCore/CompanionStorage.swift)、[`RPCOutboundQueue.swift`](../../mobile/FlipperLab/Sources/FlipperCore/RPCOutboundQueue.swift)、[`FlipperFunction.swift`](../../mobile/FlipperLab/Sources/FlipperCore/FlipperFunction.swift)
- 设备应用：[`applications/union/gps_rpc`](../../applications/union/gps_rpc)、[`applications/examples/example_network`](../../applications/examples/example_network)
- 固件服务（用于核对状态映射和路径解析）：`applications/services/gps`、`applications/services/network`、`applications/services/rpc/rpc_gps.c`、`applications/services/rpc/rpc_network.c`
- 安装步骤：[Flipper Lab 说明](../../mobile/FlipperLab/README.zh-CN.md)
