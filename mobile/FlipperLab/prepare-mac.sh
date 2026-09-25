#!/bin/sh
# Prepare the Flipper Lab iPhone project on a Mac.
#
# Run from the repository root:   sh mobile/FlipperLab/prepare-mac.sh
#
# What it does: checks for a full Xcode and for XcodeGen, generates FlipperLab.xcodeproj
# with XcodeGen, opens it in that same Xcode, and prints the manual signing steps.
# What it never does: install tools, sign in to an Apple ID, change signing settings,
# read or store secrets, export an IPA, or run Git. Signing and the install onto the
# iPhone are done by hand in Xcode (see README.zh-CN.md, section 4).
set -eu

fail() {
    printf '%s\n' "$@" >&2
    exit 1
}

if [ "$(uname -s 2>/dev/null || true)" != "Darwin" ]; then
    fail '请在 Mac 上运行此脚本；Windows 或 Linux 无法生成、编译或签名 iPhone App。'
fi

# Resolve the script directory (mobile/FlipperLab); quoting keeps paths with spaces intact.
script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd) || fail '无法进入脚本所在目录。'
spec="$script_dir/project.yml"
project="$script_dir/FlipperLab.xcodeproj"
pbxproj="$project/project.pbxproj"

if [ ! -f "$spec" ]; then
    fail "找不到 $spec" \
        '请下载完整的 GitHub 分支源码（Code → Download ZIP 或 git clone），不要只复制部分文件。'
fi

# A full Xcode.app must be selected; the Command Line Tools alone cannot build iPhone apps.
developer_dir=$(xcode-select -p 2>/dev/null || true)
case "$developer_dir" in
    */Contents/Developer) xcode_app=${developer_dir%/Contents/Developer} ;;
    *)
        fail "没有找到完整的 Xcode（当前 xcode-select 路径：${developer_dir:-无}）。" \
            '请从 App Store 安装 Xcode，打开一次完成首次设置，然后执行：' \
            '  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer'
        ;;
esac
if [ ! -d "$xcode_app" ]; then
    fail "xcode-select 指向的 $xcode_app 不存在。" \
        '请执行：sudo xcode-select -s /Applications/Xcode.app/Contents/Developer'
fi

printf 'macOS %s，Xcode：%s\n' "$(sw_vers -productVersion 2>/dev/null || echo '?')" "$xcode_app"
if ! xcodebuild -version; then
    fail '无法运行 xcodebuild。请打开一次 Xcode 完成首次设置并同意许可协议（或执行 sudo xcodebuild -license），然后重试。'
fi
if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null; then
    fail '找不到 iOS SDK，无法为 iPhone 编译。请确认 Xcode 已完成首次设置，并在 Xcode → Settings… → Components 中安装 iOS 平台。'
fi

if ! command -v xcodegen >/dev/null 2>&1; then
    fail '缺少 XcodeGen。请先安装 Homebrew（https://brew.sh），再执行：brew install xcodegen' \
        '本脚本不会自动安装任何工具。'
fi
printf 'XcodeGen：%s\n' "$(xcodegen --version 2>/dev/null || echo '未知版本')"

cd "$script_dir" || fail "无法进入 $script_dir"

before=
if [ -f "$pbxproj" ]; then
    before=$(cksum < "$pbxproj")
    printf '%s\n' '已有 FlipperLab.xcodeproj；XcodeGen 会在工程输入未变化时跳过重新生成，以保留你在 Xcode 中选择的 Team 和 Bundle ID。'
fi

# --use-cache keeps XcodeGen's cache under ~/.xcodegen/cache/ and skips regeneration while
# the project inputs are unchanged, so signing choices made in Xcode survive a plain
# re-run. When inputs change, XcodeGen may regenerate and reset those choices.
if ! xcodegen generate --spec "$spec" --use-cache; then
    fail 'XcodeGen 生成工程失败。请记录上面的完整输出。'
fi
# Guard against a cache hit after the project was deleted by hand.
if [ ! -f "$pbxproj" ]; then
    if ! xcodegen generate --spec "$spec"; then
        fail 'XcodeGen 生成工程失败。请记录上面的完整输出。'
    fi
fi
if [ ! -f "$pbxproj" ]; then
    fail "XcodeGen 没有生成 $project。"
fi

if [ -n "$before" ] && [ "$before" != "$(cksum < "$pbxproj")" ]; then
    printf '%s\n' '工程已重新生成：之前在 Xcode 的 Signing & Capabilities 中选择的 Team 和 Bundle ID 已被重置，请重新选择。'
fi

if ! open -a "$xcode_app" "$project"; then
    fail "无法自动打开工程。请在访达中双击打开：$project"
fi

cat <<'EOF'

已用 Xcode 打开 FlipperLab 工程。接下来在 Xcode 中手动完成（详见 mobile/FlipperLab/README.zh-CN.md 第 4 节）：
1. Xcode → Settings… → Accounts，登录自己的 Apple ID。
2. 左侧选中工程 FlipperLab，TARGETS 选 FlipperLab → Signing & Capabilities：
   保持 Automatically manage signing，Team 选自己的 Personal Team（免费 Apple ID）或开发者团队。
   如果提示 Bundle Identifier 已被占用，在同一页面改成自己唯一的标识。
3. 用数据线连接 iPhone，解锁并选择信任这台 Mac；在 iPhone 的 设置 → 隐私与安全性 → 开发者模式 中开启开发者模式。
4. 顶部运行目标选择你的 iPhone，按 Command-R（⌘R）安装并运行。
   如果 iPhone 提示“不受信任的开发者”，到 设置 → 通用 → VPN与设备管理 信任自己的证书后再打开。
普通（免费）Apple ID 的测试签名约 7 天到期，到期后 App 无法打开：再次执行本脚本并按 ⌘R 重新安装即可。
EOF
