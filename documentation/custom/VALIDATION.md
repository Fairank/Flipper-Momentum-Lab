# 验证记录

## 中文与功能并集第二轮：本地验收（2026-09-29）

接续代码基线 `b8e1f9f4`，范围见 [第二轮实现](UNION_CHINESE_CONTINUATION.md)，逐文件哈希及七项 Opus 实际执行状态（六项实现、一项文档核对）见 [JSON 记录](UNION_CHINESE_CONTINUATION.json)。这批改动不等于完整并集或全界面中文验收。

- 93 项 Python / 实际 C 回归通过，无跳过；包含 7,296 个月份与日历真实绘制、UTF-8 滚动、五类中文按钮、快捷设置、时钟和 FAP 名称兼容。
- `updater_package` 与随后独立的 `fap_dist` 通过，分发含 333 个 FAP、124 个独立 FAL；新增床头时钟、十个工具及原有两个伴侣应用均存在。
- 正常固件 879,632 字节，当前无线栈起点 `0x080D7000` 前仅余 1,008 字节；恢复升级器 123,857 字节，低于 131,072 字节。链接器显示的 `.free_flash` 包含无线协处理器区域，不能据此宣称主固件还有 164 KiB 可用。
- 首次最终打包因主固件越界 56 字节被拒绝；未绕过保护。删除未被使用的重复 ASCII 字形后通过布局检查。CJK 字库为 696 字形 / 18,973 字节，升级器子集为 135 字形 / 3,707 字节。
- `lint_all`、字库同步检查与 `git diff --check` 通过。42 个导入设备图标规范化后，逐个比较实际编译的像素数据完全一致；README 截图未改变，并从设备图标规则中单独排除。
- 本地升级包名称含构建前 HEAD `b8e1f9f4`，是改动工作树产物，不是干净基线包。其大小与 SHA-256 在上述 JSON 中，云端产物须另核对对应提交。
- 本机无 Xcode、无连接硬件；手机新增 13 项已安装应用（床头时钟、十个工具、两个 HID 遥控）的中文显示映射，已由下方当前代码的 Mac CI 验证。未执行刷机、BLE、AIO、实卡或射频验收。

### 本轮代码的 GitHub 验收

以下全部对应分支代码 `6017530b20b128c75450f5f77c593ae66d04e885`，PR 构建使用合并提交 `158ae9952c9b86290b2ad62e006112dd5a68abc9`。后续文档提交只补录证据，不声称重新执行代码或硬件验收。

- [Lab validation 36525103876](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/36525103876) 全部通过：93 项 Python / 实际 C 测试、89 项 Swift 核心测试、5 项 iPhone UI 测试、无签名模拟器构建及三套字库同步检查。环境为 Xcode 26.6、iPhone 17 Pro Max / iOS 26.5。
- [Lab firmware 36525103757](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/36525103757) 与 [Lint 36525103890](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/36525103890) 全部通过；构建后跟踪源码没有变化，13 项指定应用的存在性和升级器尺寸检查通过。
- [升级包附件 11014658624](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/36525103757/artifacts/11014658624) 已下载并核对 ZIP 摘要、内部 SHA256SUMS、DFU CRC 与地址边界。包内含 **280 个正式 FAP 与 121 个 FAL**；完整 `fap_dist` 另外构建 53 个 Debug / Examples 应用和 3 个示例插件，合计 333 / 124，不混算为常规升级包内容。
- 云端恢复升级器为 123,829 字节，主固件为 879,696 字节，距当前无线栈起点余 **944 字节**。云端版本字符串等构建差异会使大小与本地不同；这里记录实际下载产物，未绕过边界检查。
- 云端 TGZ 为 12,820,416 字节，SHA-256 为 `5fa8973f42e7a1561be416a5438b7a9ff18c342aac9d7c6db45a88d1ec980f3f`；ZIP SHA-256 为 `bc4dbdffee691ccaf4d5b3c2582f285ff5efbb4b9f9c0a80abea7d49c72e9bcf`。新增床头时钟和十个工具以及两个伴侣应用均在包内，两个单独附带的伴侣 FAP 与包内文件逐字节一致。
- [Flipper 源码预览附件](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/36525103876/artifacts/11014567879) 包含 66 张帮助页、6 个原生菜单及 UI 文案审计清单；已下载核对摘要，六菜单拼图与已查看的本地预览字节一致。它们不是真机照片。
- [iPhone 原始模拟器截图附件](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/36525103876/artifacts/11014940556) 已生成；摘要记录在本轮 JSON。固件和截图附件按当前保留期于 2026-10-13 到期，源码与构建入口保留。

