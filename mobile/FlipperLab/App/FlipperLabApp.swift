import SwiftUI

@main
@MainActor
struct FlipperLabApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .task { await model.load() }
                .tint(LabColor.orange)
                #if DEBUG
                .modifier(UITestPresentation(arguments: ProcessInfo.processInfo.arguments))
                #endif
        }
    }
}

#if DEBUG
/// DEBUG-only UI-test overrides for `-ui-testing-dark` and `-ui-testing-large-text`.
/// Without these launch arguments nothing is overridden: the app follows the user's
/// system appearance and Dynamic Type size.
private struct UITestPresentation: ViewModifier {
    let arguments: [String]

    @ViewBuilder func body(content: Content) -> some View {
        let scheme: ColorScheme? = arguments.contains("-ui-testing-dark") ? .dark : nil
        if arguments.contains("-ui-testing-large-text") {
            content
                .preferredColorScheme(scheme)
                .dynamicTypeSize(.accessibility3)
        } else {
            content
                .preferredColorScheme(scheme)
        }
    }
}
#endif
