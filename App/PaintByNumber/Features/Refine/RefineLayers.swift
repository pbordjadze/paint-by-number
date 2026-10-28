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