未执行刷机、蓝牙、AIO、实卡或射频验收，以上绿色结果不改变这个边界。

## 上游融合提交 `22904e309`（2026-09-29）

来源和未完成范围见 [UPSTREAM_FUSION.md](UPSTREAM_FUSION.md)。本轮适配 Momentum `d3f89dfe` 与 Unleashed `15bca58e`，本分支 API 为 89.0，协议为 0.29 并保留 ASCII 输入扩展。

- Windows / 官方工具链 39 / GCC 12.3.1：完整 `updater_package` 成功。恢复升级器 120,077 字节，低于 131,072 字节；本地工作树升级包为 12,741,817 字节。包名仍携带构建前 HEAD `c1ead037`，**不能把它当作旧提交的原始产物或新提交的 CI 产物**。
- 主固件链接报告：`.text` 677,280、`.rodata` 194,340、`.data` 956、`.bss` 7,684 字节，剩余 Flash 175,664 字节。这不是运行时剩余堆内存。
- 60 项 Python / 实际 C 回归全部通过，无跳过：增加数字输入边界、三种菜单的导航、数组比较、发布日志、加载器生命周期、GPS/网络会话归属、协议编号兼容及插件私有接口精确匹配测试。
- 旧协议 73 个 content 字段（含 Empty / StopSession）保留名称、类型及编号；新增 15 字段无冲突。实际 nanopb 生成代码已检查 ASCII 扩展及协议 0.29。
- 两套字库同步检查通过。原生中文子集为 690 字形、17,336 字节；生成了 66 张帮助页与 4 张原生页面源码布局预览，均不是真机截图。
- `fap_dist` 成功，输出 322 个 FAP 与 124 个独立 FAL，另有嵌入父应用的插件。NFC 插件接口检查按父应用实际导出表匹配，未解析接口警告已清除；两项上游非法 appid 仍按融合记录说明跳过。
- 三个新增示例图标已用仓库工具转换为无元数据的单色格式；Windows 图像检查的路径分隔符问题已修复。`lint_all`、2,031 张图标检查、289 个 Python/构建文件格式检查和 `git diff --check` 通过。
- 追加了设备侧 Sub-GHz 样本/驱动注册测试，但未在 Flipper 上执行。没有把这些测试列作已通过。
- 本轮本机没有 Xcode，未连接 iPhone、Flipper 或 AIO，未刷机。当前新增 GPS/网络代理的 iPhone 处理端未实现。

### 本提交的 GitHub 结果

- [Lab validation 36516344087](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/36516344087)：60 项主机回归、88 项 Swift 核心测试、5 项 iPhone UI 测试、iOS 模拟器构建和两套字库检查全部通过。环境为 Xcode 26.6、iPhone 17 Pro Max / iOS 26.5。输出 66 张帮助页和 4 张设备原生页面源码预览。
- [Lab firmware 36516344066](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/36516344066) 与 [Lint 36516344121](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/36516344121) 通过。云端构建未修改跟踪源码；恢复升级器为 120,049 字节，两个伴侣应用存在性检查通过。云端包使用 PR 合并提交 `0831a35b219e18b0f706a011621dd5c17ac07145`，对应分支代码 `22904e3091920052099fa025f7b5f47146847808`。
- [固件下载附件 11010948604](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/36516344066/artifacts/11010948604) 已下载核对：ZIP SHA-256 为 `1ac9207c19738c5257081e9ad12dd18138f28b99b86accef7e67825a37e14417`；内含升级包为 12,741,083 字节，SHA-256 为 `7e15b20a7764d3f41c24be78a5e2335fac4a88321091554b1e95b584232c7b9f`，与包内校验文件一致。包中有固件、无线协处理器镜像、升级器和资源，未执行刷机。
- [iPhone 模拟器截图附件](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/36516344087/artifacts/11011472896) 和 [Flipper 源码布局预览附件](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/36516344087/artifacts/11011157232) 已生成。它们不是真机验收；本轮未更改 iPhone 页面设计。
- 这些附件按当前保留期于 2026-10-13 到期；源码和构建入口保留在仓库，可重新构建。不要将附件包名的合并提交与本地构建前 HEAD 混淆。

