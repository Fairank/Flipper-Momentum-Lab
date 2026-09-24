# 验证记录与构建交接

记录日期：2026-09-24。这是源码交接状态，不是固件发布或真机可用性声明。

## 已完成的检查

| 检查 | 结果 | 能证明的范围 |
| --- | --- | --- |
| `python3 scripts/tests/test_unleashed_integration.py -v` | 3 个测试通过 | 源文件模式顺序、插件扫描及进度视图的桌面回归 |
| 修改过的 13 个 C/header 文件使用工具链 `clang-format --dry-run --Werror` | 通过 | 本批 C/header 格式 |
| Python 文件 Black 检查 | 通过 | 本批 Python 格式 |
| `git diff --check` | 通过 | 改动没有空白错误 |
| API CSV 与基线比较 | 4,675 个既有条目签名和状态不变，新增 4 个，无重复名称 | 导出表文本兼容性，不能代替应用运行 |

测试直接抽取生产实现中的函数并以桌面存储/绘图替身执行。没有验证真实 SD 卡、GUI 线程调度、板上内存和硬件行为。

## 已取得的构建环境

- 当前机器为 macOS arm64；官方工具链版本 39，GCC 12.3.1，编译器可运行。
- 主仓库基线及所有顶层子模块的固定版本见 [SOURCE_LOCK.json](SOURCE_LOCK.json)。没有改变原 gitlink 版本。
- `applications/external` 固定为 `55a446b1b01bf2a2f98161d704e62cc47075ad30`，本机目前仅稀疏检出 `subghz_playlist`、`subghz_remote`、`ir_remote`。
- FreeRTOS 的嵌套 community/partner ports 已取得。`lib/mbedtls/framework` 与 `lib/stm32wb_copro/scripts` 等嵌套依赖未全部初始化；不能声称递归依赖完整。
- 新电脑默认按 `HANDOFF.md` 初始化全部子模块；不需要复制 macOS 专用工具链或本机构建缓存。

## 最近一次完整记录的构建尝试

```sh
FBT_NO_SYNC=1 ./fbt SKIP_EXTERNAL=1 updater_package
```

退出码：2。关键错误：

```text
applications/main/archive/helpers/archive_files.c:4:10: fatal error:
applications/external/subghz_playlist/playlist_file.h: No such file or directory
scons: *** [build/f7-firmware-C/applications/main/archive/helpers/archive_files.o] Error 1
```

该文件还依赖 `subghz_remote/subghz_remote_app_i.h` 和 `ir_remote/infrared_remote.h`。随后已按固定提交补齐这三个目录，**补齐后尚未重新运行构建**，不排除后续还有其他错误。

`FBT_NO_SYNC=1` 用于旧机器分阶段取得依赖的情形。新机器应先正常同步依赖；不要在缺少依赖时直接照搬这个开关。

## 后续应补充的证据

1. 新机器操作系统/架构、项目提交号、子模块状态和工具链版本。
2. 核心构建和完整包构建各自的命令、退出码及关键错误或产物路径。
3. 成功包的文件名和 SHA-256；当前没有成功安装包可提供校验值。
4. 实际 Flipper 上的资源加载、主题、SD 错误、插件损坏、已有应用兼容结果。
5. ESP32/“WiFi 终结者”具体型号及测试记录；当前未进行该部分测试。

GitHub 上继承的工作流仍带上游发布假设和官方 API 版本一致性检查。个人定制 API 87.2 与该检查可能冲突；工作流尚未适配，不将其状态等同于此次桌面测试或完整固件验证。
