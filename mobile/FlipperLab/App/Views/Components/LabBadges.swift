import SwiftUI
import FlipperCore

/// Rounded SF Symbol tile. It grows with Dynamic Type (up to twice its size) so it keeps its
/// proportion to the text beside it. Decorative: the text next to it always names the item.
struct SymbolTile: View {
    let systemName: String
    var size: CGFloat = 30
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let side = size * min(scale, 2)
        Image(systemName: systemName)
            .font(.system(size: side * 0.5, weight: .semibold))
            .foregroundStyle(LabColor.accent)
            .frame(width: side, height: side)
            .background(LabColor.orangeSoft, in: RoundedRectangle(cornerRadius: side * 0.24, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct KindTile: View {
    let kind: RecordKind
    var size: CGFloat = 30

    var body: some View {
        SymbolTile(systemName: kind.labSymbolName, size: size)
    }
}

extension RecordKind {
    /// SF Symbol for the kind tile.
    var labSymbolName: String {
        switch self {
        case .infrared: return "av.remote"
        case .subGHz: return "antenna.radiowaves.left.and.right"
        case .nfc: return "creditcard"
        case .rfid: return "sensor.tag.radiowaves.forward"
        case .iButton: return "key"
        case .serial: return "terminal"
        }
    }
}

/// Analyser fact: title in secondary text, value selectable. Wording comes from the analyser.
struct FactRow: View {
    let fact: AnalysisFact

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(fact.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(fact.value)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Facts in one grouped row separated by hairlines, so they stay together as one
/// accessibility container and appear together when the list builds the row.
struct FactList: View {
    let facts: [AnalysisFact]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                if index > 0 {
                    Divider()
                }
                FactRow(fact: fact)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Numbered step: the number is plain secondary text; the row is spoken as one sentence.
struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: LabFormat.twoDigits(number))
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(number) 步：\(text)")
        .accessibilityAddTraits(.isStaticText)
    }
}

/// Static tag or status label on a capsule fill (not a button).
struct TagCapsule: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
    }
}

/// Horizontally scrolling kind filter: 全部 plus every RecordKind title, as 44 pt capsule
/// pills. The selected pill is orange with #1C1917 text and carries the selected trait.
struct KindFilterBar: View {
    @Binding var selection: RecordKind?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                pill("全部", identifier: "library.filter.all", selected: selection == nil) {
                    selection = nil
                }
                ForEach(RecordKind.allCases) { kind in
                    pill(kind.title, identifier: "library.filter.\(kind.rawValue)", selected: selection == kind) {
                        selection = kind
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder private func pill(_ title: String, identifier: String, selected: Bool,
                                   action: @escaping () -> Void) -> some View {
        if selected {
            Button(action: action) {
                Text(title)
                    .foregroundStyle(LabColor.lcdInk)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(LabColor.brandOrange)
            .accessibilityAddTraits(.isSelected)
            .accessibilityIdentifier(identifier)
        } else {
            Button(action: action) {
                Text(title)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(Color.secondary)
            .accessibilityIdentifier(identifier)
        }
    }
}
