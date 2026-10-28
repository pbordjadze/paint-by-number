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
    /// paint has it. A color no paint had (from the picker or the photo) stays, or becomes the
    /// paint within a just-noticeable difference of it. A paint that took another color takes it
    /// along: the paint of its number, when that number's color is new (a look, a repaint);
    /// otherwise (paints made one, a paint gone) the paint nearest it. With none, the first paint.
    static func following(_ current: SIMD3<Float>?, from before: [PaletteColor]?, to after: [PaletteColor]) -> SIMD3<Float>? {
        guard let current else { return after.first?.oklab }
        if index(of: current, in: after) != nil { return current }
        guard let before, let k = index(of: current, in: before) else { return snapped(current, to: after) }
        if before.count == after.count, index(of: after[k].oklab, in: before) == nil { return after[k].oklab }
        return after.min { ColorScience.distance($0.oklab, current) < ColorScience.distance($1.oklab, current) }?.oklab
    }

    /// A repaint sent while its paint was the current one: the edit, the color it gives that
    /// paint (`TemplateEditor.recolor(_:by:)`), and the current paint as it was sent.
    struct Repainted: Equatable {
        let edit: TemplateEditor.Edit
        let color: SIMD3<Float>
        let current: SIMD3<Float>?
    }

    /// The current paint once a template lands with `after` (`before` the last's), and whether
    /// `repainted` still waits. The template whose last edit is the repaint makes its paint the
    /// current one, so Edit Paint's open picker goes on with it: followed from its old color, a
    /// repaint whose paints came out alike (and so were numbered anew) left the picker on another
    /// paint, which its next pick recolored (QA, October 26). Otherwise the current paint follows
    /// its paint (`following`) and the repaint waits for its template, let go once another paint
    /// is the current one. One that never lands (declined, replaced) waits harmlessly: only a
    /// template with it last is its.
    static func landing(
        _ current: SIMD3<Float>?, from before: [PaletteColor]?, to after: [PaletteColor],
        repainted: Repainted?, lastEdit: TemplateEditor.Edit?
    ) -> (current: SIMD3<Float>?, waiting: Bool) {
        let followed = following(current, from: before, to: after)
        guard let repainted, repainted.current == current else { return (followed, false) }
        guard lastEdit == repainted.edit else { return (followed, true) }
        guard let k = index(of: snapped(repainted.color, to: after), in: after) else { return (followed, false) }
        return (after[k].oklab, false)
    }

    /// `lab` as a SwiftUI color, in the template's color space.
    static func color(_ lab: SIMD3<Float>, space: RGBColorSpace) -> Color {
        let rgb = ColorScience.okLabToEncoded(lab, space: space)
        return Color(space == .displayP3 ? .displayP3 : .sRGB, red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z))
    }
}

/// The painting's paints in a row, in Cells and Paint, the current one ringed; a color no paint
/// has yet shows after them, and the system color picker at the end picks any color as the
/// current paint. A swatch dragged onto a cell of the picture pours its paint there (the canvas
/// takes the drop, `color(of:in:)`). With `merge` (Edit Paint), a paint dragged onto another
/// becomes it, and VoiceOver offers the same on each paint (into the current one).
struct RefinePaletteBar: View {
    let template: Template
    @Binding var current: SIMD3<Float>?
    /// Makes paint `from` the paint `into` (both indices of the palette).
    var merge: ((_ from: Int, _ into: Int) -> Void)?

    @Environment(\.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let selected = RefinePalette.index(of: current, in: template.palette)
        HStack(spacing: 10) {
            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(template.palette.indices, id: \.self) { index in
                            mergeable(swatch(index, selected: selected == index), index, current: selected).id(index)
                        }
                        if selected == nil, let current { newPaint(current) }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 3)
                }
                .scrollIndicators(.hidden)
                .onChange(of: selected) { _, index in
                    guard let index else { return }
                    withAnimation(reduceMotion ? nil : .snappy) { reader.scrollTo(index) }
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
        .accessibilityShowsLargeContentViewer {
            Text(ColorNameText.numbered(number: index + 1, name: template.palette[index].colorName))
        }
    }