本节明确针对代码提交 `22904e309`；后续仅补录验证文档的提交不代表重新执行了一遍硬件或软件测试。下面保留的历史结果不代替本次验证。

## 离线 Classic、串口接收与原生中文（2026-09-27）

用户选择先完成代码与自动测试，暂不连接硬件，并选定 MIFARE Classic 离线样本范围。

### 已推送代码 `0d741468`

- [Lab validation 36301957045](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/36301957045)：88 项 Swift 包测试、5 项 iPhone UI 测试、39 项 Python/C 回归和 iOS 构建全部通过。环境为 Xcode 26.6、iPhone 17 Pro Max / iOS 26.5。
- [Lab firmware 36301957047](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/36301957047) 与 [Lint 36301957054](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/36301957054) 均通过。
- Classic 测试实际执行无字典恢复，使用 Proxmark3 公共已知答案并由 Swift 独立复核两组认证；C 桌面另验证四组生成密钥、错误数据、重复认证及计算中取消。Linux 启用 ASan/UBSan。不是预置界面结果，也不是用户卡片的验收。
- 串口测试编译实际 C 协议校验函数，并验证 Swift 线格式、边界、丢失计数和缓冲截断；模拟器检查离线入口不可开始。固件构建包含 Lab Bridge，但没有测到真实 AIO 输出。
- iPhone 截图 artifact `10926176563`，ZIP SHA-256 `731936d06438a34b4b23aca701899c2b986ba1ba15757489674a46c38fc19677`。已查看公开样本恢复结果与串口等待连接两张原图；没有修改图像像素。

### 后续原生中文工作树检查

- 与 `0d741468` 比较：应用/设置的 227 个 C 文件、1,039 处字符串变化；翻译审计未发现非字符串 C 标记或 printf 格式符变化。串口生命周期和 GUI 改动单独审核，不混入此计数。
- 本地 Windows/Zig 完成 46 项 Python/C 回归，无跳过；包括 7 项新增原生 GUI 测试。字体生成检查与 `git diff --check` 通过。
- 原生中文子集 679 字形、17,048 字节，逐字形检查实际像素上下界；4 个代表菜单的源码预览已生成并查看 NFC 图。旧 Flipper Lab 帮助页预览仍独立保留。
- 本地完整更新包构建通过。首次发现恢复升级器 138,753 字节超过旧固件 131,072 字节上限；主助手把中文子集排除出 RAM 恢复镜像，重建为 121,469 字节。CI 增加尺寸与两个伴侣应用存在性检查。
- 字库和 UTF-8 改动最终提交的 GitHub 结果另行追加，不能把前一提交的 iOS 结果当作新提交已经通过。

### 原生中文提交 `5cc450fe` 的云端结果

- [Lab validation 36304012415](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/36304012415) 全部通过：88 项 Swift 测试、5 项 iPhone UI 测试、46 项 Python/C 回归、两套字体同步检查、iOS 模拟器构建和 70 张设备源码布局预览。Linux C 检查包含 ASan/UBSan。
- [Lab firmware 36304012490](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/36304012490) 与 [Lint 36304012396](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/36304012396) 全部通过；更新器大小与两项伴侣应用存在性检查通过。固件包基于 PR 合并提交 `e46e8da64aa2223b7e17ff57ee29638cb20cadb4`。
- 22 张 iPhone 原始截图 artifact `10927026485` 已下载并核对 ZIP SHA-256：`14d08421701f968afda38ea2c716b1ea6c83bf3104570607f1722f4d71417d81`。本地展示页保留原图和来源提交，不把源码预览称为真机画面。
- 最后对照发现设备帮助还使用旧英文菜单名，并把已经实现的手机分析列作规划；已更新 `lab_content.json` 并重新生成两套字体。更新后原生子集为 677 字形、16,980 字节；66 张帮助预览和 4 张原生菜单预览生成通过，46 项本地回归无跳过。这项帮助修订不修改手机或恢复引擎代码。

