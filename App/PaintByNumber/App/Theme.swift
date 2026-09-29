import SwiftUI
import UIKit

/// Shared visual language: warm gallery paper, raised surfaces, SF Rounded for display text.
enum Theme {
    static let paper = Color("Paper")
    static let surface = Color("Surface")
    static let cardRadius: CGFloat = 22
    static let hairline = Color.primary.opacity(0.08)

    /// Rounded large and inline navigation titles, app-wide.
    static func configureNavigationBar() {
        let appearance = UINavigationBar.appearance()
        if let large = rounded(.largeTitle, weight: .bold) {
            appearance.largeTitleTextAttributes = [.font: large]
        }
        if let inline = rounded(.headline, weight: .semibold) {
            appearance.titleTextAttributes = [.font: inline]
        }
    }

    private static func rounded(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont? {
        let base = UIFont.preferredFont(forTextStyle: style)
        let weighted = UIFont.systemFont(ofSize: base.pointSize, weight: weight)
        guard let descriptor = weighted.fontDescriptor.withDesign(.rounded) else { return nil }
        return UIFont(descriptor: descriptor, size: base.pointSize)
    }
}

extension Font {
    /// SF Rounded at a Dynamic Type style.
    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

/// A gentle press response for tappable cards.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Small circular progress indicator in the tint color.
struct ProgressRing: View {
    var fraction: Double
    var lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle().stroke(.tint.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(fraction, 1)))
                .stroke(.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }
}
