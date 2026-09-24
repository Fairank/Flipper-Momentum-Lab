import SwiftUI
import FlipperCore

/// 编辑记录: native Form for data entry, themed with the warm palette (§5.6).
/// Save, cancel and dismissal rules are unchanged from before the redesign.
@MainActor struct EditRecordView: View {
    let model: AppModel
    @State var record: CaptureRecord
    @State private var tags = ""
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    private var nameIsEmpty: Bool {
        record.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("中文名称", text: $record.name)
                    .accessibilityIdentifier("edit.name")
                if nameIsEmpty {
                    ReasonNote("名称不能为空，填写后才能保存。")
                }
            } header: {
                PixelLabel("中文名称", spaced: false)
            }
            .listRowBackground(LabColor.surface)
            Section {
                TextField("标签，用逗号分隔", text: $tags)
                    .accessibilityIdentifier("edit.tags")
            } header: {
                PixelLabel("标签", spaced: false)
            }
            .listRowBackground(LabColor.surface)
            Section {
                TextEditor(text: $record.notes)
                    .frame(minHeight: 160)
                    .accessibilityLabel("备注")
                    .accessibilityIdentifier("edit.notes")
            } header: {
                PixelLabel("备注", spaced: false)
            } footer: {
                Text("只修改手机资料库里的名称与说明，保留原始采集数据。")
                    .labFootnote()
            }
            .listRowBackground(LabColor.surface)
        }
        .scrollContentBackground(.hidden)
        .background(LabColor.bg.ignoresSafeArea())
        .foregroundStyle(LabColor.ink)
        .labNavigation("编辑记录")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(saving && model.busy) }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    record.name = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    record.tags = tags.replacingOccurrences(of: "，", with: ",").split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    saving = true; model.saveRecord(record)
                }.disabled(model.busy || record.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear { tags = record.tags.joined(separator: ", ") }
        .onChange(of: model.busy) { _, busy in
            if saving && !busy {
                saving = false
                if model.error == nil { dismiss() }
            }
        }
        .interactiveDismissDisabled(saving && model.busy)
    }
}
