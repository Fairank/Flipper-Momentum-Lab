import SwiftUI
import FlipperCore

/// Square icon tile. Decorative: the text next to it always names the item.
struct SymbolTile: View {
    let systemName: String
    var size: CGFloat = 44
    var fill: Color = LabColor.orangeSoft

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(LabColor.ink)
            .frame(width: size, height: size)
            .background(fill, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct KindTile: View {
    let kind: RecordKind
    var size: CGFloat = 44

    var body: some View {
        SymbolTile(systemName: kind.labSymbolName, size: size)
    }
}

extension RecordKind {
    /// SF Symbol for the kind tile (§2.5).
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

/// Two-digit number block for steps and index rows; the row supplies the spoken text.
struct NumberBox: View {
    let number: Int
    var size: CGFloat = 28
    var fill: Color = LabColor.orangeSoft

    var body: some View {
        Text(verbatim: LabFormat.twoDigits(number))
            .font(LabFont.monoCaption.weight(.semibold))
            .foregroundStyle(LabColor.ink)
            .padding(.horizontal, 4)
            .frame(minWidth: size, minHeight: size)
            .background(fill, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Task state badge; the text is the model's own state name.
struct StatusBadge: View {
    let state: TaskEntry.State

    var body: some View {
        Text(state.rawValue)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var foreground: Color {
        switch state {
        case .running: return LabColor.ink
        case .completed: return LabColor.okText
        case .failed: return LabColor.dangerText
        case .cancelled: return LabColor.inkSecondary
        }
    }

    private var background: Color {
        switch state {
        case .running: return LabColor.orangeSoft
        case .completed: return LabColor.okBg
        case .failed: return LabColor.dangerBg
        case .cancelled: return LabColor.surfaceAlt
        }
    }
}

/// Analyser fact: title in secondary ink, value selectable. Wording comes from the analyser.
struct FactRow: View {
    let fact: AnalysisFact

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(fact.title)
                .font(.caption)
                .foregroundStyle(LabColor.inkSecondary)
            Text(fact.value)
                .font(.body)
                .foregroundStyle(LabColor.ink)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Facts separated by hairlines, followed by the analyser's notes.
struct FactList: View {
    let facts: [AnalysisFact]
    var notes: [String] = []

    var body: some View {
        LabPanel(padded: false) {
            ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                if index > 0 {
                    LabDivider()
                }
                FactRow(fact: fact)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            if !notes.isEmpty {
                if !facts.isEmpty {
                    LabDivider()
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                        ReasonNote(note)
                    }
                }
                .padding(16)
            }
        }
    }
}

struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            NumberBox(number: number)
            Text(text)
                .font(.body)
                .foregroundStyle(LabColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(number) 步：\(text)")
        .accessibilityAddTraits(.isStaticText)
    }
}

struct BulletRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Rectangle()
                .fill(LabColor.ink)
                .frame(width: 6, height: 6)
                .alignmentGuide(.firstTextBaseline) { dimensions in dimensions[.bottom] + 3 }
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .foregroundStyle(LabColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Monospaced, selectable path strip.
struct PathStrip: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(LabFont.mono)
            .foregroundStyle(LabColor.ink)
            .textSelection(.enabled)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(LabColor.surfaceAlt, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// Static tag label (not a button).
struct TagChip: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.caption)
            .foregroundStyle(LabColor.inkSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(LabColor.surfaceAlt, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// Horizontally scrolling kind filter: 全部 plus every RecordKind title.
struct KindChipBar: View {
    @Binding var selection: RecordKind?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip("全部", identifier: "library.filter.all", selected: selection == nil) {
                    selection = nil
                }
                ForEach(RecordKind.allCases) { kind in
                    chip(kind.title, identifier: "library.filter.\(kind.rawValue)", selected: selection == kind) {
                        selection = kind
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -16)
    }

    private func chip(_ title: String, identifier: String, selected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(LabChipButtonStyle(selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}