### 本地 Claude 实际记录

四项均请求 `claude-fable-5-1 --effort max`，只通过 CLI，无模型替换。记录位于仓库外开发日志，主助手审核后采用。

| 任务 | 实际返回与完成状态 |
| --- | --- |
| NFC 字典基础解析与测试 | `claude-fable-5-1`，退出 0，882.2 秒 |
| 原生设置和开始菜单翻译 | `claude-fable-5-1`，退出 0，2,251.5 秒 |
| 其他原生场景翻译 | `claude-fable-5-1` 及错误事件 `<synthetic>`，615.8 秒后因服务 safeguard 退出 1；部分文案经主助手词法/格式审计采用，没有记作完整交付 |
| GUI UTF-8 与回归草稿 | `claude-fable-5-1`，退出 0，3,888.2 秒；主助手修复测试编译、补齐生成字库、处理恢复镜像体积并执行回归 |

Claude 的交付文本仍称字体头不存在，这是陈旧判断；主助手已实际生成并用像素范围测试和固件构建验证。不能直接采用代理的完成或失败表述。

### 硬件与未实现范围

本轮未连接或刷写用户硬件。用户自有卡片结果、iPhone/Flipper BLE、AIO UART 全链路、吞吐/丢失以及全部原生屏幕排版均未真机验收。全系统重写、所有动态/第三方界面中文化、未知 AIO 固件专用驱动和定向 Wi-Fi 断链未完成。

新增任意串口命令手机入口的编辑被自动审批拒绝，理由是板卡固件未确认，会扩展到未批准的设备控制或 Wi-Fi 干扰；该编辑没有应用，也没有换路径重试。通用接收与离线计算不构成该入口的替代实现。

---

以下保留较早验证记录与当时状态；当前结果以上方和最新追加记录为准。

记录日期：2026-09-25。本文只记录实际运行过的检查。源码已编写不等于编译、模拟器或真机通过；CI 通过不等于真机可用。本轮没有刷写设备、部署或发布 App。

## 当前环境

