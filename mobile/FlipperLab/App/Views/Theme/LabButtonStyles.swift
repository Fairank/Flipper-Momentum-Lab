import SwiftUI

// Labels for the native button styles. Call sites apply `.borderedProminent` or `.bordered`
// with `.controlSize(.large)` themselves; these views only size and colour the label, so text
// wraps and grows with Dynamic Type instead of shrinking.

/// Full-width label for the one orange `.borderedProminent` action of a state. Enabled text is
/// #1C1917 on the orange fill; a disabled button keeps the system's own dimmed label and fill.
struct PrimaryButtonLabel: View {
    let title: String
    let systemImage: String
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        if isEnabled {
            label.foregroundStyle(LabColor.lcdInk)
        } else {
            label
        }
    }

    private var label: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

/// Full-width label for secondary and destructive `.bordered` buttons.
struct WideButtonLabel: View {
    let title: String
    var systemImage: String?

    var body: some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        } else {
            Text(title)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }
}
