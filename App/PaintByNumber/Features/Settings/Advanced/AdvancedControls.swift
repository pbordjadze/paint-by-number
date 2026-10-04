import PaintCore
import SwiftUI

/// The canvas sheet's paper and ink (`CanvasPalette.light`), for the drawings that show what
/// lines look like.
private nonisolated enum Sheet {
    static let paper = Color(red: 0.957, green: 0.937, blue: 0.902)
    static let ink = Color(red: 0.118, green: 0.102, blue: 0.133)
}

/// A section header with a Reset button while the section differs from its defaults.
struct AdvancedSectionHeader: View {
    let title: String
    let canReset: Bool
    let identifier: String
    var onReset: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 8)
            if canReset {
                Button("Reset") {
                    FeedbackEngine.shared.selectionChanged()
                    withAnimation(.snappy) { onReset() }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderless)
                .accessibilityIdentifier(identifier)
                .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.2), value: canReset)
    }
}

/// A setting's effect on the preview: "+212 areas · about 10 min longer".
struct EffectLine: View {
    let effect: AdvancedSettingsModel.Effect

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            switch effect {
            case .atDefault:
                Image(systemName: "checkmark.circle")
                Text(String(localized: "advanced.effect.default", defaultValue: "At its default",
                            comment: "Settings › Advanced: under a setting that is at its default value"))
            case .measuring(nil):
                ProgressView()
                    .controlSize(.mini)
                Text(String(localized: "advanced.effect.measuring", defaultValue: "Measuring…",
                            comment: "Settings › Advanced: under a changed setting while its effect on the preview is being worked out"))
            case .measuring(let delta?), .measured(let delta):
                Image(systemName: Self.symbol(for: delta))
                Text(AdvancedText.effect(delta))
            }
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(color)
        .opacity(isMeasuring ? 0.55 : 1)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeInOut(duration: 0.2), value: effect)
    }

    private var isMeasuring: Bool {
        if case .measuring = effect { return true }
        return false
    }

    private var color: Color {
        guard let delta = effect.delta, !delta.isZero else { return .secondary }
        return Theme.accent
    }

    private static func symbol(for delta: AdvancedStats.Delta) -> String {
        let direction = delta.areas != 0 ? delta.areas.signum() : (delta.lines ?? delta.colors).signum()
        return direction > 0 ? "arrow.up.right" : direction < 0 ? "arrow.down.right" : "equal"
    }

    /// The effect as VoiceOver reads it after the value; nil at the default.
    static func text(_ effect: AdvancedSettingsModel.Effect) -> String? {
        switch effect {
        case .atDefault:
            return nil
        case .measuring(nil):
            return String(localized: "advanced.effect.measuring", defaultValue: "Measuring…",
                          comment: "Settings › Advanced: under a changed setting while its effect on the preview is being worked out")
        case .measuring(let delta?), .measured(let delta):
            return AdvancedText.effect(delta)
        }
    }
}

/// A setting on a slider: its name, value, a line on what it does and its effect. VoiceOver
/// reads the slider alone, with all of that, moving by the setting's own step.
struct AdvancedSlider: View {
    let title: String
    var summary: String?
    let valueText: String
    let spec: SliderSpec
    let value: Double
    let isChanged: Bool
    var effect: AdvancedSettingsModel.Effect?
    let identifier: String
    var onChange: (Double) -> Void
    var onReset: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if isChanged, let onReset {
                    Button {
                        FeedbackEngine.shared.selectionChanged()
                        onReset()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.borderless)
                    // The element's own action ("Reset to Default") stands in for it.
                    .accessibilityHidden(true)
                    .transition(.opacity)
                }
                Text(valueText)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(isChanged ? Theme.accent : Color.secondary)
                    .contentTransition(.numericText())
            }
            .accessibilityHidden(true)
            Slider(value: position, in: 0...1)
                .accessibilityLabel(Text(title))
                .accessibilityValue(Text(accessibilityValue))
                .accessibilityHint(Text(summary ?? ""))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: set(spec.value(value, adjustedBy: 1))
                    case .decrement: set(spec.value(value, adjustedBy: -1))
                    @unknown default: break
                    }
                }
                .accessibilityActions {
                    if isChanged, let onReset {
                        Button("Reset to Default", action: onReset)
                    }
                }
                .accessibilityIdentifier(identifier)
            Group {
                if let summary {
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let effect {
                    EffectLine(effect: effect)
                }
            }
            // The slider's hint and value say these.
            .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .animation(.snappy(duration: 0.2), value: isChanged)
    }

    private var accessibilityValue: String {
        guard let effect, let text = EffectLine.text(effect) else { return valueText }
        return String(localized: "advanced.control.value", defaultValue: "\(valueText), \(text)",
                      comment: "Settings › Advanced: VoiceOver value of a setting; the arguments are its value and its effect, e.g. 2×, −340 areas · about 17 min shorter")
    }

    private var position: Binding<Double> {
        Binding(get: { spec.position(of: value) }, set: { set(spec.value(at: $0)) })
    }

    private func set(_ newValue: Double) {
        guard newValue != value else { return }
        // A tick as the thumb settles on the default, the slider's detent.
        if newValue == spec.defaultValue { FeedbackEngine.shared.selectionChanged() }
        onChange(newValue)
    }
}

