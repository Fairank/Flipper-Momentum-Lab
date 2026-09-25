# iPhone 苹果原生界面优化验收

基线是已运行验收的 `bfc43b4a949a6d4b4e4fa791e26f053c7abcf3d1`。这一轮针对手机界面的层级、导航、阅读和操作体验，不改变蓝牙协议、设备控制或分析算法。

## 分工记录

- 设计：本地 CLI `claude-fable-5-1 --effort max`；实际返回 `claude-fable-5-1`，退出码 0，459.6 秒。输入包括六张上一版的真实模拟器截图。设计见 [UI_APPLE_DESIGN.md](UI_APPLE_DESIGN.md)。
- 实现：按用户在本任务中的明确指定，调用本地 CLI `claude-opus-5-5 --effort max`；实际返回 `claude-opus-5-5`，退出码 0，2117.1 秒。交接记录见 [UI_APPLE_IMPLEMENTATION.md](UI_APPLE_IMPLEMENTATION.md)。
- 主助手：审核设计取舍、代码与真实运行结果。模型报告本身不作为编译、连接或真机执行成功的证据。

## 审核后的设计决定

1. 使用设备、资料库、任务、指南四个固定分页。比较和导入收进资料库，记录详情可进入比较并预选记录 A。四页是本项目的信息组织决定，苹果并没有禁止五页。
2. 页面使用原生大标题、分组列表、表单、菜单和系统导航材质；移除厚边框和大面积仿实体按键，保留橙色和小像素屏。iOS 17 使用系统兼容表现，iOS 26 由系统管理导航材质。
3. 使用语义字号、系统前景色及背景色；普通启动尊重用户外观和字号。仅 DEBUG 截图参数可强制测试外观。
4. 脉冲图继续使用原来的线性刻度，保留正负持续时间、单位和抽样说明。设计中可选的对数刻度不采纳，避免本轮改变数据表达含义。
5. 删除仍需确认；离线和忙碌状态仍禁止相应硬件操作，并显示原因。设备错误、分析失败、任务取消和资料库重试入口必须保留。
6. 主助手将蓝牙不可用说明改为实际状态对应的用户提示：未授权、已关闭、不支持和重置分别解释；移除面向开发者的模拟器测试文案。只改变提示选择，关闭连接和协议处理保持原逻辑。
7. 主助手把红外按钮改为分行的原生列表内容，避免大型遥控库一次创建全部按钮；禁用原因放在按钮前，文件中的按钮次序、执行索引和条件不变。移除已无内容的旧工具页文件。

## 参考依据

