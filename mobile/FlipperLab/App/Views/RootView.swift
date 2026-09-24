import SwiftUI
import FlipperCore

/// Shell only: five native tabs, each with its own navigation stack, the Chinese locale
/// and the shared alert that surfaces `model.error`.
@MainActor struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            NavigationStack { DeviceView(model: model) }
                .tabItem { Label("设备", systemImage: "antenna.radiowaves.left.and.right") }
                .labTabChrome()
            NavigationStack { ToolsView(model: model) }
                .tabItem { Label("工具", systemImage: "waveform.path") }
                .labTabChrome()
            NavigationStack { LibraryView(model: model) }
                .tabItem { Label("资料库", systemImage: "square.stack.3d.up") }
                .labTabChrome()
            NavigationStack { TasksView(model: model) }
                .tabItem { Label("任务", systemImage: "checklist") }
                .labTabChrome()
            NavigationStack { GuidesView(model: model) }
                .tabItem { Label("指南", systemImage: "book.closed") }
                .labTabChrome()
        }
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .alert("操作提示", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("知道了") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}