/// A generation setting on a slider, bound to the model.
struct AdvancedSliderRow: View {
    let control: AdvancedControl
    let model: AdvancedSettingsModel

    var body: some View {
        let style = model.lineArt.style
        if let spec = control.slider(for: style) {
            AdvancedSlider(
                title: control.title(for: style), summary: control.summary(for: style), valueText: model.valueText(of: control), spec: spec,
                value: model.value(of: control), isChanged: model.isChanged(control),
                effect: model.effects[control] ?? .atDefault, identifier: "advanced-control-\(control.rawValue)",
                onChange: { model.set(control, to: $0) }, onReset: { model.reset(control) })
        }
    }
}

/// A setting on a switch: its name, a line on what it does and its effect.
struct AdvancedToggleRow: View {
    let title: String
    let summary: String
    @Binding var isOn: Bool
    var effect: AdvancedSettingsModel.Effect?
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $isOn) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            Text(summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let effect {
                EffectLine(effect: effect)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// Which of the two bundled models the lines come from (`LineArtSettings.Detector`).
struct DetectorRow: View {
    @Bindable var model: AdvancedSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(selection: $model.lineArt.detector) {
                ForEach(LineArtSettings.Detector.allCases, id: \.self) { option in
                    Text(option.name).tag(option)
                }
            } label: {
                Text(AdvancedControl.detector.title)
                    .font(.subheadline.weight(.semibold))
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("advanced-control-detector")
            Text(model.lineArt.detector.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            EffectLine(effect: model.effects[.detector] ?? .atDefault)
        }
        .padding(.vertical, 2)
    }
}

/// What happens where a line runs between two areas of the same paint. A coloring book has no
/// texture lines, so it offers two choices, joining across texture shown as splitting.
struct SamePaintRow: View {
    @Bindable var model: AdvancedSettingsModel

    var body: some View {
        let style = model.lineArt.style
        let book = style == .coloringBook
        let options: [LineArtSettings.SamePaint] = book ? [.joinTexture, .joinAllButOutlines] : LineArtSettings.SamePaint.allCases
        VStack(alignment: .leading, spacing: 6) {
            Picker(selection: selection(book: book)) {
                ForEach(options, id: \.self) { option in
                    Text(option.name(in: style)).tag(option)
                }
            } label: {
                Text(AdvancedControl.samePaint.title)
                    .font(.subheadline.weight(.semibold))
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("advanced-control-samePaint")
            Text(model.lineArt.samePaint.summary(in: style))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            EffectLine(effect: model.effects[.samePaint] ?? .atDefault)
        }
        .padding(.vertical, 2)
    }

    /// In a coloring book Always Split and Join Across Texture are one choice, shown as the
    /// default (joining across texture), so the row reads "at its default" until it is changed.
    private func selection(book: Bool) -> Binding<LineArtSettings.SamePaint> {
        Binding(
            get: { book && model.lineArt.samePaint == .split ? .joinTexture : model.lineArt.samePaint },
            set: { model.lineArt.samePaint = $0 })
    }
}

/// Classic, Layered or Coloring Book, each with a small drawing of what its lines look like.
struct LineStyleRow: View {
    @Bindable var model: AdvancedSettingsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AdvancedControl.style.title)
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 10) {
                ForEach(LineArtSettings.Style.allCases, id: \.self) { style in card(style) }
            }
            Text(model.lineArt.style.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            EffectLine(effect: model.effects[.style] ?? .atDefault)
        }
        .padding(.vertical, 4)
    }

    private func card(_ style: LineArtSettings.Style) -> some View {
        let selected = model.lineArt.style == style
        return Button {
            guard !selected else { return }
            FeedbackEngine.shared.selectionChanged()
            withAnimation(reduceMotion ? nil : .snappy) { model.lineArt = model.lineArt.changing(to: style) }
        } label: {
            VStack(spacing: 8) {
                LineStyleSwatch(style: style)
                    .frame(height: 62)
                    .clipShape(.rect(cornerRadius: 10, style: .continuous))
                HStack(spacing: 4) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Theme.accent : Color.secondary)
                    Text(style.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: .rect(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : Theme.hairline, lineWidth: selected ? 2 : 1)
            }
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel(Text(style.name))
        .accessibilityHint(Text(style.summary))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("advanced-style-\(style.rawValue)")
    }
}

/// A moonlit hill drawn the way each line style draws it: Classic every line alike, Layered
/// with strong outlines, lighter detail and faint texture, Coloring Book its outlines and
/// details alike in heavy ink and nothing faint.
private struct LineStyleSwatch: View {
    let style: LineArtSettings.Style

    var body: some View {
        let style = self.style
        Canvas { context, size in
            let w = size.width, h = size.height
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Sheet.paper))
            let moon = Path(ellipseIn: CGRect(x: w * 0.68, y: h * 0.12, width: h * 0.32, height: h * 0.32))
            let crater = Path(ellipseIn: CGRect(x: w * 0.68 + h * 0.08, y: h * 0.2, width: h * 0.09, height: h * 0.09))
            var ridge = Path()
            ridge.move(to: CGPoint(x: 0, y: h * 0.62))
            ridge.addQuadCurve(to: CGPoint(x: w * 0.6, y: h * 0.6), control: CGPoint(x: w * 0.27, y: h * 0.28))
            ridge.addQuadCurve(to: CGPoint(x: w, y: h * 0.66), control: CGPoint(x: w * 0.82, y: h * 0.46))
            var hill = Path()
            hill.move(to: CGPoint(x: 0, y: h * 0.88))
            hill.addQuadCurve(to: CGPoint(x: w, y: h * 0.8), control: CGPoint(x: w * 0.45, y: h * 0.5))
            var grass = Path()
            for k in 0..<7 {
                let x = w * (0.12 + 0.11 * CGFloat(k)), y = h * (0.86 - 0.012 * CGFloat(k % 3))
                grass.move(to: CGPoint(x: x, y: y))
                grass.addLine(to: CGPoint(x: x + w * 0.02, y: y - h * 0.08))
            }
            func stroke(_ path: Path, width: CGFloat, opacity: Double) {
                context.stroke(path, with: .color(Sheet.ink.opacity(opacity)), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
            switch style {
            case .classic:
                for path in [moon, crater, ridge, hill, grass] { stroke(path, width: 1.1, opacity: 0.62) }
            case .layered:
                stroke(moon, width: 1.6, opacity: 0.9)
                stroke(hill, width: 1.6, opacity: 0.9)
                stroke(ridge, width: 1.1, opacity: 0.5)
                stroke(crater, width: 1, opacity: 0.4)
                stroke(grass, width: 0.8, opacity: 0.25)
            case .coloringBook:
                for path in [moon, hill, ridge] { stroke(path, width: 2.4, opacity: 1) }
                stroke(crater, width: 1.8, opacity: 1)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Where the three thresholds cut the scale of edge strength into texture, detail and
/// outlines, with the preview's count of lines in each layer. A coloring book has two cuts:
/// nothing below detail is drawn, so its texture layer is not shown.
struct SensitivityBand: View {
    let lineArt: LineArtSettings
    /// Lines per `LineLayer`; nil before there is a layered preview.
    let lines: [Int]?

    private var book: Bool { lineArt.style == .coloringBook }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sensitivity")
                .font(.subheadline.weight(.semibold))
            if book {
                Text("How strong an edge must be to be drawn, and to be an outline. Lower values draw more lines.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("How strong an edge must be to become each kind of line. Lower values draw more lines.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            band
            HStack {
                Text("Faint")
                Spacer()
                Text("Strong")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                      alignment: .leading, spacing: 6) {
                ForEach(book ? [LineLayer.outline, .detail, .color] : [LineLayer.outline, .detail, .texture, .color], id: \.self) { layer in
                    legend(layer)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("advanced-sensitivity")
    }

    private var band: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let texture = CGFloat(lineArt.textureThreshold), detail = CGFloat(lineArt.detailThreshold)
            let outline = CGFloat(lineArt.outlineThreshold)
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.primary.opacity(0.06))
                if !book { segment(from: texture, to: detail, layer: .texture, width: w) }
                segment(from: detail, to: outline, layer: .detail, width: w)
                segment(from: outline, to: 1, layer: .outline, width: w)
            }
            .clipShape(Capsule())
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }

    private func segment(from start: CGFloat, to end: CGFloat, layer: LineLayer, width: CGFloat) -> some View {
        Rectangle()
            .fill(Self.color(of: layer))
            .frame(width: max(0, (end - start) * width))
            .offset(x: start * width)
    }

    private static func color(of layer: LineLayer) -> Color {
        switch layer {
        case .outline: Color.primary.opacity(0.85)
        case .detail: Color.primary.opacity(0.5)
        case .texture: Color.primary.opacity(0.25)
        case .color: Color.primary.opacity(0.12)
        }
    }

    private func legend(_ layer: LineLayer) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(Self.color(of: layer))
                .frame(width: 10, height: 10)
            Text(layer.name)
                .font(.caption)
            if let count = lines?[Int(layer.rawValue)] {
                Text(count.formatted())
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .animation(.snappy, value: lines)
    }
}

/// One choice of a presets row: a capsule, filled on the signature color while chosen.
struct PresetCapsule: View {
    let title: String
    let summary: String
    let isSelected: Bool
    let identifier: String
    var action: () -> Void

    var body: some View {
        Button {
            guard !isSelected else { return }
            FeedbackEngine.shared.selectionChanged()
            withAnimation(.snappy) { action() }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? Theme.signature : Color.primary.opacity(0.07), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(summary))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

/// Presets of the whole screen (`AdvancedPreset`), the one the settings match marked, with a
/// line on what it does.
struct AdvancedPresetRow: View {
    let model: AdvancedSettingsModel

    var body: some View {
        let current = model.currentPreset
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(AdvancedPreset.allCases) { preset in
                    PresetCapsule(
                        title: preset.name, summary: preset.summary, isSelected: current == preset,
                        identifier: "advanced-preset-\(preset.rawValue)"
                    ) { model.apply(preset) }
                }
            }
            Text(current?.summary ?? String(
                localized: "advanced.presets.custom.summary", defaultValue: "Your own mix of settings.",
                comment: "Settings › Advanced › Presets: under the presets when the settings match none of them"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

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
        let current = LineAppearancePreset.matching(model.appearance)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(LineAppearancePreset.allCases) { preset in
                    PresetCapsule(
                        title: preset.name, summary: preset.summary, isSelected: current == preset,
                        identifier: "advanced-preset-\(preset.rawValue)"
                    ) { model.apply(preset) }
                }
            }
            Text(current?.summary ?? String(
                localized: "advanced.preset.custom.summary", defaultValue: "Your own values for each layer.",
                comment: "Settings › Advanced › Line Appearance: under the presets when the layers match none of them"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
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
                .background(Sheet.paper, in: .rect(cornerRadius: 8, style: .continuous))
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
            let color = Sheet.ink.opacity(Double(values.opacity[index]))
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
