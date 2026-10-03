import PaintCore
import SwiftUI

/// More › Palette › Arrange Colors: the painting's colors in a list to drag into any order,
/// which becomes its palette's Custom order. Sort By starts from one of the other orders.
struct PaletteArrangeSheet: View {
    let session: PaintingSession
    var onSave: ([Int]) -> Void

    @State private var order: [Int]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `order`: every color, as the palette shows them now.
    init(session: PaintingSession, order: [Int], onSave: @escaping ([Int]) -> Void) {
        self.session = session
        self.onSave = onSave
        _order = State(initialValue: order)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(order, id: \.self) { color in
                        row(color)
                    }
                    .onMove { order.move(fromOffsets: $0, toOffset: $1) }
                } footer: {
                    Text("Drag colors into the order you like. This painting’s palette keeps it as its Custom order.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .accessibilityIdentifier("palette-arrange-list")
            .navigationTitle("Arrange Colors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        onSave(order)
                        dismiss()
                    }
                    .accessibilityIdentifier("palette-arrange-done")
                }
                ToolbarItem(placement: .bottomBar) {
                    Menu {
                        ForEach(PaletteOrder.allCases.filter { $0 != .custom }) { preset in
                            Button(preset.name) {
                                withAnimation(reduceMotion ? nil : .snappy) {
                                    order = preset.arrange(
                                        order, palette: session.template.palette, remaining: session.remainingByColor,
                                        custom: nil)
                                }
                            }
                        }
                    } label: {
                        SwiftUI.Label("Sort By", systemImage: "arrow.up.arrow.down")
                    }
                    .accessibilityIdentifier("palette-arrange-sort")
                }
            }
        }
        .tint(Theme.accent)
    }

    private func row(_ color: Int) -> some View {
        let template = session.template
        let name = session.colorNames[color]
        let nickname = session.nickname(of: color)
        let darkInk = ColorScience.relativeLuminance(encoded: template.palette[color].rgb, space: template.colorSpace) > 0.36
        return HStack(spacing: 12) {
            Text(verbatim: "\(color + 1)")
                .font(.system(size: 14, weight: .bold, design: .serif))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .foregroundStyle(darkInk ? Color.black.opacity(0.75) : Color.white)
                .frame(width: 32, height: 32)
                .background(PaletteBar.paint(template, color), in: .circle)
                .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 1) {
                Text(nickname ?? ColorNameText.title(name))
                    .font(.body)
                if nickname != nil {
                    Text(ColorNameText.title(name))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if session.isColorComplete(color) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PaintSpeech.colorLabel(number: color + 1, name: name, nickname: nickname))
        .accessibilityIdentifier("palette-arrange-\(color + 1)")
    }
}

extension PaletteRows {
    var name: String {
        switch self {
        case .auto:
            String(localized: "palette.rows.auto", defaultValue: "Auto",
                   comment: "Palette Rows choice: as many rows as fit the screen (three on iPad, one on iPhone)")
        case .all:
            String(localized: "palette.rows.all", defaultValue: "All at Once",
                   comment: "Palette Rows choice: as many rows as it takes to show every color without scrolling")
        default:
            String(localized: "palette.rows.count", defaultValue: "\(rawValue) Rows",
                   comment: "Palette Rows choice: a fixed number of rows of swatches (columns beside a landscape iPad); the argument is the count")
        }
    }
}

extension PaletteOrder {
    var name: String {
        switch self {
        case .number:
            String(localized: "palette.order.number", defaultValue: "By Number",
                   comment: "Palette Order choice: swatches in the order of their numbers")
        case .rainbow:
            String(localized: "palette.order.rainbow", defaultValue: "Rainbow",
                   comment: "Palette Order choice: swatches by hue, red through violet, then grays")
        case .lightToDark:
            String(localized: "palette.order.lightToDark", defaultValue: "Light to Dark",
                   comment: "Palette Order choice: lightest paint first")
        case .darkToLight:
            String(localized: "palette.order.darkToLight", defaultValue: "Dark to Light",
                   comment: "Palette Order choice: darkest paint first")
        case .nearlyDone:
            String(localized: "palette.order.nearlyDone", defaultValue: "Nearly Done First",
                   comment: "Palette Order choice: colors with the fewest areas left to paint first")
        case .mostLeft:
            String(localized: "palette.order.mostLeft", defaultValue: "Most Left First",
                   comment: "Palette Order choice: colors with the most areas left to paint first")
        case .custom:
            String(localized: "palette.order.custom", defaultValue: "Custom",
                   comment: "Palette Order choice: the order the painter arranged for this painting by hand")
        }
    }
}