    /// What a swatch's drag carries before its paint's index.
    nonisolated static let dragPrefix = "refine-paint:"
    /// What the new paint's drag carries before its color (OKLab, three numbers).
    nonisolated static let colorPrefix = "refine-color:"

    /// The color a swatch's drag carries (`dragPrefix`, `colorPrefix`), as `template` has it; nil
    /// for any other text.
    nonisolated static func color(of payload: String, in template: Template) -> SIMD3<Float>? {
        if payload.hasPrefix(dragPrefix), let index = Int(payload.dropFirst(dragPrefix.count)),
           template.palette.indices.contains(index) {
            return template.palette[index].oklab
        }
        guard payload.hasPrefix(colorPrefix) else { return nil }
        let parts = payload.dropFirst(colorPrefix.count).split(separator: ",").compactMap { Float($0) }
        guard parts.count == 3, parts.allSatisfy(\.isFinite) else { return nil }
        return SIMD3(parts[0], parts[1], parts[2])
    }

    /// The new paint's drag: its color, exactly.
    nonisolated static func payload(of color: SIMD3<Float>) -> String {
        colorPrefix + [color.x, color.y, color.z].map { "\($0)" }.joined(separator: ",")
    }

    /// A swatch dragged onto the picture, and in Edit Paint onto another swatch, which takes
    /// another's drop.
    @ViewBuilder
    private func mergeable(_ swatch: some View, _ index: Int, current: Int?) -> some View {
        if let merge {
            swatch
                .draggable(Self.dragPrefix + String(index))
                .dropDestination(for: String.self) { items, _ in
                    // Only a swatch's own drag: text from elsewhere that reads as a number isn't one.
                    guard let item = items.first, item.hasPrefix(Self.dragPrefix),
                          let from = Int(item.dropFirst(Self.dragPrefix.count)), from != index, template.palette.indices.contains(from)
                    else { return false }
                    merge(from, index)
                    return true
                }
                .accessibilityActions {
                    if let current, current != index {
                        Button {
                            merge(index, current)
                        } label: {
                            Text("Merge Into Current Paint")
                        }
                    }
                }
        } else {
            swatch.draggable(Self.dragPrefix + String(index))
        }
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
            .draggable(Self.payload(of: color))
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
/// shows whatever its paint. Their path is made once per template (`path(of:)`, in `land`), so a
/// zoom only moves it.
struct RefineCellEdges: View, Equatable {
    /// The template's id, its canvas, and its undrawn edges in canvas units.
    let id: UUID?
    let size: CGSize
    let path: Path
    let rect: CGRect

    nonisolated static func == (a: RefineCellEdges, b: RefineCellEdges) -> Bool {
        a.id == b.id && a.size == b.size && a.rect == b.rect
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

    /// `edges(of:)` as one path.
    nonisolated static func path(of t: Template) -> Path {
        var path = Path()
        for line in edges(of: t) where line.count >= 2 {
            path.addLines(line.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })
        }
        return path
    }

    var body: some View {
        let size = size, rect = rect, path = path, color = Theme.signature
        Canvas { context, _ in
            guard size.width > 0, size.height > 0, rect.width > 0, rect.height > 0 else { return }
            let s = max(rect.width / size.width, rect.height / size.height)
            let origin = CGPoint(x: rect.midX - size.width * s / 2, y: rect.midY - size.height * s / 2)
            var dashed = context
            dashed.clip(to: Path(rect))
            dashed.translateBy(x: origin.x, y: origin.y)
            dashed.scaleBy(x: s, y: s)
            var style = StrokeStyle(lineWidth: 1.25 / s, lineCap: .butt, lineJoin: .round)
            style.dash = [4 / s, 3 / s]
            dashed.stroke(path, with: .color(color.opacity(0.8)), style: style)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The line Bend Line or Move Edge holds, while the finger moves: where it was, faint, and where
/// it goes, in the signature color, as it will be laid (`TemplateEditor.reshapedChain`).
struct RefineBendPreview: View {
    /// The chain, as it was and moved, in canvas units.
    let original: [SIMD2<Float>]
    let moved: [SIMD2<Float>]
    /// The template's canvas, canvas units.
    let size: CGSize
    let rect: CGRect
    let lineWidth: CGFloat

    var body: some View {
        let original = original, moved = moved, size = size, rect = rect, lineWidth = lineWidth
        let color = Theme.signature, paper = LineArtDrawing.paper
        Canvas { context, _ in
            guard size.width > 0, size.height > 0, rect.width > 0 else { return }
            func path(_ points: [SIMD2<Float>]) -> Path {
                var path = Path()
                path.addLines(points.map {
                    CGPoint(x: rect.minX + CGFloat($0.x) / size.width * rect.width, y: rect.minY + CGFloat($0.y) / size.height * rect.height)
                })
                return path
            }
            var canvas = context
            canvas.clip(to: Path(rect))
            // The line as it was, washed out, so the moved one reads as the one that will be.
            canvas.stroke(path(original), with: .color(paper.opacity(0.7)), style: RefineInkLayer.style(lineWidth + 2))
            canvas.stroke(path(moved), with: .color(color), style: RefineInkLayer.style(max(lineWidth, 2.5)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The number Move Number holds, under the finger: its paint's number on a disc of the paint,
/// ringed in the signature color.
struct RefineHeldNumber: View {
    let template: Template
    let paint: Int
    /// Where the finger has it, normalized to the picture.
    let at: SIMD2<Float>
    let rect: CGRect

    var body: some View {
        Text(verbatim: "\(paint + 1)")
            .font(.system(size: 13, weight: .bold, design: .serif))
            .monospacedDigit()
            .foregroundStyle(PaletteBar.numeralInk(template, paint))
            .frame(width: 30, height: 30)
            .background(Circle().fill(PaletteBar.paint(template, paint)))
            .overlay { Circle().stroke(Theme.signature, lineWidth: 2.5) }
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            .position(x: rect.minX + CGFloat(at.x) * rect.width, y: rect.minY + CGFloat(at.y) * rect.height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The areas' numbers over the drawing in `rect` while Numbers is picked or Paper shows, as a
/// page shows them (`LabelSizing`, `TemplateRasterizer`'s size): Move Number has something to
/// take, and Paper is the page as it will be painted. Over the painting or the photo Refine
/// shows none.
struct RefineNumbers: View, Equatable {
    let base: CreateModel.Preview
    let rect: CGRect

    nonisolated static func == (a: RefineNumbers, b: RefineNumbers) -> Bool {
        a.base.id == b.base.id && a.rect == b.rect
    }

    var body: some View {
        let template = base.template, rect = rect
        let size = CGSize(width: template.width, height: template.height)
        Canvas { context, area in
            guard size.width > 0, size.height > 0, rect.width > 0 else { return }
            let s = max(rect.width / size.width, rect.height / size.height)
            let origin = CGPoint(x: rect.midX - size.width * s / 2, y: rect.midY - size.height * s / 2)
            // Zoomed in, most numbers are off screen: a frame draws only those it shows (Paper
            // shows them through every zoom and move).
            // As large as a page draws them (`TemplateRasterizer`): a big area carries several
            // numbers of this size, which unbounded piled up over each other.
            let maximum = LabelSizing.sheetMaximumFraction * Float(max(template.width, template.height))
            // A number whose centre is just off screen still shows part of itself.
            let reach = max(40, 1.5 * CGFloat(maximum) * s)
            let shown = CGRect(origin: .zero, size: area).insetBy(dx: -reach, dy: -reach)
            for label in template.labels {
                let region = Int(label.region)
                guard region < template.regions.count else { continue }
                let paint = template.regions[region].colorIndex
                let digits = LabelSizing.digitCount(colorIndex: paint)
                let points = CGFloat(LabelSizing.fontSize(
                    radius: label.radius, digits: digits, maximum: maximum, detail: template.isDetailRegion(region))) * s
                let at = CGPoint(x: origin.x + CGFloat(label.position.x) * s, y: origin.y + CGFloat(label.position.y) * s)
                guard points >= 4, shown.contains(at) else { continue }
                let text = Text(verbatim: "\(paint + 1)")
                    .font(.system(size: points, weight: .semibold, design: .serif))
                    .foregroundStyle(LineArtDrawing.ink.opacity(0.75))
                context.draw(text, at: at)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
