import PaintCore
import SwiftUI

/// Line Appearance: presets, how each layer looks at 1×, 2× and 4×, and per layer the opacity
/// and width at those zooms; for a coloring book, which draws every line alike, its line weight.
struct LineAppearanceSection: View {
    @Bindable var model: AdvancedSettingsModel
    let zoom: CGFloat
    var onZoom: (Int) -> Void
    @State private var layer: LineLayer = .detail

    var body: some View {
        Section {
            if model.lineArt.style == .coloringBook {
                AdvancedSlider(
                    title: AdvancedText.coloringBookWeightTitle, summary: AdvancedText.coloringBookWeightSummary,
                    valueText: coloringBookWeightSlider.text(model.coloringBookWeight), spec: coloringBookWeightSlider,
                    value: model.coloringBookWeight, isChanged: model.coloringBookWeight != coloringBookWeightSlider.defaultValue,
                    identifier: "advanced-appearance-bookWeight",
                    onChange: { model.coloringBookWeight = $0 }, onReset: { model.coloringBookWeight = coloringBookWeightSlider.defaultValue })
                    .id("advanced-appearance")
            } else {
                if model.lineArt.style == .classic {
                    SwiftUI.Label {
                        Text("Layered lines are drawn this way. Choose Layered above to see it in the preview.")
                            .font(.footnote)
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Theme.accent)
                    }
                }
                presets
                    .id("advanced-appearance")
                ZoomStrip(appearance: model.appearance, layer: layer, zoom: zoom, onSelect: onZoom)
                    .padding(.vertical, 4)
                layerPicker
                values(.opacity)
                values(.width)
                paintedRow
                AdvancedToggleRow(
                    title: AdvancedText.weightTitle,
                    summary: String(localized: "advanced.appearance.weighted.summary",
                                    defaultValue: "Draws stronger edges heavier within each layer. Off draws a layer’s lines alike.",
                                    comment: "Settings › Advanced › Line Appearance: explanation under the Weight by Edge Strength switch"),
                    isOn: $model.appearance.weighted, identifier: "advanced-appearance-weighted")
            }
        } header: {
            AdvancedSectionHeader(
                title: String(localized: "advanced.section.appearance", defaultValue: "Line Appearance",
                              comment: "Settings › Advanced: header of the section on how layered lines are drawn at each zoom"),
                canReset: !model.isAppearanceDefault, identifier: "advanced-reset-appearance") { model.resetAppearance() }
        } footer: {
            if model.lineArt.style == .coloringBook {
                Text("Drawing only: changes show at once and apply to every coloring-book painting, including the ones you have.")
            } else {
                Text("Drawing only: changes show at once and apply to every layered painting, including the ones you have.")
            }
        }
    }

    private var presets: some View {
        PresetRow(
            presets: LineAppearancePreset.allCases, current: LineAppearancePreset.matching(model.appearance),
            name: { $0.name }, summary: { $0.summary },
            customSummary: String(
                localized: "advanced.preset.custom.summary", defaultValue: "Your own values for each layer.",
                comment: "Settings › Advanced › Line Appearance: under the presets when the layers match none of them"),
            apply: { model.apply($0) })
    }

    private var layerPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                layerChoices.pickerStyle(.segmented).fixedSize()
                layerChoices.pickerStyle(.menu)
            }
            SwiftUI.Label {
                Text(AdvancedText.clarity(of: model.appearance[layer]))
                    .contentTransition(.opacity)
            } icon: {
                Image(systemName: "eye")
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var layerChoices: some View {
        Picker(selection: $layer) {
            ForEach(LineLayer.allCases, id: \.self) { layer in
                Text(layer.name).tag(layer)
            }
        } label: {
            Text(String(localized: "advanced.appearance.layer", defaultValue: "Layer",
                        comment: "Settings › Advanced › Line Appearance: label of the choice of which layer the sliders below edit"))
        }
        .accessibilityIdentifier("advanced-appearance-layer")
    }

    private enum Property {
        case opacity, width

        var title: String {
            switch self {
            case .opacity: String(localized: "advanced.appearance.opacity", defaultValue: "Opacity",
                                  comment: "Settings › Advanced › Line Appearance: heading of a layer's opacity at each zoom")
            case .width: String(localized: "advanced.appearance.width", defaultValue: "Width",
                                comment: "Settings › Advanced › Line Appearance: heading of a layer's line width at each zoom, relative to a classic line")
            }
        }

        func values(of layer: LineAppearance.Layer) -> [Float] {
            switch self {
            case .opacity: layer.opacity
            case .width: layer.width
            }
        }

        func set(_ value: Float, at index: Int, in layer: inout LineAppearance.Layer) {
            switch self {
            case .opacity: layer.opacity[index] = value
            case .width: layer.width[index] = value
            }
        }
    }

    /// How much of the layer's lines stays once the areas on both sides are painted.
    private var paintedRow: some View {
        let layer = self.layer
        let spec = SliderSpec(
            range: 0...1, defaultValue: Double(LineAppearance.default[layer].painted), quantum: 0.01, accessibilityStep: 0.05,
            format: .percent)
        let value = Double(model.appearance[layer].painted)
        return AdvancedSlider(
            title: AdvancedText.paintedTitle(of: layer), summary: AdvancedText.paintedSummary, valueText: spec.text(value), spec: spec,
            value: value, isChanged: value != spec.defaultValue, identifier: "advanced-appearance-painted",
            onChange: { model.appearance[layer].painted = Float($0) },
            onReset: { model.appearance[layer].painted = LineAppearance.default[layer].painted })
    }

    /// A layer's opacity or width at the three zooms.
    private func values(_ property: Property) -> some View {
        let isOpacity = property == .opacity
        let defaults = property.values(of: LineAppearance.default[layer])
        let current = property.values(of: model.appearance[layer])
        return VStack(alignment: .leading, spacing: 2) {
            Text(property.title)
                .font(.subheadline.weight(.semibold))
            ForEach(LineAppearance.zooms.indices, id: \.self) { index in
                let spec = isOpacity
                    ? SliderSpec(range: 0...1, defaultValue: Double(defaults[index]), quantum: 0.01, accessibilityStep: 0.05, format: .percent)
                    : SliderSpec(range: 0.2...3, defaultValue: Double(defaults[index]), quantum: 0.05, accessibilityStep: 0.05, format: .multiplier)
                let zoomText = AdvancedText.zoom(Int(LineAppearance.zooms[index]))
                let layerName = layer.name
                CompactSlider(
                    label: zoomText, spec: spec, value: Double(current[index]),
                    accessibilityLabel: isOpacity
                        ? String(localized: "advanced.appearance.opacityAt", defaultValue: "\(layerName) opacity at \(zoomText)",
                                 comment: "Settings › Advanced › Line Appearance: VoiceOver label of a slider; the arguments are the layer, e.g. Texture, and the zoom, e.g. 2×")
                        : String(localized: "advanced.appearance.widthAt", defaultValue: "\(layerName) width at \(zoomText)",
                                 comment: "Settings › Advanced › Line Appearance: VoiceOver label of a slider; the arguments are the layer, e.g. Texture, and the zoom, e.g. 2×"),
                    identifier: "advanced-appearance-\(isOpacity ? "opacity" : "width")-\(index)"
                ) { value in
                    property.set(Float(value), at: index, in: &model.appearance[layer])
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// One value of a layer on a slider in a single line: the zoom, the slider, the value.
private struct CompactSlider: View {
    let label: String
    let spec: SliderSpec
    let value: Double
    let accessibilityLabel: String
    let identifier: String
    var onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 26, alignment: .leading)
                .accessibilityHidden(true)
            Slider(value: Binding(get: { spec.position(of: value) }, set: { set(spec.value(at: $0)) }), in: 0...1)
                .accessibilityLabel(Text(accessibilityLabel))
                .accessibilityValue(Text(spec.text(value)))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: set(spec.value(value, adjustedBy: 1))
                    case .decrement: set(spec.value(value, adjustedBy: -1))
                    @unknown default: break
                    }
                }
                .accessibilityIdentifier(identifier)
            Text(spec.text(value))
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(value == spec.defaultValue ? Color.secondary : Theme.accent)
                .contentTransition(.numericText())
                .frame(minWidth: 48, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private func set(_ newValue: Double) {
        guard newValue != value else { return }
        if newValue == spec.defaultValue { FeedbackEngine.shared.selectionChanged() }
        onChange(newValue)
    }
}

/// The four layers drawn as each zoom shows them (relative to a classic line), the layer being
/// edited marked. A tile zooms the preview to its level.
private struct ZoomStrip: View {
    let appearance: LineAppearance
    let layer: LineLayer
    let zoom: CGFloat
    var onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PreviewZoom.levels.indices, id: \.self) { index in
                tile(index: index, level: PreviewZoom.levels[index])
            }
        }
    }

    private func tile(index: Int, level: Int) -> some View {
        let selected = PreviewZoom.level(near: zoom) == level
        let zoomText = AdvancedText.zoom(level)
        let appearance = self.appearance, layer = self.layer, mark = Theme.accent.opacity(0.14)
        return Button {
            FeedbackEngine.shared.selectionChanged()
            onSelect(level)
        } label: {
            VStack(spacing: 5) {
                Canvas { context, size in
                    Self.draw(appearance, at: index, marking: layer, with: mark, in: context, size: size)
                }
                .frame(height: 62)
                .background(LineSwatchSheet.paper, in: .rect(cornerRadius: 8, style: .continuous))
                Text(zoomText)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(selected ? Theme.accent : Color.secondary)
            }
            .padding(5)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : Color.clear, lineWidth: 2)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String(localized: "advanced.appearance.tile", defaultValue: "Lines at \(zoomText)",
                                        comment: "Settings › Advanced › Line Appearance: VoiceOver label of a drawing of every layer at a zoom; the argument is the zoom, e.g. 2×")))
        .accessibilityHint(Text(String(localized: "advanced.appearance.tile.hint", defaultValue: "Zooms the preview to this level.",
                                       comment: "Settings › Advanced › Line Appearance: VoiceOver hint of a drawing of every layer at a zoom")))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    nonisolated private static func draw(
        _ appearance: LineAppearance, at index: Int, marking marked: LineLayer, with mark: Color, in context: GraphicsContext,
        size: CGSize
    ) {
        let layers = LineLayer.allCases
        let row = size.height / CGFloat(layers.count)
        for (position, layer) in layers.enumerated() {
            let values = appearance[layer]
            let y = row * (CGFloat(position) + 0.5)
            if layer == marked {
                context.fill(Path(CGRect(x: 0, y: y - row / 2, width: size.width, height: row)), with: .color(mark))
            }
            var path = Path()
            let inset: CGFloat = 8, swing = row * 0.32
            path.move(to: CGPoint(x: inset, y: y))
            path.addCurve(
                to: CGPoint(x: size.width - inset, y: y),
                control1: CGPoint(x: size.width * 0.38, y: y - swing), control2: CGPoint(x: size.width * 0.62, y: y + swing))
            let width = max(0.3, CGFloat(values.width[index]) * 1.6)
            let color = LineSwatchSheet.ink.opacity(Double(values.opacity[index]))
            if appearance.weighted {
                // Stronger edges heavier: one line, heavy at its start, light at its end.
                let parts: [(from: CGFloat, to: CGFloat, factor: CGFloat)] = [(0, 0.34, 1.35), (0.33, 0.67, 1), (0.66, 1, 0.65)]
                for part in parts {
                    context.stroke(
                        path.trimmedPath(from: part.from, to: part.to), with: .color(color),
                        style: StrokeStyle(lineWidth: width * part.factor, lineCap: .round))
                }
            } else {
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
        }
    }
}
