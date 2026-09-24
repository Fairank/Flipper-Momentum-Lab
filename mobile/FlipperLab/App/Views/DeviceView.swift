import SwiftUI
import UIKit
import FlipperCore

/// 设备: hero device, live status, one main action, then content panels (UI_REDESIGN.md §5.1).
/// Every value shown comes from `FlipperDevice`; nothing is simulated.
@MainActor struct DeviceView: View {
    let model: AppModel
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var device: FlipperDevice { model.device }

    var body: some View {
        LabPage {
            DeviceHeroView(state: device.state, deviceName: device.deviceName,
                           protocolVersion: device.protocolVersion)
            if model.busy {
                LabPanel(.muted) {
                    Label("正在处理，详情见“任务”页。", systemImage: "hourglass")
                        .font(.subheadline)
                        .foregroundStyle(LabColor.inkSecondary)
                }
            }
            statusBlock
            controls
            if let error = device.lastError, device.state != .unavailable {
                connectionError(error)
            }
            if device.state == .idle || device.state == .scanning {
                nearbySection
            }
            if !device.ready {
                firstConnectionSection
            }
            if !device.info.isEmpty {
                infoSection
            }
            Text("个人项目，不是 Flipper Devices 的官方 App。")
                .labFootnote()
                .padding(.top, 12)
        }
        .labNavigation("设备")
    }

    // MARK: Status

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if device.ready {
                    Rectangle()
                        .fill(LabColor.ok)
                        .frame(width: 8, height: 8)
                        .alignmentGuide(.firstTextBaseline) { dimensions in dimensions[.bottom] + 4 }
                        .accessibilityHidden(true)
                }
                Text(device.state.rawValue)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(LabColor.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("device.status")
            }
            if device.ready {
                Text(verbatim: "\(device.deviceName) · 协议 \(device.protocolVersion)")
                    .font(LabFont.mono)
                    .foregroundStyle(LabColor.inkSecondary)
                    .textSelection(.enabled)
            }
            Text(explanation)
                .font(.subheadline)
                .foregroundStyle(LabColor.inkSecondary)
        }
        .padding(.top, 4)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: device.state)
    }

    private var explanation: String {
        switch device.state {
        case .idle: return "搜索附近已开启蓝牙的 Flipper，每次搜索最长 15 秒。"
        case .scanning: return "请把 Flipper 放在手机旁边，15 秒后会自动停止。"
        case .connecting: return "首次配对时，在 iPhone 弹出的窗口中输入 Flipper 屏幕上的 6 位配对码；超过 45 秒未完成会自动断开。"
        case .discovering: return "正在准备连接…"
        case .negotiating: return "正在检查协议版本并读取设备信息。"
        case .ready: return "可以浏览设备文件并导入记录；资料库中的记录可以上传到 Flipper。"
        case .unavailable: return device.lastError ?? "请开启 iPhone 蓝牙。"
        }
    }

    // MARK: Controls — one main action per state

    @ViewBuilder private var controls: some View {
        switch device.state {
        case .idle, .unavailable:
            scanControls
        case .scanning:
            LabProgressStrip("正在搜索…")
            Button("停止搜索") { device.disconnect() }
                .buttonStyle(.labSecondary)
                .accessibilityIdentifier("device.stopScan")
        case .connecting, .discovering, .negotiating:
            LabProgressStrip("正在连接…")
            Button("取消连接") { device.disconnect() }
                .buttonStyle(.labDestructive)
                .accessibilityIdentifier("device.cancelConnect")
        case .ready:
            readyControls
        }
    }

    @ViewBuilder private var scanControls: some View {
        Button { device.scan() } label: {
            Label("搜索附近的 Flipper", systemImage: "magnifyingglass")
        }
        .buttonStyle(.labPrimary)
        .disabled(model.busy || device.state == .unavailable)
        .accessibilityIdentifier("device.scan")
        if device.state == .unavailable {
            ReasonNote("蓝牙不可用，暂时不能搜索。")
            Button { openSettings() } label: {
                Label("打开 iPhone 设置", systemImage: "gear")
            }
            .buttonStyle(.labSecondary)
            .accessibilityIdentifier("device.openSettings")
        } else if model.busy {
            ReasonNote("有任务正在进行。")
        }
    }

    @ViewBuilder private var readyControls: some View {
        NavigationLink { DeviceFilesView(model: model, path: "/ext") } label: {
            HStack(spacing: 8) {
                Text("浏览设备文件")
                Image(systemName: "chevron.right")
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.labPrimary)
        .disabled(model.busy)
        .accessibilityIdentifier("device.browseFiles")
        if model.busy {
            ReasonNote("有任务正在进行。")
        }
        Button("断开连接") { device.disconnect() }
            .buttonStyle(.labDestructive)
            .accessibilityIdentifier("device.disconnect")
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func connectionError(_ message: String) -> some View {
        ErrorPanel(title: "连接出错", message: message) {
            Button("知道了") { device.clearError() }
                .buttonStyle(.labCompact)
                .accessibilityIdentifier("device.clearError")
        }
    }

    // MARK: Panels

    @ViewBuilder private var nearbySection: some View {
        PixelLabel("附近设备", meta: device.nearby.isEmpty ? nil : "\(device.nearby.count) 台")
        LabPanel(padded: false) {
            if device.nearby.isEmpty {
                Text(device.state == .scanning ? "正在搜索，请将设备放在手机旁。" : "搜索后在这里选择设备。")
                    .font(.subheadline)
                    .foregroundStyle(LabColor.inkSecondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(device.nearby.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        LabDivider()
                    }
                    nearbyRow(item, index: index)
                }
            }
        }
    }

    private func nearbyRow(_ item: NearbyDevice, index: Int) -> some View {
        Button { device.connect(item) } label: {
            HStack(spacing: 12) {
                SymbolTile(systemName: "dot.radiowaves.left.and.right", size: 36)
                Text(verbatim: item.name)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Text(verbatim: "\(item.rssi) dBm")
                    .font(LabFont.mono)
                    .foregroundStyle(LabColor.inkSecondary)
                LabChevron()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.labRow)
        .disabled(model.busy || (device.state != .scanning && device.state != .idle))
        .accessibilityLabel("\(item.name)，信号 \(item.rssi) dBm")
        .accessibilityHint("连接此设备")
        .accessibilityIdentifier("device.nearby.\(index)")
    }

    @ViewBuilder private var firstConnectionSection: some View {
        PixelLabel("首次连接")
        LabPanel {
            StepRow(number: 1, text: "在 Flipper 设置中开启蓝牙。")
            StepRow(number: 2, text: "允许本应用使用 iPhone 蓝牙。")
            StepRow(number: 3, text: "选择设备，在 iPhone 输入 Flipper 屏幕上的配对码。")
            StepRow(number: 4, text: "等待“设备已就绪”后操作。")
            Text("传输和分析时请保持应用在前台。")
                .labFootnote()
        }
    }

    /// Keys exactly as the device reports them, sorted; values are selectable.
    @ViewBuilder private var infoSection: some View {
        PixelLabel("设备报告的信息", meta: "\(device.info.count) 项")
        LabPanel(padded: false) {
            ForEach(Array(device.info.keys.sorted().enumerated()), id: \.element) { index, key in
                if index > 0 {
                    LabDivider()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: key)
                        .font(LabFont.monoCaption)
                        .foregroundStyle(LabColor.inkSecondary)
                    Text(verbatim: device.info[key] ?? "")
                        .font(.body)
                        .foregroundStyle(LabColor.ink)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
