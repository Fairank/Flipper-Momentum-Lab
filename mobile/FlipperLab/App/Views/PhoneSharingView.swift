import SwiftUI

@MainActor struct PhoneSharingView: View {
    let companion: PhoneCompanion

    var body: some View {
        List {
            Section {
                Label("让 Flipper 使用手机的定位与网络", systemImage: "iphone.radiowaves.left.and.right")
                    .font(.headline)
                Text(companion.connected ? "共享仅用于当前连接，退出到后台或断开蓝牙会自动关闭。" : "先在“设备”页连接 Flipper，再开启需要的能力。")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(isOn: Binding(get: { companion.locationEnabled }, set: companion.setLocationEnabled)) {
                    Label("共享手机定位", systemImage: "location")
                }
                .disabled(!companion.connected)
                .accessibilityIdentifier("sharing.location")
                Text(companion.locationStatus).font(.footnote).foregroundStyle(.secondary)
            } header: { Text("定位") } footer: {
                Text("设备应用可请求经纬度、速度、方向、高度与定位精度。只在使用 App 时访问位置；卫星数量无法从 iPhone 获取。")
            }
            Section {
                Toggle(isOn: Binding(get: { companion.networkEnabled }, set: companion.setNetworkEnabled)) {
                    Label("共享手机网络", systemImage: "network")
                }
                .disabled(!companion.connected)
                .accessibilityIdentifier("sharing.network")
                Text(companion.networkStatus).font(.footnote).foregroundStyle(.secondary)
                if companion.networkEnabled {
                    LabeledContent("活动连接", value: "\(companion.connectionCount)")
                    LabeledContent("收到数据", value: ByteCountFormatter.string(fromByteCount: Int64(companion.receivedBytes), countStyle: .file))
                    LabeledContent("发出数据", value: ByteCountFormatter.string(fromByteCount: Int64(companion.sentBytes), countStyle: .file))
                    if let endpoint = companion.lastEndpoint {
                        LabeledContent("最近服务器", value: endpoint).textSelection(.enabled)
                    }
                }
            } header: { Text("网络") } footer: {
                Text("设备应用通过 iPhone 的 Wi-Fi 或蜂窝网络访问服务器，可能消耗流量。支持 HTTPS、WebSocket、TCP 和 UDP；同时最多 4 个连接及 2 个网页请求。HTTP 与未加密 WebSocket 受 iOS 连接保护限制。")
            }
            Section {
                Label("单个网页请求或文件最多 2 MB", systemImage: "doc")
                Text("设备请求的文件只读写 SD 卡 apps_data 下的应用目录。写入后会校验内容；取消或断开时，未写完的文件需要重新下载。")
                    .foregroundStyle(.secondary)
                Text("需要本项目支持手机共享的固件与应用。开启开关不会自动请求位置、扫描 Wi-Fi 或连接服务器。")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("文件与兼容性") }
        }
        .navigationTitle("手机能力共享")
        .navigationBarTitleDisplayMode(.inline)
        .tint(LabColor.brandOrange)
    }
}
