import SwiftUI
import FlipperCore

/// Shell only: five native tabs (设备 · 功能 · 资料库 · 任务 · 指南), each with its own navigation
/// stack, the Chinese locale and the shared alert that surfaces `model.error`. 功能 opens
/// Flipper applications over Bluetooth from a Chinese list on the phone; it never mirrors the
/// device screen. The system owns the tab bar material on every iOS version.
@MainActor struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            NavigationStack { DeviceView(model: model) }
                .tabItem { Label("设备", systemImage: "antenna.radiowaves.left.and.right") }
            NavigationStack { FunctionsView(model: model) }
                .tabItem { Label("功能", systemImage: "square.grid.2x2") }
            NavigationStack { LibraryView(model: model) }
                .tabItem { Label("资料库", systemImage: "square.stack.3d.up") }
            NavigationStack { TasksView(model: model) }
                .tabItem { Label("任务", systemImage: "checklist") }
            NavigationStack { GuidesView(model: model) }
                .tabItem { Label("指南", systemImage: "book.closed") }
        }
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .alert("操作提示", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("知道了") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}
