import SwiftUI
import UniformTypeIdentifiers
import FlipperCore

@MainActor struct SerialBridgeView: View {
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var port: UInt8 = 0
    @State private var baud: UInt32 = 115200
    @State private var exporting = false
    @State private var exportError: String?

    var body: some View {
        List {
            Section {
                Picker("串口", selection: $port) {
                    Text("USART").tag(UInt8(0))
                    Text("LPUART").tag(UInt8(1))
                }
                Picker("波特率", selection: $baud) {
                    ForEach(SerialBridge.baudRates, id: \.self) { Text(String($0)).tag($0) }
                }
            } header: { SectionHeader("连接设置") }
              footer: { Text("端口、波特率和板卡供电需与实物一致。接收功能不会自动刷写或识别板卡固件。") }
              .disabled(model.busy)
            Section {
                if model.serialRunning {
                    Button("停止接收", role: .destructive) { model.stopSerial() }
                        .accessibilityIdentifier("serial.stop")
                } else {
                    Button("开始接收") { model.startSerial(port: port, baud: baud) }
                        .disabled(!model.device.ready || model.busy)
                        .accessibilityIdentifier("serial.start")
                }
                if !model.device.ready { Text("请先在设备页连接 Flipper。").foregroundStyle(.secondary) }
                LabeledContent("已接收", value: "\(model.serialCapture.receivedBytes) 字节")
                LabeledContent("设备缓冲丢失", value: "\(model.serialCapture.deviceDroppedBytes) 字节")
                LabeledContent("手机日志截断", value: "\(model.serialCapture.trimmedBytes) 字节")
                Button("导出原始数据") { exporting = true }
                    .disabled(model.serialCapture.data.isEmpty || model.serialRunning)
            } header: { SectionHeader("实时接收") }
              footer: { Text("保留最近 64 KiB 原始数据，屏幕显示末尾 8 KiB。出现丢失或截断时，导出内容不是完整记录。") }
            Section {
                Text(model.serialCapture.data.isEmpty ? "等待扩展板输出…" : model.serialCapture.displayText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("serial.output")
            } header: { SectionHeader("串口输出") }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("扩展板实时数据")
        .onDisappear { model.stopSerial() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.stopSerial() } }
        .fileExporter(isPresented: $exporting, document: SerialDataDocument(data: model.serialCapture.data),
                      contentType: .data, defaultFilename: "Flipper-serial.bin") { result in
            if case .failure(let error) = result { exportError = error.localizedDescription }
        }
        .alert("导出失败", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("知道了") { exportError = nil }
        } message: { Text(exportError ?? "") }
    }
}

struct SerialDataDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
