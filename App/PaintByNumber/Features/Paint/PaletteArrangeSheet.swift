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
        return HStack(spacing: 12) {
            Text(verbatim: "\(color + 1)")
                .font(.system(size: 14, weight: .bold, design: .serif))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .foregroundStyle(PaletteBar.numeralInk(template, color))
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
