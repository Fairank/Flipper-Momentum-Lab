import SwiftUI
import UIKit
import FlipperCore

/// 设备: compact LCD status header with one main action per state, then grouped sections
/// (UI_APPLE_DESIGN.md §4). Every value shown comes from `FlipperDevice`; nothing is simulated.
@MainActor struct DeviceView: View {
    let model: AppModel
    @Environment(\.openURL) private var openURL
    @State private var browsing = false
    @State private var remoteControlling = false

    private var device: FlipperDevice { model.device }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    DeviceStatusHeader(state: device.state, deviceName: device.deviceName,
                                       protocolVersion: device.protocolVersion, explanation: explanation)
                    controls
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
            }
            if let error = device.lastError, device.state != .unavailable {
                Section {
                    ErrorRow(title: "连接出错", message: error) {
                        Button("知道了") { device.clearError() }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.large)
                            .accessibilityIdentifier("device.clearError")
                    }
                }
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
            Section {
                Text("个人项目，不是 Flipper Devices 的官方 App。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("设备")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(isPresented: $remoteControlling) {
            RemoteControlView(model: model)
        }
        .navigationDestination(isPresented: $browsing) {
            DeviceFilesView(model: model, path: "/ext")
        }
    }

    private var explanation: String {
        switch device.state {
        case .idle: return "搜索附近已开启蓝牙的 Flipper，每次搜索最长 15 秒。"
        case .scanning: return "请把 Flipper 放在手机旁边，15 秒后会自动停止。"
        case .connecting: return "首次配对时，在 iPhone 弹出的窗口中输入 Flipper 屏幕上的 6 位配对码；超过 45 秒未完成会自动断开。"
        case .discovering: return "正在准备连接…"
        case .negotiating: return "正在检查协议版本并读取设备信息。"
        case .ready: return "可以远程查看 Flipper 屏幕并发送按键，也可以浏览设备文件并导入记录；资料库中的记录可以上传到 Flipper。"
        case .unavailable: return device.lastError ?? "请开启 iPhone 蓝牙。"
        }
    }

    // MARK: Controls — one prominent action per state

    /// The status header already names the state, so no extra note repeats it; the busy
    /// reason appears once, under the actions, only while a task runs.
    private var controls: some View {
        VStack(spacing: 12) {
            switch device.state {
            case .idle:
                Button { device.scan() } label: {
                    PrimaryButtonLabel(title: "搜索附近的 Flipper", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(LabColor.brandOrange)
                .disabled(model.busy || device.state == .unavailable)
                .accessibilityIdentifier("device.scan")
            case .unavailable:
                Button { openSettings() } label: {
                    PrimaryButtonLabel(title: "打开 iPhone 设置", systemImage: "gear")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(LabColor.brandOrange)
                .accessibilityIdentifier("device.openSettings")
                Button { device.scan() } label: {
                    WideButtonLabel(title: "搜索附近的 Flipper", systemImage: "magnifyingglass")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(model.busy || device.state == .unavailable)
                .accessibilityIdentifier("device.scan")
            case .scanning:
                Button { device.disconnect() } label: {
                    WideButtonLabel(title: "停止搜索")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("device.stopScan")
            case .connecting, .discovering, .negotiating:
                Button(role: .destructive) { device.disconnect() } label: {
                    WideButtonLabel(title: "取消连接")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("device.cancelConnect")
            case .ready:
                // Remote control is the one prominent action once connected; the file
                // browser stays as the secondary button with its existing identifier.
                Button { remoteControlling = true } label: {
                    PrimaryButtonLabel(title: "远程操作 Flipper", systemImage: "dpad")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(LabColor.brandOrange)
                .disabled(model.busy)
                .accessibilityHint("查看已连接 Flipper 的屏幕并发送按键")
                .accessibilityIdentifier("device.remoteControl")
                Button { browsing = true } label: {
                    WideButtonLabel(title: "浏览设备文件", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(model.busy)
                .accessibilityIdentifier("device.browseFiles")
                Button(role: .destructive) { device.disconnect() } label: {
                    WideButtonLabel(title: "断开连接")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("device.disconnect")
            }
            if model.busy {
                ReasonNote("有任务正在进行，详情见“任务”页。")
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    // MARK: Sections

    private var nearbySection: some View {
        Section {
            if device.nearby.isEmpty {
                Text(device.state == .scanning ? "正在搜索，请将设备放在手机旁。" : "搜索后在这里选择设备。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(device.nearby.enumerated()), id: \.element.id) { index, item in
                    nearbyRow(item, index: index)
                }
            }
        } header: {
            SectionHeader("附近设备", count: device.nearby.isEmpty ? nil : "\(device.nearby.count) 台")
        }
    }

    private func nearbyRow(_ item: NearbyDevice, index: Int) -> some View {
        Button { device.connect(item) } label: {
            AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: 8) {
                Label(item.name, systemImage: "dot.radiowaves.left.and.right")
                Spacer(minLength: 8)
                Text(verbatim: "\(item.rssi) dBm")
                    .font(LabFont.mono)
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
        }
        .disabled(model.busy || (device.state != .scanning && device.state != .idle))
        .accessibilityLabel("\(item.name)，信号 \(item.rssi) dBm")
        .accessibilityHint("连接此设备")
        .accessibilityIdentifier("device.nearby.\(index)")
    }

    private var firstConnectionSection: some View {
        Section {
            StepRow(number: 1, text: "在 Flipper 设置中开启蓝牙。")
            StepRow(number: 2, text: "允许本应用使用 iPhone 蓝牙。")
            StepRow(number: 3, text: "选择设备，在 iPhone 输入 Flipper 屏幕上的配对码。")
            StepRow(number: 4, text: "等待“设备已就绪”后操作。")
        } header: {
            SectionHeader("首次连接")
        } footer: {
            Text("传输和分析时请保持应用在前台。")
        }
    }

    /// Keys exactly as the device reports them, sorted; values are selectable.
    private var infoSection: some View {
        Section {
            ForEach(device.info.keys.sorted(), id: \.self) { key in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: key)
                        .font(LabFont.mono)
                        .foregroundStyle(.secondary)
                    Text(verbatim: device.info[key] ?? "")
                        .textSelection(.enabled)
                }
            }
        } header: {
            SectionHeader("设备报告的信息", count: "\(device.info.count) 项")
        }
    }
}
