import SwiftUI

/// Shown when the gallery is empty: an invitation to make the first painting.
struct EmptyGalleryView: View {
    var onCreate: () -> Void

    var body: some View {
        VStack(spacing: 34) {
            NightSketch()
                .frame(width: 270, height: 198)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("Every painting starts with a photo")
                    .font(.display(.title))
                Text("Turn any photo into a numbered canvas, then bring it to life one color at a time.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .containerRelativeFrame(.horizontal) { length, _ in max(0, min(length - 64, 400)) }

            Button(action: onCreate) {
                Label("New Painting", systemImage: "plus")
                    .font(.headline)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.signature)
            .controlSize(.large)
        }
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// An unpainted night landscape, outlines and numbers only: moon, stars, mountains, a lake.
private struct NightSketch: View {
    /// The drawing's own coordinate space.
    private static let size = CGSize(width: 300, height: 220)

    var body: some View {
        let outline = Theme.outline, gold = Theme.gold, moon = Self.moon
        Canvas { context, size in
            let s = min(size.width / Self.size.width, size.height / Self.size.height)
            context.scaleBy(x: s, y: s)
            let line = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)

            context.stroke(Path(roundedRect: CGRect(x: 1, y: 1, width: 298, height: 218), cornerRadius: 14),
                           with: .color(outline), style: line)
            context.stroke(moon, with: .color(gold), style: line)
            for star in [CGRect(x: 50, y: 30, width: 20, height: 20), CGRect(x: 144, y: 56, width: 12, height: 12)] {
                context.stroke(Sparkle(pinch: 0).path(in: star), with: .color(outline), style: line)
            }
            var mountains = Path()
            mountains.addLines([CGPoint(x: 2, y: 140), CGPoint(x: 70, y: 70), CGPoint(x: 118, y: 118),
                                CGPoint(x: 170, y: 58), CGPoint(x: 240, y: 128), CGPoint(x: 298, y: 98)])
            context.stroke(mountains, with: .color(outline), style: line)
            var shore = Path()
            shore.move(to: CGPoint(x: 2, y: 172))
            shore.addCurve(to: CGPoint(x: 298, y: 168), control1: CGPoint(x: 80, y: 158), control2: CGPoint(x: 200, y: 162))
            context.stroke(shore, with: .color(outline), style: line)

            for (number, baseline) in [(1, CGPoint(x: 110, y: 40)), (4, CGPoint(x: 168, y: 130)), (2, CGPoint(x: 150, y: 202))] {
                let text = Text(verbatim: "\(number)")
                    .font(.system(size: 20, weight: .heavy, design: .serif))
                    .foregroundStyle(.secondary)
                context.draw(text, at: baseline, anchor: .bottom)
            }
        }
    }

    /// A crescent: the outer arc of one circle and the inner arc of a smaller, offset one.
    private static let moon: Path = {
        var p = Path()
        func arc(center: CGPoint, radius: CGFloat, from a0: Double, to a1: Double) {
            let steps = 40
            for k in 0...steps {
                let a = (a0 + (a1 - a0) * Double(k) / Double(steps)) * .pi / 180
                let point = CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
                if p.isEmpty { p.move(to: point) } else { p.addLine(to: point) }
            }
        }
        arc(center: CGPoint(x: 232.27, y: 59.73), radius: 26, from: -81.75, to: -326.7)
        arc(center: CGPoint(x: 238.68, y: 56.84), radius: 23, from: 48.24, to: 263.31)
        p.closeSubpath()
        return p
    }()
}
