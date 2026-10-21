import Foundation
import PaintCore
import SwiftUI

/// The Refine Toolbox's current paint: a color as on screen (OKLab), which the Bucket gives a cell
/// (`TemplateEditor.Edit.paintArea`, which lands it on the paint of that color, or adds it as a
/// paint of its own). Held as a color, not a number, so a color the painting has no paint for yet
/// (from the color picker or the photo) can be current; it follows its paint as edits change the
/// palette (`following`).
nonisolated enum RefinePalette {
    /// The paint of exactly `color`, as on screen.
    static func index(of color: SIMD3<Float>?, in palette: [PaletteColor]) -> Int? {
        guard let color else { return nil }
        return palette.firstIndex { $0.oklab == color }
    }

    /// `color`, or the paint within a just-noticeable difference of it (PaintCore's
    /// `SegmentationParameters.jnd`, the paintArea's own reach), which a Bucket tap would give.
    static func snapped(_ color: SIMD3<Float>, to palette: [PaletteColor]) -> SIMD3<Float> {
        let nearest = palette.min { ColorScience.distance($0.oklab, color) < ColorScience.distance($1.oklab, color) }
        guard let nearest, ColorScience.distance(nearest.oklab, color) <= justNoticeable else { return color }
        return nearest.oklab
    }

    /// A just-noticeable difference in OKLab.
    static let justNoticeable: Float = 0.02

    /// The current paint once the palette went from `before` to `after`: still its color when a
    /// paint has it, else the color of the paint of the same number when only colors changed (a
    /// look, a repaint), else the paint within a just-noticeable difference, else the color as it
    /// was (a paint not made yet). With none, the first paint.
    static func following(_ current: SIMD3<Float>?, from before: [PaletteColor]?, to after: [PaletteColor]) -> SIMD3<Float>? {
        guard let current else { return after.first?.oklab }
        if index(of: current, in: after) != nil { return current }
        if let before, before.count == after.count, let k = index(of: current, in: before) { return after[k].oklab }
        return snapped(current, to: after)
    }

    /// `lab` as a SwiftUI color, in the template's color space.
    static func color(_ lab: SIMD3<Float>, space: RGBColorSpace) -> Color {
        let rgb = ColorScience.okLabToEncoded(lab, space: space)
        return Color(space == .displayP3 ? .displayP3 : .sRGB, red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z))
    }
}

/// The painting's paints in a row, in Cells and Paint, the current one ringed; a color no paint
/// has yet shows after them, and the system color picker at the end picks any color as the
/// current paint.
struct RefinePaletteBar: View {
    let template: Template
    @Binding var current: SIMD3<Float>?

    @Environment(\.self) private var environment

    var body: some View {
        let selected = RefinePalette.index(of: current, in: template.palette)
        HStack(spacing: 10) {
            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(template.palette.indices, id: \.self) { index in
                            swatch(index, selected: selected == index).id(index)
                        }
                        if selected == nil, let current { newPaint(current) }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 3)
                }
                .scrollIndicators(.hidden)
                .onChange(of: selected) { _, index in
                    guard let index else { return }
                    withAnimation(.snappy) { reader.scrollTo(index) }
                }
            }
            ColorPicker(selection: picked, supportsOpacity: false) { Text("New Paint") }
                .labelsHidden()
                .accessibilityLabel(Text("New Paint"))
                .accessibilityHint(Text(String(
                    localized: "refine.palette.new.hint", defaultValue: "Picks any color as the current paint. The Bucket adds it to the painting.",
                    comment: "Refine screen, the palette: VoiceOver hint of the color picker at its end, which makes a color the current paint; the Bucket then adds it as a paint")))
                .accessibilityIdentifier("refine-palette-new")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .capsule)
        .frame(maxWidth: 720)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Palette"))
        .accessibilityIdentifier("refine-palette")
    }

    private func swatch(_ index: Int, selected: Bool) -> some View {
        Button {
            FeedbackEngine.shared.selectionChanged()
            current = template.palette[index].oklab
        } label: {
            Text(verbatim: "\(index + 1)")
                .font(.system(size: 12, weight: .bold, design: .serif))
                .monospacedDigit()
                .foregroundStyle(PaletteBar.numeralInk(template, index))
                .frame(width: 32, height: 32)
                .background(Circle().fill(PaletteBar.paint(template, index)))
                .overlay { Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5) }
                .padding(3)
                .overlay { Circle().stroke(selected ? Theme.signature : .clear, lineWidth: 2.5) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(ColorNameText.numbered(number: index + 1, name: template.palette[index].colorName)))
        .accessibilityHint(Text(String(
            localized: "refine.palette.paint.hint", defaultValue: "Makes this the current paint.",
            comment: "Refine screen, the palette: VoiceOver hint of a paint's swatch, which makes it the paint the Bucket gives and Edit Paint changes")))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("refine-paint-\(index + 1)")
    }

    /// The current color, which no paint has yet: ringed, with a plus, as the Bucket will add it.
    private func newPaint(_ color: SIMD3<Float>) -> some View {
        Image(systemName: "plus")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color.white)
            .shadow(color: .black.opacity(0.5), radius: 1)
            .frame(width: 32, height: 32)
            .background(Circle().fill(RefinePalette.color(color, space: template.colorSpace)))
            .overlay { Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5) }
            .padding(3)
            .overlay { Circle().stroke(Theme.signature, lineWidth: 2.5) }
            .accessibilityElement()
            .accessibilityLabel(Text("New Paint"))
            .accessibilityAddTraits(.isSelected)
            .accessibilityIdentifier("refine-paint-new")
    }

    /// The picker's color: the current paint's; a color picked becomes the current paint, or the
    /// painting's paint that a Bucket tap would give for it.
    private var picked: Binding<Color> {
        Binding(
            get: { current.map { RefinePalette.color($0, space: template.colorSpace) } ?? .gray },
            set: { color in
                let resolved = color.resolve(in: environment)
                let lab = ColorScience.linearSRGBToOKLab(SIMD3(resolved.linearRed, resolved.linearGreen, resolved.linearBlue))
                current = RefinePalette.snapped(lab, to: template.palette)
            })
    }
}