- 分支 `codex/iphone-zh-architecture`，基于 `b06c940ec326fef33954b49cffbc085f16607aaf`，已推送。草稿 PR：[Fairank/Flipper-Momentum-Lab#1](https://github.com/Fairank/Flipper-Momentum-Lab/pull/1)，目标分支 `codex/momentum-unleashed`，尚未合并。首个提交 `8c4695de2763fa6457d3b0b5c76e803129ea9379`；当前功能代码提交与运行证据见文末。
- GitHub 访问：GitHub App 安装 164333683 已限制为只授权 `Fairank/Flipper-Momentum-Lab`，浏览器授权由主控在用户明确许可后完成；连接器可写入该仓库。本机 `gh` 未登录。
- Windows 11 原生环境，官方工具链 39 可用；工作区内有 Zig 0.16.0，可作为桌面回归的 C 编译器。
- 全部固定子模块已递归初始化，未升级任何 gitlink；版本见 [SOURCE_LOCK.json](SOURCE_LOCK.json)。
- 本机没有 Xcode，也没有可用的 Mac；iPhone、Flipper 和扩展板均未接入测试。

## 新测试环境基线（提交 43bd0358）

2026-09-24，[Lab validation 35977973407](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35977973407) 在 Xcode 26.6、iPhone 17 Pro Max / iOS 26.5 上完成：52 项核心测试、2 项 UI 测试、36 项桌面回归通过，65 个 Flipper 源码画面成功生成。Lint 与 Lab firmware 同样通过。此提交仍为旧手机界面，视觉重做的结果必须另行记录。

## 后续核验（提交 `8a1347be`）

- [Lab validation 35975959905](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35975959905)：51 项 Swift 包测试、模拟器构建、2 项 UI 测试、36 项 Python/C 回归全部通过。截图附件 10 张已导出，并查看设备、示例资料库和脉冲图。模拟器为 **iPhone 16 Pro / iOS 18.5**，工具为 Xcode 16.4；不是用户的 17 Pro Max 真机。
- [Lint 35975959943](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35975959943)：通过。
- [Lab firmware 35975959893](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35975959893)：通过。PR 检出合并提交 `4c49beb70a2f4486a934b51c077fa4df97bb0d8d`，对应分支头 `8a1347beb085431eb4d9164a066387db5f32916a`。
- CI 更新包 `flipper-z-f7-update-mntm-HEAD-4c49beb7.tgz`：12,649,645 字节；SHA-256 `f098a60ebfc0c5cc5b8bc08dc468ee676fa617a1b45014339a4e7ef4b6277693`。下载后已核对清单；包内 `resources.tar.gz` 的 `apps/Tools/lab.fap` 与单独产物逐字节一致，22,360 字节。它取代下方较早的本地未提交包作为当前构建证据，尚未刷写。
- `render_lab_preview.py --all`：实际运行成功，65 个画面（10 个菜单状态、55 页说明），无警告；PNG 已打开检查。布局预览由实际字库与源码计算，**不是固件运行或真机截图**。
- 用户否定旧手机界面，要求 Claude 5.1 Max 设计、Opus 5.5 实现，正在重做。旧截图仅作历史验证，不能代表新版完成。
- 本次同时新增资料库编码前总量检查及一项回归，以及文件读取的 2 MiB + 1 硬上限，等待新的 macOS CI（预期 52 项包测试）。CI 已改为 Xcode 26.6、iPhone 17 Pro Max / iOS 26.5，结果待跑；不把该设置写成已通过。

## 较早结果

### 固件

| 检查 | 结果 | 能证明的范围 |
| --- | --- | --- |
| 核心固件构建：`FBT_NO_SYNC=1 fbt.cmd SKIP_EXTERNAL=1 updater_package` | 2026-09-24 15:37（本地时间）结束，退出码 0 | 当时的工作区能编译核心固件并打包；不含 Flipper Lab 与 UTF-8 修复 |
| 完整更新包：`FBT_NO_SYNC=1 fbt.cmd -j1 updater_package fap_dist`（含外部应用、Flipper Lab、字库、UTF-8 修复） | 成功；日志在仓库外 `../flipper-tools/full-build-zh-retry.log` | 当时的工作树（基于 `b06c940e`，含未提交改动，早于最后的格式化和文档改动）能完整编译并生成更新包和 `.fap` 分发目录 |
| 同时请求 `updater_package fap_dist` | Windows 再次重建时失败，`-j1` 也会复现 | `sconsdist.py` 会清理整个输出目录，导致同一构建图中已检查的安装目录失效；应分两次调用，先 `updater_package`，成功后再 `fap_dist` |

完整包产物：

- `dist/f7-C/flipper-z-f7-update-mntm-codex-iphone-zh-architecture-b06c940e.tgz`
- 大小：12,649,553 字节
- SHA-256：`dbae720f9b2207694994c8d6a35d58a40872a06fe468fb7a75bcc088862096e9`
- `dist/f7-C/apps/Tools/lab.fap`：22,360 字节

包名中的 `b06c940e` 只是基线提交，不证明该包对应远程的任何提交；用最终源码（CI 的 `lab-firmware.yml` 或本地重建）生成的包可以取代它。构建输出提示两个上游无效 appid（`.cli_gui`、`.f0_mtp`）被排除，这是继承自上游应用清单的警告，未处理，也不是本定制引入的。产物未刷写到任何设备。

大小记录（只作参考，不能据此推算剩余 Flash/RAM；堆、运行时和各存储区域需要另行测量）：

| 对象 | 数值 |
| --- | --- |
| 固件 `arm-none-eabi-size` | text 838,296 / data 960 / bss 9,956 |
| `lab.fap` 文件 | 22,360 字节 |
| `lab.fap` 加载后的代码段 | 15,913 字节，另加应用栈 3,072 字节和运行时动态堆 |
| 字库子集 | 423 字形，9,896 字节 |

### 桌面回归与生成器

| 检查 | 结果 | 能证明的范围 |
| --- | --- | --- |
| Windows：`scripts/tests/test_unleashed_integration.py` 与 `scripts/tests/test_gui_utf8.py`，`cc` 解析到工作区 Zig 0.16.0 的 `zig cc` | 3 项旧回归 + 3 项 UTF-8 测试通过，无跳过（真实编译） | 源文件顺序、插件扫描、进度视图，以及 UTF-8 换行的桌面替身行为 |
| Windows：`scripts/tests/test_lab_font.py` | 30 项通过；生成器改为 clang-format 兼容输出后复跑仍通过 | 字库子集、文本尺寸检查、启动目标核对 |
| GitHub Ubuntu 任务（run 35974984160，首个提交）：`unittest discover` 与 `generate_lab_font.py --check` | 任务通过，36 项测试全部通过 | 同上，在自带 `cc` 的 Linux 上 |

### iPhone App（GitHub macOS CI，首个提交）

运行：<https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35974984160>，工作流 `lab-validation.yml`。

| 检查 | 结果 | 能证明的范围 |
| --- | --- | --- |
| `swift test --package-path mobile/FlipperLab` | 51 项通过 | RPC 分帧、protoc 生成的互操作向量、六类记录解析、存储上限与损坏处理、内置指南完整性；在 macOS 上以 macOS 为目标编译 |
| XcodeGen 生成工程 + 不签名 iOS 模拟器构建 | 通过 | `App/` 与 UI 测试目标能为模拟器编译 |
| 模拟器 UI 测试 `testOfflineNavigationAndChineseGuide` | 1 项通过：依次进入设备、资料库、工具（含比较记录）、任务、指南五个页面，并打开“设备连接”指南 | 离线模拟器界面能启动和导航；**不证明蓝牙、文件传输或红外** |
| 所用模拟器机型与 iOS 版本 | 未记录（首个运行的日志不可用） | — |
| 截图导出产物（`iphone-screenshots-<attempt>`、`simulator-test-evidence-<attempt>`）与示例记录固定样本测试 `testExampleRecordAnalysis` | 首个运行之后加入，结果待记录 | 暂无 |

### 尚未运行

| 检查 | 状态 |
| --- | --- |
| `lab-firmware.yml` | 后续运行已通过，见上方“后续核验” |
| iPhone 17 Pro Max 真机、蓝牙流程、红外实际响应 | 未运行；没有可用的 Mac 和真机 |
| Flipper 真机屏幕检查（Flipper Lab、UTF-8 换行） | 未运行；源码渲染预览已运行成功，其输出不是真机截图 |
| 剩余 Flash/RAM 测量 | 未做 |
| 新增 API 导出与已有应用的兼容性核对 | 未做 |

### Windows 中文路径

原工作区路径含中文，旧版 protoc 无法处理，构建因此失败。用 `subst` 把仓库临时映射到一个 ASCII 盘符，并设置 `PYTHONUTF8=1` 后，核心构建与完整包构建通过。操作步骤见 [HANDOFF.md](../../HANDOFF.md) 的“Windows 固件”；`subst P: /D` 只删除盘符映射，不删除源码。

`FBT_NO_SYNC=1` 会跳过 fbt 的子模块同步，只能在子模块已按固定提交初始化后使用。

## 本轮源码状态

各模块的源码状态与已有验证见 [REQUIREMENTS.md](REQUIREMENTS.md)。功能说明中的状态以 [FEATURE_CATALOG.zh-CN.json](FEATURE_CATALOG.zh-CN.json) 为准（`catalog_status: implementation_in_progress`；条目状态为 `implemented_unverified`、`in_progress` 或 `hardware_required`）。

## 委派记录

- 方式：用户授权的本机 Claude CLI 工作进程。主控负责决策、验收、蓝牙与设备控制代码，并审查全部改动。
- 较早的委派请求并返回 `claude-opus-5-5`（`--effort max`）：记录解析与存储、设备端中文说明、工程与 CI、UTF-8 修复、文档五项退出码 0；iOS 界面一项因服务端安全策略退出码 1，没有产出任何界面文件，界面由主控直接实现。
- 主控已复核解析与存储、设备端说明、字库生成器和 UTF-8 修复的代码，并运行了上述测试。
- 当前的委派要求为 `claude-fable-5-1 --effort max`：连通性探测返回该模型，退出码 0；预览与文档任务均实际返回该模型、退出码 0，主控已复核。用户随后明确指定界面重做由 5.1 Max 设计、Opus 5.5 实现，该任务按新指令执行并单独记录；其他任务默认保持 5.1 Max。
- [IPHONE_ZH_PLAN.md](IPHONE_ZH_PLAN.md) 中“未找到 CLI、未调用委派”是当时的状态，已由本节更新。

## 待补证据

1. 新界面与内存上限检查已有新版 CI 证据，见下方手机界面各轮验收记录；后续代码变更须补相应证据。
2. 固件若继续变更，重新生成对应提交的更新包及 SHA-256。
3. 剩余 Flash/RAM 的测量。
4. 模拟器主要页面截图已检查；其他设备尺寸、VoiceOver 与真实操作状态仍待验收。
5. iPhone 17 Pro Max 与 Flipper 真机的完整蓝牙流程。
6. Flipper 真机屏幕检查；65 个源码渲染预览已输出并通过 CI，不能替代真机检查。
7. 扩展板型号及测试记录。

仓库继承的上游固件工作流仍带上游发布假设和官方 API 版本一致性检查；它们的状态不能等同于本定制的验证结论，本定制以 `lab-validation.yml` 与 `lab-firmware.yml` 为准。

## 历史记录：上一台 macOS

以下结果来自上一台 macOS arm64 机器（官方工具链 39，GCC 12.3.1），本轮未在 macOS 复跑。

| 检查 | 结果 | 能证明的范围 |
| --- | --- | --- |
| `python3 scripts/tests/test_unleashed_integration.py -v` | 3 个测试通过 | 源文件模式顺序、插件扫描及进度视图的桌面回归 |
| 修改过的 13 个 C/header 文件使用工具链 `clang-format --dry-run --Werror` | 通过 | 本批 C/header 格式 |
| Python 文件 Black 检查 | 通过 | 本批 Python 格式 |
| `git diff --check` | 通过 | 改动没有空白错误 |
| API CSV 与基线比较 | 4,675 个既有条目签名和状态不变，新增 4 个，无重复名称 | 导出表文本兼容性，不能代替应用运行 |

这些测试从生产实现抽取函数，以桌面存储/绘图替身执行，没有验证真实 SD 卡、GUI 线程调度、板上内存和硬件行为。

当时 `applications/external` 只稀疏检出三个目录，嵌套依赖也未完整初始化。`FBT_NO_SYNC=1 ./fbt SKIP_EXTERNAL=1 updater_package` 以退出码 2 失败：

```text
applications/main/archive/helpers/archive_files.c:4:10: fatal error:
applications/external/subghz_playlist/playlist_file.h: No such file or directory
```

本轮在完整初始化的子模块上，Windows 核心构建与完整包构建均已通过；macOS 上没有重新构建。

## 手机首轮界面验收（2026-09-24）

代码版本 `bfc43b4a949a6d4b4e4fa791e26f053c7abcf3d1` 在 [35985874280](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35985874280) 通过 52 项核心测试、3 项 UI 测试、36 项桌面回归与模拟器构建；完整固件构建 [35985874510](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35985874510) 和 Lint 亦通过。运行环境为 Xcode 26.6 / iPhone 17 Pro Max / iOS 26.5；17 张原始截图，含修正后的浅色栏、完整波形和深色大字页面。模型分工、实际返回值、主控修正和截图 SHA256 见 [UI_REVIEW.md](UI_REVIEW.md)。

设计由本机 `claude-fable-5-1 --effort max` 完成，实现由用户本轮指定的 `claude-opus-5-5 --effort max` 完成；实际模型一致，均退出码 0。主控审阅后采纳，并修复截图检查发现的问题。

## 手机苹果原生界面优化（2026-09-24）

根据用户的新反馈，手机重新整理为设备、资料库、任务、指南四页，使用原生导航、分组列表、表单、菜单和系统颜色，保留 Flipper 橙色及小像素屏。Fable 5.1 Max 负责设计，Opus 5.5 Max 负责实现，均由本地 CLI 实际调用并正常退出；主助手审核决定并修复截图发现的问题。实际模型、代码核对和各轮运行证据见 [UI_APPLE_REVIEW.md](UI_APPLE_REVIEW.md)。

最终验证提交 `9611f7403c5f41df964048c01ee0c622b3c6842d` 已通过 [35998623945](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35998623945) 的 52 项核心测试、3 项 UI 测试、36 项桌面回归与模拟器构建。[完整固件构建](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35998623890) 与 [Lint](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35998623705) 通过。运行环境为 Xcode 26.6 / iPhone 17 Pro Max / iOS 26.5。

应用源码在 `4e80b06e` 后保持不变，后续修正截图测试，使资料库和记录详情的图标检查直接针对保存的整屏原图。最新 17 张截图中一张受到模拟器系统通知遮挡，因此展示选取同一应用代码两次运行中的 17 张无遮挡原图；每张注明出处且未编辑像素。完整来源、ZIP SHA-256、人工核对范围及测试局限见 [UI_APPLE_REVIEW.md](UI_APPLE_REVIEW.md)。之后只更新文档的提交不另作一次代码验证。

## 独立手机功能中心与门禁凭证说明（2026-09-25）

用户决定手机采用自己的中文功能页，点选后仅通过蓝牙要求 Flipper 打开应用，不返回或镜像 Flipper 屏幕。最终功能代码提交 `0729721d0fd85de58029dec2fa64d1067cf00f8f`：

- [Lab validation 36108391458](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/36108391458)：54 项 Swift 包测试、3 项离线 UI 测试、37 项 Python/C 桌面回归、iOS 模拟器构建与 65 张 Flipper 源码布局预览全部通过。UI 测试包括五页导航、功能页离线点选提示、示例分析及深色大字。模拟器是 iPhone 17 Pro Max / iOS 26.5，Xcode 26.6。
- [Lab firmware 36108391450](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/36108391450) 与 [Lint 36108391502](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/36108391502)：通过。
- 截图产物 `iphone-screenshots-1`（artifact `10852621263`）包含 18 张模拟器原图，ZIP SHA-256 为 `e509a99e89cb9d5845012c88051f7055987b2ca7be3c030e906d70ecab7380b0`。其中功能页原图 SHA-256 为 `28cf65e85862274036a085f4e75d1274f62e450f7da0789631f1c75c3c7a5cb6`；已查看文字层次，图库中的拷贝与原图校验值一致，没有修改像素。Flipper 预览产物 `flipper-source-previews-1`（artifact `10852128066`）为源码生成，不是真机截图。
- 本地 Claude CLI 的功能页 UI 委派实际返回 `claude-fable-5-1`、`--effort max`、退出码 0；主助手审核并修正离线可读性、协议和测试。另一次边界清晰的门禁说明 UI 委派因 `ECONNREFUSED` 退出码 1，未返回实际模型或代码；主助手自行实现并在上述模拟器构建中验证编译。

真实 iPhone 与 Flipper 的 BLE 配对、逐项应用启动、已安装 `.fap` 读取，以及门禁发行方数字凭证或刷门均未实测。模拟器不提供这些硬件结论。本次未把 Flipper 卡文件直接转换为 iPhone NFC 凭证。

