import SwiftUI

/// A 44 pt circular Liquid Glass button with an SF Symbol. Uses the system glass button style:
/// interactive glass on a plain button's label swallows the tap, so the action never ran.
struct GlassIconButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    let action: () -> Void

    init(systemImage: String, label: LocalizedStringKey, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.action = action
    }

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            GlassIconLabel(systemImage: systemImage)
                .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(Text(label))
        .accessibilityShowsLargeContentViewer { Label(label, systemImage: systemImage) }
    }
}

/// The symbol inside a circular glass button; the style's padding brings it to 44 pt.
struct GlassIconLabel: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.primary)
            .frame(width: 30, height: 30)
    }
}