- [Apple HIG：布局](https://developer.apple.com/design/human-interface-guidelines/layout)：层级、分组、对齐和安全区域。
- [Apple HIG：排版](https://developer.apple.com/design/human-interface-guidelines/typography)：语义文字样式和动态字号。
- [Apple HIG：标签栏](https://developer.apple.com/design/human-interface-guidelines/tab-bars)：清楚、稳定的主要目的地。
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)：原生控件和导航材质适配。

文档中的具体间距、圆角和页面数量是设计选择，并非苹果强制数值，也不构成苹果认证。

## 本轮运行证据

首轮代码版本：`1a8f4ee8c15cdd2e6e333ecc09746db68bf8fe1f`。

主助手已逐文件审阅界面变更，并与前一提交逐字对照：比较算法、比较异步任务、记录分析异步任务、红外执行条件、目录读取任务及导入条件均一致。蓝牙文件除提示选择外其余内容一致。旧配色和自定义导航栏引用已清理，差异格式检查通过。

首轮 Mac CI [35992211349](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35992211349) 通过模拟器编译、52 项核心测试、3 项 UI 测试和 36 项桌面回归，导出 17 张截图。人工查看全部截图后，仍发现空资料库按钮被拉成竖长图标、大字号搜索按钮截字，以及比较页次要文字继承橙色导致偏淡。自动测试通过不代表视觉验收通过。

主助手将空状态按钮移到独立列表行，按钮文字显式允许完整换行，比较字段改用系统语义颜色，工具栏“更多”使用明确的图标和可访问名称；补充空资料库按钮尺寸回归检查。

修正版本 `4e80b06e1036256e452b911eed72a59f22ed4c0b` 在 [35994273332](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35994273332) 再次通过模拟器构建、52 项核心测试、3 项 UI 测试及 36 项桌面回归；[完整固件构建](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35994273431) 和 [Lint](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35994273423) 也通过。17 张截图的 ZIP SHA-256 为 `241121c8ea32d1b33e3fafe0ed782b86f64916156d89a66b103ce645ad9a5c06`，artifact `10805742699`。

全部截图已逐张检查：空资料库按钮恢复横向文字布局；辅助大字号搜索按钮完整换行；浅色与深色比较字段使用清楚的系统颜色；深色记录页显示完整“更多”图标。第 09 张首次进入记录详情的截图仍缺少该图标，而第 10、11 张与菜单交互正常。因此补充首次进入时的图标像素检查，必须确认图标已经绘制才截图，避免仅凭辅助功能树判断可见。

测试提交 `c9f77c8b052d885832418fb0c5c0efa6563534e8` 在 [35995691654](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35995691654) 通过，首次记录详情图标检查和第 09 张截图均正常。资料库第 02 张又捕获到菜单尚未绘制的中间画面，后续菜单交互通过；因此将同一像素检查补到空资料库与示例资料库截图之前。

`39f34791` 的 [35997043753](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35997043753) 仍然通过测试，但第 08、09 张整屏截图缺少菜单。这证明“检查按钮局部截图，再另拍整屏”无法保证交付图像的一致性。主助手改为从整屏原图中测量图标所在区域，只有该原图通过检查才把同一张未经修改的整屏图保存为附件；区域裁切仅用于像素测量，不改绘或替换展示图片。上述后续提交只改变截图测试，应用代码保持 `4e80b06e`。

### 最终验证

- 验证提交：`9611f7403c5f41df964048c01ee0c622b3c6842d`；[Lab validation 35998623945](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35998623945) 全部通过：52 项核心测试、3 项 UI 测试、36 项桌面回归，模拟器构建成功。环境为 Xcode 26.6 / iPhone 17 Pro Max / iOS 26.5。
- [完整固件构建](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35998623890) 和 [Lint](https://github.com/Fairank/Flipper-Momentum-Lab/actions/runs/35998623705) 通过。继承的上游 `Build` 因 fork 条件跳过，不作为本项目构建证据。
- 最新截图附件 `iphone-screenshots-1`：artifact `10807562323`，17 张，ZIP SHA-256 `c607274091442fa7e5335adec1918ef441b25ad9b42dcffa30209401aecfb438`。第 02、08 张完整显示工具栏。第 09 张被模拟器的 Apple Intelligence 系统通知遮挡，说明像素检查仍须结合人工核对，不能视为完整视觉判断。
- 展示选取逐页看过的 17 张无遮挡原图：第 09 张取自 `c9f77c8b` 的 run `35995691654`（artifact `10805899711`，ZIP SHA-256 `52ec878cb7347baad9bab63ff56be0b40873457ede2df5e63d932e0791718bfe`）；其余 16 张取自 `4e80b06e` 的 run `35994273332`（artifact `10805742699`，SHA-256 见上文）。两个提交的应用源码、资源、包和工程配置完全相同，只有截图测试不同。每张新版图片附原始运行出处，文件复制后逐张核对 SHA-256，未修改图片像素。
- 人工核对覆盖四个主页面、空资料库及菜单、示例资料库、记录字段、完整脉冲图、离线红外禁用原因、中文指南、深色大字及记录预选比较。空状态按钮、大字号换行、比较字段颜色与工具栏图标均使用修正后的应用实现。VoiceOver、其他设备尺寸及 iOS 17 实际运行没有在本轮验证。

本地展示页面支持新版/上一版原图切换；17 张手机图片来自模拟器原始附件，未改绘。Flipper 区域提供三张入口示例及全部 65 个源码布局画面的链接，始终明确标注不是设备运行截图。

## 验证边界

模拟器可以验证编译、离线流程和布局。真实 iPhone 与 Flipper 的配对、传输、红外执行和真机显示仍需硬件验证。Flipper 中文小屏展示继续标注为源码布局预览；这轮手机样式调整不表示 Flipper 全部原生应用已完成中文重写。
