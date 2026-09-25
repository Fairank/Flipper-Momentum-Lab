import SwiftUI
import FlipperCore

/// Browse a saved, passive Wi-Fi survey on the phone. Selection only changes local statistics.
@MainActor struct WiFiSurveyView: View {
    let rawText: String

    @State private var survey: WiFiSurvey?
    @State private var failure: String?
    @State private var search = ""
    @State private var selected: Set<String> = []

    private var visible: [WiFiAccessPoint] {
        guard let survey else { return [] }
        guard !search.isEmpty else { return survey.accessPoints }
        return survey.accessPoints.filter {
            ($0.ssid + $0.bssid + $0.security + String($0.channel))
                .localizedCaseInsensitiveContains(search)
        }
    }

    private var selectedPoints: [WiFiAccessPoint] {
        survey?.accessPoints.filter { selected.contains(identity($0)) } ?? []
    }

    var body: some View {
        List {
            if let failure {
                Section { ErrorRow(title: "无法读取扫描结果", message: failure) }
            } else if let survey {
                Section {
                    LabeledContent("记录来源", value: survey.source.title)
                    LabeledContent("发现的接入点", value: "\(survey.accessPoints.count)")
                    LabeledContent("不同网络名称", value: "\(survey.uniqueSSIDCount)")
                    if !selected.isEmpty {
                        LabeledContent("已标记用于比较", value: "\(selected.count)")
                        LabeledContent("涉及信道", value: selectedChannels)
                    }
                } header: {
                    SectionHeader("扫描概览")
                } footer: {
                    Text(survey.source == .marauderScanLog
                         ? "ESP32 日志未记录安全类型。标记网络仅用于手机本地比较。"
                         : "标记网络仅用于手机本地比较，不会连接网络或向扩展板发送指令。")
                }

                Section {
                    if visible.isEmpty {
                        ContentUnavailableView("没有匹配的网络", systemImage: "magnifyingglass")
                    } else {
                        ForEach(visible) { point in
                            networkRow(point)
                        }
                    }
                } header: {
                    SectionHeader("网络", count: "\(visible.count) 项")
                }
            } else {
                Section { BusyRow("正在整理扫描结果…") }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Wi-Fi 扫描")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $search, prompt: "名称、BSSID、信道")
        .task {
            do {
                let text = rawText
                survey = try await Task.detached(priority: .userInitiated) {
                    try WiFiSurvey.parse(text)
                }.value
                failure = nil
            } catch {
                survey = nil
                failure = error.localizedDescription
            }
        }
    }

    private var selectedChannels: String {
        let channels = Set(selectedPoints.map(\.channel)).sorted()
        return channels.map(String.init).joined(separator: "、")
    }

    private func identity(_ point: WiFiAccessPoint) -> String {
        point.bssid + ":\(point.channel)"
    }

    private func networkRow(_ point: WiFiAccessPoint) -> some View {
        let marked = selected.contains(identity(point))
        return Button {
            let key = identity(point)
            if marked { selected.remove(key) } else { selected.insert(key) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                SymbolTile(systemName: "wifi", size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: point.ssid.isEmpty ? "隐藏网络" : point.ssid)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(verbatim: point.bssid)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text("信道 \(point.channel) · \(point.rssi) dBm · \(point.security)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if marked {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(LabColor.brandOrange)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(point.ssid.isEmpty ? "隐藏网络" : point.ssid)，\(point.bssid)，信道 \(point.channel)，\(point.rssi) dBm，\(point.security)")
        .accessibilityValue(marked ? "已标记" : "未标记")
        .accessibilityHint("双击切换本地比较标记")
    }
}
