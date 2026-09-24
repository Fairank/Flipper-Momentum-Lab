import SwiftUI

@main
@MainActor
struct FlipperLabApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .task { await model.load() }
                .tint(.orange)
        }
    }
}
