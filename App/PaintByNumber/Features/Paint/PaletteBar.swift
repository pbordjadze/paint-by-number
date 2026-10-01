import PaintCore
import SwiftUI
import TipKit

/// Swatch geometry at a Dynamic Type size. Numerals grow with text up to 1.4×, so the palette
/// keeps its place on screen at accessibility sizes; the Large Content Viewer covers the rest.
/// At the default size every value equals the original fixed layout.
nonisolated struct PaletteMetrics: Equatable, Sendable {
    let scale: CGFloat

    init(scale: CGFloat) { self.scale = scale }

    init(dynamicTypeSize: DynamicTypeSize) {
        let steps: [(DynamicTypeSize, CGFloat)] = [
            (.xLarge, 1.08), (.xxLarge, 1.16), (.xxxLarge, 1.24), (.accessibility1, 1.32), (.accessibility2, 1.4),
        ]
        scale = steps.last(where: { $0.0 <= dynamicTypeSize })?.1 ?? 1
    }

    static let standard = PaletteMetrics(scale: 1)
    static let spacing: CGFloat = 8
    static let padding: CGFloat = 14
    static let endPadding: CGFloat = 16

    var diameter: CGFloat { 40 * scale }
    /// Distance between neighbouring swatch centres.
    var pitch: CGFloat { diameter + 16 }
    var numeralSize: CGFloat { 16 * scale }
    var checkmarkSize: CGFloat { 15 * scale }
    var captionFontSize: CGFloat { 13 * scale }
    /// Height of the current-color caption row above the swatches (compact widths).
    var captionHeight: CGFloat { (24 * scale).rounded(.up) }

    /// Bar thickness across its axis.
    func thickness(lines: Int, caption: Bool) -> CGFloat {
        CGFloat(lines) * pitch - Self.spacing + 2 * Self.padding + (caption ? captionHeight : 0)
    }

    /// Bar length along its axis for `count` swatches in `lines` lines.
    func length(count: Int, lines: Int) -> CGFloat {
        CGFloat((count + lines - 1) / max(lines, 1)) * pitch - Self.spacing + 2 * Self.endPadding
    }

    /// The fewest lines (up to `maxLines`) that fit `count` swatches in `length` points.
    func lines(count: Int, length: CGFloat, maxLines: Int) -> Int {
        let perLine = max(1, Int((length - 2 * Self.endPadding + Self.spacing) / pitch))
        return min(max(1, maxLines), max(1, (count + perLine - 1) / perLine))
    }
}

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
    var metrics: PaletteMetrics = .standard
    /// Shows the selected color's number and name above the swatches, so the color can be
    /// told by name (horizontal bars only; wide layouts show it in the progress badge).
    var showsCurrentColor = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        session: PaintingSession, axis: Axis = .horizontal, lines: Int = 1, shakes: [Int: Int] = [:],
        tip: (any Tip)? = nil, metrics: PaletteMetrics = .standard, showsCurrentColor: Bool = false
    ) {
        self.session = session
        self.axis = axis
        self.lines = lines
        self.shakes = shakes
        self.tip = tip
        self.metrics = metrics
        self.showsCurrentColor = showsCurrentColor
    }

    /// Colors still to paint (plus the selected one): finished colors leave the palette.
    static func visibleColors(_ session: PaintingSession) -> [Int] {
        (0..<session.paletteCount).filter { !session.isColorComplete($0) || session.selectedColor == $0 }
    }

    /// The paint of palette color `index` as a SwiftUI color.
    static func paint(_ template: Template, _ index: Int) -> Color {
        let rgb = template.palette[index].rgb
        return Color(template.colorSpace == .displayP3 ? .displayP3 : .sRGB,
                     red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z))
    }

    var body: some View {
        let colors = Self.visibleColors(session)
        let count = max(colors.count, 1)
        let lineCount = max(1, min(lines, count))
        let columns = max(1, axis == .horizontal ? (count + lineCount - 1) / lineCount : lineCount)
        let caption = showsCurrentColor && axis == .horizontal
        let thickness = metrics.thickness(lines: lineCount, caption: caption)
        let radius = min(thickness / 2, 38)
        // A caption needs room for a long name even when few swatches are left.
        let minLength = caption ? 260 * metrics.scale : 0
        let transition: AnyTransition = reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity)
        VStack(spacing: 0) {
            if caption {
                CurrentColorLabel(session: session, font: .system(size: metrics.captionFontSize, weight: .semibold))
                    .frame(height: metrics.captionHeight - 8)
                    .padding(.top, 8)
                    .padding(.horizontal, PaletteMetrics.endPadding)
            }
            ScrollViewReader { proxy in
                ScrollView(axis == .horizontal ? .horizontal : .vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: PaletteMetrics.spacing) {
                        ForEach(Array(stride(from: 0, to: colors.count, by: columns)), id: \.self) { start in
                            HStack(spacing: PaletteMetrics.spacing) {
                                ForEach(colors[start..<min(start + columns, colors.count)], id: \.self) { index in
                                    swatch(index).id(index)
                                        .transition(transition)
                                }
                            }
                        }
                    }
                    .padding(axis == .horizontal ? .horizontal : .vertical, PaletteMetrics.endPadding)
                    .padding(axis == .horizontal ? .vertical : .horizontal, PaletteMetrics.padding)
                    .frame(minWidth: minLength, alignment: .center)
                }
                .onAppear {
                    if let selected = session.selectedColor { proxy.scrollTo(selected, anchor: .center) }
                }
                .onChange(of: session.selectedColor) { _, selected in
                    guard let selected else { return }
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) { proxy.scrollTo(selected, anchor: .center) }
                }
            }
        }
        .frame(width: axis == .vertical ? thickness : nil,
               height: axis == .horizontal ? thickness : nil)
        .frame(maxWidth: axis == .horizontal ? max(metrics.length(count: count, lines: lineCount), minLength) : nil,
               maxHeight: axis == .vertical ? metrics.length(count: count, lines: lineCount) : nil)
        .clipShape(.rect(cornerRadius: radius))
        .glassEffect(.regular, in: .rect(cornerRadius: radius))
        .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: colors)
    }

    private func swatch(_ index: Int) -> some View {
        let template = session.template
        let total = session.totalByColor[index]
        let painted = total - session.remainingByColor[index]
        let fraction = 1 - Double(session.remainingByColor[index]) / Double(max(total, 1))
        let complete = session.isColorComplete(index)
        let selected = session.selectedColor == index
        let darkInk = ColorScience.relativeLuminance(encoded: template.palette[index].rgb, space: template.colorSpace) > 0.36
        let name = session.colorNames[index]
        return Button {
            if selected {
                session.showHint()
            } else {
                session.select(color: index)
                FeedbackEngine.shared.selectionChanged()
            }
        } label: {
            Swatch(
                number: index + 1, color: Self.paint(template, index), darkInk: darkInk, fraction: fraction,
                isComplete: complete, isSelected: selected, metrics: metrics, reduceMotion: reduceMotion)
                .modifier(Shake(amount: CGFloat(shakes[index] ?? 0)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PaintSpeech.colorLabel(number: index + 1, name: name))
        .accessibilityValue(PaintSpeech.colorProgress(painted: painted, total: total))
        .accessibilityHint(PaintSpeech.swatchHint(selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
        // Over a bottom bar, beside a trailing one.
        .popoverTip(selected ? tip : nil, arrowEdge: axis == .horizontal ? .bottom : .trailing)
        .accessibilityIdentifier("swatch-\(index + 1)")
        .accessibilityShowsLargeContentViewer {
            Text(verbatim: "\(index + 1) · \(ColorNameText.title(name))")
        }
    }
}

/// The selected color's number, paint and name ("12 · Dark green"), for people who can't tell
/// the paints apart by eye. Renders nothing when no color is selected.
struct CurrentColorLabel: View {
    let session: PaintingSession
    let font: Font

    var body: some View {
        if let color = session.selectedColor {
            let name = session.colorNames[color]
            HStack(spacing: 6) {
                Circle()
                    .fill(PaletteBar.paint(session.template, color))
                    .frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                Text(verbatim: "\(color + 1) · \(ColorNameText.title(name))")
                    .font(font)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "paint.currentColor", defaultValue: "Current color",
                                       comment: "VoiceOver label of the selected color's name shown on screen"))
            .accessibilityValue(PaintSpeech.colorLabel(number: color + 1, name: name))
            .accessibilityIdentifier("current-color")
        }
    }
}

private struct Swatch: View {
    let number: Int
    let color: Color
    let darkInk: Bool
    let fraction: Double
    let isComplete: Bool
    let isSelected: Bool
    let metrics: PaletteMetrics
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Circle().fill(color)
            Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5)
            if isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: metrics.checkmarkSize, weight: .heavy))
            } else {
                Text(verbatim: "\(number)")
                    .font(.system(size: metrics.numeralSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .foregroundStyle(darkInk ? Color.black.opacity(0.75) : Color.white)
        .frame(width: metrics.diameter, height: metrics.diameter)
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
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.6), value: isSelected)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: fraction)
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
