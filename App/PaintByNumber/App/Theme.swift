import SwiftUI
import UIKit

/// Shared visual language, the Pipo identity: parchment by day and violet night after dark,
/// raised surfaces, New York for titles and numerals, Nightshade and antique gold.
enum Theme {
    static let paper = Color("Paper")
    static let surface = Color("Surface")
    static let cardRadius: CGFloat = 22
    static let hairline = Color.primary.opacity(0.08)
    /// Text and symbol tint: Nightshade on parchment, antique gold at night (Nightshade
    /// would be too dark to read there).
    static let accent = Color("AccentColor")
    /// Nightshade in both appearances, under white labels: prominent buttons and badges.
    static let signature = Color(red: 0.482, green: 0.247, blue: 0.494)
    /// The antique gold of the identity's moon and sparkles.
    static let gold = Color(red: 0.788, green: 0.635, blue: 0.290)
    /// Line work of unpainted outlines.
    static let outline = Color(red: 0.431, green: 0.408, blue: 0.455)

    /// Navigation titles in New York, like the identity's headings.
    static func styleNavigationTitles() {
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: serifFont(.largeTitle, size: 34, weight: .bold)]
        bar.titleTextAttributes = [.font: serifFont(.headline, size: 17, weight: .semibold)]
    }

    /// `size` is the style's size at the default text size; the font scales from it.
    private static func serifFont(_ style: UIFont.TextStyle, size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let system = UIFont.systemFont(ofSize: size, weight: weight)
        let serif = system.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? system
        return UIFontMetrics(forTextStyle: style).scaledFont(for: serif)
    }
}

extension Font {
    /// New York (the system serif) at a Dynamic Type style: titles and numerals.
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        .system(style, design: .serif, weight: weight)
    }
}

/// The identity's four-point sparkle. `pinch` is how far the control points sit off the
/// centre, as a fraction of the half-size: 0 gives needle-thin arms.
nonisolated struct Sparkle: Shape {
    var pinch: CGFloat = 0.133

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let kx = rect.width / 2 * pinch, ky = rect.height / 2 * pinch
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: c.y), control: CGPoint(x: c.x + kx, y: c.y - ky))
        p.addQuadCurve(to: CGPoint(x: c.x, y: rect.maxY), control: CGPoint(x: c.x + kx, y: c.y + ky))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: c.y), control: CGPoint(x: c.x - kx, y: c.y + ky))
        p.addQuadCurve(to: CGPoint(x: c.x, y: rect.minY), control: CGPoint(x: c.x - kx, y: c.y - ky))
        p.closeSubpath()
        return p
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