/// The cell Select picked: its paint, how many areas share it and how much of the picture it
/// covers, and Change Color, which opens its card (`RefineAreaCard`).
struct RefineSelectionBar: View {
    let template: Template
    let region: Int
    let changeColor: () -> Void

    var body: some View {
        let paint = Int(template.regions[region].colorIndex)
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                Text(verbatim: "\(paint + 1)")
                    .font(.display(.headline))
                    .monospacedDigit()
                    .foregroundStyle(PaletteBar.numeralInk(template, paint))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(PaletteBar.paint(template, paint)))
                    .overlay { Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5) }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ColorNameText.title(template.palette[paint].colorName))
                        .font(.subheadline.weight(.semibold))
                    Text(Self.subtitle(region: region, in: template))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button(action: changeColor) {
                Label { Text("Change Color") } icon: { Image(systemName: "drop.halffull") }
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("refine-selection-color")
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
        .frame(maxWidth: 560)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("refine-selection")
    }

    /// "Paint 6 · 4 areas · 2% of the picture".
    nonisolated static func subtitle(region: Int, in template: Template) -> String {
        let paint = Int(template.regions[region].colorIndex)
        let number = (paint + 1).formatted()
        let areas = TemplateCounts.areas(RefineAreaCard.areaCount(of: paint, in: template))
        let share = (Double(template.regions[region].area) / Double(max(template.width * template.height, 1)))
            .formatted(.percent.precision(.significantDigits(1...2)))
        return String(
            localized: "refine.selection", defaultValue: "Paint \(number) · \(areas) · \(share) of the picture",
            comment: "Refine screen, Select's bar: the selected area's paint number (formatted), how many areas have that paint (\"3 areas\"), and how much of the picture the area covers (a formatted percentage)")
    }
}

/// The cells' undrawn edges (the boundaries between colors with no ink: a cell edge, a soft edge
/// of the photo), dashed over the drawing in `rect` while a Cells tool is picked, so every cell
/// shows whatever its paint.
struct RefineCellEdges: View, Equatable {
    let base: CreateModel.Preview?
    let rect: CGRect

    nonisolated static func == (a: RefineCellEdges, b: RefineCellEdges) -> Bool {
        a.base?.id == b.base?.id && a.rect == b.rect
    }

    /// The undrawn edges between regions of `t`, in canvas units: none for a classic template,
    /// whose every edge is drawn.
    nonisolated static func edges(of t: Template) -> [[SIMD2<Float>]] {
        guard let drawable = DrawableLineArt(t) else { return [] }
        return t.edges.indices.compactMap { e in
            let edge = t.edges[e]
            guard edge.right != BoundaryEdge.outside, !DrawableLineArt.isDrawn(drawable.edgeLayers[e]) else { return nil }
            return Array(t.points(of: edge))
        }
    }

    var body: some View {
        let lines = base.map { Self.edges(of: $0.template) } ?? []
        let size = base.map { CGSize(width: $0.template.width, height: $0.template.height) } ?? .zero
        let rect = rect, color = Theme.signature
        Canvas { context, _ in
            guard size.width > 0, size.height > 0, rect.width > 0, rect.height > 0 else { return }
            let s = max(rect.width / size.width, rect.height / size.height)
            let origin = CGPoint(x: rect.midX - size.width * s / 2, y: rect.midY - size.height * s / 2)
            var dashed = context
            dashed.clip(to: Path(rect))
            dashed.translateBy(x: origin.x, y: origin.y)
            dashed.scaleBy(x: s, y: s)
            var path = Path()
            for line in lines where line.count >= 2 {
                path.addLines(line.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })
            }
            var style = StrokeStyle(lineWidth: 1.25 / s, lineCap: .butt, lineJoin: .round)
            style.dash = [4 / s, 3 / s]
            dashed.stroke(path, with: .color(color.opacity(0.8)), style: style)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
