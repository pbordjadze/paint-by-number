import CoreGraphics
import Foundation
import PaintCore

/// Per-frame shader constants. Layout mirrors `FrameUniforms` in Shaders.metal (only 16-byte
/// vectors, so Swift and MSL agree without padding rules).
nonisolated struct CanvasUniforms {
    /// xy: translation (px), z: px per canvas unit, w: px per point.
    var transform: SIMD4<Float> = .zero
    /// xy: target size (px), zw: canvas size (units).
    var viewport: SIMD4<Float> = .zero
    var background: SIMD4<Float> = .zero
    /// rgb: unpainted paper, a: drop shadow opacity.
    var paper: SIMD4<Float> = .zero
    /// rgb: outline and number ink, a: outline opacity.
    var ink: SIMD4<Float> = .zero
    /// rgb: selected paint, a: 1 when a color is selected.
    var selected: SIMD4<Float> = .zero
    /// x: outline width (px), y: selected outline width (px), z: hatch strength, w: numbers visibility.
    var outline: SIMD4<Float> = .zero
    /// x…y: legibility fade range (font px), z: max font px, w: min font px of a bumped number.
    var labels: SIMD4<Float> = .zero
    /// x: number opacity, y: selected-color number opacity, z: selected boldness (SDF units).
    var numbers: SIMD4<Float> = .zero
    /// x: now, y: selection change, z: pulse start, w: bump start (renderer clock, seconds).
    var time: SIMD4<Float> = .zero
    /// xy: position (px), z: radius (px), w: opacity.
    var brush: SIMD4<Float> = .zero
    /// x: start of a light sweep over finished paint, y: its palette color (-1 = everything).
    var shine: SIMD4<Float> = SIMD4(-10_000, -1, 0, 0)
    /// x: selected color, y: hovered region, z: pulsing region, w: bumped region (-1 = none).
    var ids: SIMD4<Int32> = SIMD4(repeating: -1)
    /// x: source photo opacity (0 = hidden).
    var photo: SIMD4<Float> = .zero
}

/// Animated paint state of one region. Layout mirrors `RegionState` in Shaders.metal.
nonisolated struct RegionState {
    var origin: SIMD2<Float>
    var start: Float
    var duration: Float
    var radius: Float
    var painted: Float
    var seed: Float
    var pad: Float = 0

    /// Settled state: painted or not, no animation.
    static func settled(painted: Bool, origin: SIMD2<Float>, seed: Float) -> RegionState {
        RegionState(origin: origin, start: -10_000, duration: painted ? 0 : 0.2, radius: 0, painted: painted ? 1 : 0, seed: seed)
    }
}

/// One digit of a region number. Layout mirrors `GlyphInstance` in Shaders.metal.
nonisolated struct GlyphInstance {
    var center: SIMD2<Float>
    var size: Float
    var offset: Float
    var digit: UInt32
    var region: UInt32
}

/// Linear Display P3 colors of the canvas chrome, for light and dark appearance.
nonisolated struct CanvasPalette: Sendable {
    var background: SIMD3<Float>
    var paper: SIMD3<Float>
    var ink: SIMD3<Float>
    var shadowOpacity: Float
    var outlineOpacity: Float

    static let light = CanvasPalette(
        background: CanvasColor.linearP3(sRGB: SIMD3(0.949, 0.949, 0.965)),
        paper: CanvasColor.linearP3(sRGB: SIMD3(0.998, 0.994, 0.982)),
        ink: CanvasColor.linearP3(sRGB: SIMD3(0.20, 0.19, 0.18)),
        shadowOpacity: 0.16, outlineOpacity: 0.62)

    static let dark = CanvasPalette(
        background: CanvasColor.linearP3(sRGB: SIMD3(0.075, 0.075, 0.082)),
        paper: CanvasColor.linearP3(sRGB: SIMD3(0.925, 0.918, 0.900)),
        ink: CanvasColor.linearP3(sRGB: SIMD3(0.17, 0.16, 0.15)),
        shadowOpacity: 0.55, outlineOpacity: 0.62)

    static func appearance(dark: Bool) -> CanvasPalette { dark ? .dark : .light }
}

nonisolated enum CanvasColor {
    /// sRGB-encoded (sRGB primaries) → linear Display P3.
    static func linearP3(sRGB c: SIMD3<Float>) -> SIMD3<Float> {
        ColorScience.sRGBToP3Linear(SIMD3(
            ColorScience.decodeSRGB(c.x), ColorScience.decodeSRGB(c.y), ColorScience.decodeSRGB(c.z)))
    }

    /// A palette color → linear Display P3.
    static func linearP3(_ color: PaletteColor, space: RGBColorSpace) -> SIMD3<Float> {
        let lin = SIMD3(
            ColorScience.decodeSRGB(color.rgb.x), ColorScience.decodeSRGB(color.rgb.y), ColorScience.decodeSRGB(color.rgb.z))
        return space == .displayP3 ? lin : ColorScience.sRGBToP3Linear(lin)
    }
}
