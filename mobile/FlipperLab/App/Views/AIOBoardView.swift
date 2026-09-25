import SwiftUI

/// Reference information for the user's board name; no live hardware state is inferred.
@MainActor struct AIOBoardView: View {
    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    SymbolTile(systemName: "cpu", size: 44)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AIO Board 1.4")
                            .font(.title3.weight(.semibold))
                        Text("已提供板卡名称，厂商和芯片丝印尚未核实。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }

            Section {
                LabeledContent("Wi-Fi", value: "ESP32 系列")
                LabeledContent("Sub-GHz", value: "CC1101")
                LabeledContent("2.4 GHz", value: "nRF24")
            } header: {
                SectionHeader("参考模块")
            } footer: {
                Text("同名板卡可能有不同批次。部分 AIO V1.4 资料写为 ESP32-S2；具体芯片以你的实物丝印为准。")
            }

            Section {
                Label("可导入已保存的 ESP32 接入点扫描日志", systemImage: "doc.text")
                Label("可在手机本地查看网络、信道与信号强度", systemImage: "chart.bar")
            } header: {
                SectionHeader("手机现有能力")
            } footer: {
                Text("这些功能读取已有文件，不代表手机已连上扩展板。")
            }

            Section {
                LabeledContent("板卡固件版本", value: "未读取")
                LabeledContent("Flipper 与板卡通信", value: "未真机验证")
                LabeledContent("手机实时接收", value: "未实现")
            } header: {
                SectionHeader("尚待验收")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("AIO Board 1.4")
        .navigationBarTitleDisplayMode(.large)
    }
}
