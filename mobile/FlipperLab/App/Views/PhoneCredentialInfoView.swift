import SwiftUI
import FlipperCore

/// Explains the iPhone credential boundary for an imported card record. The record's type is
/// the only input; the app never claims an individual door system has been tested.
@MainActor struct PhoneCredentialInfoView: View {
    let kind: RecordKind
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Label("这份记录不能直接变成 iPhone 门禁卡", systemImage: "info.circle")
                    .font(.headline)
                    .foregroundStyle(LabColor.brandOrange)
                Text("从 Flipper 传到手机后，可以保存、查看和分析卡资料；这不等于 iPhone 能向门禁读卡器出示同一张卡。")
                    .font(.subheadline)
            }

            Section {
                Text(kind == .rfid
                     ? "这是 125 kHz 低频 RFID 记录。iPhone 的 NFC 不具备模拟这种低频卡的硬件，不能用这份文件直接刷门。"
                     : "这是 13.56 MHz NFC 记录。即使 Flipper 已读取卡片，普通 iPhone App 也不能把原始卡文件直接导入为可刷门的 NFC 凭证。")
                    .font(.body)
                    .textSelection(.enabled)
            } header: {
                SectionHeader(kind == .rfid ? "低频 RFID" : "NFC")
            }

            Section {
                Text("询问门禁管理员或发卡方：该系统是否正式支持 iPhone 数字门禁凭证，例如兼容的 Apple Wallet 员工证或住宅钥匙。")
                Text("如受支持，请按发行方的官方流程开通。Flipper 保存的文件不能代替发行方授权。")
                    .foregroundStyle(.secondary)
            } header: {
                SectionHeader("可行的下一步")
            } footer: {
                Text("这里没有模拟刷卡，也没有验证这套门禁系统的手机兼容性。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("iPhone 与门禁卡")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") { dismiss() }
            }
        }
    }
}
