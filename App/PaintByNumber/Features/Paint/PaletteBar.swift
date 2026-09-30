import PaintCore
import SwiftUI
import TipKit

/// The paint palette: circular swatches with their number and a progress ring per color;
/// finished colors leave it. Swatches wrap into up to `lines` rows (columns when vertical)
/// in palette order, and scroll when they still don't fit; the selected color is kept in view.
struct PaletteBar: View {
    let session: PaintingSession
    var axis: Axis = .horizontal
    /// Rows of a horizontal bar, columns of a vertical one.
    var lines = 1
    /// Per color, bumped to shake its swatch (e.g. after tapping a region of that color).
    var shakes: [Int: Int] = [:]
    /// A tip about the selected color, shown from its swatch.
    var tip: (any Tip)? = nil

    static let swatchPitch: CGFloat = 56
    private static let spacing: CGFloat = 8
    private static let padding: CGFloat = 14
    private static let endPadding: CGFloat = 16

    /// Bar thickness across its axis.
    static func thickness(lines: Int) -> CGFloat { CGFloat(lines) * swatchPitch - spacing + 2 * padding }
    static var thickness: CGFloat { thickness(lines: 1) }

    /// Bar length along its axis for `count` swatches in `lines` lines.
    static func length(count: Int, lines: Int) -> CGFloat {
        CGFloat((count + lines - 1) / max(lines, 1)) * swatchPitch - spacing + 2 * endPadding
    }

    /// The fewest lines (up to `maxLines`) that fit `count` swatches in `length` points.
    static func lines(count: Int, length: CGFloat, maxLines: Int) -> Int {
        let perLine = max(1, Int((length - 2 * endPadding + spacing) / swatchPitch))
        return min(max(1, maxLines), max(1, (count + perLine - 1) / perLine))
    }

    /// Colors still to paint (plus the selected one): finished colors leave the palette.
    static func visibleColors(_ session: PaintingSession) -> [Int] {
        (0..<session.paletteCount).filter { !session.isColorComplete($0) || session.selectedColor == $0 }
    }

    var body: some View {
        let colors = Self.visibleColors(session)
        let count = max(colors.count, 1)
        let lineCount = max(1, min(lines, count))
        let columns = max(1, axis == .horizontal ? (count + lineCount - 1) / lineCount : lineCount)
        let radius = min(Self.thickness(lines: lineCount) / 2, 38)
        ScrollViewReader { proxy in
            ScrollView(axis == .horizontal ? .horizontal : .vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Self.spacing) {
                    ForEach(Array(stride(from: 0, to: colors.count, by: columns)), id: \.self) { start in
                        HStack(spacing: Self.spacing) {
                            ForEach(colors[start..<min(start + columns, colors.count)], id: \.self) { index in
                                swatch(index).id(index)
                                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                            }
                        }
                    }
                }
                .padding(axis == .horizontal ? .horizontal : .vertical, Self.endPadding)
                .padding(axis == .horizontal ? .vertical : .horizontal, Self.padding)
            }
            .onAppear {
                if let selected = session.selectedColor { proxy.scrollTo(selected, anchor: .center) }
            }
            .onChange(of: session.selectedColor) { _, selected in
                guard let selected else { return }
                withAnimation(.smooth(duration: 0.35)) { proxy.scrollTo(selected, anchor: .center) }
            }
        }
        .frame(width: axis == .vertical ? Self.thickness(lines: lineCount) : nil,
               height: axis == .horizontal ? Self.thickness(lines: lineCount) : nil)
        .frame(maxWidth: axis == .horizontal ? Self.length(count: count, lines: lineCount) : nil,
               maxHeight: axis == .vertical ? Self.length(count: count, lines: lineCount) : nil)
        .clipShape(.rect(cornerRadius: radius))
        .glassEffect(.regular, in: .rect(cornerRadius: radius))
        .animation(.snappy(duration: 0.35), value: colors)
    }

    private func swatch(_ index: Int) -> some View {
        let template = session.template
        let paint = template.palette[index].rgb
        let total = max(session.totalByColor[index], 1)
        let fraction = 1 - Double(session.remainingByColor[index]) / Double(total)
        let complete = session.isColorComplete(index)
        let selected = session.selectedColor == index
        let darkInk = ColorScience.relativeLuminance(encoded: paint, space: template.colorSpace) > 0.36
        return Button {
            if selected {
                session.showHint()
            } else {
                session.select(color: index)
                FeedbackEngine.shared.selectionChanged()
            }
        } label: {
            Swatch(
                number: index + 1,
                color: Color(template.colorSpace == .displayP3 ? .displayP3 : .sRGB,
                             red: Double(paint.x), green: Double(paint.y), blue: Double(paint.z)),
                darkInk: darkInk, fraction: fraction, isComplete: complete, isSelected: selected)
                .modifier(Shake(amount: CGFloat(shakes[index] ?? 0)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Color \(index + 1)"))
        .accessibilityValue(Text(complete ? "Complete" : "\(Int(fraction * 100)) percent painted"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        // Over a bottom bar, beside a trailing one.
        .popoverTip(selected ? tip : nil, arrowEdge: axis == .horizontal ? .bottom : .trailing)
    }
}

private struct Swatch: View {
    let number: Int
    let color: Color
    let darkInk: Bool
    let fraction: Double
    let isComplete: Bool
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle().fill(color)
            Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5)
            if isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .heavy))
            } else {
                Text("\(number)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(darkInk ? Color.black.opacity(0.75) : Color.white)
        .frame(width: 40, height: 40)
        .padding(4)
        .overlay {
            Circle()
                .stroke(Color.primary.opacity(isSelected ? 0.16 : 0.08), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.primary.opacity(isSelected ? 0.85 : 0.4), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .opacity(isComplete && !isSelected ? 0.4 : 1)
        .scaleEffect(isSelected ? 1.14 : 1)
        .animation(.spring(response: 0.32, dampingFraction: 0.6), value: isSelected)
        .animation(.easeOut(duration: 0.35), value: fraction)
        .contentShape(.circle)
    }
}

/// A short horizontal shake; animate `amount` by +1 to play it once.
nonisolated private struct Shake: GeometryEffect {
    var amount: CGFloat

    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 5 * sin(amount * .pi * 4), y: 0))
    }
}
