import Foundation
import SwiftUI

/// What the Refine screen shows, as a stack of layers over the paper, top to bottom: the numbers,
/// the ink, the paint and the photo, the stack a Procreate artist builds to color line art. A
/// layer can be hidden, and the paint and the photo each have an opacity. Layers change only what
/// shows, never the picture (the template has one drawing, one set of cells and one paint each).
nonisolated struct RefineLayers: Hashable {
    /// A layer of the stack, in its order from the top.
    enum Layer: Hashable, CaseIterable {
        case numbers, ink, paint, photo
    }

    var numbers = false
    var ink = true
    var paint = true
    /// How opaque the paint is over what lies beneath it (the photo, or the paper).
    var paintOpacity: Double = 1
    var photo = false
    var photoOpacity: Double = 1

    /// Every cell in its paint, as the picture will look finished: Refine opens on it.
    static let painting = RefineLayers()
    /// The page before it is painted: the lines and the numbers on the paper.
    static let paper = RefineLayers(numbers: true, paint: false)
    /// The photo under the lines.
    static let photograph = RefineLayers(paint: false, photo: true)
    /// The painting at half strength over the photo, for tracing.
    static let tracing = RefineLayers(paintOpacity: 0.5, photo: true)

    func shows(_ layer: Layer) -> Bool {
        switch layer {
        case .numbers: numbers
        case .ink: ink
        case .paint: paint
        case .photo: photo
        }
    }

    mutating func set(_ layer: Layer, shown: Bool) {
        switch layer {
        case .numbers: numbers = shown
        case .ink: ink = shown
        case .paint: paint = shown
        case .photo: photo = shown
        }
    }

    /// How much of the paint shows, 0 to 1.
    var paintStrength: Double { paint ? paintOpacity : 0 }

    /// How much of the photo shows through what lies over it, 0 to 1.
    var photoStrength: Double { photo ? photoOpacity * (1 - paintStrength) : 0 }

    /// The photo is what shows most, so the Eyedropper picks its color rather than a cell's paint.
    var photoReads: Bool { photoStrength > paintStrength }
}

extension RefineTool {
    /// The layer the tool works on, which the Layers panel marks: the ink's tools the ink, the
    /// cells' and the paint's the paint, Move Number the numbers; Writing and Try Painting none.
    var layer: RefineLayers.Layer? {
        switch group {
        case .ink: .ink
        case .cells, .paint: .paint
        case .numbers: .numbers
        case .see: nil
        }
    }
}

/// The Layers panel, from Refine's top bar: the stack from the top, each layer with its switch, the
/// paint and the photo with their opacity, and the layer the picked tool works on marked.
struct RefineLayersPanel: View {
    @Binding var layers: RefineLayers
    /// The layer the picked tool works on.
    let working: RefineLayers.Layer?

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Layers")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            ForEach(RefineLayers.Layer.allCases, id: \.self) { row($0) }
            Text("Layers change only what you see, never the picture.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.top, 4)
        }
        .padding(12)
        .frame(width: typeSize.isAccessibilitySize ? nil : 320)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("refine-layers-panel")
    }

    private func row(_ layer: RefineLayers.Layer) -> some View {
        let isWorking = working == layer
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: Self.symbol(layer))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isWorking ? Theme.signature : Color.secondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Toggle(isOn: shown(layer)) {
                    VStack(alignment: .leading, spacing: 1) {
                        Self.name(layer)
                        if isWorking {
                            Text("Your tool’s layer")
                                .font(.caption)
                                .foregroundStyle(Theme.signature)
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(Theme.signature)
                .accessibilityIdentifier("refine-layer-\(layer)")
            }
            if let opacity = opacity(layer) {
                HStack(spacing: 10) {
                    Slider(value: opacity, in: 0...1)
                        .tint(Theme.signature)
                        .accessibilityLabel(layer == .paint ? Text("Paint Opacity") : Text("Photo Opacity"))
                        .accessibilityValue(Text(opacity.wrappedValue.formatted(.percent.precision(.fractionLength(0)))))
                        .accessibilityIdentifier("refine-layer-\(layer)-opacity")
                    Text(opacity.wrappedValue.formatted(.percent.precision(.fractionLength(0))))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 40, alignment: .trailing)
                        .accessibilityHidden(true)
                }
                .padding(.leading, 36)
                .disabled(!layers.shows(layer))
            }
        }
        .padding(10)
        .background {
            if isWorking {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.signature.opacity(0.12))
            }
        }
    }

    private func shown(_ layer: RefineLayers.Layer) -> Binding<Bool> {
        Binding(get: { layers.shows(layer) }, set: { shown in
            FeedbackEngine.shared.selectionChanged()
            layers.set(layer, shown: shown)
        })
    }

    /// The paint's and the photo's opacity; the others have none.
    private func opacity(_ layer: RefineLayers.Layer) -> Binding<Double>? {
        switch layer {
        case .paint: $layers.paintOpacity
        case .photo: $layers.photoOpacity
        case .numbers, .ink: nil
        }
    }

    static func name(_ layer: RefineLayers.Layer) -> Text {
        switch layer {
        case .numbers: Text("Numbers")
        case .ink: Text("Ink")
        case .paint: Text("Paint")
        case .photo: Text("Photo")
        }
    }

    static func symbol(_ layer: RefineLayers.Layer) -> String {
        switch layer {
        case .numbers: "number"
        case .ink: "scribble.variable"
        case .paint: "paintpalette"
        case .photo: "photo"
        }
    }
}
